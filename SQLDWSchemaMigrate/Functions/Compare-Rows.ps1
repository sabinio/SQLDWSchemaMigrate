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
    $SqlQuerySumOfColumns = "SELECT s.name as schemaName, o.name as TableName, COUNT(*) as SumOfColumns
		FROM sys.columns c
		INNER JOIN sys.objects o ON c.object_id = o.object_id
		INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
		INNER JOIN sys.tables t ON t.object_id= o.object_id
		WHERE o.type = 'U'
			AND o.name NOT IN (
				'sourceColumns'
				,'sourceColumnsNew'
                ,'SourceDefinitions'
                ,'DDLStatements'
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
    try{
        $same = Compare-Rows $sourceDataSet $targetDataSet;
        if ($same.Count -eq 0) {
            Write-Host "The number of columns are correct for each table that exists on both source and target databases.";
        }
        else {
            Write-Host  "There are some tables with columns that exist in source but not on target. Determining which tables require columns added to.";
            Return $same
        }
    }
    catch{
        Write-Host $_.Exception
    }
    finally{
    Remove-SystemDataObject -SystemDataObject $sourceDataSet
    Remove-SystemDataObject -SystemDataObject $targetDataSet
    Remove-SystemDataObject -SystemDataObject $sourceResultSet
    Remove-SystemDataObject -SystemDataObject $targetResultSet
    Remove-SystemDataObject -SystemDataObject $DataAdapter
    }
}
Function Compare-Rows {
    <#
    .Synopsis
    Compares the sums of columns in a table that exists on both source and target databases and returns a hashtable of arrays of schemaName/TableName.
    .Description
    Loops through the source dataset of tables and find the corresponding entry in the target dataset and compares number of columns.
    If this is different then array of schema/table name are added to a hashtable which is returned at the end. 
    This Function itself is called by Compare-TableDelta
    .Parameter sourceDataset
    All tables and number of columns from source database.
    .Parameter targetDataset
    All tables and number of columns from Target database.
     .Example
     $same = Compare-Rows $sourceDataSet $targetDataSet;
    #>
    [CmdletBinding()]
    param(
        $sourceDataSet, 
        $targetDataSet)
    
    $output = @()

    $sourceRowIndex = 0;
    foreach ($sourceRow in $sourceDataSet.Rows) {
        $targetRow = $targetDataSet.Rows | Where-Object {($_.ItemArray[0] -eq $sourceRow.ItemArray[0] -and $_.ItemArray[1] -eq $sourceRow.ItemArray[1])}
        if ($null -ne $targetRow) {
            if ($sourceRow.ItemArray[2] -ne $targetRow.ItemArray[2]) {
                Write-Host "Column count mismatch for $($targetRow[0]).$($targetRow[1]) ($($sourceRow.ItemArray[2]) vs. $($targetRow.ItemArray[2]))"
                $output += (@{$sourceRow.ItemArray[0] = $($sourceRow.ItemArray[1])});
            }
            else {
                Write-Verbose "Column count matches for $($targetRow[0]).$($targetRow[1]) ($($targetRow[2]))"
            } 
        }
        else {
            Write-Host "Unable to find table $($sourceRow.ItemArray[0]).$($sourceRow.ItemArray[1]) on target database! Consider migrating tables over using 'Export-CreateScriptsForObjects -objectType Tables' and trying again."
        }
        $sourceRowIndex += 1;
    }
    return $output;
}