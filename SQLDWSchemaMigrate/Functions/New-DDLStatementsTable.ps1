Function New-DDLStatementsTable {
    [CmdletBinding()]
    <#
.Synopsis
Create a new DDLStatements table
.Description
(Re)creates a DDLStatements table, used for storing DDL statements made against the database during execution.
Used for extraction later if a migration script is required.
.Parameter TargetDbCon
The connection to the database in which the table should be (re)created.
.Example
New-DDLStatementsTable -TargetDbCon
#>
    param(
        [System.Data.SqlClient.SqlConnection]$TargetDbCon
    )
    $sqlCommandText = "IF OBJECT_ID ('DDLStatements', 'U') IS NOT NULL DROP TABLE DDLStatements; CREATE TABLE DDLStatements (ID INT IDENTITY, TargetObject NVARCHAR(510), DDLStmt NVARCHAR(MAX), CreateDate DATETIME) WITH (HEAP);"
    $Cmd = New-Object System.Data.SqlClient.SqlCommand
    $Cmd.Connection = $TargetDbCon
    $Cmd.CommandText = $sqlCommandText
    $Cmd.ExecuteNonQuery() | Out-Null
}