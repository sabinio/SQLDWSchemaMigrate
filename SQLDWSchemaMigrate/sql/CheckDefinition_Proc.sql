
SET NOCOUNT ON;

DECLARE @objectName [VARCHAR](255);
SET @objectName =	(SELECT DISTINCT OBJECT_NAME($(object_id))  
					FROM sys.objects);

DECLARE @schemaName [VARCHAR](255);
SET @schemaName = (SELECT DISTINCT SCHEMA_NAME($(schema_id))
                   FROM sys.objects);

DECLARE @checkDiff [VARCHAR] (MAX)
SET @checkDiff = '
if exists (select replace(rtrim(ltrim(object_definition)), char(13) + char(10), '''') from sourceDefinitions sd
inner join [sys].[sql_modules] sql on replace(replace(rtrim(ltrim(sql.definition)), char(13) + char(10), ''''), '''''''','''') = replace(rtrim(ltrim(object_definition)), char(13) + char(10), '''')
						inner join sys.objects obj on obj.object_id = sql.object_id
						inner join sys.schemas sch on sch.schema_id = obj.schema_id
where 
						objectname = '''+@objectName+'''
						and
						schemaname = '''+@schemaName+'''
                        and
                        type_desc = ''SQL_STORED_PROCEDURE'')
PRINT ''identical''
ELSE
PRINT ''different'''
SELECT @checkDiff
