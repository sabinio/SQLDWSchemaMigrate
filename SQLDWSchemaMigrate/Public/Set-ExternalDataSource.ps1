Function Set-ExternalDataSource {
    [CmdletBinding()]
    <#
.Synopsis
Creates External Data Sources
.Description
Get each of the external data sources from the source database.
If External Data Source does not exist on target server, it is created.
.Parameter SourceDbcon
The source database connection
.Parameter TargetDbCon
The target database connection
.Example
Set-ExternalDataSources -SourceDbcon $conn -TargetDbCon $TargetDbConn
#>
    param(
        [System.Data.SqlClient.SqlConnection]$SourceDbcon, 
        [System.Data.SqlClient.SqlConnection]$TargetDbCon
    )
    $sqlCommandText = "select eds.name, eds.type_desc, eds.location, dsc.name as credname, eds.database_name, eds.shard_map_name, eds.resource_manager_location from sys.external_data_sources eds
    left join sys.database_scoped_credentials dsc on dsc.credential_id = eds.credential_id"
    $GetDataSourceListCmd = New-Object System.Data.SqlClient.SqlCommand
    $GetDataSourceListCmd.Connection = $SourceDbcon
    $GetDataSourceListCmd.CommandText = $sqlCommandText
    $DataSourceListReader = $GetDataSourceListCmd.ExecuteReader();
    if ($DataSourceListReader.HasRows) {
        while ($DataSourceListReader.Read()) {
            $extDsname = $DataSourceListReader.GetString(0)
            $extTypeDesc = $DataSourceListReader.GetString(1)
            $extLocation = $DataSourceListReader.GetString(2)
            if (!$DataSourceListReader.IsDBNull($DataSourceListReader.GetOrdinal("credname"))) {
                $extCredentialName = $DataSourceListReader.GetString(3)
            }
            else {$extCredentialName = $null}
            if (!$DataSourceListReader.IsDBNull($DataSourceListReader.GetOrdinal("database_name"))) {
                $extDatabasename = $DataSourceListReader.GetString(4)
            }
            else {$extDatabasename = $null}
            if (!$DataSourceListReader.IsDBNull($DataSourceListReader.GetOrdinal("shard_map_name"))) {
                $extShardMapName = $DataSourceListReader.GetString(5)
            }
            if (!$DataSourceListReader.IsDBNull($DataSourceListReader.GetOrdinal("resource_manager_location"))) {
                $extResourceManagerLocation = $DataSourceListReader.GetString(6)
            }
            else {$extResourceManagerLocation = $null}
            $createExternalDataSource = "IF NOT EXISTS (SELECT NAME FROM sys.external_data_sources ds where ds.name = '$extDsname' )
            CREATE EXTERNAL DATA SOURCE $extDsname WITH (
            TYPE = $extTypeDesc
            ,LOCATION = '$extLocation'
            " 
            if ($null -ne $extCredentialName) {
                $createExternalDataSource = $createExternalDataSource + ",CREDENTIAL = [$extCredentialName]
            "
            }
            if ($null -ne $extDatabaseName) {
                $createExternalDataSource = $createExternalDataSource + ",DATABASE_NAME = '$extDatabaseName'
            "
            }
            if ($null -ne $extShardmapName) {
                $createExternalDataSource = $createExternalDataSource + ", SHARD_MAP_NAME = '$extShardMapName'
            "
            }
            if ($null -ne $extResourceManagerLocation) {
                $createExternalDataSource = $createExternalDataSource + ", 'RESOURCE_MANAGER_LOCATION' = $extResourceManagerLocation
            "
            }
            $createExternalDataSource = $createExternalDataSource + " );"
            $TargetDataSourceCmd = New-Object System.Data.SqlClient.SqlCommand
            $TargetDataSourceCmd.Connection = $TargetDbCon
            $TargetDataSourceCmd.CommandText = $createExternalDataSource
            try {
                $TargetDataSourceCmd.ExecuteNonQuery() | Out-Null    
            }
            catch {
                Throw $_.Exception
            }
        }
    }
    $DataSourceListReader.Dispose()
}