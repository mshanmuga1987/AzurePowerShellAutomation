<# 

.SYNOPSIS
   Function to automate deployment of LAMP components while provisioning CentOS Azure Linux VMs.
.DESCRIPTION
   Function to automate deployment of LAMP components while provisioning CentOS Azure Linux VMs using ARM templates and a bash script.
   It also automates the encryption of the VM OS Disk using the Azure Disk Encrytion feature and restarts the Linux VM when ready to complete the encryption process.
   This function can be deployed as an Automation runbook.
.PARAMETER SubscriptionName
        Subscription to be processed.
.PARAMETER ResourceGroupName
        ResourceGroup for the VM to be deployed.
.PARAMETER AadClientID
        Application ID of the Service Principal(assigned Contributor role) with access to the Key Vault for encryption.
        Can be retrieved by using the Get-AzureADApplication, Get-AzureRmADApplication or Get-AzureRmADServicePrincipal.
.PARAMETER AadClientSecret
        The password/client key of the Service Principal generated from the AzureAD portal App Registrations/Key blade.
       
.FUNCTIONALITY
        PowerShell Language
/#>

Param(
    $Location = "southcentralus",
    $SubscriptionName = "Trial",
    $ResourceGroupName = "RGXavier"
)

#Login-AzureRmAccount

$connectionName = "AzureRunAsConnection"

#Azure Logon
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

#region declare and initialize variables
$StorageAccountName = "store0518"
$VaultName = "vaultspr"
$KeyName = "EncryptKey"
$AadClientID = "74b9c8a5-00ba-49c1-adb8-1db4757ea4df"
$AadClientSecret = "7227-voya"
$TemplateUriLinux = "https://store0518.blob.core.windows.net/templates/LinuxVMInstancesTemplate.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"
$TemplateParameterUriLinux = "https://store0518.blob.core.windows.net/templates/VMSecretParameters.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"

    #endregion
#Remove existing resources and vhds if any
try {
    Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName | ? {$_.ResourceName -ne $VaultName -and $_.ResourceName -ne $StorageAccountName} | Remove-AzureRmResource -Force
}
catch {
    $ErrorMessage = $_ 
    throw $ErrorMessage 
}
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
try {
    if (($vhdblobs = Get-AzureStorageBlob -Container vhds -Context $storageAccount.Context -ErrorAction SilentlyContinue | ? {$_.Name -like "*centos*"})) {
        $vhdblobs | Remove-AzureStorageBlob -Force
    }
}
catch {$thrownError = $_}
Get-AzureStorageContainer -Context $storageAccount.Context | ? {$_.Name -like "bootdiagnostic*"} | Remove-AzureStorageContainer -Force

#Get Key Vault
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
    $setpolicy = Set-AzureRmKeyVaultAccessPolicy -VaultName $VaultName -ResourceGroupName $ResourceGroupName -ServicePrincipalName $servicePrincipalConnection.ApplicationId `
        -PermissionsToKeys all -PermissionsToSecrets all -PermissionsToCertificates all
}

#Get Kek
$kek = Get-AzureKeyVaultKey -VaultName $VaultName -Name $KeyName
$KeyEncryptionKeyUrl = $kek.Key.Kid

#Deploy VMs
Write-Host -Object ("Started $(Get-Date)")
$armdeploy = New-AzureRmResourceGroupDeployment -Name centosdeploy -ResourceGroupName $ResourceGroupName `
    -DeploymentDebugLogLevel All -TemplateUri $TemplateUriLinux -TemplateParameterUri $TemplateParameterUriLinux -Verbose

#Get Completed VMs
$vms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName | ? {$_.Name -notlike "*vm2k*"}
$encryptedVMs = @()
#Initiate encryption after VM deployment is complete
foreach ($vm in $vms) {
    $encrypt = Set-AzureRmVMDiskEncryptionExtension -ResourceGroupName $ResourceGroupName -VMName $vm.name -AadClientID $AadClientID `
        -AadClientSecret $AadClientSecret -DiskEncryptionKeyVaultUrl $keyVault.VaultUri -DiskEncryptionKeyVaultId $keyVault.ResourceId `
        -KeyEncryptionKeyUrl $KeyEncryptionKeyUrl -KeyEncryptionKeyVaultId $keyVault.ResourceId -Force -VolumeType All -KeyEncryptionAlgorithm RSA-OAEP
}

#Wait before verifying status of Linux VMs and initiating restart
Start-Sleep -Seconds 10
$linuxvms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName | ? {$_.OSProfile.LinuxConfiguration -ne $null}
foreach ($linuxvm in $linuxvms) {
    $retries = 1
    $encryptstatus = "EncryptionInProgress"
    while ($encryptstatus -eq "EncryptionInProgress" -and $retries -gt 0) {
        $encryptstatus = (Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $ResourceGroupName  -VMName $linuxvm.name).OsVolumeEncrypted
        $retries++
    }
    if ($encryptstatus -eq "VMRestartPending") {
        $restartStatus = Restart-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $linuxvm.name
        $encryptedVMs += $linuxvm
    }
}
#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls