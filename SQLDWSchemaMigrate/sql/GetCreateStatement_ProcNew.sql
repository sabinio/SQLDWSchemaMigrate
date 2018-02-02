
SET NOCOUNT ON;

IF OBJECTPROPERTY(object_id('$(schema_name).$(object_name)'), N'IsProcedure') = 1

DROP PROCEDURE [$(schema_name)].[$(object_name)]
GO

$(createStatement)


