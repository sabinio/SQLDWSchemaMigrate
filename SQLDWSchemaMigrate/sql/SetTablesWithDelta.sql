

SET NOCOUNT ON;

DELETE
FROM sourceColumns
WHERE tablename IN (
		'sourceColumns'
		,'sourceColumnsNew'
		,'SourceDefinitions'
		)

SELECT DISTINCT tablename
	,COUNT(colname) AS SourceSumofColumns
INTO #tempSourceColumns
FROM sourceColumns
GROUP BY tablename

SELECT DISTINCT o.name AS tableName
	,COUNT(c.name) AS TargetSumOfColumns
INTO #tempTargetColumns
FROM sys.columns c
INNER JOIN sys.objects o ON c.object_id = o.object_id
WHERE o.type = 'U'
	AND o.name NOT IN (
		'sourceColumns'
		,'sourceColumnsNew'
		,'SourceDefinitions'
		)
GROUP BY o.name

DELETE
FROM sourceColumns
WHERE tablename IN (
		SELECT DISTINCT ttc.tableName
		FROM #tempTargetColumns ttc
		LEFT JOIN #tempSourceColumns tsc ON ttc.tableName = tsc.tableName
		LEFT JOIN sourceColumns sc ON sc.tablename = tsc.tablename
		WHERE tsc.SourceSumofColumns = ttc.TargetSumOfColumns
		)

DROP TABLE #tempSourceColumns

DROP TABLE #tempTargetColumns

