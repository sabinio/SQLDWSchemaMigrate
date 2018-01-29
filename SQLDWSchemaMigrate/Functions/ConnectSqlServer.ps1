
Function Connect-SqlServer {
     <#
    .Synopsis
    create a connection to sql instance
    .Description
    Using sqldataclient.sqlconnection, create a connection to sql instance
    return connection
    Currently only uses active directory password
    .Parameter sqlServerName
    Full name of instance that Azure Datawarehouse is hosted on
    .Parameter sqlDatabaseName
    Name of database for initial connection
    .Parameter userName
    SQL User we are connecting with
    .Parameter Password
    Password of SQL User
    .Example
    $ServerName = "myServer.database.windows.net"
    $DatabaseName = "AdwSourceDatabase"
    $uName = "me"
    $pword = "Passwords4U"
    $conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
    #>
    param(
        $sqlServerName,
        $sqlDatabaseName,
        $userName,
        $password
    )
    $userDbCon = New-Object System.Data.SqlClient.SqlConnection
    $userDbCon.ConnectionString = "Server = $SqlServerName; Database = $SqlDatabaseName; Authentication=Active Directory Password; UID = $Username; PWD = $Password;"
    Write-Host $userDbCon.ConnectionString
    Write-Host "Opening connection to $SqlServerName"
    try {
        $userDbCon.Open();
        Write-Host "Connection ready"
        Return $userDbCon
    }
    catch {
        Throw $_.Exception
    }

}