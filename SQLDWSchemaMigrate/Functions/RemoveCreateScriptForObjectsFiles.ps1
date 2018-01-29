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
        $sqlDatabaseName) 

    $GetObjectListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetObjectListCmd.Connection = $DbCon
    $GetObjectListCmd.CommandText = $QueryForObjectList
    $ObjectListReader = $GetObjectListCmd.ExecuteReader();
    if ($ObjectListReader.HasRows) {
        while ($ObjectListReader.Read()) {
            $PathToOutput = ".\$sqlDatabaseName\$($ObjectListReader.GetString(0))\$ObjectType\"
            if (Test-Path $PathToOutput) {
                Write-Host "Removing path $PathToOutput"
                Remove-Item $PathToOutput -Recurse
            }
        }
    }
    $ObjectListReader.Close()
}