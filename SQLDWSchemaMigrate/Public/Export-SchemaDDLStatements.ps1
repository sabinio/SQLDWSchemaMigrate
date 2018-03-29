
Function Export-SchemaDDLStatements {
    [CmdletBinding()]
    <#
.Synopsis
Gets the DDL statements to update the schema in the target database and exports them to a file (or files)
.Description
All DDL statements executed against a target database within the module are stored in a table called "DDLStatements" on the target database.
Use this function to export the statements to a file.
.Parameter DbCon
The database connection
.Parameter OutputDirectory
The directory to save the file(s) to
.Parameter OutputFileName
The name of the file to create
.Parameter SplitByDatabaseObject
Used for creating one file per object
.Example
Export-SchemaDDLStatements -Dbcon $targetDbcon -OutputDirectory 'c:\temp' -OutputFileName 'foobar.sql'  
#>
    param(
        [System.Data.SqlClient.SqlConnection]$Dbcon,
        [string] $OutputDirectory,
        [string] $OutputFileName,
        [switch] $SplitByDatabaseObject
    )

    # Directory exists?
    if (-not (Test-Path $OutputDirectory)) {
        Write-Error "Output directory '$OutputDirectory' does not exist."
        throw
    }

    $DDLStatements = Read-SchemaDDLStatements -Dbcon $Dbcon 

    $FilesWritten = @{}

    If ($PSBoundParameters.ContainsKey('SplitByDatabaseObject')) {
        Write-Output "SplitByDatabaseObject was set - `$OutputFileName will be ignored"

        foreach ($DDLStatement in $DDLStatements) {
            $OutputFullFileName = (Join-Path $OutputDirectory "$($DDLStatement.TargetObject).sql")

            if ($FilesWritten.$OutputFullFileName -eq $null) {

                Write-Verbose "Writing to $OutputFullFileName"

                $($DDLStatement.DDLStmt)  | Out-File -FilePath $OutputFullFileName 
            }
            else {

                Write-Verbose "Appending to $OutputFullFileName"

                $($DDLStatement.DDLStmt)  | Out-File -FilePath $OutputFullFileName -Append    
            }           

            $FilesWritten.$OutputFullFileName ++            
        }
    }
    else {
        $OutputFullFileName = (Join-Path $OutputDirectory $OutputFileName)

        if (Test-Path $OutputFullFileName) {
            Remove-Item $OutputFullFileName
        }

        Write-Verbose "Writing to $OutputFullFileName"
        
        foreach ($DDLStatement in $DDLStatements) {
            "$($DDLStatement.DDLStmt)`n`n"  | Out-File -FilePath $OutputFullFileName -Append
        }
    }
}

