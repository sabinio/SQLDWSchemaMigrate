function Disconnect-SqlServer {
 <#
.Synopsis
dispose of a connection to sql instance
.Description
Using sqldataclient.sqlconnection, dispose a connection to sql instance
Dispose method also calls close, so it return connection back to the pool
State of conection can be open, closed, broken, connecting, executing, fetching
.Parameter sqlConnection
The connection we wish to dispose of.
.Example
Disconnect-SqlServer -sqlConnection $mySqlConnection
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, mandatory = $true)]
        [System.Data.SqlClient.SqlConnection] 
        $sqlConnection
        )
    if ($sqlConnection.State -ne "Closed") {
        try {
            Write-Host "Disconnecting from database $($sqlConnection.Database) on server $($sqlConnection.Datasource).. "
            $sqlConnection.Dispose()            
            return
        }
        catch {
            Write-Error $_.Exception
            Throw
        }
    }
}