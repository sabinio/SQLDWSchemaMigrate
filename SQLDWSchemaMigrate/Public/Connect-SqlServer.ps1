
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
    .Parameter Credential
    A powershell credential object
    .Parameter Authentication
    The authentication method
    .EXAMPLE
    $ServerName = "myServer.database.windows.net"
    $DatabaseName = "AdwSourceDatabase"
    $uName = "me"
    $pword = "Passwords4U"
    $conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
    .EXAMPLE
    $ServerName = "myServer.database.windows.net"
    $DatabaseName = "AdwSourceDatabase"
    $Credential = Get-Credential
    $conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -credential $Credential
    .EXAMPLE
    $ServerName = "myServer.database.windows.net"
    $DatabaseName = "AdwSourceDatabase"
    $Credential = Get-Credential
    $conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -credential $Credential -authentication 'SQL'
    #>
    [CmdletBinding()]
    param(
        [string] $sqlServerName,
        [string] $sqlDatabaseName,
        [string] $userName,
        [string] $password,
        [pscredential] $credential,
        [ValidateSet('Active Directory Password','SQL')]
        [string] $authentication = 'Active Directory Password'
    )



    if ($credential) {
        Write-Verbose "`$credential parameter was supplied - ignoring `$username and `$password parameters!"
        $userName = $credential.UserName
        $password = $credential.GetNetworkCredential().Password
    }
    else {
        if (-not $userName) {
            Write-Error "No authentication credentials supplied. Either pass -username and -password parameters, or use -credential to pass a credential object." -ErrorAction Stop
        }
    }

    switch ($authentication) {
        'Active Directory Password' {
            $connString = "Server = $SqlServerName; Database = $SqlDatabaseName; Authentication=Active Directory Password; UID = $Username; PWD = $Password;"
        }
        'SQL' {
            $connString = "Server = $SqlServerName; Database = $SqlDatabaseName; UID = $Username; PWD = $Password;"
        }


    }

    $userDbCon = New-Object System.Data.SqlClient.SqlConnection
    $userDbCon.ConnectionString = $connString
    try {
        Write-Host "Opening connection to database $SqlDatabaseName on server $SqlServerName.."
        $userDbCon.Open();
        Return $userDbCon
    }
    catch {
        Throw $_.Exception
    }
}