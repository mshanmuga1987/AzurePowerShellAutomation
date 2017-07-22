﻿<#Create Managed Images from Managed Disk VMs in different Resource Group.Then Create Managed VMs from the Images (Centos 7.3 Linux)
/#>
Param(
$Location = "southcentralus",
$SourceSubscriptionName = "Free Trial",
$SourceResourceGroupName = "RGXavier",
$TargetResourceGroupName = "RGManagedDisks",
$VMSize = "Standard_A5",
$VMName = "centos73vm",
$SourceVMName = "centos73vm",
$SubscriptionName = "Free Trial",
$ImageName = "centos73Image",
$Fqdn = "centos73vm.southcentralus.cloudapp.azure.com",
$sshusername = "root",
$sshpassword = "7227-voya"
)

#region Azure Logon
$connectionName = "AzureRunAsConnection"
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

#endregion

#region
#Generalize source Resource Group VM. SSH into source Linux VM and run deprovision command
New-SshSession -ComputerName $Fqdn -Username $sshusername -Password $sshpassword
Get-SshSession
$result = Invoke-SshCommand -ComputerName $Fqdn -Command "sudo waagent -deprovision -force"
Stop-AzureRmVM -ResourceGroupName $SourceResourceGroupName -Name $SourceVMName -Force
Set-AzureRmVM -ResourceGroupName $SourceResourceGroupName -Name $SourceVMName -Generalized

#endregion

#region
#Initialize and create new managed image from source Resource Group VM
$disks = Get-AzureRmDisk -ResourceGroupName $SourceResourceGroupName
$imageConfig = New-AzureRmImageConfig -Location $Location
$imageConfig = Set-AzureRmImageOsDisk -Image $imageConfig -OsType Linux -OsState Generalized -ManagedDiskId $disks[0].Id
New-AzureRmImage -ResourceGroupName $TargetResourceGroupName -ImageName $ImageName -Image $imageConfig

#endregion

#region
#Create nic, pip and vnet resources for the VM
$myvmpassword = ConvertTo-SecureString -String "7227-voya" -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential("slocal",$myvmpassword)
$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -AddressPrefix "192.168.1.0/27"
$vNet = New-AzureRmVirtualNetwork -Name vnet -ResourceGroupName $TargetResourceGroupName -Location $Location -AddressPrefix "192.168.1.0/24" -Subnet $subnet
$pip = New-AzureRmPublicIpAddress -Name pip -ResourceGroupName $TargetResourceGroupName -Location $Location -AllocationMethod Dynamic -IpAddressVersion IPv4 -DomainNameLabel ($VMName + "1")
$pip =Get-AzureRmPublicIpAddress -Name pip -ResourceGroupName $TargetResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name subnet1 -VirtualNetwork $vNet
$nic = New-AzureRmNetworkInterface -Name nic -ResourceGroupName $TargetResourceGroupName -Location $Location -Subnet $subnet -PublicIpAddress $pip

#Initialize virtual machine configuration and create VM from image
$image = Get-AzureRmImage -ResourceGroupName $TargetResourceGroupName -ImageName $ImageName
$vm = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
$vm = Set-AzureRmVMSourceImage -VM $vm -Id $image.Id
$vm = Set-AzureRmVMOSDisk -VM $vm -StorageAccountType StandardLRS -DiskSizeInGB 60 -CreateOption FromImage -Caching ReadWrite
$vm = Set-AzureRmVMOperatingSystem -VM $vm -ComputerName $VMName -Linux -Credential $credential
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
$vm = New-AzureRmVM -ResourceGroupName $TargetResourceGroupName -Location $Location -VM $vm

#endregion

#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls