#Function Check-StorageAccountLogsv2{
<#
.SYNOPSIS
  Function checks for the presence of Read/Write logtype activity and returns a boolean.
 .DESCRIPTION
  Function checks for the presence of Read/Write log activity and returns a boolean. It can check any of the storage account service types.
  Please note that Azure File storage currently supports Storage Analytics metrics, but does not yet support logging.
  https://docs.microsoft.com/en-us/azure/storage/storage-monitor-storage-account#configure-logging
 .PARAMETER StorageAccountName
  Storage Account Name of the Storage Object.
 .PARAMETER ResourceGroupName
  ResourceGroupName of the storage account .
 .PARAMETER ServiceType
  ServiceType to be checked against
 .PARAMETER LogType
  LogType activity to be checked for. Valid values are read, write, delete
 .EXAMPLE
  # Checking for Logs
  Check-StorageAccountLogsv2 -StorageAccountName "testSA" -ResourceGroupName "testRG" -ServiceType Blob -LogType read
/#>
Param(
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "storage1218",
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "rglab",
    [Parameter(Mandatory=$false)]
    [validateset("Blob","Table","Queue")]
    [string]$ServiceType = "Blob",
    [Parameter(Mandatory=$false)]
    [validateset("write","read","delete")]
    [string]$LogType = "write"
    )
#Login-AzureRmAccount
$logCheck = $false
[string]$Year = (Get-Date).Year # current year in format "YYYY"
[string]$Month = (Get-Date).GetDateTimeFormats()[3].Substring(0,2) #current month in format "MM"
[string]$Day = (Get-Date).AddDays(-1).GetDateTimeFormats()[3].Substring(3,2) # last 2 days in format "DD"
$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
$servicetypeName = $ServiceType+"/"+$Year+"/"+$Month+"/"+$Day

#Determine current state of storage logging for service type blob
$loggingState = Get-AzureStorageServiceLoggingProperty -ServiceType $ServiceType -Context $storageAccount.Context
if($loggingState.LoggingOperations -eq "None"){
    # Enabling Logging.There will be no log readings for atleast 1 hour"
    Set-AzureStorageServiceLoggingProperty -ServiceType $ServiceType -LoggingOperations All -RetentionDays 5 -Context $storageAccount.Context

}else{
    #Attempt to get available logs for the specified log type
    $storageLogs = Get-AzureStorageBlob -Container '$logs' -Context $storageAccount.Context | ?{$_.Name -match "$servicetypeName" -and $_.ICloudBlob.Metadata.LogType -match "$LogType"} `
    | %{"{0}, {1}, {2}, {3}" -f $_.Name, $_.ICloudBlob.Metadata.StartTime, $_.ICloudBlob.Metadata.EndTime, $_.ICloudBlob.Metadata.LogType}
}
if($storageLogs.Count -ne 0){$logCheck = $true}
$logCheck

#Get-Variable | Remove-Variable -ErrorAction SilentlyContinue
#cls
#}

