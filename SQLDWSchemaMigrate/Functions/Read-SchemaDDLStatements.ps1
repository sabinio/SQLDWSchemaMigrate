Function Read-SchemaDDLStatements {
    [CmdletBinding()]
    <#
.Synopsis
Gets the DDL statements to update the schema in the target database
.Description
All DDL statements executed against a target database within the module are stored in a table called "DDLStatements" on the target database.
Use this function to access the statements.
.Parameter DbCon
The database connection
.Example
Read-SchemaDDLStatements -Dbcon $conn 
#>
    param(
        [System.Data.SqlClient.SqlConnection]$Dbcon
    )

    $sqlCommandText = "SELECT TargetObject, DDLStmt FROM ddlstatements ORDER BY ID"

    $cmd = New-Object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $Dbcon
    $cmd.CommandText = $sqlCommandText

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $ds = New-Object System.Data.DataSet
    $adapter.Fill($ds) | out-null

    $Result = $ds.Tables[0] | Select-Object TargetObject, DDLStmt

    return $Result

}