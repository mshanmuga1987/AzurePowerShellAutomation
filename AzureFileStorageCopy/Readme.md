The Copy-AzureStorageFilesFunctionApp Function automates Azure Storage file sync to a separate storage account in the same subscription. At this time while developing this function 9/13/2017, Azure Backup and snapshots are not supported for Azure File Storage. 

It is deployed as a Time triggered PowerShell Azure Function App executed once at the top of every hour. It take a Resource Group name and subscription name as parameters. An email notification is sent to the Subscription Admin with a list of the items copied.
