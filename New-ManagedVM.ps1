<# 
.SYNOPSIS
   PowerShell function to create a new Managed Disk Azure VM
.DESCRIPTION
   PowerShell function to create a new Managed Disk Azure linux VM.
   It calls a Custom Script Extension type that invokes a bash script to install the LAMP Stack software
   components in the Azure Linux VM runnning CentOS 6.8. It can be deployed as a runbook and triggered via a set schedule or webhook.
   An example on how to use the extension can be found at:
   https://docs.microsoft.com/en-us/powershell/module/azurerm.compute/set-azurermvmextension?view=azurermps-4.2.0
.PARAMETER SubscriptionName
        Subscription to be processed
.PARAMETER ResourceGroupName
        Resource Group in which the Azure VM will be provisioned
.FUNCTIONALITY
        PowerShell Language
/#>
Param(
$SubscriptionName = "Free Trial",
$Location = "southcentralus",
$ResourceGroupName = "RGManagedDisks"
)


#Azure Logon
try
{
    $connectionName = "AzureRunAsConnection"
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

#Remove the defined Resources if the Resource Group currently exists

try{
        "Removing existing Resources"
        Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName | Remove-AzureRmResource -Force
}catch {
        $ErrorMessage = "Resource Group $ResourceGroupName not found."
        Write-Host $ErrorMessage
        }

#Recreate the Resource Group if not Available

try
{
    # Get the ResourceGroup "RGManagedDisks "
    $ResourceGroup= Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop         
}
catch {
        $ErrorMessage = "Resource Group $ResourceGroupName not found.Creating Target Resource Group"
        Write-Host $ErrorMessage
        New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force
    }
    $ResourceGroup= Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location


#Create Managed Disk VM
# Define a credential object
$VaultName = "vaultspr"
$SecretName = "vmadminpassword"
$myvmpassword = (Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValue
$credential = New-Object -TypeName System.Management.Automation.PSCredential("slocal",$myvmpassword)

#Create VM properties
$VMName = "centos68vm"
$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -AddressPrefix "192.168.1.0/27"
$vNet = New-AzureRmVirtualNetwork -Name vnet -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "192.168.1.0/24" -Subnet $subnet
$pip = New-AzureRmPublicIpAddress -Name pip -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic -IpAddressVersion IPv4 -DomainNameLabel $VMName
$pip =Get-AzureRmPublicIpAddress -Name pip -ResourceGroupName $ResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -VirtualNetwork $vNet
$nic = New-AzureRmNetworkInterface -Name nic -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $subnet -PublicIpAddress $pip

# Create a virtual machine configuration
$vm = New-AzureRmVMConfig -VMName $VMName -VMSize "standard_A5" | `
    Set-AzureRmVMOperatingSystem -Linux -ComputerName managedDiskVm -Credential $credential | `
    Set-AzureRmVMSourceImage -PublisherName OpenLogic -Offer CentOS `
    -Skus "6.8" -Version latest | Add-AzureRmVMNetworkInterface -Id $nic.Id
$vm = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vm

#Deploy LAP Stack via VMExtension
$LampUri = "https://store0518.blob.core.windows.net/templates/lamp68-setup.sh?sv=2016-05-31&ss=b&srt=sco&sp=rwdlac&se=2017-12-21T00:51:20Z&st=2017-06-20T16:51:20Z&spr=https&sig=f%2FLnz4u40U0tGdmxBDfO6VgWdhHzj%2BRJMVK8UjMKTUI%3D"
$Settings = @{"fileUris"= @($LampUri);"commandToExecute"="sh lamp68-setup.sh"}
Set-AzureRmVMExtension -Publisher Microsoft.Azure.Extensions -ResourceGroupName $ResourceGroupName -VMName $VMName `
-Name CustomScript -Settings $Settings -TypeHandlerVersion 2.0 -Location $Location -ExtensionType CustomScript


#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls