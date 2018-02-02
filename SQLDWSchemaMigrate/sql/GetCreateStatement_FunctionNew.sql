
SET NOCOUNT ON;

IF OBJECTPROPERTY(object_id('$(schema_name).$(object_name)'), N'IsScalarFunction') = 1

DROP PROCEDURE [$(schema_name)].[$(object_name)]
GO

$(createStatement)


