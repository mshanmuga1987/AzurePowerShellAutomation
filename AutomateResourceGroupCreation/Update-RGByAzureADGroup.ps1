<# 
.SYNOPSIS
   PowerShell function to automate the creation and removal of Azure Resource Groups based on Azure AD Group membership in an Azure subscription.

.DESCRIPTION
   PowerShell function to automate the creation and removal of Azure Resource Groups based on Azure AD Group membership in an Azure subscription.
   Resource groups are automatically provisioned or removed based on the modifications to an Azure AD security group membership(adding or removing members).
   The function can be deployed as a Runbook in an Azure Automation account and scheduled to run once a day.

.PARAMETER Subscription Name
        Subscription to be processed.

.FUNCTIONALITY
        PowerShell Language
/#>

param(
            [parameter(Mandatory=$false)]
            [string]$subscriptionName = "Free Trial"
            
        )

#region Azure Logon 
$adAppId = Get-AutomationVariable -Name “AutomationAppId” 
$tenantId = Get-AutomationVariable -Name “AutomationTenantId” 
$subscriptionId = Get-AutomationVariable -Name "AutomationSubscriptionId” 
$cert = Get-AutomationCertificate -Name “AutomationCertificate” 
$certThumbprint = ($cert.Thumbprint).ToString() 
Login-AzureRmAccount -ServicePrincipal -TenantId $tenantId -ApplicationId $adAppId -CertificateThumbprint $certThumbprint 
Connect-AzureAD -TenantId $tenantId -ApplicationId $adAppId -CertificateThumbprint $certThumbprint Select-AzureRmSubscription -SubscriptionName $subscriptionName 
#endregion

Select-AzureRmSubscription -SubscriptionName $subscriptionName

$RGPrefix = "RGCloudGroup_"
$Location = "southcentralus"
$cloudGroupObj = Get-AzureADGroup -SearchString "Cloud Group"
$cloudGroupMembers = Get-AzureADGroupMember -ObjectId $cloudGroupObj.ObjectId
$groupMembersDisplayNames=Get-AzureADGroupMember -ObjectId $cloudGroupObj.ObjectId |%{($_.MailNickName)}
$rgNamesSplit=@(Get-AzureRmResourceGroup  |? ResourceGroupName -like "*RGCloudGroup_*"| %{$_.ResourceGroupName.Split("_",2)[1]})
if($rgNamesSplit.Count -eq 0){
      foreach($cloudGroupMember  in $cloudGroupMembers){
        $rgsuffix = ($cloudGroupMember.MailNickName)
        $clouduser=Get-AzureADUser -SearchString $cloudGroupMember.MailNickName
        $tags = @{
                   CreatedBy = "Automation"
                   Department = "CloudGroup"
                   }
        $rgObj = New-AzureRmResourceGroup -Name ($RGPrefix + $rgsuffix) -Tag $tags -Location $Location
        New-AzureRmRoleAssignment -ResourceGroupName ($rgObj.ResourceGroupName) -RoleDefinitionName Owner -ObjectId $clouduser.ObjectId -ErrorAction SilentlyContinue
        }  
    }else{
$compares=Compare-Object -ReferenceObject $groupMembersDisplayNames -DifferenceObject $rgNamesSplit
foreach($compare in $compares){
    if($compare.SideIndicator -eq "<="){
    $newMember=$compare.InputObject
    $rgsuffix = $newMember
    $cloudUser = Get-AzureADUser -SearchString $newMember
        $tags = @{
                   CreatedBy = "Automation"
                   Department = "CloudGroup"
                   }
        $rg=Get-AzureRmResourceGroup -Name ($RGPrefix + $rgsuffix) -ErrorAction SilentlyContinue       
        if($rg -eq $null){
        $rgObj = New-AzureRmResourceGroup -Name ($RGPrefix + $rgsuffix) -Tag $tags -Location $Location
        New-AzureRmRoleAssignment -ResourceGroupName ($rgObj.ResourceGroupName) -RoleDefinitionName Owner -ObjectId $cloudUser.ObjectId -ErrorAction SilentlyContinue
        }
}elseif($compare.SideIndicator -eq "=>"){
$removedMember=$compare.InputObject
Remove-AzureRmResourceGroup -Name ($RGPrefix + $removedMember) -Force -ErrorAction SilentlyContinue
        }
    }
}


#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls