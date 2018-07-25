beta package - [<img src="https://sabinio.visualstudio.com/_apis/public/build/definitions/573f7b7f-2303-49f0-9b89-6e3117380331/131/badge"/>](https://sabinio.visualstudio.com/Sabin.IO/_apps/hub/ms.vss-ciworkflow.build-ci-hub?_a=edit-build-definition&id=131)

# Migrate Azure SQL Datawarehouse Schemas
This repo will store the PowerShell Module that will be used to Migrate any changes to the schema from a source Azure Data Warehouse to a target Azure Data Warehouse. This does not migrate data!

## Deploy or Migrate?
Because SSDT does not support Azure DataWarehouse, there is no clear way to deploy changes to Azure SQL DW. What this module actually does is connect to a data warehouse that contains the source schema and migrates the changes over to the target data warehouse.

Note that data is not migrated over! 

## What Needs to Be Installed For Module To Work?
The following MSI's need to be installed on the box -  
* [Microsoft Online Services Sign-In Assistant for IT Professionals RTW](https://www.microsoft.com/en-us/download/confirmation.aspx?id=28177) 
* [Microsoft Active Directory Authentication Library for Microsoft SQL Server](https://www.microsoft.com/en-us/download/confirmation.aspx?id=48742) 
* [Microsoft ODBC Driver 13.1 for SQL Server](https://www.microsoft.com/en-us/download/details.aspx?id=53591)
* [Microsoft Command Line Utilities 13.1 for SQL Server](https://www.microsoft.com/en-us/download/details.aspx?id=53339) 

SSMS and SQL Server versions may come packaged with their own versions of these components, which may not work! So either uninstall/install these versions, or run on a separate box.  

## How Long Does a Migration Take?
If you're deploying an entire database, then it might take a while - in my testing a database with 200+ tables, 50+ views and over 200 procedures took about 10 minutes. After that, adding a single object takes about 30 seconds.

The more objects you have to deploy, and the more objects that exist in your source database, the longer a deployment takes, which is why it is best to deploy often to minimize the time taken and risk of failure.  

### What Objects Are Migrated?
Currently there are 10 Objects supported; 
1. Tables
2. Views
3. Schemas
4. Stored procedures
5. Scalar functions
6. External Data Sources
7. External File Formats
8. External Tables
9. Database-scoped Credentials
10. Database Master Key

In addition, columns added to tables that already exist on the server are migrated. 

### How Are Objects Migrated?
Some objects can be dropped and re-created; however where data loss is a possibility, this is obviously a very bad idea. Despite this, the process for all objects follows a similar pattern - 

* Connect to source database.
* Run a query that lists objects of a certain type (ie function, view etc.)
* For each object, connect to source database and generate a script to drop/create the object.
* If it needs to be run (see details for each object below) connect to target database and run drop/create script.

Below details individually how objects are migrated. 

#### Schemas
All user schemas are listed from source database and if they do not exist then are created on target database. This step needs to run prior to any other object as there may be a dependency.

#### External File Formats and External Data Sources
All of the External File Formats/Data Sources are listed from the target. For each of these objects, a SQL Command is created and executed on the target. Note it is only created if it does not exist - currnelty it is not possible to alter either of these obejcts without dropping and re-creating. This is complicated by the fact that you cannot drop either of these objects if there is an external table which references them. This option may or may not be added in the near future!

#### Database-Scoped Credentials
External Data Sources use database-scoped credentials to access the external data. If credential does nto exist it is created. however it if exists it is altered. This allows to modify the IDENTITY and SECRET of a credential.

Because it is not possible to read the SECRET from the source server, a PowerShell variable that matches the name of the credential set to the value of the secret must exist in order to set the SECRET. If this does not exist, then the Function will fail. It is possible to override this behaviour, as noted inteh the Get-Help for the function ```set-databasescopedcredentials```
```powershell
# .Parameter ContinueOnMissingSecrets
# If not all of your credentials require secrets, then you can include this switch. 
# .Parameter alterCredentialsWithSecretOnly
# Like the switch above, this will prevent secrets from being accidentally dropped on the target server if a PowerShell variable is not specified in the session.
# However unlike the Switch above that omits an error being thrown, this will continue to alter those credentials that have secrets set. 
```
#### Database Master Keys
As Credentials require database master keys to be created, the function ```New-AzureDatabaseMasterkey``` will create such a key. This needs to be explicitly executed with a password.

#### Functions, Views and Procedures
Details of objects are listed from source database. The source definition of the object is compared to the defintion on the target database. If the definitions do not match the object is dropped on the target and re-created. No data loss can occur.

Views in SQL Data Warehouse are metadata only. Consequently the following options are not available:

* There is no schema binding option
* Base tables cannot be updated through the view
* Views cannot be created over temporary tables
* There is no support for the EXPAND / NOEXPAND hints
* There are no indexed views in SQL Data Warehouse

Because of this, no data loss can occur.

#### Tables And External Tables
Tables are a little more complicated. There is a process to create tables that are not in target but are in source that follows the same process as the objects above, except that a stored procedure is created (usp_ConstructCreateStatementForTable for typical tables and usp_ConstructCreateStatementForExternalTable for external tables) and executed for each table that needs to be created.

External tables which differ are dropped before being re-created.  External tables which exist in the target database but not in the source database are dropped.

##### Managing table changes
The advice from Microsoft is never drop columns from an Azure DataWarehouse, only add more columns. Therefore at this time, only adding columns is supported through the migration method. The process to add columns is - 

* Create table in target database that will store all columns for all tables (this table is created as dbo.sourceColumns)
* Get sum of columns for each table on source, and do the same for target database
* Loop through all the rows from the source resultset and find the corresponding table in the target resultset
* If the number of rows match, do nothing, if they do not add details of columns from source table to sourceColumns table on target database. When this is complete execute a script that will add the columnsto the corresponding table on the target database.

This is the schema of the table that is created on the target database to store columns - 
  ```sql
CREATE TABLE [dbo].[sourceColumns]
(
	[databasename] [varchar](8000) NULL,
	[tablename] [varchar](8000) NULL,
	[colname] [sysname] NOT NULL,
	[user_type_id] [int] NULL,
	[column_id] [int] NULL
)
WITH
(
	DISTRIBUTION = ROUND_ROBIN,
	CLUSTERED COLUMNSTORE INDEX
)
```
##### What Happens if I Add Column in the Middle of a Table on the Source Database?
If you add a column in the middle of the table on the source database then the column will just be added to the end of the table on the target. Other than the look of the thing, it does not matter where your columns are in relation to one another. This is especially true for Clustered Columnstore tables. 

##### What Happens If I Rename a Column on the Source Database?
As of January 2018, according to [Microsoft Docs](https://docs.microsoft.com/en-us/sql/relational-databases/tables/rename-columns-database-engine), you cannot rename columns on Azure SQL Data Warehouse.   

##### What Happens If I Drop A Column on the Source Database?
Currently the behaviour is that it is not dropped on the target database. THere's plans to add a "drop in target not in source" type functionality at some point. 

##### What Happens to Table Changes on the Target Database When I Run Apply Changes from Source?
Basically, you're on your own. The idea of this module is to automate aligning databases from source to target. If you go and make changes to the target database not using this PowerShell Module then I don't really know how the changes will apply and there's a limit to how much can be anticipated.

#### Are There Any Other Objects Created on The Databases By This Module
Two stored procedures called ```usp_ConstructCreateStatementForTable``` and ```usp_ConstructCreateStatementForExternalTable``` are created, which is used to generated the ```CREATE <EXTERNAL> TABLE``` statement. This is created on the source database. The columns are added when the module runs ```AddTableChanges.sql```

#### What Happens If I Rename an Object on the Source Database?
As of January 2018, and as with columns, renaming objects is not supported by Azure SQL Data Warehouse.

### Authentication
Currently, the only authentication method supported by this module is Azure Active Directory Password Authentication. There is a huge amount of documentation on the [Microsoft Docs Website](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure#active-directory-password-authentication). However for brevities sake, in the ```Connect-SqlServer``` function, you can see that the connection string invoked sets the authentication type, as well as user name and password - 
```"Server = $SqlServerName; Database = $SqlDatabaseName; Authentication=Active Directory Password; UID = $Username; PWD = $Password;"```
The files that are created are executed using sqlcmd - throughout ```Export-CreateScriptsForObjects``` you will notice sqlcmd being used multiple times - 
```sqlcmd -i $FileWithCheckDefinitionQuery -S $SqlServerName -d $SqlDatabaseName -U $Username -P $Password -G -I -o $PathToOutput$ObjectName'_Check'.sql -v object_id=$ObjectId schema_id=$SchemaId  -y 0 -b -j ```

The -G option defines that sqlcmd uses Azure Active Directory for authentication. -U and -P Can still be used to pass the username and password.

### Permissions
 Because we are dropping and creating objects, as well as reading sys tables, db_owner on the table should be the minimum.

### How do I know what changes were migrated?
Any changes made to the target database are logged to a table called `DDLStatements`.  This table contains every DDL statement executed against the target database.  The function `Export-SchemaDDLStatements` can be used to save the DDL statements to a single file, or one file per object modified.


### How To
The below script will extract all the differences from the source database and apply them to the target database. This assumes you have both databases created, the relevant permissions setup,and that the source database has some objects to migrate over.  

The example also assumes that database are on seperate servers, but this does not have to be the case in real life.

```powershell
$SourceServerName = 'sourcedbserver.database.windows.net'
$TargetServerName = 'targetdbserver.database.windows.net'

$DatabaseName = 'SourceDB'
$targetDatabaseName = 'TargetDB'

# Get Credential for Source DB?
if ($SourceDBCredential) {Write-Host "Using saved credential for SourceDB.."} else {$SourceDBCredential = Get-Credential}
$SourceDBUsername = $SourceDBCredential.UserName
$SourceDBPassword = $SourceDBCredential.GetNetworkCredential().Password

# Get Credential for Target DB?
if ($TargetDBCredential) {Write-Host "Using saved credential for TargetDB.."} else {$TargetDBCredential = Get-Credential}
$TargetDBUsername = $TargetDBCredential.UserName
$TargetDBPassword = $TargetDBCredential.GetNetworkCredential().Password

#Source database connection..
$sourceDbcon = Connect-SqlServer -sqlServerName $SourceServerName -sqlDatabaseName $DatabaseName -userName $SourceDBUsername -password $SourceDBPassword

#Target database connection..
$targetDbcon = Connect-SqlServer -sqlServerName $TargetServerName -sqlDatabaseName $targetDatabaseName -userName $TargetDBUsername -password $TargetDBPassword


##########
#        #
# remove #
#        #
##########
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName 
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName 
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName 
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName 
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName                                                                                                       
# ##########
# #        #
# # export #
# #        #
# ##########

$date1=get-date

New-DDLStatementsTable -TargetDbCon $targetDbcon 

#Set-DatabaseScopedCredential -SourceDbcon $sourceDbcon -TargetDbCon $targetDbcon
Set-ExternalDataSource -SourceDbcon $sourceDbcon -TargetDbCon $targetDbcon
Set-ExternalFileFormat -SourceDbcon $sourceDbcon -TargetDbCon $targetDbcon

Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "Schemas"              -TargetDbCon $targetDbcon  
Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "Tables"               -TargetDbCon $targetDbcon  
Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "ExternalTables"       -TargetDbCon $targetDbcon 
Export-ColumnChanges           -SourceDbcon $sourceDbcon  -TargetDbCon $targetDbcon -TargetDBCredential $TargetDBCredential
Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "VIEW"                 -TargetDbCon $targetDbcon 
Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "SQL_SCALAR_FUNCTION"  -TargetDbCon $targetDbcon  
Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon  -ObjectType "SQL_STORED_PROCEDURE" -TargetDbCon $targetDbcon 

#Show DDL statements on console
Read-SchemaDDLStatements -Dbcon $targetDbcon | Format-Table -Wrap

# Save DDL statements to a single file
Export-SchemaDDLStatements -Dbcon $targetDbcon -OutputDirectory 'c:\temp' -OutputFileName 'DDLStatements.sql'

#.. or, save DDL statements to multiple files (1 file per db object modified - file name is "Schema.Objectname.sql")
Export-SchemaDDLStatements -Dbcon $targetDbcon -OutputDirectory 'c:\temp' -SplitByDatabaseObject  

Disconnect-SqlServer -sqlConnection $sourceDbcon
Disconnect-SqlServer -sqlConnection $targetDbcon



$taskTime = "Task took(HH:MM:SS:MS) "+(New-TimeSpan -Start $date1 -End (get-date))
write-Host $taskTime -ForegroundColor Yellow -BackgroundColor DarkGray
```
