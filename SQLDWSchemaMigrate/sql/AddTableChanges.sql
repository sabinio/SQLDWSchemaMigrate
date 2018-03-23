

SET NOCOUNT ON;

-- All tables currently in "production db" that are also in sourceColumns table
SELECT *
	,row_number() OVER (
		ORDER BY (
				SELECT 0
				)
		) AS number
INTO #Temp1
FROM (
	SELECT DISTINCT 
	sch.name As schema_name
		,obj.name AS object_name
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
		AND sch.name = sc.schemaname
		AND NOT (obj.name LIKE '%Source%')
	) A

DECLARE @TotalTables INT
DECLARE @counter INT
DECLARE @currentTable NVARCHAR(max);
DECLARE @currentSchema NVARCHAR(max);
DECLARE @objectSchemaAndName NVARCHAR(max);

DECLARE @Now DATETIME;
SET @Now = GETDATE();

SET @TotalTables = (
		SELECT count(*)
		FROM #Temp1
		);
SET @counter = 1
-- Looping through all tables in "production" and checking for deltas
WHILE (@counter <= @TotalTables)
BEGIN
	-- Current table in prod db and collecting all column names it should have based on source columns
	SELECT 	@currentTable = object_name,
			@currentSchema = schema_name,
			@objectSchemaAndName = object_name + '.' + schema_name
	FROM #Temp1
	WHERE number = @counter

   
	SELECT sys.columns.name
		,sys.columns.user_type_id, sys.columns.max_length
	INTO #tempprodtablecolumns
	FROM sys.columns
	INNER JOIN sys.tables ON sys.columns.object_id = sys.tables.object_id
	INNER JOIN sys.schemas ON sys.tables.schema_id = sys.schemas.schema_id 
	WHERE sys.tables.name = @currentTable
		AND sys.schemas.name = @currentSchema;
	
	SELECT schemaname 
		,tablename
		,colname
		,user_type_id
		,max_length
	INTO #tempdevtablecolumns
	FROM sourceColumns
	WHERE tablename = @currentTable
	AND schemaname = @currentSchema

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

	PRINT 'Total new columns for table '+ @currentSchema +'.'+ @currentTable + ' is ' + CONVERT(VARCHAR(10), @totalnewcolumns);

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
		IF (@currentcoltype IN (231, 167, 175, 239))
		BEGIN
				SET @currentcollength = ' ('+(
						SELECT CAST (max_length as nvarchar (8)) + ')'
						FROM #addedcolumns
						WHERE number = @secondcounter 
				);
				SET @coltypename = @coltypename + @currentcollength
		END
		SET @SQL = 'ALTER TABLE ' + @currentSchema +'.'+ @currentTable + ' ADD ' + @currentcolname + ' ' + @coltypename;

		PRINT '---------- Altering statement: ' + @SQL + ' ---------- ';

		INSERT INTO DDLStatements (TargetObject, DDLStmt, CreateDate) VALUES (@objectSchemaAndName, @SQL, @Now)

		EXEC (@SQL);

		SET @secondcounter = @secondcounter + 1
	END

	DROP TABLE #addedcolumns

	SET @counter = @counter + 1;
END

DROP TABLE #Temp1;

