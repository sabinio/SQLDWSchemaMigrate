SET NOCOUNT ON;
DECLARE @autoDeploy [VARCHAR](MAX);
SET @autoDeploy = 'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''$(schema_name)'')
BEGIN
DECLARE @createSchema NVARCHAR (MAX)
EXEC (''CREATE SCHEMA' + ' $(schema_name)' + ' AUTHORIZATION ' + ' $(authorisation_name)'')	
END'
SELECT @autoDeploy