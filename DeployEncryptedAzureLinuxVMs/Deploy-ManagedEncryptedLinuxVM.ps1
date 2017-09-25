<#
.SYNOPSIS
The Deploy-ManagedEncryptedLinuxVM function automates the provisioning, installation of LAMP Stack software components and encryption of one or more Managed Disk Azure VM(s) running CentOS 7.3.

.DESCRIPTION
The Deploy-ManagedEncryptedLinuxVM function automates the provisioning, installation of LAMP Stack software components and encryption of one or more Managed Disk Azure VM(s) running CentOS 7.3.
The function assumes that the Azure Key Vault infrastructure is already in place. An ARM template is used to provison the VM(s) and install the LAMP Stack.
PowerShell is used to initiate Azure encryption and restart the VM to complete the encryption process.The function could be deployed as a Runbook and triggered with a set schedule or a webhook.

.PARAMETER SubscriptionName
Source Subscription of the VM to be deployed.

.PARAMETER Location
Location to provision the VM .

.PARAMETER ResourceGroupName
ResourceGroupName to deploy and encrypt the VM.

.EXAMPLE
Deploy-ManagedEncryptedLinuxVM

.FUNCTIONALITY
        PowerShell Language
/#>
Param(
    $Location = "southcentralus",
    $SubscriptionName = "Trial",
    $ResourceGroupName = "RGXavier"
)

$connectionName = "AzureRunAsConnection"

#region Azure Logon
try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#endregion

#region keyvault and encryption variables
$StorageAccountName = "store0518"
$VaultName = "labvault"
$KeyName = "EncryptKey"
$SecretName = "AadClientSecret"
$AadClientID = "74b9c8a5-00ba-49c1-adb8-1db4757eaedf"
$AadClientSecret = (Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValueText
$TemplateUriLinux = "https://store0518.blob.core.windows.net/scripts/ManagedDiskLinuxVM.json?sv=2016-05-31&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-08-02T23:47:00Z&st=2017-08-02T15:47:00Z&spr=https&sig=OoDzCOi6FoLVt4ZkTJu%2BEsadOM2KhNDfWSppsvE864w%3D"
$TemplateParameterUriLinux = "https://store0518.blob.core.windows.net/scripts/VMSecretParameters.json?sv=2016-05-31&ss=bfqt&srt=sco&sp=rwdlacup&se=2018-08-02T23:47:00Z&st=2017-08-02T15:47:00Z&spr=https&sig=OoDzCOi6FoLVt4ZkTJu%2BEsadOM2KhNDfWSppsvE864w%3D"
#endregion

#region Remove existing resources and vhds if any
try {
    Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName | ? {$_.ResourceName -ne $VaultName -and $_.ResourceName -ne $StorageAccountName} | Remove-AzureRmResource -Force
}
catch {
    $ErrorMessage = $_ 
    throw $ErrorMessage 
}

#endregion

#region Get Key Vault and verify access policy
try {
    $keyVault = Get-AzureRmKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
}
catch { 
    if (!$keyVault) {
        $ErrorMessage = "Vault $vaultName not found."
        throw $ErrorMessage
    }
}

#Check Vault Access Policy
$servicePrincipalConnectionObjId = (Get-AzureRmADServicePrincipal -ServicePrincipalName $servicePrincipalConnection.ApplicationId).id
$policyaccessid = ((Get-AzureRmKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName).AccessPolicies | ? {$_.ObjectId -eq $servicePrincipalConnectionObjId}).ObjectId
if ($servicePrincipalConnectionObjId -notmatch $policyaccessid) {
    Set-AzureRmKeyVaultAccessPolicy -VaultName $VaultName -ResourceGroupName $ResourceGroupName -ServicePrincipalName $servicePrincipalConnection.ApplicationId `
        -PermissionsToKeys all -PermissionsToSecrets all -PermissionsToCertificates all
}

#Get Kek
$kek = Get-AzureKeyVaultKey -VaultName $VaultName -Name $KeyName
$KeyEncryptionKeyUrl = $kek.Key.Kid

#endregion

#region
#Deploy VM ARM Template
Write-Host -Object ("Started $(Get-Date)")
New-AzureRmResourceGroupDeployment -Name ManagedEncryptedVM -ResourceGroupName $ResourceGroupName `
    -TemplateUri $TemplateUriLinux -TemplateParameterUri $TemplateParameterUriLinux -Verbose
#endregion

#Get Completed VMs
$vms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName | ? {$_.Name -like "*centos73*"}
$encryptedVMs = @()
<#Initiate encryption after VM deployment is complete. To successfully complete encryption
on a managed disk linux VM, use the SkipVmBackup switch parameter. This solution is still valid
as of today 7/28/2017.The enable encryption command typically adds to extensions to the target VM.
A VMBackup extension and the encryption extension. 
The VMBackup extension is a recovery safeguard in case encryption fails. 
Unfortunately the VMBackup extension is not compatible with managed disks. 
This causes the enable encryption command to fail at the point it attempts to make a backup of the managed disk,
prior to performing encryption.
/#> 
foreach ($vm in $vms) {
    Set-AzureRmVMDiskEncryptionExtension -ResourceGroupName $ResourceGroupName -VMName $vm.name -AadClientID $AadClientID `
        -AadClientSecret $AadClientSecret -DiskEncryptionKeyVaultUrl $keyVault.VaultUri -DiskEncryptionKeyVaultId $keyVault.ResourceId `
        -KeyEncryptionKeyUrl $KeyEncryptionKeyUrl -KeyEncryptionKeyVaultId $keyVault.ResourceId -Force -VolumeType All -KeyEncryptionAlgorithm RSA-OAEP -SkipVmBackup
    $retries = 1
    $encryptstatus = "EncryptionInProgress"
    while ($encryptstatus -eq "EncryptionInProgress" -or $encryptstatus -eq "Unknown" -and $retries -gt 0) {
        $diskstatus = Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $ResourceGroupName  -VMName $vm.name
        $encryptstatus = $diskstatus.OsVolumeEncrypted
        $retries++
    }
    if ($encryptstatus -eq "VMRestartPending") {
        Restart-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $vm.name
        $encryptedVMs += $vm
    }
    $retries = 1
    $encryptstatus = "VMRestartPending"
    while ($encryptstatus -eq "VMRestartPending" -or $encryptstatus -eq "EncryptionInProgress" -and $retries -gt 0) {
        $diskstatus = Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $ResourceGroupName  -VMName $vm.name
        $encryptstatus = $diskstatus.OsVolumeEncrypted
        $retries++
    }
}

#region create email creds
$Smtpserver = "smtp.sendgrid.net"
$From = "jack.bauer@democonsults.com"
$To = "tony.stark@democonsults.com"
$Port = "587"
$VaultName = "vaultspr"
$SecretName = "SendgridPassword"
$sendgridusername = "azure_a8a3e2815501214fbc3adf4ad15cc425@azure.com"
$sendgridPassword = (Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValueText
$emailpassword = ConvertTo-SecureString -String $sendgridPassword -AsPlainText -Force
$emailcred = New-Object System.Management.Automation.PSCredential($sendgridusername, $emailpassword)
#endregion
#region process email

$a = "<style>"
$a = $a + "BODY{background-color:white;}"
$a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$a = $a + "TH{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "TD{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "</style>"
$body = ""
$body += "<BR>"
$body += "Please review the encryption status of the following" + " " + ($encryptedVMs.count) + " " + "VMs. Thank you."
$body += "<BR>"
$body += "<BR>"
$body +=  $encryptedVMs | Select-Object -Property  Name, @{"Label" = "OSDisk Encryption Status"; e = {((Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $_.ResourceGroupName -VMName $_.Name).OsVolumeEncrypted)}}, `
@{"Label" = "Data Disk Encryption Status"; e = {((Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $_.ResourceGroupName -VMName $_.Name).DataVolumesEncrypted)}}, `
@{"Label" = "Encryption Status"; e = {((Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $_.ResourceGroupName -VMName $_.Name).ProgressMessage)}}| ConvertTo-Html -Head $a
$body = $body |Out-String
$subject = "Provisioned VMs Encryption Status."
if ($encryptedVMs -ne $null) {
    Send-MailMessage -Body $body `
        -BodyAsHtml `
        -SmtpServer $smtpserver `
        -From $from `
        -Subject $subject `
        -To $to `
        -Port $port `
        -Credential $emailcred `
        -UseSsl
}
#endregion