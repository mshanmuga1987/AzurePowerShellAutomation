#This function creates a new Managed Disk Azure VM.
Param(
$Location = "southcentralus",
$SubscriptionName = "Free Trial",
$SourceResourceGroupName = "RGXavier",
$ResourceGroupName = "RGManagedDisks",
$StorageAccountName = "store0518"
)

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
$myvmpassword = ConvertTo-SecureString -String "7227-voya" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential("slocal",$myvmpassword)


$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -AddressPrefix "192.168.1.0/27"
$vNet = New-AzureRmVirtualNetwork -Name vnet -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "192.168.1.0/24" -Subnet $subnet
$pip = New-AzureRmPublicIpAddress -Name pip -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Dynamic -IpAddressVersion IPv4 -DomainNameLabel "manageddiskvm"
$pip =Get-AzureRmPublicIpAddress -Name pip -ResourceGroupName $ResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -VirtualNetwork $vNet
$nic = New-AzureRmNetworkInterface -Name nic -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $subnet -PublicIpAddress $pip

# Create a virtual machine configuration
$vm = New-AzureRmVMConfig -VMName managedDiskVm -VMSize "standard_A5" | `
    Set-AzureRmVMOperatingSystem -Linux -ComputerName managedDiskVm -Credential $credential | `
    Set-AzureRmVMSourceImage -PublisherName OpenLogic -Offer CentOS `
    -Skus "6.8" -Version latest | Add-AzureRmVMNetworkInterface -Id $nic.Id
$vm = New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vm

#Clean up scripts 
#$resources = Find-AzureRmResource -ResourceGroupNameContains $ResourceGroupName
#$resources | Remove-AzureRmResource -Force

#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls