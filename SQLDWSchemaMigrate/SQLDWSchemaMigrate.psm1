foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1")) {
    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

function Export-CreateScriptsForObjects {
    <#
	.Synopsis
	Used to generate CREATE statements for objects on source database that can be migrated to target database 
	.Description
    Based on object we are migrating, execute a query on source database to get objects of a certain type, and generate CREATE statements. 
    Where no data loss can occur, we drop and recreate if the definitions between source and target are not identical.
	.Parameter dbcon
    Connection to source database. Used to get list of all objects on source database (ie executes QueryForObjectList)
    .Parameter tableCon
    Connection to source database. Used for getting create statements.
    .Parameter QueryForObjectList
    Query to list all objects. See Get-ListQuery Function to see query that is passed in.
    .Parameter ObjectType
    The type of object we are migrating. Used for if statements as not all objects queries return the same columns and sqlcmd requires different variables
    .Parameter targetDbCon
    Connection to target database. Used to apply create files to.
    .Parameter OutputDirectory
    Currently not in use, will be used eventually!
	.Example
    Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listSchemasQuery -ObjectType "Schemas" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles
    #>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [System.Data.SqlClient.SqlConnection]$TableCon, 
        [string]$QueryForObjectList, 
        [string]$ObjectType,
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        [String]$OutputDirectory ) 

    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $PSScriptRoot
    }
    switch ($ObjectType) {
        "SQL_STORED_PROCEDURE" {$TypeForDropStatement = 'PROCEDURE'; break}
        "SQL_SCALAR_FUNCTION" {$TypeForDropStatement = 'FUNCTION'; break}
        "VIEW" {$TypeForDropStatement = 'VIEW'; break}
        default {break}
    }
    $ReCreateusp_ConstructCreateStatementForTable = 0
    [System.Collections.ArrayList]$FilePaths = @()
    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $DbCon
    $GetObjectListCmd.CommandText = $QueryForObjectList
    $ObjectListReader = $GetObjectListCmd.ExecuteReader();
    if ($ObjectListReader.HasRows) {
        $AddDefinitionListCmd = New-Object System.Data.SqlClient.SqlCommand
        $AddDefinitionListCmd.Connection = $TargetDbCon
        while ($ObjectListReader.Read()) {
            if ($objectType -in "SQL_STORED_PROCEDURE", "SQL_SCALAR_FUNCTION", "VIEW") {
                $SchemaName = $ObjectListReader.GetString(0)
                $ObjectName = $ObjectListReader.GetString(1)
                $ObjectId = $ObjectListReader.GetInt32(2)
                $definitionForFile = $ObjectListReader.GetString(4)
                $sqlCommandText = "select mod.definition from sys.objects obj inner join sys.schemas sch on obj.schema_id = sch.schema_id inner join [sys].[sql_modules] mod on mod.object_id = obj.object_id where obj.type_desc = '$ObjectType' and sch.name = '$schemaName' and obj.name = '$objectName';"
                $AddDefinitionListCmd.CommandText = "SET NOCOUNT ON;
                $sqlCommandText"
                $executeCreateOnTarget = 0
                $executeDropOnTarget = 0
                $gren = $AddDefinitionListCmd.ExecuteScalar();
                if ($null -eq $gren) {
                    $executeCreateOnTarget = 1
                }
                else {
                    $diff = Compare-Object $gren $definitionForFile
                    if ($null -ne $diff) {
                        $executeDropOnTarget = 1
                        $executeCreateOnTarget = 1
                    }
                }
                if ($executeDropOnTarget -eq 1) {
                    Write-Host "Dropping object [$SchemaName].[$ObjectName] of type $ObjectType on target."
                    $AddDefinitionListCmd.CommandText = "DROP $TypeForDropStatement [$SchemaName].[$ObjectName]"
                    try {
                        $AddDefinitionListCmd.ExecuteScalar();    
                    }
                    catch {
                        throw $_.Exception
                    }
                }
                if ($executeCreateOnTarget -eq 1) {
                    Write-Host "Creating object [$SchemaName].[$ObjectName] of type $ObjectType on target."
                    $AddDefinitionListCmd.CommandText = $definitionForFile
                    try {
                        $AddDefinitionListCmd.ExecuteScalar();    
                    }
                    catch {
                        throw $_.Exception
                    }
                    
                }
                elseif (($executeCreateOnTarget -eq 0) -and ($executeDropOnTarget -eq 0) ) {
                    Write-Verbose "No changes to make to object [$SchemaName].[$ObjectName] of type $ObjectType"
                }
            }
            elseif ($ObjectType -eq "Schemas") {
                $SchemaName = $ObjectListReader.GetString(0)
                $AuthorisationName = $ObjectListReader.GetString(1)
                $AddDefinitionListCmd.CommandText = "
                IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$SchemaName')
                SELECT 0
                ELSE
                SELECT 1"
                $schemaExists = $AddDefinitionListCmd.ExecuteScalar();
                if ($schemaExists -eq 0) {
                    $AddDefinitionListCmd.CommandText = "CREATE SCHEMA $schemaName AUTHORIZATION $AuthorisationName"
                    Write-Host "Creating schema $schemaName with authorisation $AuthorisationName"
                    try {
                        $AddDefinitionListCmd.ExecuteScalar();    
                    }
                    catch {
                        throw $_.Exception
                    }
                }
                elseif ($schemaExists -eq 0) {
                    Write-Verbose "Schema [$SchemaName] already exists..."
                }
            }
            elseif ($ObjectType -eq "Tables") {
                $ExecuteCreateTable = New-Object System.Data.SqlClient.SqlCommand
                $ExecuteCreateTable.Connection = $TableCon
                $SchemaName = $ObjectListReader.GetString(0)
                $ObjectName = $ObjectListReader.GetString(1)
                $ObjectId = $ObjectListReader.GetInt32(2)
                if ($ReCreateusp_ConstructCreateStatementForTable -eq 0) {
                    Write-Verbose "Recreating usp_ConstructCreateStatementForTable on database $DatabaseName"
                    $AddDefinitionListCmd.CommandText = "IF OBJECTPROPERTY(object_id('usp_ConstructCreateStatementForTable'),  'IsProcedure') = 1
                    DROP PROCEDURE usp_ConstructCreateStatementForTable"
                    $AddDefinitionListCmd.ExecuteNonQuery();
                    $AddDefinitionListCmd.CommandText = Get-Content $PSScriptRoot\sql\usp_ConstructCreateStatementForTable.sql
                    $AddDefinitionListCmd.ExecuteNonQuery();
                    $ReCreateusp_ConstructCreateStatementForTable = 1                    
                }
                Write-Verbose "Checking if [$SchemaName].[$ObjectName] exists on target server..."
                $AddDefinitionListCmd.CommandText = "
                if not exists
                (
                    select obj.name as object_name from sys.tables obj inner join sys.schemas sch on obj.schema_id = sch.schema_id 
                    where sch.name = '$schemaName' and obj.name = '$objectName'
                )
                SELECT 1
                ELSE
                SELECT 0
                "
                $TableExists = $AddDefinitionListCmd.ExecuteScalar();
                if ($TableExists -eq 1) {
                    Write-Host "Generating CREATE TABLE Script for [$SchemaName].[$ObjectName] and executing on target database..."  
                    $sqlCommandText = "    
                        DECLARE @objectId AS BIGINT;
                        SET @objectId = $ObjectId;
                        DECLARE @schemaName AS [VARCHAR](50);
                        DECLARE @tableName [VARCHAR](255);

                        SET @schemaName = (SELECT sch.[name]
                                        FROM [sys].[objects] obj
                                        INNER JOIN [sys].[schemas] sch
                                        ON obj.[schema_id] = [sch].[schema_id]
                                        WHERE obj.[object_id] = @objectId);
                        SET @tableName = (SELECT obj.[name]
                                        FROM [sys].[objects] obj
                                        WHERE obj.[object_id] = @objectId);

                        DECLARE @sqlCmd AS VARCHAR(8000);
                        EXEC [usp_ConstructCreateStatementForTable] @schemaName, @tableName, '', @sqlCmd OUTPUT;
                        SELECT @sqlCmd;"
                    $ExecuteCreateTable.CommandText = $sqlCommandText 
                    $CreateStatement = $ExecuteCreateTable.ExecuteScalar()
                    try {
                        $AddDefinitionListCmd.CommandText = $CreateStatement
                        $AddDefinitionListQuery = $AddDefinitionListCmd.ExecuteNonQuery()
                        $AddDefinitionListQuery | Out-Null
                    }
                    catch {
                        $ohDear = "$CreateStatement `n failed with the following error - $($_.Exception)"
                        throw $ohDear
                    }
                }
                elseif ($tableExists -eq 0) {
                    Write-Verbose "Table [$SchemaName].[$ObjectName] already exists..."
                }
            }
        }
    }
    $ObjectListReader.Close()
}

Function Remove-CreateScriptForObjectsFiles {
    <#
	.Synopsis
	Used to generate CREATE statements for objects on source database that can be migratedto target database 
	.Description
    Based on object we are migrating, execute a query on source database to get objects of a certain type, and generate CREATe statements. 
    Where no data loss can occur, we drop and recreate.
	.Parameter dbcon
    Connection to source database. Used to get list of all objects on source database (ie executes QueryForObjectList)
    .Parameter QueryForObjectList
    Query to list all objects. See Get-ListQuery Function to see query that is passed in.
    .Parameter ObjectType
    The type of object we are migrating.
	.Parameter sqlDatabaseName
    Used for creating folders
	.Example
    Remove-CreateScriptForObjectsFiles $conn $listSchemasQuery "schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
    Remove-CreateScriptForObjectsFiles $conn $listStoredProceduresQuery "SQL_STORED_PROCEDURE" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName                                                                                                                                         
    Remove-CreateScriptForObjectsFiles $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
    Remove-CreateScriptForObjectsFiles $conn $listFunctionsQuery "SQL_SCALAR_FUNCTION" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
    Remove-CreateScriptForObjectsFiles $conn $listViewsQuery "VIEW" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName  
    #>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [string]$QueryForObjectList, 
        [string]$ObjectType,
        $sqlDatabaseName,
        [String]$OutputDirectory) 
    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $PSScriptRoot
    }
    $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$ObjectType\"
    if (Test-Path $PathToOutput) {
        Write-Host "Removing path $PathToOutput"
        Remove-Item $PathToOutput -Recurse
    }
}

function Export-ColumnChanges {
    <#
   .Synopsis
   Export column additions from source database to target database.
   .Description
   Will check on target database the drift in terms of number of columns for all tables on source database.
   If any columns are missing, they are added.
   If table exists on source but not on target, nothing happens!
   If table exists on target but not on source ... nothing happens!
   .Parameter dbcon
   Connection to source database. Used to get list of all tables on source database
   .Parameter ColDbCon
   Connection to source database. Whilst looping through tables, get column info on current table
   .Parameter QueryForObjectList
   Query to list all tables. See Get-ListQuery ObjectType Tables to see query that is passed in.
   .Parameter sqlDatabaseName
   Used when inserting into SourceColumns table
   .Parameter TargetSqlServerName
   Used when running sqlcmd to execute script at end of process
   .Parameter sqlTargetDatabaseName
   Used when running sqlcmd to execute script at end of process
   .Parameter TargetColDbCon
   used to create SourceColumns table on target database
   .Parameter userName
   used when connecting via sqlcmd
   .Parameter Password
   Corresponding password for username when connecting via sqlcmd
   .Example
   Export-ColumnChanges -DbCon $conn $columnConn $listColumnsQuery -tableQueryList $listTablesQuery -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -OutputDirectory $pathToSaveFiles
#>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [System.Data.SqlClient.SqlConnection]$ColDbCon, 
        [string]$QueryForObjectList,
        $sqlServerName,
        $sqlDatabaseName,
        $TargetSqlServerName,
        $sqlTargetDatabaseName,
        [System.Data.SqlClient.SqlConnection]$TargetColDbCon,
        $userName,
        $Password,
        [String]$OutputDirectory ) 

    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $PSScriptRoot
    }
    Write-Host "Creating new table sourceColumns in target db to store column metadata"
    $AddColumnListCmd = New-Object System.Data.SqlClient.SqlCommand
    $AddColumnListCmd.Connection = $TargetColDbCon
    $AddColumnListCmd.CommandText = "IF OBJECT_ID ('sourceColumns', 'U') IS NOT NULL DROP TABLE sourceColumns; CREATE TABLE sourceColumns (databasename varchar(8000), schemaname varchar (8000), tablename varchar(8000),colname sysname,user_type_id int,column_id int, max_length SMALLINT)"
    $TargetColumnListReader = $AddColumnListCmd.ExecuteScalar();
    $whatIs = Compare-TableDelta -sourceConn $DbCon -targetConn $TargetColDbCon
    foreach ($What in $WhatIs) {
        foreach ($wKeys in $What.Keys) {
            $schemaName = $wKeys
            $objectName = $What[$wKeys]
            $NewQueryForObjectList = "SELECT s.name
            ,o.name
            ,c.name
            ,c.user_type_id
            ,C.COLUMN_ID
            ,c.max_length
        FROM sys.columns c
        INNER JOIN sys.objects o ON c.object_id = o.object_id
        INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
        INNER JOIN sys.tables t ON t.object_id = o.object_id
        WHERE o.type = 'U'
            AND s.name = '$schemaName'
            and t.name = '$obJectName'
            AND t.is_external = 0"
            $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
            $GetObjectListCmd.Connection = $DbCon
            $GetObjectListCmd.CommandText = $NewQueryForObjectList
            $ObjectListReader = $GetObjectListCmd.ExecuteReader();
            if ($ObjectListReader.HasRows) {
                $InsertStatement = "SET NOCOUNT ON `n INSERT INTO sourceColumns (databasename, schemaname, tablename, colname,user_type_id, column_id, max_length) "        
                while ($ObjectListReader.Read()) {
                    $schemaName = $ObjectListReader.GetString(0)
                    $ColumnTable = $ObjectListReader.GetString(1)
                    $ColumnName = $ObjectListReader.GetString(2)
                    $ColumnType = $ObjectListReader.GetInt32(3)
                    $ColumnId = $ObjectListReader.GetInt32(4)
                    if ($ColumnType -in 167, 175, 231, 239) {
                        $maxLength = $ObjectListReader.GetInt16(5)
                        if ($columnType -in 231, 239) {
                            if ($maxLength -gt 1) {
                                $maxLength = $maxLength / 2
                            }
                        }
                    }
                    else{
                        $maxLength = 0
                    }
                    $InsertStatement += "SELECT '$SqlDatabaseName', '$schemaName', '$ColumnTable', '$ColumnName', '$ColumnType', '$ColumnId', '$maxLength' UNION ALL`n"
                }
                $InsertStatement = $InsertStatement.Substring(0, $InsertStatement.Length - 10)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\InsertStatement_$schemaName$ColumnTable.sql"
                Set-Content $PathToOutput $InsertStatement
                sqlcmd -i $PathToOutput -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
            }
            $ObjectListReader.Close()       
        }
    }
    if ($whatIs.Count -gt 0) {
        Write-Host "Running script to add any missing columns, this can take some time..."
        sqlcmd -i $PSScriptRoot\sql\AddTableChanges.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
            Throw $msgToThrow 
        }
    }
}