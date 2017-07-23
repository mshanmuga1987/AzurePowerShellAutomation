#This function deploys a Managed Disk Azure VM running CentOS 7.3 Linux with the LAMP Stack using an ARM Template.
#The Azure CentOS VM will be generalized and used to create a Managed Image in a seperate Resource Group
#for provisioning multiple VMs.
Param(
$Location = "southcentralus",
$SubscriptionName = "Free Trial",
$ResourceGroupName = "RGXavier",
$StorageAccountName = "store0518",
$VaultName = "vaultspr",
$KeyName = "EncryptKey",
$TemplateUriLinux = "https://store0518.blob.core.windows.net/templates/ManagedDiskLinuxVM.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D",
$TemplateParameterUriLinux = "https://store0518.blob.core.windows.net/templates/VMSecretParameters.json?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"

)

#Login-AzureRmAccount

$connectionName = "AzureRunAsConnection"

#Azure Logon
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
            }
    }
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#Remove existing resources and vhds if any
try{
Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName | ?{$_.ResourceName -ne $VaultName -and $_.ResourceName -ne $StorageAccountName} | Remove-AzureRmResource -Force
}catch{ $ErrorMessage = $_ 
    throw $ErrorMessage }

#region
#Deploy VM ARM Template
Write-Host -Object ("Started $(Get-Date)")
$armdeploy = New-AzureRmResourceGroupDeployment -Name ManagedDiskLinuxVM -ResourceGroupName $ResourceGroupName `
-DeploymentDebugLogLevel All -TemplateUri $TemplateUriLinux -TemplateParameterUri $TemplateParameterUriLinux -Verbose
#endregion

#Get Completed VMs
$vms = Get-AzureRmVM -ResourceGroupName $ResourceGroupName | ?{$_.OSProfile.LinuxConfiguration -ne $null}


#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls