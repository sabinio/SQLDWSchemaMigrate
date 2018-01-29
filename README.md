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

### How Are Objects Migrated?
Some objects can be dropped and re-created; however where data loss is a possibility, this is obviously a very bad idea. Despite this, the process for all objects follows a similar pattern - 

* Connect to source database.
* Run a query that lists a given object (ie function, view etc.)
* Foreach object, use sqlcmd to connect to source database and generate a script to dorp/create the object.
* If it needs to be run (see details for each object below) connect to target database and run drop/create script.

Below details individually how objects are migrated. 

#### Schemas
All user schemas are listed from source database and if they do not exist then are created on target database. This step needs to run prior to any other object as there may be a dependency.

#### Functions
All scalar functions are listed from source database. The definition is copied from the source to a table created on the target database called "sourceDefinitions". Ii the definitions in this table do not match the defintion of the object on the target database they are dropped and re-created. No data loss can occur.

#### Views
All scalar functions are listed from source database. The definition is copied from the source to a table created on the target database called "sourceDefinitions". Ii the definitions in this table do not match the defintion of the object on the target database they are dropped and re-created.
 
Views in SQL Data Warehouse are metadata only. Consequently the following options are not available:

* There is no schema binding option
* Base tables cannot be updated through the view
* Views cannot be created over temporary tables
* There is no support for the EXPAND / NOEXPAND hints
* There are no indexed views in SQL Data Warehouse

Because of this, no data loss can occur.

#### Stored Procedures
All scalar functions are listed from source database. The definition is copied from the source to a table created on the target database called "sourceDefinitions". Ii the definitions in this table do not match the defintion of the object on the target database they are dropped and re-created. No data loss can occur.


#### Tables
Tables are a little more complicated. There is a process to create tables that are not in target but are in source that follows the same process as the objects above, except that a stored procedure is created (usp_ConstructCreateStatementForTable) and executed for each table that needs to be created.

##### Managing table changes
The advice from Microsoft is never drop columns from an Azure DataWarehouse, only add more columns. Therefore at this time, only adding columns is supported through the migration method. The process to add columns is - 

* Create table in target database that will store all columns for all tables
* Loop through all the tables in the source database
* Loop through all the columns in the tables in the source database and insert into SourceColumns
* Execute script on target database that will compare current column list with new column list. If there is a difference then script will create an ALTER TABLE statement and execute it.

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
##### StoredDefinitions table
Views, stored procedures and scalar functions all have their definitions copied from the source database to the target database. This definition is then compared against the definition in sql_modules on the target database. If they do not match then the target database is updated to match the source. This is the schema od the table that is created on the target database - 

```sql

CREATE TABLE [dbo].[sourceDefinitions]
(
	[Databasename] [varchar](8000) NULL,
	[schemaName] [varchar](8000) NULL,
	[objectName] [varchar](8000) NULL,
	[object_definition] [varchar](max) NULL
)
WITH
(
	DISTRIBUTION = ROUND_ROBIN,
	HEAP
)
GO
```

Note that this table is used by all object types, but is dropped and re-created each time the ```Export-CreateScriptsForObjects``` function is called  for either views, stored procedures or scalar functions (ie for each object).

####Are There Any Other Objects Created on The Databases By This Module
A stored procedure called "usp_ConstructCreateStatementForTable" exists, which is used to generated the ```CREATE TABLE``` statement. The columns are added when the module runs ```AddTableChanges.sql```

###Authentication
Currently, the only authentication method supported by this module is Azure Active Directory Password Authentication. There is a huge amount of documentation on the [Microsoft Docs Website](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure#active-directory-password-authentication). However for brevities sake, in the ```Connect-SqlServer``` function, you can see that the connection string invoked sets the authentication type, as well as user name and password - 
```"Server = $SqlServerName; Database = $SqlDatabaseName; Authentication=Active Directory Password; UID = $Username; PWD = $Password;"```
The files that are created are executed using sqlcmd - throughout ```Export-CreateScriptsForObjects``` you will notice sqlcmd being used multiple times - 
```sqlcmd -i $FileWithCheckDefinitionQuery -S $SqlServerName -d $SqlDatabaseName -U $Username -P $Password -G -I -o $PathToOutput$ObjectName'_Check'.sql -v object_id=$ObjectId schema_id=$SchemaId  -y 0 -b -j ```

The -G option defines that sqlcmd uses Azure Active Directory for authentication. -U and -P Can still be used to pass the username and password.

###Permissions
 Because we are dropping and creating objects, as well as reading sys tables, db_owner on the table should be the minimum.

### How To
The below script will extract all the differences from the source database and apply them to the target database. This assumes you have both databases created, the relevant permissions setup,and that the source database has some objects to migrate over.  

The example also assumes that database are on seperate servers, but this does not have to be the case in real life.

```powershell

$ServerName = "myLittleServer.database.windows.net"
$DatabaseName = "AdwSourceDatabase"
$uName = "me"
$pword = "noPasswords4U!"

$targetDatabaseName = "AdwTargetDatabase"
$conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
$columnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
$targetConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $uName -password $pword
$targetColumnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $uName -password $pword

$listSchemasQuery = Get-ListQuery "Schemas" 
$listStoredProceduresQuery = Get-ListQuery "StoredProcedures"
$listTablesQuery = Get-ListQuery "Tables"
$listFunctionsQuery = Get-ListQuery "ScalarFunctions"
$listViewsQuery = Get-ListQuery "Views"

##########
#        #
# remove #
#        #
##########

Remove-CreateScriptForObjectsFiles $conn $listSchemasQuery "schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName                                                                                                                                         
Remove-CreateScriptForObjectsFiles $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName      

##########
#        
# export #
#        #
##########

Export-CreateScriptsForObjects $conn $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-ColumnChanges $conn $columnConn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -TargetColDbCon $targetColumnConn
Export-CreateScriptsForObjects $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName

Disconnect-SqlServer -sqlConnection $conn
Disconnect-SqlServer -sqlConnection $targetConn
Disconnect-SqlServer -sqlConnection $columnConn
Disconnect-SqlServer -sqlConnection $targetColumnConn
```
