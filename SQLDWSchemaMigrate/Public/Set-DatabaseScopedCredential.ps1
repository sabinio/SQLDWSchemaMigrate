Function Set-DatabaseScopedCredential {
    [CmdletBinding()]
    <#
.Synopsis
Configures a scoped credential on target to match source database. 
.Description
Loop through each database scoped credential that is used by an external data source. If it does not exist, create it, if it does exist, then alter it so that secret and identity are current.
Secrets are set by having a PowerShell variable that has a name of the credential present in the session. So if you have a credential named "bob" in the source database and it requires a secret, then in  
the Powershell session that executes the funciton you will need a variable "$bob" with the value set to the secret required for the credential.  
There are two switches here to protect users from accidentally wiping secrets on the target server. 
    The Switch "ContinueOnMissingSecrets" can be included to ignore any PowerShell variables are missing for secrets. By default it is set to fail.
    The Switch  "alterCredentialsWithSecretOnly" means that if a variable is not found then the credential will not be updated.
If no variable exists, and the switches above are not used, then the credential will be updated to no longer have a password.
Sadly there is no way of determining which credentials have secrets set on the source, hence the fail safe Switches.
.Parameter SourceDbcon
The source database connection
.Parameter TargetDbCon
The target database connection
.Parameter ContinueOnMissingSecrets
If not all of your credentials require secrets, then you can include this switch. 
.Parameter alterCredentialsWithSecretOnly
Like the switch above, this will prevent secrets from being accidentally dropped on the target server if a PowerShell variable is not specified in the session.
However unlike the Switch above that omits an error being thrown, this will continue to alter those credentials that have secrets set. 
.Example
$conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
$TargetDbConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $uName -password $pword

Set-DatabaseScopedCredential -SourceDbcon $conn -TargetDbCon $TargetDbConn -alterCredentialsWithSecretOnly -ContinueOnMissingSecrets
#>
    param(
        [System.Data.SqlClient.SqlConnection]$SourceDbcon, 
        [System.Data.SqlClient.SqlConnection]$TargetDbCon,
        [Switch]$ContinueOnMissingSecrets,
        [Switch]$alterCredentialsWithSecretOnly
    )
    if ($ContinueOnMissingSecrets) {
        $ErrorActionPreference = 'SilentlyContinue'
    }
    else {
        $ErrorActionPreference = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('AlterCredentialsWithSecretOnly') -eq $true) {
        $alterSecretCredentialOnly = $true
    }
    else {
        $alterSecretCredentialOnly = $false
    }
    $sqlCommandText = "select name, principal_id, credential_id, credential_identity from sys.database_scoped_credentials where credential_id in (
        select distinct credential_id from sys.external_data_sources)"
    $GetCredentialListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetCredentialListCmd.Connection = $SourceDbcon
    $GetCredentialListCmd.CommandText = $sqlCommandText
    $CredentialListReader = $GetCredentialListCmd.ExecuteReader();
    if ($CredentialListReader.HasRows) {
        while ($CredentialListReader.Read()) {
            $sqlCreateScopedCredential = $null
            $credentialName = $CredentialListReader.GetString(0)
            $credentialIdentity = $CredentialListReader.GetString(3)
            $credentialSecret = Get-Variable $credentialName -ValueOnly
        }
        if ($null -eq $credentialSecret -and $alterSecretCredentialOnly -eq $false) {
            Write-Host "No variable named $credentialName exists in session. Will create/alter scoped credential without a secret."
            $sqlCreateScopedCredential = "IF NOT EXISTS (select name from sys.database_scoped_credentials where name = '$credentialName')
            CREATE DATABASE SCOPED CREDENTIAL $credentialName  
            WITH IDENTITY = '$credentialIdentity'
            ELSE
            ALTER DATABASE SCOPED CREDENTIAL $credentialName WITH IDENTITY = '$credentialIdentity'"
        } 
        elseif ($null -eq $credentialSecret -and $alterSecretCredentialOnly -eq $true) {
            Write-Host "No variable named $credentialName exists in session, and Switch 'alterCredentialsWithSecretOnly' is preventing credential $credentialName from being updated."
        }
        elseif ($null -ne $credentialSecret) {
            Write-Host "Variable $credentialName exists in session. Will create/alter scoped credential with a secret."
            $sqlCreateScopedCredential = "IF NOT EXISTS (select name from sys.database_scoped_credentials where name = '$credentialName')
            CREATE DATABASE SCOPED CREDENTIAL $credentialName  
            WITH IDENTITY = '$credentialIdentity',
            SECRET = '$credentialSecret';
            ELSE
            ALTER DATABASE SCOPED CREDENTIAL $credentialName WITH IDENTITY = '$credentialIdentity', SECRET = '$credentialSecret'"
        }
        if ($null -ne $sqlCreateScopedCredential) {
            $newsqlCreateScopedCredentialCmd = New-Object System.Data.SqlClient.SqlCommand
            $newsqlCreateScopedCredentialCmd.Connection = $TargetDbCon
            $newsqlCreateScopedCredentialCmd.CommandText = $sqlCreateScopedCredential
            try {
                Write-Host "Executing statement to create/alter Database Scoped Credential $credentialName"
                $newsqlCreateScopedCredentialCmd.ExecuteNonQuery() | Out-Null
            }
            catch {
                $_.Exception
            }
            $verifyQuery = "IF EXISTS (SELECT name, credential_identity from sys.database_scoped_credentials where name = '$credentialName' and credential_identity = '$credentialIdentity') SELECT 1"
            $newsqlCreateScopedCredentialCmd.CommandText = $verifyQuery
            $VerifySCopedCredential = $newsqlCreateScopedCredentialCmd.ExecuteScalar()
            if ($VerifySCopedCredential -ne 1) {
                $msg = "Something has gone wrong in trying to create/update scoped credential"
                Throw $msg
            }
            else {
                Write-Verbose "Database Scoped Credential $credentialName successfully created/altered."
            }
        }
    }
    $CredentialListReader.Close()
}