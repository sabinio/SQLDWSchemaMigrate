Function New-AzureDatabaseMasterKey {
    [CmdletBinding()]
    <#
.Synopsis
Create a new database master key
.Description
If not exists, will create a master database key.
These are required for Database Scoped Cdreentials, which are required by external data sources
.Parameter masterkeyPassword
Password for the master key.
.Example
New-AzureDatabaseMasterKey -masterKeyPassword "noPasswords4U!"
#>
    param(
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        $masterKeyPassword
    )
    $sqlCommandText = "IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys symkeys WHERE symkeys.symmetric_key_id = 101)
CREATE MASTER KEY ENCRYPTION BY PASSWORD = $masterKeyPassword"
    $MasterkeyCmd = New-Object System.Data.SqlClient.SqlCommand
    $MasterkeyCmd.Connection = $TargetDbCon
    $MasterkeyCmd.CommandText = $sqlCommandText
    $GetObjectListCmd.ExecuteNonQuery() | Out-Null
}