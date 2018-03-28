Function Save-DDLStatement {
    [CmdletBinding()]
    <#
.Synopsis
Insert a record into the DDLStatements table
.Description
Persist the DDL statement in the DDLStatements table for use later on.  Created for later extraction of all DDL statments run against target database
.Parameter TargetDbCon
The connection to the database.
.Parameter TargetObject
The object which is the subject of the DDL statement.
.Parameter DDLStatement
The DDL statement to be added to the DDLStatements table
.Example
Save-DDLStatement -TargetDbCon $MyDB -TargetObject "Blah" -DDLStatement "ALTER TABLE Blah ADD NewCol INT;"
#>
    param(
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        [string]$TargetObject,
        [string]$DDLStatement
    )

    $cmd = New-Object System.Data.SqlClient.SqlCommand
    $cmd.Connection = $TargetDbCon
    $cmd.CommandText = "INSERT INTO DDLStatements (TargetObject, DDLStmt, CreateDate) VALUES (@TargetObject, @DDLStatement, '$((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))')"
    $cmd.Parameters.AddWithValue("@TargetObject",$TargetObject) | Out-Null    
    $cmd.Parameters.AddWithValue("@DDLStatement",$DDLStatement) | Out-Null    

    $cmd.ExecuteNonQuery() | Out-Null    
}