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