function Export-ColumnChanges {
    <#
   .Synopsis
   Export column additions from source database to target database.
   .Description
   Will check on target database the drift in terms of number of columns for all tables on source database.
   If any columns are missing, they are added.
   If table exists on source but not on target, nothing happens!
   If table exists on target but not on source ... nothing happens!
   .Parameter SourceDbcon
   Connection to source database. Used to get list of all tables on source database
   .Parameter TargetDbCon
   used to create SourceColumns table on target database
   .Parameter TargetDBCredential
   The credentials used during sqlcmd execution
   .Example
   Export-ColumnChanges -SourceDbcon $SourceDbcon -TargetDbCon -$TargetDbCon -TargetDBCredential $TargetDBCredential 
#>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$SourceDbcon, 
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        [PSCredential] $TargetDBCredential) 

    $WorkingDirectory = $Env:temp
    Write-Verbose "`$WorkingDirectory is $WorkingDirectory"

    $sqlDatabaseName = $SourceDbcon.Database
    
    $TargetSqlServerName = $TargetDbCon.DataSource
    $TargetDatabaseName = $TargetDbCon.Database
    $userName  = $TargetDBCredential.UserName
    $Password  = $TargetDBCredential.GetNetworkCredential().Password

    Write-Host "Creating new table sourceColumns in $TargetSqlServerName to store column metadata"
    $AddColumnListCmd = New-Object System.Data.SqlClient.SqlCommand
    $AddColumnListCmd.Connection = $TargetDbCon
    $AddColumnListCmd.CommandText = "IF OBJECT_ID ('sourceColumns', 'U') IS NOT NULL DROP TABLE sourceColumns; CREATE TABLE sourceColumns (databasename varchar(8000), schemaname varchar (8000), tablename varchar(8000),colname sysname,user_type_id int,column_id int, max_length SMALLINT)"
    $AddColumnListCmd.ExecuteNonQuery() | Out-Null


    $whatIs = Compare-TableDelta -sourceConn $SourceDbcon -targetConn $TargetDbCon
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
            $GetObjectListCmd.Connection = $SourceDbcon
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
                
                $PathToOutput = "$WorkingDirectory\$sqlDatabaseName\InsertStatement_$schemaName$ColumnTable.sql"
                New-item -path $PathToOutput -value $InsertStatement -type 'file' -force | Out-Null
                sqlcmd -i $PathToOutput -S $TargetSqlServerName -d $TargetDatabaseName -G -U $Username -P $Password -I  -y 0 -b -j
                if ($LASTEXITCODE -ne 0) {
                    $msgToThrow = "Something has gone wrong, consult the output of sqlcmd above for issue."
                    Throw $msgToThrow
                }
            }
            $ObjectListReader.Close()       
        }
    }
    if ($whatIs.Count -gt 0) {
        Write-Host "Running script on server $TargetSqlServerName, database $TargetDatabaseName to add any missing columns, this can take some time..."

        $SQLFile = "$WorkingDirectory\AddTableChanges.sql"
        New-item -path $SQLFile -value $(Get-HelperSQL 'AddTableChanges') -type 'file' -force | Out-Null

        sqlcmd -i $SQLFile -S $TargetSqlServerName -d $TargetDatabaseName  -G -U $Username -P $Password -I  -y 0 -b -j  
        if ($LASTEXITCODE -ne 0) {
            $msgToThrow = "Something went wrong whilst adding new columns. Consult the output of sqlcmd above for issue."
            Throw $msgToThrow 
        }
    }
}