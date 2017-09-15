<#
.SYNOPSIS
   The Copy-AzureStorageFilesFunctionApp Function copies files from one storage account to another in the same subscription.
.DESCRIPTION
   The Copy-AzureStorageFilesFunctionApp Function copies files from one storage account to another in the same subscription. At this time while developing this function 9/13/2017,
   Azure Backup and snapshots are not supported for Azure File Storage.
   This function is written to be deployed as an Azure Function App and executed based on an hourly time trigger.
   It take a Resource Group name and subscription name as parameters.
   An email notification is sent to the Subscription Admin with a list of the items copied.
.PARAMETER SubscriptionName
        Subscription to be processed.
.PARAMETER ResourceGroupName
        ResourceGroupName of the source and target storage accounts.
.EXAMPLE
        Copy-AzureStorageFilesFunctionApp            
.FUNCTIONALITY
        PowerShell Language
#>
[CmdletBinding()]

param(
    [parameter(Mandatory = $false)]
    [string]$SubscriptionName = "Trial",
    [parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "RGVPN"
       
)

#region Azure Logon
$Username = $env:AzureUsernameCredential
$EncryptedPassword = $env:AzurePasswordCredential
$AESKeyPath = "D:\home\site\wwwroot\TimerTriggerPowerShell1\bin\AESKey.key"
$SecurePassword = ConvertTo-SecureString -String $EncryptedPassword -Key (Get-Content -Path $AESKeyPath)
$Credential = New-Object -TypeName System.Management.Automation.PSCredential($Username, $SecurePassword)
Login-AzureRmAccount -Credential $Credential
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

#endregion

#region create email creds
$Smtpserver = "smtp.sendgrid.net"
$From = "jack.bauer@democonsults.com"
$To = "jack.bauer@democonsults.com"
$Port = "587"
$sendgridusername = "azure_a8a3e2815501214fbc3adf4ad15cc425@azure.com"
$sendgridPassword = $env:SendGridPasswordCredential
$emailpassword = ConvertTo-SecureString -String $sendgridPassword -Key (Get-Content -Path $AESKeyPath)
$emailcred = New-Object System.Management.Automation.PSCredential($sendgridusername, $emailpassword)
#endregion

#Initialize storage variables
$StorageAccountName = "storevpn0518"
$DestStorageAccountName = "store0518"
$DestResourceGroupName = "RGXavier"
$Store = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$Shares = Get-AzureStorageShare -Context $Store.context
$Deststore = Get-AzureRmStorageAccount -ResourceGroupName $DestResourceGroupName -Name $DestStorageAccountName
$Items = @()


foreach ($Share in $Shares) {
    $Directories = Get-AzureStorageFile -Share $Share

    foreach ($Directory in $Directories) {
        if ((Get-AzureStorageShare -Name $Share.Name -Context $Deststore.Context -ErrorAction SilentlyContinue) -eq $null) { 
            
            New-AzureStorageShare -Name $Share.Name -Context $Deststore.Context    
        }
        if ((Get-AzureStorageFile -ShareName $Share.Name -Context $Deststore.Context -Path $Directory.Name -ErrorAction SilentlyContinue) -eq $null) {
            New-AzureStorageDirectory -ShareName $Share.Name -Context $Deststore.Context -Path $Directory.Name               
                
        }
        $sourcefiles = Get-AzureStorageFile -ShareName $Share.Name -Context $Store.context -Path $Directory.Name | Get-AzureStorageFile        
        $destfiles = Get-AzureStorageFile -ShareName $Share.Name -Context $Deststore.Context -Path $Directory.Name -ErrorAction SilentlyContinue `
            | Get-AzureStorageFile
        if ($destfiles.count -eq 0) {
            foreach ($sourcefile in $sourcefiles) {
                Start-AzureStorageFileCopy -SrcShareName $Share.Name -SrcFilePath ($Directory.Name + "/" + $sourcefile.Name)  -Context $Store.Context `
                    -DestShareName $Share.Name -DestFilePath ($Directory.Name + "/" + $sourcefile.Name) -DestContext $Deststore.Context -ErrorAction SilentlyContinue
            }
        }
        else {
            foreach ($sourcefile in $sourcefiles) {
                $sourcefile.FetchAttributes()
                if ($sourcefile.Properties.LastModified.LocalDateTime -gt ((Get-Date).AddMinutes(-60)) ) {
                    Start-AzureStorageFileCopy -SrcShareName $Share.Name -SrcFilePath ($Directory.Name + "/" + $sourcefile.Name)  -Context $Store.Context `
                        -DestShareName $Share.Name -DestFilePath ($Directory.Name + "/" + $sourcefile.Name) -DestContext $Deststore.Context -Force -ErrorAction SilentlyContinue

                    $copyState = Get-AzureStorageFileCopyState -ShareName $Share.Name -FilePath ($Directory.Name + "/" + $sourcefile.Name) -Context $Deststore.Context `
                        -WaitForComplete -ErrorAction SilentlyContinue
                    $Items += $copyState
                }
            }
        }
    }
}

#region process email

$a = "<style>"
$a = $a + "BODY{background-color:white;}"
$a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}"
$a = $a + "TH{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "TD{border-width: 1px;padding: 10px;border-style: solid;border-color: black;}"
$a = $a + "</style>"
$body = ""
$body += "<BR>"
$body += "These" + " " + ($Items.count) + " " + "file storage items were processed for copy. Thank you."
$body += "<BR>"
$body += $Items | Select-Object -Property Status, @{"Label" = "Completion Time"; e = {$_.CompletionTime.LocalDateTime}}, @{"Label" = "Item"; e = {$_.Source.AbsolutePath}} | ConvertTo-Html -Head $a
$body = $body |Out-String
$subject = "These items were processed for copy."
if ($Items -ne $null) {
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