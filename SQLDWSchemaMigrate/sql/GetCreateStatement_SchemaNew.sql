SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '$(schema_name)')
BEGIN
DECLARE @autoDeploy [VARCHAR](MAX);
SET @autoDeploy = 'EXEC (''CREATE SCHEMA ' + '$(schema_name)' + ' AUTHORIZATION ' + '$(authorisation_name)'')'
END
EXEC (@autoDeploy)