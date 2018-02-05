

SET NOCOUNT ON;

-- All tables currently in "production db"
SELECT *
	,row_number() OVER (
		ORDER BY (
				SELECT 0
				)
		) AS number
INTO #Temp1
FROM (
	SELECT DISTINCT obj.name AS object_name
		,obj.object_id
	FROM sys.tables obj
	INNER JOIN sys.schemas sch ON obj.schema_id = sch.schema_id
	INNER JOIN sourceColumns sc on sc.tablename = obj.name
	WHERE is_external = 0
		AND obj.name NOT LIKE '%_Backup%'
		AND obj.name NOT LIKE '%_BKP%'
		AND obj.name NOT LIKE '%_tmp%'
		AND obj.name NOT LIKE '%_wDuplicates%'
		AND sch.name != 'temp'
		AND NOT (obj.name LIKE '%Source%')
		AND obj.name IN (select distinct sc.tablename from sourceColumns sc)
	) A

DELETE FROM #Temp1 WHERE #Temp1.object_name NOT IN (SELECT sc.tablename FROM sourceColumns sc)

DECLARE @TotalTables INT
DECLARE @counter INT
DECLARE @currentTable NVARCHAR(max);

SET @TotalTables = (
		SELECT count(*)
		FROM #Temp1
		);
SET @counter = 1

-- Looping through all tables in "production" and checking for deltas
WHILE (@counter <= @TotalTables)
BEGIN
	-- Current table in prod db and collecting all column names it should have based on source columns
	SET @currentTable = (
			SELECT object_name
			FROM #Temp1
			WHERE number = @counter
			);

	SELECT sys.columns.name
		,sys.columns.user_type_id, sys.columns.max_length
	INTO #tempprodtablecolumns
	FROM sys.columns
	INNER JOIN sys.tables ON sys.columns.object_id = sys.tables.object_id
	WHERE sys.tables.name = @currentTable;

	SELECT tablename
		,colname
		,user_type_id
		,max_length
	INTO #tempdevtablecolumns
	FROM sourceColumns
	WHERE tablename = @currentTable

	-- Find newly added columns not in "production" into temp table
	SELECT user_type_id
		,colname
		,row_number() OVER (
			ORDER BY (
					SELECT 0
					)
			) AS number,
			max_length
	INTO #addedcolumns
	FROM (
		SELECT b.*
			,a.user_type_id missingcolumn, a.max_length prod_max_length
		FROM #tempprodtablecolumns a
		RIGHT JOIN #tempdevtablecolumns b ON a.name = b.colname
		) A
	WHERE missingcolumn IS NULL;

	SELECT *
	FROM #tempprodtablecolumns

	SELECT *
	FROM #tempdevtablecolumns

	SELECT *
	FROM #addedcolumns

	-- Clean up temp tables
	DROP TABLE #tempprodtablecolumns;

	DROP TABLE #tempdevtablecolumns;

	DECLARE @totalnewcolumns INT
	DECLARE @secondcounter INT
	DECLARE @currentcolname NVARCHAR(max);
	DECLARE @currentcoltype NVARCHAR(max);
	DECLARE @coltypename NVARCHAR(max);
	DECLARE @currentcollength NVARCHAR(max) = '';
	DECLARE @SQL NVARCHAR(max);

	SET @totalnewcolumns = (
			SELECT count(*)
			FROM #addedcolumns
			);
	SET @secondcounter = 1

	PRINT 'Total new columns for table ' + @currentTable + ' is ' + CONVERT(VARCHAR(10), @totalnewcolumns);

	-- Loop through added columns and adding columns in "production" table
	WHILE (@secondcounter <= @totalnewcolumns)
	BEGIN
		SET @currentcolname = (
				SELECT colname
				FROM #addedcolumns
				WHERE number = @secondcounter
				);
		SET @currentcoltype = (
				SELECT user_type_id
				FROM #addedcolumns
				WHERE number = @secondcounter
				);
		SET @coltypename = (
				SELECT name
				FROM sys.types
				WHERE user_type_id = @currentcoltype
				)
		IF (@currentcoltype = 231)
		BEGIN
				SET @currentcollength = ' ('+(
						SELECT CAST (max_length as nvarchar (8)) + ')'
						FROM #addedcolumns
						WHERE number = @secondcounter 
				);
				SET @coltypename = @coltypename + @currentcollength
		END
		SET @SQL = 'ALTER TABLE ' + @currentTable + ' ADD ' + @currentcolname + ' ' + @coltypename;

		PRINT '---------- Altering statement: ' + @SQL + ' ---------- ';

		EXEC (@SQL);

		SET @secondcounter = @secondcounter + 1
	END

	DROP TABLE #addedcolumns

	SET @counter = @counter + 1;
END

DROP TABLE #Temp1;

