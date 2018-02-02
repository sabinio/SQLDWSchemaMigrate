DECLARE @sourceColumnsTotal INT;

SET @sourceColumnsTotal = (
		SELECT COUNT(*)
		FROM sourceColumns
		WHERE tablename NOT IN (
				'sourceColumns'
				,'sourceColumnsNew'
				,'SourceDefinitions'
				)
		);

DECLARE @targetColumnsTotal INT;

SET @targetColumnsTotal = (
		SELECT COUNT(*)
		FROM sys.columns c
		INNER JOIN sys.objects o ON c.object_id = o.object_id
		WHERE o.type = 'U'
			AND o.name NOT IN (
				'sourceColumns'
				,'sourceColumnsNew'
				,'SourceDefinitions'
				)
		);

IF @sourceColumnsTotal > @targetColumnsTotal
SELECT 'moreInSourceThanInTarget'
IF @sourceColumnsTotal = @targetColumnsTotal
SELECT 'sameInSourceAndTarget'
IF @sourceColumnsTotal < @targetColumnsTotal
SELECT 'LessInSourceThanInTarget'