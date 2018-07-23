
Function Compare-ExternalTables {
    <#
   .Synopsis
   Compares the external tables between target and source databases
   .Description
   Compares the external tables between target and source databases
   Returns an array giving object name (Schema.TableName) and type of difference. Any type of difference is checked (only on one DB, or different between the two) 
   .Parameter sourceConn
   Connection to source database.
   .Parameter targetConn
   Connection to target database.
    .Example
    $Differences = Compare-ExternalTables -sourceConn $DbCon -targetConn $TargetColDbCon
   #>
    [CmdletBinding()]
    param(
        [System.Data.SqlClient.SqlConnection]$sourceConn, 
        [System.Data.SqlClient.SqlConnection]$targetConn
    )


    Write-Verbose "Comparing external tables on DB $($sourceConn.Database) on server $($sourceConn.DataSource) with DB $($targetConn.Database) on server $($targetConn.DataSource).."

    $sqlQuery = ";WITH WorkingCTE AS (
        select 
        s.[Name] as SchemaName,
        o.[Name] as ObjectName,
        c.[Name] as ColumnName,
        c.[column_id], c.[system_type_id], c.[user_type_id], c.[max_length], c.[precision], c.[scale], c.[collation_name], c.[is_nullable], c.[is_ansi_padded], c.[is_rowguidcol], c.[is_identity], c.[is_computed], c.[is_filestream], c.[is_replicated], c.[is_non_sql_subscribed], c.[is_merge_published], c.[is_dts_replicated], c.[is_xml_document], c.[xml_collection_id], c.[default_object_id], c.[rule_object_id], c.[is_sparse], c.[is_column_set], c.[generated_always_type], c.[generated_always_type_desc], c.[encryption_type], c.[encryption_type_desc], c.[encryption_algorithm_name], c.[column_encryption_key_id], c.[column_encryption_key_database_name], c.[is_hidden], c.[is_masked], c.[graph_type], c.[graph_type_desc]
        from sys.columns c
        INNER JOIN sys.objects o ON c.object_id = o.object_id
        INNER JOIN sys.schemas s ON s.schema_id = o.schema_id
        INNER JOIN sys.tables t ON t.object_id= o.object_id
        WHERE t.is_external = 1
        ),
        WorkingCTE1 AS (
       select	s.Name as SchemaName,
            et.Name as ExternalTableName,
            et.location,
            et.reject_type,
            et.reject_value,
            eds.Name as ExternalDataSourceName,
            eff.Name as FileformatName
    from	sys.external_tables et
    join	sys.schemas s on et.schema_id = s.schema_id
    join	sys.external_data_sources eds on et.data_source_id = eds.data_source_id
    join	sys.external_file_formats eff on et.file_format_id = eff.file_format_id
        )
        select  SchemaName + '.' + ObjectName as ObjectName, 
                SchemaName + '.' + ObjectName + '|' + ColumnName + '|' + CONVERT(VARCHAR(20),CHECKSUM(*)) as rowhash 
        from WorkingCTE
        UNION ALL
        select SchemaName + '.' + ExternalTableName as ObjectName,  
                SchemaName + '.' + ExternalTableName + '|' + CONVERT(VARCHAR(20),CHECKSUM(*)) as rowhash 
        from WorkingCTE1"

    $sourceResultSet = New-Object "System.Data.DataSet" "DsCols"
    $dataAdapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($sqlQuery, $sourceConn);
    $dataAdapter.Fill($sourceResultSet) | Out-Null 
    $sourceColumnHashes = $sourceResultSet.Tables[0] | Select-Object ObjectName, rowhash
    Write-Verbose "SourceDB object rows: $((($sourceColumnHashes) | Measure-Object).Count)"

    $targetResultSet = New-Object "System.Data.DataSet" "DsCols"
    $dataAdapter = new-object "System.Data.SqlClient.SqlDataAdapter" ($sqlQuery, $targetConn);
    $dataAdapter.Fill($targetResultSet) | Out-Null    
    $targetColumnHashes = $targetResultSet.Tables[0] | Select-Object ObjectName, rowhash
    Write-Verbose "TargetDB object rows: $((($targetColumnHashes) | Measure-Object).Count)"

    # If there are no results from the target database:
    if (!$targetColumnHashes) {
        Write-Verbose "No external tables exist in the target database"
        if ($sourceColumnHashes) {
            $diffs = @()
            $sourceColumnHashes | ForEach-Object {
                $diffs += (New-Object -Type psobject -Property  @{'ObjectName' =$_.ObjectName;  'ComparisonResult' = 'SourceOnly'    })                
            }
            $comparisonResults = $diffs | Select-Object ObjectName, ComparisonResult | Sort-Object -Property ObjectName  -Unique 
        }        
    }

    # If there are no results from the source database:
    if (!$sourceColumnHashes) {
        Write-Verbose "No external tables exist in the source database"
        if ($targetColumnHashes) {
            $diffs = @()
            $targetColumnHashes | ForEach-Object {
                $diffs += (New-Object -Type psobject -Property  @{'ObjectName' =$_.ObjectName;  'ComparisonResult' = 'TargetOnly'    })                
            }
            $comparisonResults = $diffs | Select-Object ObjectName, ComparisonResult | Sort-Object -Property ObjectName  -Unique 
        }        
    }
    
    if ($sourceColumnHashes -and $targetColumnHashes) {
        Write-Verbose "External tables exist in both source and target databases"
        $diffs = @()
        $same = @()
        $comparisonResults = @()

        # Objects only in source or only in target database:
        Compare-Object -ReferenceObject $sourceColumnHashes -DifferenceObject $targetColumnHashes -Property ObjectName | 
        Sort-Object ObjectName -Unique | 
        where-object {@('=>','<=') -contains $_.SideIndicator} -PipelineVariable diff | 
        ForEach-Object {
            $ComparisonResult = if($diff.SideIndicator -eq '=>') {'TargetOnly'} else {'SourceOnly'}
            $diffs += (New-Object -Type psobject -Property  @{'ObjectName' = $diff.ObjectName;  'ComparisonResult' = $ComparisonResult   })                
        }
        $comparisonResults += $diffs
    
        # Objects which differ
         Compare-Object -ReferenceObject $sourceColumnHashes -DifferenceObject $targetColumnHashes -Property RowHash -PipelineVariable Diff | ForEach-Object {        
             $ObjectName = ($diff.RowHash -split '\|')[0]             
             $diffs += (New-Object -Type psobject -Property  @{'ObjectName' = $ObjectName;  'ComparisonResult' = 'Differ'    })                
         }
         $comparisonResults += $diffs | Select-Object ObjectName, ComparisonResult | 
                                        Sort-Object -Property ObjectName, ComparisonResult -Unique | 
                                        Where-Object {$comparisonResults.ObjectName -notcontains $_.ObjectName}

         # Matching objects
         Compare-Object -ReferenceObject $sourceColumnHashes -DifferenceObject $targetColumnHashes -IncludeEqual -ExcludeDifferent -Property ObjectName | 
         Sort-Object ObjectName -Unique -PipelineVariable diff | 
         ForEach-Object {
             $same += (New-Object -Type psobject -Property  @{'ObjectName' = $diff.ObjectName;  'ComparisonResult' = 'Equal'   })                
         }
         $comparisonResults += $same | Select-Object ObjectName, ComparisonResult | 
                                       Sort-Object -Property ObjectName, ComparisonResult -Unique | 
                                       Where-Object {$comparisonResults.ObjectName -notcontains $_.ObjectName}


    }

    Write-Verbose "Comparison summary:"
    Write-Verbose "    SourceOnly: $(($comparisonResults | Where-Object {$_.ComparisonResult -eq 'SourceOnly'} | Measure-Object).Count)"
    Write-Verbose "    TargetOnly: $(($comparisonResults | Where-Object {$_.ComparisonResult -eq 'TargetOnly'} | Measure-Object).Count)"
    Write-Verbose "    Differ    : $(($comparisonResults | Where-Object {$_.ComparisonResult -eq 'Differ'} | Measure-Object).Count)"
    Write-Verbose "    Equal     : $(($comparisonResults | Where-Object {$_.ComparisonResult -eq 'Equal'} | Measure-Object).Count)"

    $comparisonResults | out-file 'c:\temp\foo1.txt'

    Return $comparisonResults 

}
