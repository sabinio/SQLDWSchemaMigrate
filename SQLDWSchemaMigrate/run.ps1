Get-ChildItem
Clear-Host
Import-Module "C:\Users\richardlee\source\repos\inf-pe-adw-deploy\MigrateAzureSQLDW" -Force
Start-Sleep -Seconds 1

$ServerName = "asani-dw-live-eun-d003.database.windows.net"
$DatabaseName = "AdwSourceSample"
$aaduName = "richardlee@asos.com"
$aadpword = "Necrozma#0800"

# $uname = "me"
# $pword = "Passwords4U"

$targetDatabaseName = "AdwTargetDatabase"

$conn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword
$columnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword
$targetConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $aaduName -password $aadpword
$targetColumnConn = Connect-SqlServer -sqlServerName $ServerName -sqlDatabaseName $targetDatabaseName -userName $aaduName -password $aadpword

$listSchemasQuery = Get-ListQuery "Schemas" 
$listStoredProceduresQuery = Get-ListQuery "StoredProcedures"
$listTablesQuery = Get-ListQuery "Tables"
$listFunctionsQuery = Get-ListQuery "ScalarFunctions"
$listViewsQuery = Get-ListQuery "Views"

##########
#        #
# remove #
#        #
##########
Remove-CreateScriptForObjectsFiles $conn $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName
Remove-CreateScriptForObjectsFiles $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName   
Remove-CreateScriptForObjectsFiles $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName                                                                                                                                         
   

##########
#        #
# export #
#        #
##########
$d1 = Get-Date -Format "HH:mm:ss"
Export-CreateScriptsForObjects $conn $listSchemasQuery "Schemas" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-ColumnChanges $conn $columnConn $listTablesQuery "Tables" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName -TargetColDbCon $targetColumnConn
Export-CreateScriptsForObjects $conn $listFunctionsQuery "ScalarFunctions" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listViewsQuery "Views" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName
Export-CreateScriptsForObjects $conn $listStoredProceduresQuery "StoredProcedures" -sqlServerName $ServerName -sqlDatabaseName $DatabaseName -userName $aaduName -password $aadpword -TargetDbCon $targetConn -TargetSqlServerName $ServerName -sqlTargetDatabaseName $targetDatabaseName

Disconnect-SqlServer -sqlConnection $conn
Disconnect-SqlServer -sqlConnection $targetConn
Disconnect-SqlServer -sqlConnection $columnConn
Disconnect-SqlServer -sqlConnection $targetColumnConn

Write-Host $d1
Get-Date -Format "HH:mm:ss"