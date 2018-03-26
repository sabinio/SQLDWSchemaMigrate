cls

Import-Module 'C:\Repos\SQLDWSchemaMigrate\SQLDWSchemaMigrate\SQLDWSchemaMigrate.psm1' -force 

cls


###########################################################################################################################################################
$ServerName = 'asani-dw-live-eun-d003.database.windows.net'
$DatabaseName = 'ADSSourceSchema'
$targetDatabaseName = 'ADSTargetDatabase'

if ($DBCredential) {
    Write-Host "Using saved credential.."
}
else {    
    $DBCredential = Get-Credential 
}

$uName = $DBCredential.UserName
$pword = $DBCredential.GetNetworkCredential().Password

$VerbosePreference = 'silentlycontinue'


$sourceDbcon = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword
$targetDbcon = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $uName -password $pword
$columnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword





##########
#        #
# remove #
#        #
##########
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles
# Remove-CreateScriptForObjectsFiles $sourceDbcon $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -OutputDirectory $pathToSaveFiles                                                                                                                                        
# ##########
# #        #
# # export #
# #        #
# ##########

$date1=get-date

New-DDLStatementsTable -TargetDbCon $targetDbcon 

#Set-DatabaseScopedCredential -SourceDbcon $sourceDbcon -targetCon $targetDbcon
#Set-ExternalDataSource -SourceDbcon $sourceDbcon -targetCon $targetDbcon
#Set-ExternalFileFormat -SourceDbcon $sourceDbcon -targetCon $targetDbcon

#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon                                           -ObjectType "Schemas"        -TargetDbCon $targetDbcon  
#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon -SourceDBConnTabCreateStmnts $columnConn  -ObjectType "Tables"         -TargetDbCon $targetDbcon  
#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon -SourceDBConnTabCreateStmnts $columnConn  -ObjectType "ExternalTables"  -TargetDbCon $targetDbcon 
Export-ColumnChanges           -SourceDbcon $sourceDbcon -ColDbCon $columnConn -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $uName -password $pword -TargetColDbCon $targetDbcon   
#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon                                           -ObjectType "VIEW"                 -TargetDbCon $targetDbcon 
#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon                                           -ObjectType "SQL_SCALAR_FUNCTION" -TargetDbCon $targetDbcon  
#Export-CreateScriptsForObjects -SourceDbcon $sourceDbcon                                           -ObjectType "SQL_STORED_PROCEDURE" -TargetDbCon $targetDbcon 



Disconnect-SqlServer -sqlConnection $sourceDbcon
Disconnect-SqlServer -sqlConnection $targetDbcon
Disconnect-SqlServer -sqlConnection $columnConn


$taskTime = "Task took(HH:MM:SS:MS) "+(New-TimeSpan -Start $date1 -End (get-date))
write-Host $taskTime -ForegroundColor Yellow -BackgroundColor DarkGray