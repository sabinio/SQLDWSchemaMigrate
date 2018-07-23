function Remove-ModifiedExternalTables {
    <#
   .Synopsis
   Drops external tables in the target database which have been modified or dropped in the source database.
   .Description
   Drops external tables in the target database which have been modified or dropped in the source database.
   .Parameter SourceDbcon
   Connection to source database. 
   .Parameter TargetDbCon
   Connection to target database. 
   .Example
   Remove-ModifiedExternalTables -SourceDbcon $SourceDbcon -TargetDbCon -$TargetDbCon 
#>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$SourceDbcon, 
        [System.Data.SqlClient.SqlConnection]$TargetDbCon
        ) 

        # Get a list of external tables to drop
        $ExternalTablesForDeletion = Compare-ExternalTables -sourceConn $sourceDbcon -targetConn $targetDbcon | Where-Object {@('TargetOnly','Differ') -contains $_.ComparisonResult} 

        $SQLCmdObj = New-Object System.Data.SqlClient.SqlCommand
        $SQLCmdObj.Connection = $TargetDbCon

        $ExternalTablesForDeletion | Select-Object -PipelineVariable Diff | ForEach-Object {

            $SQLToExecute = "DROP EXTERNAL TABLE $($Diff.ObjectName);"
            Write-Verbose "Dropping external table $($Diff.ObjectName). Reason: $($Diff.ComparisonResult)"

            $SQLCmdObj.CommandText = $SQLToExecute
            try {
                $SQLCmdObj.ExecuteNonQuery() | Out-Null
                Save-DDLStatement -TargetDbCon $TargetDbCon -TargetObject "$($Diff.ObjectName)" -DDLStatement $SQLToExecute
            }
            catch {
                throw $_.Exception
            }

        }

        Return $ExternalTablesForDeletion 
}