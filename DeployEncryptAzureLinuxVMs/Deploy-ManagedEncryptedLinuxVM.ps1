<#
.SYNOPSIS
This function provisions, installs the LAMP Stack software components and encrypts a Managed Disk Azure VM running CentOS 7.3.

.DESCRIPTION
This function provisions, installs the LAMP Stack software components and encrypts a Managed Disk Azure VM running CentOS 7.3.
The VM with the LAMP Stack installation is done with an ARM template. PowerShell is used to initiate and restart the VM to
complete the encryption process.The Azure CentOS VM could be generalized and used to create a Managed Image in a seperate Resource Group,
serving as a Managed Image repository for provisioning multiple copies of the VM.The function could be deployed as a Runbook
and triggered with a set schedule or a webhook.

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
    $SubscriptionName = "Trial Subscription",
    $ResourceGroupName = "RGXavier"
)

#Login-AzureRmAccount

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
$VaultName = "vaultspr"
$KeyName = "EncryptKey"
$AadClientID = "74b9c8a5-00ba-49c1-adb8-1db4757ea4df"
$AadClientSecret = "7227-voya"
$TemplateUriLinux = "https://store0518.blob.core.windows.net/templates/ManagedDiskLinuxVM.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"
$TemplateParameterUriLinux = "https://store0518.blob.core.windows.net/templates/VMSecretParameters.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"

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
New-AzureRmResourceGroupDeployment -Name ManagedDiskLinuxVM -ResourceGroupName $ResourceGroupName `
    -DeploymentDebugLogLevel All -TemplateUri $TemplateUriLinux -TemplateParameterUri $TemplateParameterUriLinux -Verbose
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
}

#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls