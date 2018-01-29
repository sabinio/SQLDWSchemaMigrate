SET NOCOUNT ON;

DECLARE @objectId AS BIGINT;
SET @objectId = $(object_id);

DECLARE @schemaName AS [VARCHAR](50);
DECLARE @tableName [VARCHAR](255);

SET @schemaName = (SELECT sch.[name]
				   FROM [sys].[objects] obj
				   INNER JOIN [sys].[schemas] sch
				   ON obj.[schema_id] = [sch].[schema_id]
				   WHERE obj.[object_id] = @objectId);
SET @tableName = (SELECT obj.[name]
				  FROM [sys].[objects] obj
				  WHERE obj.[object_id] = @objectId);

DECLARE @sqlCmd AS VARCHAR(8000);
EXEC [usp_ConstructCreateStatementForTable] @schemaName, @tableName, '', @sqlCmd OUTPUT;
SELECT @sqlCmd;