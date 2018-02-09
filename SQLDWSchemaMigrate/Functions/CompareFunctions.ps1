Function Compare-TableDelta {
    <#
   .Synopsis
   Compares the sums of the number of columns for each table that exists on both target and soruce databases.
   .Description
   Connects to sql to get a dataset ofthe number of columns for each table on both source and target databases. 
   Returns a hashtable which contains array of schema/tablename of columns that have mismatching columns.
   Calls "Compare-Rows" to establish which tables ahve differences, if any.
   This Function itself is called by Export-ColumnChanges
   .Parameter sourceConn
   Connection to source database.
   .Parameter targetConn
   Connection to target database.
    .Example
    $whatIs = Compare-TableDelta -sourceConn $DbCon -targetConn $TargetColDbCon
   #>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$sourceConn, 
        [System.Data.SqlClient.SqlConnection]$targetConn
    ) 
    $SqlQuerySumOfColumns = "	SELECT s.name as schemaName, o.name as TableName, COUNT(*) as SumOfColumns
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
                GROUP by o.name,s.name
                ORDER BY 1,2 DESC"
    $sourceResultSet = New-Object "System.Data.DataSet" "DsSumOfCOlumns"
    $targetResultSet = New-Object "System.Data.DataSet" "DsSumOfCOlumns"
    $DataAdapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($SqlQuerySumOfColumns, $sourceConn);
    $DataAdapter.Fill($sourceResultSet) | Out-Null;
    $DataAdapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($SqlQuerySumOfColumns, $targetConn);
    $DataAdapter.Fill($targetResultSet) | Out-Null;
    [System.Data.DataTable]$sourceDataSet = $sourceResultSet.Tables[0];
    [System.Data.DataTable]$targetDataSet = $targetResultSet.Tables[0];
    $same = Compare-Rows $sourceDataSet $targetDataSet;
    if ($same.Count -eq 0) {
        Write-Host "The number of columns are correct for each table that exists on both source and target databases.";
    }
    else {
        Write-Host  "There are some tables with columns that exist in source but not on target. Determining which tables require columns added to.";
        Return $same
    }
    $sourceDataSet.Dispose();
    $targetDataSet.Dispose();
    $sourceResultSet.Dispose();
    $targetResultSet.Dispose();
    $DataAdapter.Dispose();
}
Function Compare-Rows {
    <#
    .Synopsis
    Compares the sums of columns in a table that exists on both source and target databases and returns a hashtable of arrays of schemanName/TableName.
    .Description
    Loopsthrough the source dataset of tables and find the corresponding entry in the target dataset and compares number of columns.
    If this is differnet then array of schema/table name are added to a hashtable which is returned at the end. 
    This Function itself is called by Compare-TableDeltas
    .Parameter souceDataset
    All tables and number of columns from source database.
    .Parameter TargetDataset
    All tables and number of columns from Target database.
     .Example
     $same = Compare-Rows $sourceDataSet $targetDataSet;
    #>
    [CmdletBinding()]
    param(
        $sourceDataSet, 
        $targetDataSet)
    
    $sourceRowIndex = 0;
    foreach ($sourceRow in $sourceDataSet.Rows) {
        $targetRow = $targetDataSet.Rows | Where-Object {($_.ItemArray[0] -eq $sourceRow.ItemArray[0] -and $_.ItemArray[1] -eq $sourceRow.ItemArray[1])}
        if ($null -ne $targetRow) {
            if ($sourceRow.ItemArray[2] -ne $targetRow.ItemArray[2]) {
                $output + (@{$sourceRow.ItemArray[0] = $($sourceRow.ItemArray[1])});
            } 
        }
        else {
            Write-Host "Unable to find table $($sourceRow.ItemArray[0]).$($sourceRow.ItemArray[1]) on target database! Consider migrating tables over using 'Export-CreateScriptsForObjects -objectType Tables' and trying again."
        }
        $sourceRowIndex += 1;
    }
    return $output;
}