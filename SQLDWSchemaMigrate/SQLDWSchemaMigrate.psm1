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
        "Schemas" {$FileWithGetCreateQueryNew = "$PSScriptRoot\sql\GetCreateStatement_SchemaNew.sql"; $FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Schema.sql"; break}
        "Tables" {$FileWithGetCreateQuery = "$PSScriptRoot\sql\GetCreateStatement_Table.sql"; break}
        default {"Something else happened"; break}
    }

    $ReCreateusp_ConstructCreateStatementForTable = 0
    [System.Collections.ArrayList]$FilePaths = @()
    Write-Host "Creating new table sourceDefinitions in target db to store definitions"
    if ($objectType -ne $schemas) {
        $AddDefinitionListCmd = New-Object System.Data.SqlClient.SqlCommand
        $AddDefinitionListCmd.Connection = $TargetDbCon
        if ($objectType -in "StoredProcedures", "ScalarFunctions", "Views") {
            $AddDefinitionListCmd.CommandText = "IF OBJECT_ID ('sourceDefinitions', 'U') IS NOT NULL DROP TABLE sourceDefinitions; CREATE TABLE sourceDefinitions (Databasename VARCHAR(8000), schemaName varchar(8000), objectName varchar(8000), object_definition varchar(MAX)) WITH (HEAP)"
            $TargetDefinitionListReader = $AddDefinitionListCmd.ExecuteReader();
            $TargetDefinitionListReader.Close();
        }
    }
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
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$ObjectType\"
                if (-not (Test-Path $PathToOutput)) {
                    New-Item $PathToOutput -Type Directory
                }
                $sqlCommandText = (Get-Content $FileWithCheckDefinitionQuery).Replace('$(object_name)', $ObjectName).Replace('$(schema_name)', $SchemaName)
                Write-Host "Inserting definition for object [$SchemaName].[$ObjectName] into sourceDefinitions on target server."
                $AddDefinitionListCmd.CommandText = "SET NOCOUNT ON;
                INSERT INTO sourceDefinitions VALUES ('$SqlDatabaseName', '$schemaName', '$objectName', '$definition');
                $sqlCommandText" 
                $gren = $AddDefinitionListCmd.ExecuteScalar();
                if ($gren -match 'identical') {
                    Write-Host "[$SchemaName].[$ObjectName] are identical on source and target databases. No further action required."
                
                }
                elseif ($gren -match 'different') {
                    if (-not ($FilePaths -contains $PathToOutput)) {
                        $FilePaths.Add($PathToOutput)
                    }
                    Write-Host "Exporting CREATE statement for [$SchemaName].[$ObjectName] of type $ObjectType as definitions do not match."
                    (Get-Content $FileWithGetCreateQueryNew).Replace("OBJECTPROPERTY('object_id(`$(schema_name).`$(object_name)')", "OBJECTPROPERTY('object_id($SchemaName.$ObjectName'").Replace('$(object_name)', $ObjectName).Replace('$(schema_name)', $SchemaName).Replace('$(createStatement)', $definitionForFile)  | Set-Content $PathToOutput$SchemaName$ObjectName'_Create'.sql
                }
                else {
                    Write-Host "hmmm..."
                    Write-Host $gren
                    Throw  
                }
            }
            elseif ($ObjectType -eq "Schemas") {
                $SchemaName = $ObjectListReader.GetString(0)
                $AuthorisationName = $ObjectListReader.GetString(1)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$ObjectType\"
                if (-not (Test-Path $PathToOutput)) {
                    New-Item $PathToOutput -Type Directory
                }
                $AddDefinitionListCmd.CommandText = "
                IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$SchemaName')
                SELECT 1
                ELSE
                SELECT 0"
                $schemaExists = $AddDefinitionListCmd.ExecuteScalar();
                if ($schemaExists -eq 1) {
                    Write-Host "Exporting CREATE statement for [$SchemaName] of type $ObjectType"
                    (Get-Content $FileWithGetCreateQueryNew).Replace('$(schema_name)', $SchemaName).Replace('$(authorisation_name)', $AuthorisationName)  | Set-Content $PathToOutput$SchemaName'_Create'.sql
                    If (-not ($FilePaths -contains $PathToOutput)) {
                        $FilePaths.Add($PathToOutput)
                    }
                }
                elseif ($schemaExists -eq 0) {
                    Write-Host "Schema [$SchemaName] already exists..."
                }
            }
            elseif ($ObjectType -eq "Tables") {
                $SchemaName = $ObjectListReader.GetString(0)
                $ObjectName = $ObjectListReader.GetString(1)
                $ObjectId = $ObjectListReader.GetInt32(2)
                $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$ObjectType\"
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
                Write-Host "Checking if [$SchemaName].[$ObjectName] exists on target server..."
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
                    Write-Host "Generating CREATE TABLE Script for [$SchemaName].[$ObjectName]..."
                    sqlcmd -i $FileWithGetCreateQuery -S $SqlServerName -d $SqlDatabaseName -G -U $Username -P $Password -I -o $PathToOutput$SchemaName$ObjectName'_Create'.sql -v object_id=$ObjectId -y 0 -b -j 
                    if ($LASTEXITCODE -ne 0) {
                        $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                        Throw $msgToThrow
                    }
                }
                elseif ($tableExists -eq 0) {
                    Write-Host "Table [$SchemaName].[$ObjectName] already exists..."
                }
            }
        }
    }
    if ($objectType -in "StoredProcedures", "ScalarFunctions", "Views", "Tables") {
        foreach ($filePath in $FilePaths) {
            $schema = @(Get-ChildItem $filePath"\*_Create*")
            Write-Host "Here"
            Start-Sleep -Seconds 20
            if ($schema.count -gt 0) {
                Write-Host "Executing scripts in folder $filePath"
                sqlcmd -i $schema -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
            }
        }
    }
    if ($objectType -eq "Schemas") {
        foreach ($filePath in $FilePaths) {
            $schema = @(Get-ChildItem $filePath"\*_Create*")
            if ($schema.count -gt 0) {
                Write-Host "Executing on target database $sqlTargetDatabaseName"
                sqlcmd -i $schema -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
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
    $PathToOutput = "$OutputDirectory\$sqlDatabaseName\$ObjectType\"
    if (Test-Path $PathToOutput) {
        Write-Host "Removing path $PathToOutput"
        Remove-Item $PathToOutput -Recurse
    }
}

Function Compare-TableDelta {

    param(
        [System.Data.SqlClient.SqlConnection]$sourceConn, 
        [System.Data.SqlClient.SqlConnection]$targetConn
    ) 
    $q1 = "	SELECT s.name, o.name, COUNT(*)
		FROM sys.columns c
		INNER JOIN sys.objects o ON c.object_id = o.object_id
		INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
		INNER JOIN sys.tables t ON t.object_id= o.object_id
		WHERE o.type = 'U'
			AND o.name NOT IN (
				'sourceColumns'
				,'sourceColumnsNew'
				,'SourceDefinitions'
				)
				AND t.is_external = 0 
				GROUP by o.name,s.name";
    # # Create dataset objects
    $resultset1 = New-Object "System.Data.DataSet" "myDs";
    $resultset2 = New-Object "System.Data.DataSet" "myDs";
    # Run query 1 and fill resultset1
    $data_adap = new-object "System.Data.SqlClient.SqlDataAdapter" ($q1, $sourceConn);
    $data_adap.Fill($resultset1) | Out-Null;
    # Run query 2 and fill resultset2
    $data_adap = new-object "System.Data.SqlClient.SqlDataAdapter" ($q1, $targetConn);
    $data_adap.Fill($resultset2) | Out-Null;
    # Get data table (only first table will be compared).
    [System.Data.DataTable]$dataset1 = $resultset1.Tables[0];
    [System.Data.DataTable]$dataset2 = $resultset2.Tables[0];
    # Compare tables
    Write-Host $resultset1.Tables[0]
    Write-Host $resultset2.Tables[0]
    $diff = Compare-Object $dataset1 $dataset2;
    # Are there any differences?
    if ($diff -eq $null) {
        Write-Host "The resultset objects look the same... Performing a detailed RBAR check...";
        $same = RBAR-Check $dataset1 $dataset2;
        if ($same.Count -eq 0) {
            Write-Host -ForegroundColor Green "The resultsets are the same.";
        }
        else {
            Write-Host -ForegroundColor Red "The resultsets are not the same.";
            $str = $same | Out-String
            Return $same
        }
    }
    else {
        Write-Host "The resultsets are different.";
    }
    # Clean up
    $dataset1.Dispose();
    $dataset2.Dispose();
    $resultset1.Dispose();
    $resultset2.Dispose();
    $data_adap.Dispose();
}


function RBAR-Check ($dataset1, $dataset2) {
    $row_index = 0;
    foreach ($row in $dataset1.Rows) {
        $column_index = 0;
        foreach ($col in $row.ItemArray) {
            $col2 = $dataset2.Rows[$row_index][$column_index];
            if ($col -ne $col2) {
                $output + (@{$row.ItemArray[0] = $($row.ItemArray[1])});
            }
            $column_index += 1;
        }
        $row_index += 1;
    }
    return $output;
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

    $sourceSumOfColumns = sqlcmd -i $PSScriptRoot\sql\CheckSumOfColumnsNew.sql -S $SqlServerName -d $SqlDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j -r0 -k1
    if ($LASTEXITCODE -ne 0) {
        $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
        Throw $msgToThrow
    }
    $targetSumofColumns = sqlcmd -i $PSScriptRoot\sql\CheckSumOfColumnsNew.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j -r0 -k1
    if ($LASTEXITCODE -ne 0) {
        $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
        Throw $msgToThrow
    }
    if ($targetSumofColumns -lt $sourceSumOfColumns) {
        Write-Host "Creating new table sourceColumns in target db to store column metadata"
        $AddColumnListCmd = New-Object System.Data.SqlClient.SqlCommand
        $AddColumnListCmd.Connection = $TargetColDbCon
        $AddColumnListCmd.CommandText = "IF OBJECT_ID ('sourceColumns', 'U') IS NOT NULL DROP TABLE sourceColumns; CREATE TABLE sourceColumns (databasename varchar(8000), schemaname varchar (8000), tablename varchar(8000),colname sysname,user_type_id int,column_id int, max_length SMALLINT)"
        $TargetColumnListReader = $AddColumnListCmd.ExecuteReader();
        $TargetColumnListReader.Close();
        $whatIs = Compare-TableDelta -sourceConn $DbCon -targetConn $TargetColDbCon
        $str = $whatIs | Out-String
        Write-Host $str
        Start-Sleep -Seconds 4
        foreach ($What in $WhatIs) {
            foreach ($wKeys in $What.Keys) {
                $message = 'Schema name is {0} and Table Name is {1}' -f $wKeys, $What[$wKeys]
                Write-Host $message
                $schemaName = $wKeys
                $objectName = $What[$wKeys]
                Write-Host "Schema name is $schemaName and Table Name is $objectName!" -ForegroundColor DarkGreen -BackgroundColor White
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
                        if ($ColumnType -eq 231) {
                            $maxLength = $ObjectListReader.GetInt16(5) 
                            if ($maxLength -gt 1) {
                                $maxLength = $maxLength / 2
                            }
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
        Write-Host "Adding missing columns, this can take some time..."
        sqlcmd -i $PSScriptRoot\sql\AddTableChanges.sql -S $TargetSqlServerName -d $sqlTargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
            Throw $msgToThrow
        } 
    }
    elseif ($targetSumofColumns -eq $sourceSumOfColumns) {
        Write-Host "Number of columns on source and target match..."
    }
}