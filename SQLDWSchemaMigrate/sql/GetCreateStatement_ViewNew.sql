
SET NOCOUNT ON;

IF OBJECTPROPERTY(object_id('$(schema_name).$(object_name)'), N'IsView') = 1

DROP VIEW [$(schema_name)].[$(object_name)]
GO

$(createStatement)


