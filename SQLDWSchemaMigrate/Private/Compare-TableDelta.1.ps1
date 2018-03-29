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
