The Copy-AzureStorageFilesFunctionApp Function copies files from one storage account to another in the same subscription. At this time while developing this function 9/13/2017,
   Azure Backup and snapshots are not supported for Azure File Storage.
   This function is written to be deployed as an Azure Function App and executed based on an hourly time trigger.
   It take a Resource Group name and subscription name as parameters.
   An email notification is sent to the Subscription Admin with a list of the items copied.
