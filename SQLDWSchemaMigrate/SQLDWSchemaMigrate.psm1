foreach ($function in (Get-ChildItem "$PSScriptRoot\functions\*.ps1")) {
    $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($function))), $null, $null)
}

function Export-CreateScriptsForObjects {
    <#
	.Synopsis
	Used to generate CREATE statements for objects on source database that can be migratedto target database 
	.Description
    Based on object we are migrating, execute a query on source database to get objects of a certain type, and generate CREATE statements. 
    Where no data loss can occur, we drop and recreate if the definitions between source and target are not identical.
    sqlcmd uses Azure Active Directory, and requires a username and password.
	.Parameter dbcon
    Connection to source database. Used to get list of all objects on source database (ie executes QueryForObjectList)
    .Parameter QueryForObjectList
    Query to list all objects. See Get-ListQuery Function to see query that is passed in.
    .Parameter ObjectType
    The type of object we are migrating. Used for if statements as not all objects queries return the same columns and sqlcmd requires different variables
	.Parameter sqlServerName
	Used by sqlcmd when generating CREATE statements.
	.Parameter sqlDatabaseName
    Used for creating folders and connecting via sqlcmd
    .Parameter userName
	used when connecting via sqlcmd
	.Parameter Password
	Corresponding password for username when connecting via sqlcmd
	.Parameter TargetSqlServerName
	Used when running sqlcmd to execute script at end of process
	.Parameter sqlTargetDatabaseName
	Used when running sqlcmd to execute script at end of process
	.Example
	Export-ColumnChanges $conn $columnConn $listTablesQuery ".\sql\AddTableChanges.sql" "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -TargetColDbCon $targetColumnConn
	#>
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [string]$QueryForObjectList, 
        [string]$ObjectType,
        $sqlServerName,
        $sqlDatabaseName,
        $userName,
        $password,
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        $TargetSqlServerName,
        $sqlTargetDatabaseName,
        [String]$OutputDirectory ) 

    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $PSScriptRoot
    }
    
    switch ($ObjectType) {
        "StoredProcedures" {$FileWithGetCreateQueryNew = "$PSScriptRoot\sql\GetCreateStatement_ProcNew.sql"; $FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Proc.sql"; $FileWithCheckDefinitionQuery = "$PSScriptRoot\sql\CheckDefinition_Proc.sql"; break}
        "ScalarFunctions" {$FileWithGetCreateQueryNew = "$PSScriptRoot\sql\GetCreateStatement_ProcNew.sql"; $FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Function.sql"; $FileWithCheckDefinitionQuery = "$PSScriptRoot\sql\CheckDefinition_Function.sql"; break}
        "Views" {$FileWithGetCreateQueryNew = "$PSScriptRoot\sql\GetCreateStatement_ViewNew.sql"; $FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_View.sql"; $FileWithCheckDefinitionQuery = "$PSScriptRoot\sql\CheckDefinition_View.sql"; break}
        "Schemas" {$FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Schema.sql"; break}
        "Tables" {$FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Table.sql"; break}
        default {"Something else happened"; break}
    }

    $ReCreateusp_ConstructCreateStatementForTable = 0
    [System.Collections.ArrayList]$FilePaths = @()
    Write-Host "Creating new table sourceDefinitions in target db to store definitions"
    $AddDefinitionListCmd = New-Object System.Data.SqlClient.SqlCommand
    $AddDefinitionListCmd.Connection = $TargetDbCon
    $AddDefinitionListCmd.CommandText = "IF OBJECT_ID ('sourceDefinitions', 'U') IS NOT NULL DROP TABLE sourceDefinitions; CREATE TABLE sourceDefinitions (Databasename VARCHAR(8000), schemaName varchar(8000), objectName varchar(8000), object_definition varchar(MAX)) WITH (HEAP)"
    $TargetDefinitionListReader = $AddDefinitionListCmd.ExecuteReader();
    $TargetDefinitionListReader.Close();
    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $DbCon
    $GetObjectListCmd.CommandText = $QueryForObjectList
    $ObjectListReader = $GetObjectListCmd.ExecuteReader();
    if ($ObjectListReader.HasRows) {
        while ($ObjectListReader.Read()) {
            if ($objectType -in "StoredProcedures", "ScalarFunctions", "Views") {
                $SchemaName = $ObjectListReader.GetString(0)
                $ObjectName = $ObjectListReader.GetString(1)
                $ObjectId = $ObjectListReader.GetInt32(2)
                $SchemaId = $ObjectListReader.GetInt32(3)
                $definition = $ObjectListReader.GetString(4).Replace("'", '')
                $definitionForFile = $ObjectListReader.GetString(4)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$SchemaName\$ObjectType\"
                if (-not (Test-Path $PathToOutput)) {
                    New-Item $PathToOutput -Type Directory
                }
                Write-Host "Inserting definition for object [$SchemaName].[$ObjectName] into sourceDefinitions on target server."
                $AddDefinitionListCmd.CommandText = "INSERT INTO sourceDefinitions VALUES ('$SqlDatabaseName', '$schemaName', '$objectName', '$definition');"
                $TargetDefinitionListReader = $AddDefinitionListCmd.ExecuteReader();
                $TargetDefinitionListReader.Close()
                Write-Host "Exporting compare definition statement for [$SchemaName].[$ObjectName] of type $ObjectType"
                sqlcmd -i $FileWithCheckDefinitionQuery -S $SqlServerName -d $SqlDatabaseName -U $Username -P $Password -G -I -o $PathToOutput$ObjectName'_Check'.sql -v object_id=$ObjectId schema_id=$SchemaId  -y 0 -b -j 
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
                Write-Host "Checking if object [$SchemaName].[$ObjectName] on source database matches target database $sqlTargetDatabaseName"
                $gren = sqlcmd -i $PathToOutput$ObjectName'_Check'.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j -r0 -k1
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
                if ($gren -match 'identical') {
                    Write-Host "[$SchemaName].[$ObjectName] are identical on source and target databases. No further action required."
                
                }
                elseif ($gren -match 'different') {
                    if (-not ($FilePaths -contains $PathToOutput)) {
                        $FilePaths.Add($PathToOutput)
                    }
                    Write-Host "Exporting CREATE statement for [$SchemaName].[$ObjectName] of type $ObjectType as definitions do not match."
                    (Get-Content $FileWithGetCreateQueryNew).Replace("OBJECTPROPERTY('object_id(`$(schema_name).`$(object_name)')", "OBJECTPROPERTY('object_id($SchemaName.$ObjectName'").Replace('$(object_name)', $ObjectName).Replace('$(schema_name)', $SchemaName).Replace('$(createStatement)', $definitionForFile)  | Set-Content $PathToOutput$ObjectName'_Create'.sql
                }
                else {
                    Write-Host "hmmm..."
                    Write-Host $gren
                    Throw  
                }
            }
            elseif ($ObjectType -eq "Schemas") {
                Write-Host "here"
                $SchemaName = $ObjectListReader.GetString(0)
                $AuthorisationName = $ObjectListReader.GetString(1)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$SchemaName\$ObjectType\"
                if (-not (Test-Path $PathToOutput)) {
                    New-Item $PathToOutput -Type Directory
                }
                Write-Host "Exporting CREATE statement for [$SchemaName] of type $ObjectType"
                sqlcmd -i $FileWithGetCreateQuery -S $SqlServerName -d $SqlDatabaseName -G -U $Username -P $Password -I -o $PathToOutput$SchemaName.sql -v schema_name=$SchemaName authorisation_name=$AuthorisationName  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
                Write-Host "Executing on target database $sqlTargetDatabaseName"
                sqlcmd -i $PathToOutput$SchemaName.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
            }
            elseif ($ObjectType -eq "Tables") {
                $SchemaName = $ObjectListReader.GetString(0)
                $ObjectName = $ObjectListReader.GetString(1)
                $ObjectId = $ObjectListReader.GetInt32(2)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$SchemaName\$ObjectType\"
                if (-not (Test-Path $PathToOutput)) {
                    New-Item $PathToOutput -Type Directory
                }
                If (-not ($FilePaths -contains $PathToOutput)) {
                    $FilePaths.Add($PathToOutput)
                }
                if ($ReCreateusp_ConstructCreateStatementForTable -eq 0) {
                    Write-Host "Recreating usp_ConstructCreateStatementForTable on database $DatabaseName"
                    sqlcmd -i "$PSScriptRoot\sql\usp_ConstructCreateStatementForTable.sql" -S $SqlServerName -d $DatabaseName -G -U $UserName -P $Password -I  -y 0 -b -j
                    if ($LASTEXITCODE -ne 0) {
                        $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                        Throw $msgToThrow
                    }
                    $ReCreateusp_ConstructCreateStatementForTable = 1
                }
                Write-Host "Exporting CREATE statement for [$SchemaName].[$Objectname] of type $ObjectType"
                sqlcmd -i $FileWithGetCreateQuery -S $SqlServerName -d $SqlDatabaseName -G -U $Username -P $Password -I -o $PathToOutput$ObjectName'_Create'.sql -v object_id=$ObjectId -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
            }
        }
    }
    if ($objectType -in "StoredProcedures", "ScalarFunctions", "Views", "Tables") {
        foreach ($filePath in $FilePaths) {
            $schema = @(Get-ChildItem $filePath"\*_Create*")
            Write-Host "Executing scripts in folder $filePath"
            sqlcmd -i $schema -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
            if ($LASTEXITCODE -ne 0) {
                $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                Throw $msgToThrow
            }
        }
    }
    $ObjectListReader.Close()
}


function Export-ColumnChanges {
    <#
   .Synopsis
   Export column additions from source database to target database.
   .Description
   List all the coluns for all the tables in the source database and store them in a table (dbo.SourceColumns) on the target database.
   Execute some SQL to compare the columns stored in dbo.SourceColumns for a given table and if are any missing in the target table then generate an alter table script.
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
   Export-ColumnChanges $conn $columnConn $listTablesQuery ".\sql\AddTableChanges.sql" "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -TargetColDbCon $targetColumnConn
   #>
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [System.Data.SqlClient.SqlConnection]$ColDbCon, 
        [string]$QueryForObjectList,
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
    Write-Host "Starting source table connection"
    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $DbCon
    $GetObjectListCmd.CommandText = $QueryForObjectList
    $ObjectListReader = $GetObjectListCmd.ExecuteReader();
    if ($ObjectListReader.HasRows) {
        Write-Host "Creating new table sourceColumns in target db to store column metadata"
        $AddColumnListCmd = New-Object System.Data.SqlClient.SqlCommand
        $AddColumnListCmd.Connection = $TargetColDbCon
        $AddColumnListCmd.CommandText = "IF OBJECT_ID ('sourceColumns', 'U') IS NOT NULL DROP TABLE sourceColumns; CREATE TABLE sourceColumns (databasename varchar(8000), tablename varchar(8000),colname sysname,user_type_id int,column_id int)"
        $TargetColumnListReader = $AddColumnListCmd.ExecuteReader();
        $TargetColumnListReader.Close();
        $InsertStatement = "SET NOCOUNT ON `n INSERT INTO sourceColumns (databasename, tablename, colname,user_type_id, column_id) "
        while ($ObjectListReader.Read()) {
            $ColumnTable = $ObjectListReader.GetString(0)
            $ColumnName = $ObjectListReader.GetString(1)
            $ColumnType = $ObjectListReader.GetInt32(2)
            $ColumnId = $ObjectListReader.GetInt32(3)
            $InsertStatement = $InsertStatement + "SELECT '$SqlDatabaseName', '$ColumnTable', '$ColumnName', '$ColumnType', '$ColumnId' UNION ALL `n"
        }
        $InsertStatement = $InsertStatement.Substring(0, $InsertStatement.Length - 10)
        $PathToOutput = "$OutputDirectory\$sqlDatabaseName\InsertStatement_$sqlDatabaseName.sql"
        Set-Content $PathToOutput $InsertStatement
        sqlcmd -i $PathToOutput -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
            Throw $msgToThrow
        }
    }
    $ObjectListReader.Close()
    $checkSumOfColumns = sqlcmd -i $PSScriptRoot\sql\CheckSumOfColumns.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j -r0 -k1
    if ($LASTEXITCODE -ne 0) {
        $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
        Throw $msgToThrow
    }
    if ($checkSumOfColumns -match 'moreInSourceThanInTarget') {
        Write-Host "More columns in source database than target database. Determining which tables are affected."
        sqlcmd -i $PSScriptRoot\sql\SetTablesWithDelta.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
            Throw $msgToThrow
        }
        Write-Host "Adding missing columns, this can take some time..."
        sqlcmd -i $PSScriptRoot\sql\AddTableChanges.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
            Throw $msgToThrow
        }
    }
    if ($checkSumOfColumns -match 'sameInSourceAndTarget') {
        Write-Host "Sums of columns in both source and target databases match..."
    }
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
    Remove-CreateScriptForObjectsFiles $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName                                                                                                                                         
    Remove-CreateScriptForObjectsFiles $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
    Remove-CreateScriptForObjectsFiles $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
    Remove-CreateScriptForObjectsFiles $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName  
    #>
    param(
        [System.Data.SqlClient.SqlConnection]$DbCon, 
        [string]$QueryForObjectList, 
        [string]$ObjectType,
        $sqlDatabaseName,
        [String]$OutputDirectory) 

        
    if ($PSBoundParameters.ContainsKey('OutputDirectory') -eq $false) {
        $OutputDirectory = $PSScriptRoot
    }

    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $DbCon
    $GetObjectListCmd.CommandText = $QueryForObjectList
    $ObjectListReader = $GetObjectListCmd.ExecuteReader();
    if ($ObjectListReader.HasRows) {
        while ($ObjectListReader.Read()) {
            $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$($ObjectListReader.GetString(0))\$ObjectType\"
            if (Test-Path $PathToOutput) {
                Write-Host "Removing path $PathToOutput"
                Remove-Item $PathToOutput -Recurse
            }
        }
    }
    $ObjectListReader.Close()
}