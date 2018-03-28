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