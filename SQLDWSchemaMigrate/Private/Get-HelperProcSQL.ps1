Function Get-HelperSQL {
    [CmdletBinding()]
    <#
.Synopsis
Returns the SQL needed to create the "helper" sql stored procedures.
.Description
Returns the SQL needed to create the "helper" sql stored procedures.
.Parameter SQLToGet
The name of the SQL to retrieve
.Example
Get-HelperSQL -SQLToGet 'usp_ConstructCreateStatementForExternalTable'
#>
    param(
        [string]$SQLToGet
    )

    switch ($SQLToGet) {
        'usp_ConstructCreateStatementForExternalTable' {
            $SQL = @'
CREATE PROC [usp_ConstructCreateStatementForExternalTable] @schemaName [VARCHAR](50),@tableName [VARCHAR](255),@nameAppendix [VARCHAR](255),@sqlCmd [VARCHAR](8000) OUT AS
        BEGIN
                SET NOCOUNT ON
                DECLARE @createClause AS VARCHAR(1000)
                DECLARE @columnOrdinal AS INT
                DECLARE @columnDefinition AS VARCHAR(255)
                DECLARE @columnList AS VARCHAR(8000)
                DECLARE @ExternalOptions AS VARCHAR(8000)
                SET @createClause = 
                'IF  NOT EXISTS (SELECT * FROM sys.objects 
                WHERE object_id = OBJECT_ID(N''[' + @schemaName + '].[' + @tableName + @nameAppendix + ']'') AND type in (N''U''))
                BEGIN
                CREATE EXTERNAL TABLE [' + @schemaName + '].[' + @tableName + @nameAppendix + ']'
                SET @columnList = '(' + CHAR(13)+CHAR(10) + '   '
                SET @columnDefinition = ''
                SET @columnOrdinal = 0
                WHILE @columnDefinition IS NOT NULL
                BEGIN
                        IF @columnOrdinal > 1
                                SET @columnList = @columnList + ',' + CHAR(13)+CHAR(10) + '   '
        
                        IF @columnOrdinal > 0
                                SET @columnList = @columnList + @columnDefinition
        
                        SET @columnOrdinal = @columnOrdinal + 1
        
                        SET @columnDefinition = (SELECT '[' + [COLUMN_NAME] + '] [' + [DATA_TYPE] + ']' 
                                                                                + CASE WHEN [DATA_TYPE] LIKE '%char%' THEN ISNULL('(' + CASE WHEN [CHARACTER_MAXIMUM_LENGTH] = '-1' THEN 'MAX'  WHEN [CHARACTER_MAXIMUM_LENGTH] != '-1' THEN CAST([CHARACTER_MAXIMUM_LENGTH] AS VARCHAR(10)) END + ')','') ELSE '' END
                                                                                + CASE WHEN [DATA_TYPE] LIKE '%binary%' THEN ISNULL('(' + CAST([CHARACTER_MAXIMUM_LENGTH] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                + CASE WHEN [DATA_TYPE] LIKE '%decimal%' THEN ISNULL('(' + CAST([NUMERIC_PRECISION] AS VARCHAR(10)) + ', ' + CAST([NUMERIC_SCALE] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                + CASE WHEN [DATA_TYPE] LIKE '%numeric%' THEN ISNULL('(' + CAST([NUMERIC_PRECISION] AS VARCHAR(10)) + ', ' + CAST([NUMERIC_SCALE] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                + CASE WHEN [DATA_TYPE] in ('datetime2','datetimeoffset') THEN ISNULL('(' + CAST([DATETIME_PRECISION] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                + CASE WHEN [IS_NULLABLE] = 'YES' THEN ' NULL' ELSE ' NOT NULL' END
                                                                FROM INFORMATION_SCHEMA.COLUMNS
                                                                WHERE [TABLE_SCHEMA] = @schemaName
                                                                AND [TABLE_NAME] = @tableName
                                                                AND [ORDINAL_POSITION] = @columnOrdinal)
                END
                SET @columnList = @columnList +  + CHAR(13)+CHAR(10) + ')'
                SET @ExternalOptions = (SELECT 'DATA_SOURCE = [' + exd.name + ']' 
            + ',LOCATION = N''' + ext.location + '''' 
            + ',FILE_FORMAT = [' + exf.name + ']' 
            +  ',REJECT_TYPE = ' + CAST (ext.reject_type as VARCHAR(10))
            +  ',REJECT_VALUE = ' + CAST (ext.reject_value as VARCHAR (10))
                + CASE WHEN ext.reject_sample_value != NULL THEN ',REJECT_SAMPLE_VALUE = ' + CAST (ext.reject_sample_value as VARCHAR(10)) ELSE '' END
        FROM sys.external_tables ext
        INNER JOIN sys.external_data_sources exd ON exd.data_source_id = ext.data_source_id
        INNER JOIN sys.external_file_formats exf ON exf.file_format_id = ext.file_format_id
        INNER JOIN sys.schemas sch on sch.schema_id = ext.schema_id
        WHERE ext.name = @tableName
        AND sch.name = @schemaName)
        
                SET @sqlCmd = @createClause
                                            + ' ' + @columnList
                                            + ' WITH ('  + CHAR(13)+CHAR(10) + @ExternalOptions
                                            + CHAR(13)+CHAR(10) + ')
                                            END'
        END
'@
        }


        'usp_ConstructCreateStatementForTable' {
            $SQL = @'
            CREATE PROC [usp_ConstructCreateStatementForTable] @schemaName [VARCHAR](50),@tableName [VARCHAR](255),@nameAppendix [VARCHAR](255),@sqlCmd [VARCHAR](8000) OUT AS
            BEGIN
                   SET NOCOUNT ON
                   DECLARE @distributionType AS VARCHAR(50)
                   DECLARE @distributionColumn AS VARCHAR(255)
                   DECLARE @indexType AS VARCHAR(50)
                   DECLARE @createClause AS VARCHAR(1000)
                   DECLARE @columnOrdinal AS INT
                   DECLARE @columnDefinition AS VARCHAR(255)
                   DECLARE @columnList AS VARCHAR(8000)
                   DECLARE @distributionClause AS VARCHAR(1000)
                   DECLARE @indexClause AS VARCHAR(1000)
                   SET @createClause = 
                   'IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[' + @schemaName + '].[' + @tableName + @nameAppendix + ']'') AND type in (N''U''))
BEGIN
	CREATE TABLE [' + @schemaName + '].[' + @tableName + @nameAppendix + ']'
                   SET @columnList = '(' + CHAR(13)+CHAR(10) + '   '
                   SET @columnDefinition = ''
                   SET @columnOrdinal = 0
                   WHILE @columnDefinition IS NOT NULL
                   BEGIN
                          IF @columnOrdinal > 1
                                 SET @columnList = @columnList + ',' + CHAR(13)+CHAR(10) + '   '
            
                          IF @columnOrdinal > 0
                                 SET @columnList = @columnList + @columnDefinition
            
                          SET @columnOrdinal = @columnOrdinal + 1
            
                          SET @columnDefinition = (SELECT '[' + c.[COLUMN_NAME] + '] [' + c.[DATA_TYPE] + ']' 
                                                                                 + CASE WHEN c.[DATA_TYPE] LIKE '%char%' THEN ISNULL('(' + CASE WHEN c.[CHARACTER_MAXIMUM_LENGTH] = '-1' THEN 'MAX'  WHEN c.[CHARACTER_MAXIMUM_LENGTH] != '-1' THEN CAST(c.[CHARACTER_MAXIMUM_LENGTH] AS VARCHAR(10)) END + ')','') ELSE '' END
                                                                                 + CASE WHEN c.[DATA_TYPE] LIKE '%binary%' THEN ISNULL('(' + CAST(c.[CHARACTER_MAXIMUM_LENGTH] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                 + CASE WHEN c.[DATA_TYPE] LIKE '%decimal%' THEN ISNULL('(' + CAST(c.[NUMERIC_PRECISION] AS VARCHAR(10)) + ', ' + CAST(c.[NUMERIC_SCALE] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                 + CASE WHEN c.[DATA_TYPE] LIKE '%numeric%' THEN ISNULL('(' + CAST(c.[NUMERIC_PRECISION] AS VARCHAR(10)) + ', ' + CAST(c.[NUMERIC_SCALE] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                 + CASE WHEN c.[DATA_TYPE] in ('datetime2','datetimeoffset') THEN ISNULL('(' + CAST(c.[DATETIME_PRECISION] AS VARCHAR(10)) + ')','') ELSE '' END
                                                                                 + CASE WHEN c.[IS_NULLABLE] = 'YES' THEN ' NULL' ELSE ' NOT NULL' END
																				 + CASE WHEN ISNULL(ident.is_identity,0) = 1 THEN ' IDENTITY (' + CAST(ident.seed_value AS VARCHAR(5)) + ',' + CAST(ident.increment_value AS VARCHAR(5)) + ')' ELSE '' END
                                                                   FROM INFORMATION_SCHEMA.COLUMNS c
																   LEFT JOIN	(
																				SELECT	s.name as [SCHEMA_NAME],
																						o.name as [TABLE_NAME],
																						c.name as [COLUMN_NAME],
																						c.is_identity,
																						i.seed_value,
																						i.increment_value
																				FROM	sys.schemas s 
																				JOIN	sys.objects o on s.schema_id = o.schema_id
																				JOIN	sys.columns c on o.object_id = c.object_id
																				JOIN	sys.identity_columns i on o.object_id = i.object_id 
																											and c.column_id = i.column_id
																				) ident ON c.[TABLE_SCHEMA] = ident.[SCHEMA_NAME]
																						AND c.[TABLE_NAME] = ident.[TABLE_NAME]
																						AND c.[COLUMN_NAME] = ident.[COLUMN_NAME]
                                                                   WHERE c.[TABLE_SCHEMA] = @schemaName
                                                                   AND c.[TABLE_NAME] = @tableName
                                                                   AND c.[ORDINAL_POSITION] = @columnOrdinal)

                   END
                   SET @columnList = @columnList +  + CHAR(13)+CHAR(10) + ')'
                   SET @distributionType = (
                          SELECT tdp.[distribution_policy_desc]
                          FROM sys.pdw_table_distribution_properties tdp
                          INNER JOIN sys.tables t
                                 ON tdp.[object_id] = t.[object_id]
                          INNER JOIN sys.schemas s
                                 ON t.[schema_id] = s.[schema_id]
                          WHERE t.[name] = @tableName
                          AND s.[name] = @schemaName
                   )
            
                   SET @distributionColumn = (
                          SELECT c.[name]
                          FROM sys.pdw_column_distribution_properties cdp 
                          INNER JOIN sys.tables t
                                 ON cdp.[object_id] = t.[object_id]
                          INNER JOIN sys.schemas s
                                 ON t.[schema_id] = s.[schema_id]
                          INNER JOIN sys.columns c
                                 ON t.[object_id] = c.[object_id]
                                 AND cdp.[column_id] = c.[column_id]
                          WHERE t.[name] = @tableName
                          AND s.[name] = @schemaName
                          AND cdp.[distribution_ordinal] = 1
                   )
            
                   SET @distributionClause = ' DISTRIBUTION = '
                                                              + @distributionType
                                                              + ISNULL(' ( [' + @distributionColumn + '] )','')
                   SET @indexType = (
                          SELECT idx.[type_desc]
                          FROM sys.indexes idx
                          INNER JOIN sys.tables t
                                 ON idx.[object_id] = t.[object_id]
                          INNER JOIN sys.schemas s
                                 ON t.[schema_id] = s.[schema_id]
                          WHERE t.[name] = @tableName
                          AND s.[name] = @schemaName
                   )
            
                   IF @indexType LIKE 'CLUSTERED%' 
                   SET @indexClause = @indexType + ' INDEX'
                   ELSE IF @indexType = 'HEAP'
                   SET @indexClause = @indexType
            
                   IF @indexType = 'CLUSTERED'
                   BEGIN
                          DECLARE @objectID BIGINT = (SELECT t.[object_id]
                                                                          FROM [sys].[tables] t
                                                                          INNER JOIN [sys].[schemas] sch ON t.[schema_id] = sch.[schema_id]
                                                                          WHERE t.[name] = @tableName
                                                                          AND sch.[name] = @schemaName)
                          DECLARE @indexColumns VARCHAR(1000) = ' ('
                          DECLARE @countIndexColumns INT = (SELECT COUNT(*) FROM [sys].[index_columns] WHERE [object_id] = @objectId and [index_id] = 1)
                          DECLARE @indexColumnOrdinal INT = 1
                          DECLARE @indexColumnName VARCHAR(1000)
                          DECLARE @indexColumnSortDirection VARCHAR(1000)
                          WHILE @indexColumnOrdinal <= @countIndexColumns
                          BEGIN
                                 SET @columnOrdinal = (SELECT [column_id]
                                                                     FROM [sys].[index_columns]
                                                                     WHERE [object_id] = @objectId and [index_id] = 1 and [key_ordinal] = @indexColumnOrdinal)
                                 SET @indexColumnSortDirection = (SELECT CASE WHEN [is_descending_key] = 1 THEN ' DESC' ELSE ' ASC' END
                                                                                       FROM [sys].[index_columns]
                                                                                       WHERE [object_id] = @objectId and [index_id] = 1 and [key_ordinal] = @indexColumnOrdinal)
                                 SET @indexColumnName = (SELECT '[' + [COLUMN_NAME] + ']'
                                                                          FROM INFORMATION_SCHEMA.COLUMNS
                                                                          WHERE [TABLE_SCHEMA] = @schemaName
                                                                          AND [TABLE_NAME] = @tableName
                                                                          AND [ORDINAL_POSITION] = @columnOrdinal)
                                 IF @indexColumnOrdinal > 1
                                       SET @indexColumns = @indexColumns + ', '
                                 SET @indexColumns = @indexColumns + @indexColumnName + @indexColumnSortDirection
                                 SET @indexColumnOrdinal = @indexColumnOrdinal + 1
                          END
                          SET @indexColumns = @indexColumns + ')'
                          SET @indexClause = @indexClause + @indexColumns
                   END
                   SET @sqlCmd = @createClause
                                              + ' ' + @columnList
                                              + ' WITH ('  + CHAR(13)+CHAR(10) + @distributionClause
                                              + ', ' + @indexClause
                                              + CHAR(13)+CHAR(10) + ')
END'
            END
'@
        }
        'AddTableChanges' {
            $SQL = @'


            SET NOCOUNT ON;

            -- All tables currently in "production db" that are also in sourceColumns table
            SELECT *
                ,row_number() OVER (
                    ORDER BY (
                            SELECT 0
                            )
                    ) AS number
            INTO #Temp1
            FROM (
                SELECT DISTINCT 
                sch.name As schema_name
                    ,obj.name AS object_name
                    ,obj.object_id
                FROM sys.tables obj
                INNER JOIN sys.schemas sch ON obj.schema_id = sch.schema_id
                INNER JOIN sourceColumns sc on sc.tablename = obj.name
                WHERE is_external = 0
                    AND obj.name NOT LIKE '%_Backup%'
                    AND obj.name NOT LIKE '%_BKP%'
                    AND obj.name NOT LIKE '%_tmp%'
                    AND obj.name NOT LIKE '%_wDuplicates%'
                    AND sch.name != 'temp'
                    AND sch.name = sc.schemaname
                    AND NOT (obj.name LIKE '%Source%')
                ) A
            
            DECLARE @TotalTables INT
            DECLARE @counter INT
            DECLARE @currentTable NVARCHAR(max);
            DECLARE @currentSchema NVARCHAR(max);
            DECLARE @objectSchemaAndName NVARCHAR(max);
            
            DECLARE @Now DATETIME;
            SET @Now = GETDATE();
            
            SET @TotalTables = (
                    SELECT count(*)
                    FROM #Temp1
                    );
            SET @counter = 1
            -- Looping through all tables in "production" and checking for deltas
            WHILE (@counter <= @TotalTables)
            BEGIN
                -- Current table in prod db and collecting all column names it should have based on source columns
                SELECT 	@currentTable = object_name,
                        @currentSchema = schema_name,
                        @objectSchemaAndName = schema_name + '.' + object_name
                FROM #Temp1
                WHERE number = @counter
            
               
                SELECT sys.columns.name
                    ,sys.columns.user_type_id, sys.columns.max_length
                INTO #tempprodtablecolumns
                FROM sys.columns
                INNER JOIN sys.tables ON sys.columns.object_id = sys.tables.object_id
                INNER JOIN sys.schemas ON sys.tables.schema_id = sys.schemas.schema_id 
                WHERE sys.tables.name = @currentTable
                    AND sys.schemas.name = @currentSchema;
                
                SELECT schemaname 
                    ,tablename
                    ,colname
                    ,user_type_id
                    ,max_length
					,is_identity
					,seed_value
					,increment_value
                INTO #tempdevtablecolumns
                FROM sourceColumns
                WHERE tablename = @currentTable
                AND schemaname = @currentSchema
            
                -- Find newly added columns not in "production" into temp table
                SELECT user_type_id
                    ,colname
                    ,row_number() OVER (
                        ORDER BY (
                                SELECT 0
                                )
                        ) AS number,
                        max_length,
						is_identity,
						seed_value,
						increment_value
                INTO #addedcolumns
                FROM (
                    SELECT b.*
                        ,a.user_type_id missingcolumn, a.max_length prod_max_length
                    FROM #tempprodtablecolumns a
                    RIGHT JOIN #tempdevtablecolumns b ON a.name = b.colname
                    ) A
                WHERE missingcolumn IS NULL;
                -- Clean up temp tables
                DROP TABLE #tempprodtablecolumns;
            
                DROP TABLE #tempdevtablecolumns;
            
                DECLARE @totalnewcolumns INT
                DECLARE @secondcounter INT
                DECLARE @currentcolname NVARCHAR(max);
                DECLARE @currentcoltype NVARCHAR(max);
                DECLARE @coltypename NVARCHAR(max);
				DECLARE @colidentity NVARCHAR(max);
				DECLARE @currentColIsIdentity INT;
				DECLARE @currentColIsIdentitySeed INT;
				DECLARE @currentColIsIdentityIncrement INT;
                DECLARE @currentcollength NVARCHAR(max) = '';
                DECLARE @SQL NVARCHAR(max);
            
                SET @totalnewcolumns = (
                        SELECT count(*)
                        FROM #addedcolumns
                        );
                SET @secondcounter = 1
            
                PRINT 'Total new columns for table '+ @currentSchema +'.'+ @currentTable + ' is ' + CONVERT(VARCHAR(10), @totalnewcolumns);
            
                -- Loop through added columns and adding columns in "production" table
                WHILE (@secondcounter <= @totalnewcolumns)
                BEGIN

                    SET @colidentity = ''
				
					SELECT	@currentcolname = colname,
							@currentcoltype = user_type_id,
							@currentColIsIdentity = is_identity, 
							@currentColIsIdentitySeed = seed_value, 
							@currentColIsIdentityIncrement = increment_value
					FROM	#addedcolumns
					WHERE	number = @secondcounter;					
					
					
					SET @coltypename = (
                            SELECT name
                            FROM sys.types
                            WHERE user_type_id = @currentcoltype
                            )
                    IF (@currentcoltype IN (231, 167, 175, 239))
                    BEGIN
                            SET @currentcollength = ' ('+(
                                    SELECT CAST (max_length as nvarchar (8)) + ')'
                                    FROM #addedcolumns
                                    WHERE number = @secondcounter 
                            );
                            SET @coltypename = @coltypename + @currentcollength
                    END

					IF (@currentColIsIdentity = 1)
					BEGIN
							SET @colidentity = ' IDENTITY (' + CAST(@currentColIsIdentitySeed AS VARCHAR(5)) + ',' +  CAST(@currentColIsIdentityIncrement AS VARCHAR(5)) + ')'
					END

                    SET @SQL = 'ALTER TABLE ' + @currentSchema +'.'+ @currentTable + ' ADD ' + @currentcolname + ' ' + @coltypename + @colidentity;
            
                    PRINT '---------- Altering statement: ' + @SQL + ' ---------- ';
            
                    INSERT INTO DDLStatements (TargetObject, DDLStmt, CreateDate) VALUES (@objectSchemaAndName, @SQL, @Now)            

                    EXEC (@SQL);
            
                    SET @secondcounter = @secondcounter + 1
                END
            
                DROP TABLE #addedcolumns
            
                SET @counter = @counter + 1;
            END
            
            DROP TABLE #Temp1;          
            
'@            
        }
        default {$SQL = 'OOPS!'}
    }

    return $SQL    




}