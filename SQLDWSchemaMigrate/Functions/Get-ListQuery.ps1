Function Get-ListQuery {
     <#
    .Synopsis
    Return query to list objects
    .Parameter ObjectType
    Used to enter correct if statement
    .Example
    $listSchemasQuery = Get-ListQuery "Schemas" 
    $listStoredProceduresQuery = Get-ListQuery "StoredProcedures"
    $listTablesQuery = Get-ListQuery "Tables"
    $listFunctionsQuery = Get-ListQuery "Functions"
    $listViewsQuery = Get-ListQuery "Views"
    #>
    param(
        [ValidateSet("Schemas", "SQL_STORED_PROCEDURE", "Tables", "VIEW", "SQL_SCALAR_FUNCTION", "Columns", "ExternalTables")]    
        [String]$ObjectType
    )
    
    if ($ObjectType -eq "Schemas") {
        $QueryToReturn = "SELECT sch.name, db_princ.name from sys.schemas sch inner join sys.database_principals db_princ on sch.principal_id = db_princ.principal_id WHERE sch.name NOT IN ('dbo','sys', 'INFORMATION_SCHEMA', 'sysdiag')"
    }
    elseif ($ObjectType -eq "SQL_STORED_PROCEDURE") {
        $QueryToReturn = "select sch.name as schema_name, obj.name as object_name, obj.object_id, obj.schema_id, mod.definition from sys.objects obj inner join sys.schemas sch on obj.schema_id = sch.schema_id inner join [sys].[sql_modules] mod on mod.object_id = obj.object_id where obj.type_desc = 'SQL_STORED_PROCEDURE' and sch.name != 'temp' AND obj.name NOT IN ('usp_ConstructCreateStatementForTable','usp_ConstructCreateStatementForExternalTable') ORDER BY 1, 2;"
    }
    elseif ($ObjectType -eq "Tables") {
        $QueryToReturn = "select sch.name as schema_name, obj.name as object_name, obj.object_id from sys.tables obj inner join sys.schemas sch on obj.schema_id = sch.schema_id where is_external = 0 and obj.name not like '%_Backup%' and obj.name not like '%_BKP%' and obj.name not like '%_tmp%' and obj.name not like '%_wDuplicates%' and sch.name != 'temp' ORDER BY 1, 2;"
    }
    elseif ($ObjectType -eq "SQL_SCALAR_FUNCTION") {
        $QueryToReturn = "select sch.name as schema_name, obj.name as object_name, obj.object_id, obj.schema_id, mod.definition from sys.objects obj inner join sys.schemas sch on obj.schema_id = sch.schema_id inner join [sys].[sql_modules] mod on mod.object_id = obj.object_id where obj.type_desc = 'SQL_SCALAR_FUNCTION' and sch.name != 'temp' ORDER BY 1, 2;"
    }
    elseif ($ObjectType -eq "VIEW") {
        $QueryToReturn = "select sch.name as schema_name, obj.name as object_name, obj.object_id, obj.schema_id, mod.definition from sys.objects obj inner join sys.schemas sch on obj.schema_id = sch.schema_id inner join [sys].[sql_modules] mod on mod.object_id = obj.object_id where obj.type_desc = 'VIEW' and sch.name != 'temp' ORDER BY 1, 2;"
    }
    elseif ($ObjectType -eq "Columns") {
        $QueryToReturn = "SELECT s.name, o.name, c.name, c.user_type_id, C.COLUMN_ID, c.max_length FROM sys.columns c INNER JOIN sys.objects o ON c.object_id = o.object_id INNER join sys.schemas s on s.schema_id = o.schema_id INNER JOIN sys.tables t ON t.object_id= o.object_id WHERE o.type = 'U' AND o.name NOT IN ('sourceColumns' ,'sourceColumnsNew','SourceDefinitions','DDLStatements') AND t.is_external = 0"
    }
    elseif ($objectType -eq "ExternalTables"){
        $QueryToReturn = "select sch.name as schema_name, obj.name as object_name, obj.object_id from sys.tables obj inner join sys.schemas sch on obj.schema_id = sch.schema_id where is_external = 1 and obj.name not like '%_Backup%' and obj.name not like '%_BKP%' and obj.name not like '%_tmp%' and obj.name not like '%_wDuplicates%' and sch.name != 'temp' ORDER BY 1, 2;"
    }
    Return $QueryToReturn
}