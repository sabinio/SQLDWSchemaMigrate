function Export-CreateScriptsForObjects {
    <#
	.Synopsis
	Used to generate CREATE statements for objects on source database that can be migrated to target database 
	.Description
    Based on object we are migrating, execute a query on source database to get objects of a certain type, and generate CREATE statements. 
    Where no data loss can occur, we drop and recreate if the definitions between source and target are not identical.
	.Parameter SourceDbcon
    Connection to source database. Used to get list of all objects on source database (ie executes QueryForObjectList)
    .Parameter ObjectType
    The type of object we are migrating. Used for if statements as not all objects queries return the same columns and sqlcmd requires different variables
    .Parameter TargetDbCon
    Connection to target database. Used to apply create files to.
    .Parameter OutputDirectory
    Currently not in use, will be used eventually!
	.Example
    Export-CreateScriptsForObjects -DbCon $conn -QueryForObjectList $listSchemasQuery -ObjectType "Schemas" -TargetDbCon $targetConn -OutputDirectory $pathToSaveFiles
    #>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$SourceDbcon, 
        [System.Data.SqlClient.SqlConnection]$SourceDBConnTabCreateStmnts, 
        [string]$ObjectType,
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        [String]$OutputDirectory ) 

    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $Env:temp
    }

    Write-Verbose "`$OutputDirectory is $OutputDirectory"

    Write-Verbose "Checking for differences within object type '$ObjectType'"

    $ErrorActionPreference = 'stop'
    $QueryForObjectList = Get-ListQuery -ObjectType $ObjectType

    switch ($ObjectType) {
        "SQL_STORED_PROCEDURE" {$TypeForDropStatement = 'PROCEDURE'; break}
        "SQL_SCALAR_FUNCTION" {$TypeForDropStatement = 'FUNCTION'; break}
        "VIEW" {$TypeForDropStatement = 'VIEW'; break}
        default {break}
    }
    $ReCreateProc = 0
    [System.Collections.ArrayList]$FilePaths = @()
    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $SourceDbcon
    $GetObjectListCmd.CommandText = $QueryForObjectList

    
    $ObjectListAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $GetObjectListCmd
    $ObjectListDataSet = New-Object System.Data.DataSet
    $ObjectListAdapter.Fill($ObjectListDataSet) | out-null
    $ObjectListReader.Close()

    $AddDefinitionListCmd = New-Object System.Data.SqlClient.SqlCommand
    $AddDefinitionListCmd.Connection = $TargetDbCon

    foreach ($Row in $ObjectListDataSet.Tables[0].Rows)
    { 
        if ($objectType -in "SQL_STORED_PROCEDURE", "SQL_SCALAR_FUNCTION", "VIEW") {
            $SchemaName = $Row[0]
            $ObjectName =$Row[1]
            $ObjectId = $Row[2]
            $definitionForFile = $Row[4]

            $sqlCommandText = "select mod.definition from sys.objects obj inner join sys.schemas sch on obj.schema_id = sch.schema_id inner join [sys].[sql_modules] mod on mod.object_id = obj.object_id where obj.type_desc = '$ObjectType' and sch.name = '$schemaName' and obj.name = '$objectName';"
            $AddDefinitionListCmd.CommandText = "SET NOCOUNT ON;`n$sqlCommandText"
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

                $SQLToExecute = "DROP $TypeForDropStatement [$SchemaName].[$ObjectName]"
                $AddDefinitionListCmd.CommandText = $SQLToExecute
                try {
                    $AddDefinitionListCmd.ExecuteNonQuery() | Out-Null
                    Save-DDLStatement -TargetDbCon $TargetDbCon -TargetObject "$SchemaName.$ObjectName" -DDLStatement $SQLToExecute
                }
                catch {
                    throw $_.Exception
                }
            }
            if ($executeCreateOnTarget -eq 1) {
                Write-Host "Creating object [$SchemaName].[$ObjectName] of type $ObjectType on target."
                $AddDefinitionListCmd.CommandText = $definitionForFile
                try {
                    $AddDefinitionListCmd.ExecuteNonQuery() | Out-Null    
                    Save-DDLStatement -TargetDbCon $TargetDbCon -TargetObject "$SchemaName.$ObjectName" -DDLStatement $definitionForFile 
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

            $SchemaName = $Row[0]
            $AuthorisationName =$Row[1]
            $AddDefinitionListCmd.CommandText = "
            IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$SchemaName')
            SELECT 0
            ELSE
            SELECT 1"
            $schemaExists = $AddDefinitionListCmd.ExecuteScalar();           
            if ($schemaExists -eq 0) {
                $SQLToExecute = "CREATE SCHEMA $schemaName AUTHORIZATION $AuthorisationName"
                $AddDefinitionListCmd.CommandText = $SQLToExecute
                Write-Host "Creating schema $schemaName with authorisation $AuthorisationName on $($AddDefinitionListCmd.Connection.Database)"
                try {
                    $AddDefinitionListCmd.ExecuteNonQuery() | Out-Null 
                    Save-DDLStatement -TargetDbCon $TargetDbCon -TargetObject $SchemaName -DDLStatement $SQLToExecute 
                }
                catch {
                    throw $_.Exception
                }
            }
            elseif ($schemaExists -eq 0) {
                Write-Verbose "Schema [$SchemaName] already exists..."
            }
        }
        elseif ($ObjectType -in "Tables", "ExternalTables") {
            $TableScriptCmd = New-Object System.Data.SqlClient.SqlCommand
            $TableScriptCmd.CommandTimeout = 300
            $TableScriptCmd.Connection = $SourceDbcon

            $SchemaName = $Row[0]
            $ObjectName =$Row[1]
            $ObjectId = $Row[2]

            if ($ReCreateProc -eq 0) {
                switch ($ObjectType) {
                    "Tables" {$proc = "usp_ConstructCreateStatementForTable"; break}
                    "ExternalTables" {$proc = "usp_ConstructCreateStatementForExternalTable"; break}
                }
                Write-Verbose "Recreating $proc on database $($TableScriptCmd.Connection.Database)"
                $TableScriptCmd.CommandText = "IF OBJECTPROPERTY(object_id('$proc'),  'IsProcedure') = 1 `n DROP PROCEDURE $proc"
                $TableScriptCmd.ExecuteNonQuery() | Out-Null
                
                $SQLToExecute = (Get-HelperSQL $proc)

                $TableScriptCmd.CommandText = $SQLToExecute
                $TableScriptCmd.ExecuteNonQuery() | Out-Null
                $ReCreateProc = 1                    

            }
            Write-Verbose "Checking if [$SchemaName].[$ObjectName] exists on database $($AddDefinitionListCmd.Connection.Database) "
            $AddDefinitionListCmd.CommandText = "
            if exists
            (
                select obj.name as object_name from sys.tables obj inner join sys.schemas sch on obj.schema_id = sch.schema_id 
                where sch.name = '$schemaName' and obj.name = '$objectName'
            )
            SELECT 1
            ELSE
            SELECT 0
            "
            $TableExists = $AddDefinitionListCmd.ExecuteScalar();
            if ($TableExists -eq 0) {
                Write-Host "Getting table creation script for [$SchemaName].[$ObjectName] from $($TableScriptCmd.Connection.Database) on server $($TableScriptCmd.Connection.DataSource)."  
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
                    EXEC [$proc] @schemaName, @tableName, '', @sqlCmd OUTPUT;
                    SELECT @sqlCmd;"

                $TableScriptCmd.CommandText = $sqlCommandText 
                
                $CreateStatement = $TableScriptCmd.ExecuteScalar()

                try {
                    Write-Host "Executing table creation script for [$SchemaName].[$ObjectName] on $($AddDefinitionListCmd.Connection.Database) on server $($AddDefinitionListCmd.Connection.DataSource)."  

                    $AddDefinitionListCmd.CommandTimeout = 300
                    $AddDefinitionListCmd.CommandText = $CreateStatement

                    $AddDefinitionListQuery = $AddDefinitionListCmd.ExecuteNonQuery()
                    $AddDefinitionListQuery | Out-Null

                    Save-DDLStatement -TargetDbCon $TargetDbCon -TargetObject "$SchemaName.$ObjectName" -DDLStatement $CreateStatement

                    
                }
                catch {
                    $ohDear = "$CreateStatement `n failed with the following error - $($_.Exception)"
                    throw $ohDear
                }
                finally{
                    $AddDefinitionListCmd.CommandTimeout = 30
                }
            }
            elseif ($tableExists -eq 1) {
                Write-Verbose "Table [$SchemaName].[$ObjectName] already exists..."
            }
        }
    }
}