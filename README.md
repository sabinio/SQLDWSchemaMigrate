# Migrate Azure SQL Datawarehouse Schemas
This repo will store the PowerShell Module that will be used to Migrate any changes to the schema from a source Azure Data Warehouse to a target Azure Data Warehouse. This does not migrate data!

## Deploy or Migrate?
Because SSDT does not support Azure DataWarehouse, the current project in DataServices generates the deployment scripts. However there is not way to migrate these changes from one data warehouse to another. What this module actually does is connect to a data warehouse that contains the source schema and migrates the changes over to the target data warehouse.

Note that data is not migrated over! 

## What Needs to Be Installed For Module To Work?
The following MSI's need to be installed on the box -  
* [Microsoft Online Services Sign-In Assistant for IT Professionals RTW](https://www.microsoft.com/en-us/download/confirmation.aspx?id=28177) 
* [Microsoft Active Directory Authentication Library for Microsoft SQL Server](https://www.microsoft.com/en-us/download/confirmation.aspx?id=48742) 
* [Microsoft ODBC Driver 13.1 for SQL Server](https://www.microsoft.com/en-us/download/details.aspx?id=53591)
* [Microsoft Command Line Utilities 13.1 for SQL Server](https://www.microsoft.com/en-us/download/details.aspx?id=53339) 

SSMS and SQL Server versions may come packaged with their own versions of these components, which may not work! So either uninstall/install these versions, or run on a seperate box.  

## How Long Does a Migration Take?
If you're deploying an entire database, then it might take a while - in my testing a database with 200+ tables, 50+ views and over 200 procedures took about 10 minutes. After that, adding a single object takes about 30 seconds.

The more objects you have to deploy, and the more objects that exist in your source database, the longer a deployment takes, which is why it is best to deploy often to minimize the time taken and risk of failure.  

### What Objects Are Migrated?
Currently there are 5 Objects supported; 
1. tables
2. views
3. schemas
4. stored procedures
5. scalar functions. 

There is a need to add the following - 
1. External Data Sources
2. External File Formats
3. External Tables

### How Are Objects Migrated?
Some objects can be dropped and re-created; however where data loss is a possibility, this is obviously a very bad idea. Despite this, the process for all objects follows a similar pattern - 

* Connect to source database.
* Run a query that lists a given object (ie function, view etc.)
* Foreach object, connect to source database and generate a script to drop/create the object.
* If it needs to be run (see details for each object below) connect to target database and run drop/create script.

Below details individually how objects are migrated. 

#### Schemas
All user schemas are listed from source database and if they do not exist then are created on target database. This step needs to run prior to any other object as there may be a dependency.

#### Functions, Views and Procedures
Details of objects are listed from source database. The source definition of the object is compared to the defintion on the target database. If the definitions do not match the object is dropped on the target and re-created. No data loss can occur.

Views in SQL Data Warehouse are metadata only. Consequently the following options are not available:

* There is no schema binding option
* Base tables cannot be updated through the view
* Views cannot be created over temporary tables
* There is no support for the EXPAND / NOEXPAND hints
* There are no indexed views in SQL Data Warehouse

Because of this, no data loss can occur.

#### Tables
Tables are a little more complicated. There is a process to create tables that are not in target but are in source that follows the same process as the objects above, except that a stored procedure is created (usp_ConstructCreateStatementForTable) and executed for each table that needs to be created.

##### Managing table changes
The advice from Microsoft is never drop columns from an Azure DataWarehouse, only add more columns. Therefore at this time, only adding columns is supported through the migration method. The process to add columns is - 

* Create table in target database that will store all columns for all tables (this table is created as dbo.sourceColumns)
* Get sum of columns for each table on source, and do the same for target database
* Loop through all the rows fom the source resultset and find the corresponding table in the target resultset
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
Currently the behaviour  is that it is not dropped on the target database. THere's plans to add a "drop in target not in source" type functionality at some point. 

##### What Happens to Table Changes on the Target Database When I Run Apply Changes from Source?
Basically, you're on your own. The idea of this module is to automate aligning databases from source to target. If you go and make changes to the target database not using this PowerSHell Module then I don't really know how the changes will apply and there's a limit to how much can be anticipated.

#### Are There Any Other Objects Created on The Databases By This Module
A stored procedure called "usp_ConstructCreateStatementForTable" exists, which is used to generated the ```CREATE TABLE``` statement. This is created on the source database. The columns are added when the module runs ```AddTableChanges.sql```

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

### Where Are Created Files Stored?
Currently no files are being created. This feature may change! 

~~ On both ```Remove-CreateScriptForObjectsFiles``` and ```Export-CreateScriptsForObjects``` there is a parameter called ```$outputDir```. Set this to the location you want the "CREATE" statements saved to. If this parameter is not used then ```$PSScriptRoot``` is used. EG - 
```powershell
  if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
            $OutputDirectory = $PSScriptRoot
	}
```

### Are There Any Files That Are Not Created?
The "ALTER" statements for applying COLUMN changes are not generated. Instead a print statement is generated for logging purposes.~~

### How To
The below script will extract all the differences from the source database and apply them to the target database. This assumes you have both databases created, the relevant permissions setup,and that the source database has some objects to migrate over.  

The example also assumes that database are on seperate servers, but this does not have to be the case in real life.

```powershell

$ServerName = "myLittleServer.database.windows.net"
$DatabaseName = "AdwSourceDatabase"
$targetDatabaseName = "AdwTargetDatabase"
$uName = "me"
$pword = "noPasswords4U!"

$conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword
$targetConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $aaduName -password $aadpword
$columnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword

$listSchemasQuery = Get-ListQuery "Schemas" 
$listStoredProceduresQuery = Get-ListQuery "StoredProcedures"
$listTablesQuery = Get-ListQuery "Tables"
$listFunctionsQuery = Get-ListQuery "ScalarFunctions"
$listViewsQuery = Get-ListQuery "Views"
$listColumnsQuery = Get-ListQuery "Columns"

##########
#        #
# remove #
#        #
##########
# Remove-CreateScriptForObjectsFiles $conn $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles                                                                                                                                        
# ##########
# #        #
# # export #
# #        #
# ##########

$date1=get-date

Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listSchemasQuery -ObjectType "Schemas" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles -verbose
Export-CreateScriptsForObjects -DbCon $conn -TableCon $columnConn -QueryForObjectList $listTablesQuery -ObjectType "Tables" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles -verbose
Export-ColumnChanges -DbCon $conn $columnConn $listColumnsQuery -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetColDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -OutputDirectory $pathToSaveFiles -verbose
Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listViewsQuery -ObjectType "VIEW" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles -verbose
Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listFunctionsQuery -ObjectType "SQL_SCALAR_FUNCTION" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles -verbose
Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listStoredProceduresQuery -ObjectType "SQL_STORED_PROCEDURE" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles -verbose

Disconnect-SqlServer -sqlConnection $conn
Disconnect-SqlServer -sqlConnection $targetConn

Disconnect-SqlServer -sqlConnection $columnConn
Disconnect-SqlServer -sqlConnection $targetColumnConn

$date2=get-date
$taskTime = "Task took(HH:MM:SS:MS) "+(New-TimeSpan -Start $date1 -End $date2)
write-Host $taskTime -ForegroundColor DarkGreen -BackgroundColor DarkGray
```
