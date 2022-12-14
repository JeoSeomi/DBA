USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_definition]    Script Date: 2022-11-17 오전 9:18:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO

/******************************************************************************
    name        :   [sp_definition]
    description :   get object definition
    timing      : 
    excute ex)  :   EXEC [dbo].[sp_definition] @Name='GuildMember'
  
    Ver         Date        Author          Description
    ---------   ----------  --------------- ------------------------------------

******************************************************************************/
ALTER PROCEDURE [dbo].[sp_definition]
    @Name SYSNAME = NULL
,	@OwnerName SYSNAME = NULL
AS
BEGIN
    -- ??????
    SET NOCOUNT ON
    SET XACT_ABORT ON
    SET LOCK_TIMEOUT 3000 
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
    
    ------------------------------------------------------------------------
    -- declare.
    ------------------------------------------------------------------------
	DECLARE @ObjectId INT
	DECLARE @ObjectType CHAR(2)

	BEGIN TRY
		
		------------------------------------------------------------------------
		-- get object info.
		------------------------------------------------------------------------
		SELECT @ObjectId = [object_id], @ObjectType = [type], @Name = [Name], @OwnerName = SCHEMA_NAME([schema_id])
		FROM sys.objects
		WHERE [name] = @Name

		IF @@ROWCOUNT = 0
			SELECT @ObjectId = type_table_object_id, @ObjectType = 'TT', @Name = [Name], @OwnerName = SCHEMA_NAME([schema_id])
			FROM sys.table_types
			WHERE [name] = @Name

		IF @@ROWCOUNT = 0
			SELECT @ObjectId = [object_id], @ObjectType = 'DT', @Name = [Name], @OwnerName = ''
			FROM sys.triggers
			WHERE [name] = @Name AND parent_class_desc = 'DATABASE'
			

		------------------------------------------------------------------------
		-- all objects(invalid name)
		------------------------------------------------------------------------
		IF @ObjectType IS NULL
		BEGIN		
			SELECT [object_id], [name], [type_desc], create_date, modify_date
			FROM sys.objects 
			WHERE [type] <> 'S' AND [name] LIKE '%'+@Name+'%'
			UNION ALL			
			SELECT [object_id], [name], [type_desc], create_date, modify_date
			FROM sys.triggers
			WHERE [name] LIKE '%'+@Name+'%' AND parent_class_desc = 'DATABASE'
			ORDER BY [type_desc] DESC, [name]
			
			IF @@ROWCOUNT = 0
				SELECT [object_id], [name], [type_desc], create_date, modify_date
				FROM sys.objects 
				WHERE [type] <> 'S'
				ORDER BY [type] DESC, [name]

		END
		------------------------------------------------------------------------
		-- procedures, view, trigger, functions.
		------------------------------------------------------------------------
		ELSE IF @ObjectType IN ('P', 'RF', 'V', 'TR', 'FN', 'IF', 'TF', 'R')
		BEGIN
			WITH [Definition] AS (
				SELECT 1 [#]
				,	[definition]
				,	CONCAT(
						'USE [',DB_NAME(),']',CHAR(10),'GO',CHAR(10)
					,	'-- DROP '
					,	CASE @ObjectType 
							WHEN 'P' THEN 'PROCEDURE'
							WHEN 'RF' THEN 'PROCEDURE'
							WHEN 'V' THEN 'VIEW'
							WHEN 'FN' THEN 'FUNCTION'
							WHEN 'IF' THEN 'FUNCTION'
							WHEN 'R' THEN 'RULE'
							WHEN 'TR' THEN 'TRIGGER'
						END
					,	' IF EXISTS ', [name],CHAR(10)
					,	CASE OBJECTPROPERTY(B.[object_id],'ExecIsAnsiNullsOn') WHEN 0 THEN 'SET ANSI_NULLS IFF' WHEN 1 THEN 'SET ANSI_NULLS ON' ELSE '' END , CHAR(10) , 'GO' , CHAR(10)
					,	CASE OBJECTPROPERTY(B.[object_id],'ExecIsQuotedIdentOn')  WHEN 0 THEN 'SET QUOTED_IDENTIFIER OFF' WHEN 1 THEN 'SET QUOTED_IDENTIFIER ON' ELSE '' END , CHAR(10) , 'GO' , CHAR(10)
					,	SUBSTRING([definition],1,40000)
					) definition2
				,	LEN([definition]) len_definition
				,	1 start_offset
				,	40000 end_offset
				,	B.[object_id], [name], [type_desc], create_date, modify_date
				FROM sys.sql_modules A
					INNER JOIN sys.objects B ON A.[object_id] = B.[object_id]
				WHERE A.[object_id] = @ObjectId
				UNION ALL
				SELECT 1 + [#] [#]
				,	[definition]
				,	SUBSTRING([definition],start_offset+end_offset,end_offset) [definition2]
				,	len_definition
				,	start_offset + end_offset start_offset
				,	end_offset
				,	NULL, NULL, NULL, NULL, NULL
				FROM [Definition]
				WHERE start_offset+end_offset < len_definition
			)
			SELECT [#], definition2 [definition], CONVERT(VARCHAR(20),[object_id]) [object_id], [name], [type_desc], CONVERT(VARCHAR(24),create_date,121) create_date, CONVERT(VARCHAR(24),modify_date,121) modify_date
			FROM [Definition]
			UNION ALL
			SELECT MAX([#])+1, 'GO', '', '', '', '', ''
			FROM [Definition]
			
			-- property			
			SELECT '' parameter_id
			,	'' parameter_name
			,	'' type_name
			,	C.value property_value
			,	CONCAT(
				'EXEC sys.sp_addextendedproperty @name = N''', C.name, ''', '
			,	'@value = N''', CONVERT(NVARCHAR(MAX),value), ''', '
			,	'@level0type = N''', 'SCHEMA', ''', '
			,	'@level0name = N''', @OwnerName, ''', '
			,	'@level1type = N''', 'PROCEDURE', ''', '
			,	'@level1name = N''', @Name, ''', '
			,	CASE C.class
					WHEN 1 THEN '@level2type = NULL, @level2name = NULL'
					WHEN 2 THEN CONCAT('@level2type = N''', 'PARAMETER', ''', ', '@level2name = N''', C.name, '''')
				END
			--,	CHAR(10), 'GO'
			) [property_add_definition]
			,	CONCAT(
					'EXEC sys.sp_dropextendedproperty @name = N''', C.name, ''', '
				,	'@level0type = N''', 'SCHEMA', ''', '
				,	'@level0name = N''', @OwnerName, ''', '
				,	'@level1type = N''', 'PROCEDURE', ''', '
				,	'@level1name = N''', @Name, ''', '
				,	CASE C.class
						WHEN 1 THEN '@level2type = NULL, @level2name = NULL'
						WHEN 2 THEN CONCAT('@level2type = N''', 'PARAMETER', ''', ', '@level2name = N''', C.name, '''')
					END
				--,	CHAR(10), 'GO'
				) [property_drop_definition]
			FROM sys.extended_properties C
			WHERE C.minor_id = 0 AND C.major_id = @ObjectId AND C.class = 1
			UNION ALL
			SELECT CONVERT(VARCHAR(20),ISNULL(A.parameter_id,0))
			,	ISNULL(A.name,'') 
			,	ISNULL(
					CONCAT(
						B.name
					,   CASE
							WHEN B.name IN ('NCHAR','NVARCHAR') AND A.max_length != -1 THEN CONCAT('(',A.max_length/2,')')
							WHEN B.name IN ('CHAR','VARCHAR','BINARY','VARBINARY') AND A.max_length != -1 THEN CONCAT('(',A.max_length,')')
							WHEN B.name IN ('CHAR','VARCHAR','NCHAR','NVARCHAR','BINARY','VARBINARY') AND A.max_length = -1 THEN '(MAX)'
							WHEN B.name IN ('DECIMAL','NUMERIC') THEN CONCAT('(',A.[precision],',',A.scale,')')
							ELSE ''
						END
					)
				,	''
				) 
			,	ISNULL(C.value,'') property_value
			,	ISNULL(C.[property_add_definition],'') 
			,	ISNULL(C.[property_drop_definition],'') 
			FROM sys.parameters A
				INNER JOIN sys.types B ON B.system_type_id = A.system_type_id AND A.user_type_id = B.user_type_id
				OUTER APPLY (
					SELECT C.value
					,	CONCAT(
						'EXEC sys.sp_addextendedproperty @name = N''', C.name, ''', '
					,	'@value = N''', CONVERT(NVARCHAR(MAX),value), ''', '
					,	'@level0type = N''', 'SCHEMA', ''', '
					,	'@level0name = N''', @OwnerName, ''', '
					,	'@level1type = N''', 'PROCEDURE', ''', '
					,	'@level1name = N''', @Name, ''', '
					,	CASE C.class
							WHEN 1 THEN '@level2type = NULL, @level2name = NULL'
							WHEN 2 THEN CONCAT('@level2type = N''', 'PARAMETER', ''', ', '@level2name = N''', C.name, '''')
						END
					--,	CHAR(10), 'GO'
					) [property_add_definition]
					,	CONCAT(
							'EXEC sys.sp_dropextendedproperty @name = N''', C.name, ''', '
						,	'@level0type = N''', 'SCHEMA', ''', '
						,	'@level0name = N''', @OwnerName, ''', '
						,	'@level1type = N''', 'PROCEDURE', ''', '
						,	'@level1name = N''', @Name, ''', '
						,	CASE C.class
								WHEN 1 THEN '@level2type = NULL, @level2name = NULL'
								WHEN 2 THEN CONCAT('@level2type = N''', 'PARAMETER', ''', ', '@level2name = N''', C.name, '''')
							END
						--,	CHAR(10), 'GO'
						) [property_drop_definition]
					FROM sys.extended_properties C
					WHERE C.minor_id = A.parameter_id AND C.major_id = A.[object_id] AND C.class = 2
				) C 
			WHERE A.[object_id] = @ObjectID

		END
		------------------------------------------------------------------------
		-- database trigger
		------------------------------------------------------------------------
		ELSE IF @ObjectType = 'DT'
		BEGIN
			SELECT OBJECT_DEFINITION([object_id]) [definition], [object_id], [name], [type_desc], create_date, modify_date
			FROM sys.triggers 
			WHERE [object_id] = @ObjectId
		END
		------------------------------------------------------------------------
		-- table.
		------------------------------------------------------------------------
		ELSE IF @ObjectType IN ('U','TT')
		BEGIN 
			-- table info
			SELECT [object_id], A.[name], [type_desc], create_date, modify_date, ISNULL(B.[value],'') property_value
			FROM sys.objects A
				LEFT JOIN sys.extended_properties B ON B.major_id = A.[object_id] AND B.class = 1 AND B.minor_id = 0
			WHERE [object_id] = @ObjectId

			-- table create
			SELECT CONCAT(CASE WHEN @ObjectType = 'TT' THEN 'CREATE TYPE ' ELSE 'CREATE TABLE ' END,@OwnerName,'.',@Name,CASE WHEN @ObjectType = 'TT' THEN ' AS TABLE' ELSE ' ' END,'(') table_definition
			,	'' property_value
			UNION ALL
			SELECT CONCAT(					
					CASE WHEN c.column_id = 1 THEN '' ELSE ',' END
				,   CHAR(9)
				,   QUOTENAME(c.[name])
				,   ' '
				,   t.name
				,   CASE
						WHEN t.name IN ('NCHAR','NVARCHAR') AND c.max_length != -1 THEN CONCAT('(',c.max_length/2,')')
						WHEN t.name IN ('CHAR','VARCHAR','BINARY','VARBINARY') AND c.max_length != -1 THEN CONCAT('(',c.max_length,')')
						WHEN t.name IN ('CHAR','VARCHAR','NCHAR','NVARCHAR','BINARY','VARBINARY') AND c.max_length = -1 THEN '(MAX)'
						WHEN t.name IN ('DECIMAL','NUMERIC') THEN CONCAT('(',c.[precision],',',c.scale,')')
						ELSE ''
					END
				,   ' '
				,   CASE c.is_nullable WHEN 1 THEN 'NULL' WHEN 0 THEN 'NOT NULL' END
				,   CASE c.is_identity WHEN 1 THEN CONCAT(' IDENTITY(',CAST(n.seed_value AS VARCHAR),',',CAST(n.increment_value AS VARCHAR),')') ELSE '' END
				)
			,	ISNULL(e.value,'')
			FROM sys.columns c
				INNER JOIN sys.types t ON c.user_type_id = t.user_type_id AND c.system_type_id = t.system_type_id
				LEFT JOIN sys.identity_columns n ON c.[object_id] = n.[object_id] AND c.column_id = n.column_id
				LEFT JOIN sys.extended_properties e ON c.[object_id] = e.major_id AND e.class = 1 AND c.column_id = e.minor_id
			WHERE c.[object_id] = @ObjectId
			UNION ALL
			SELECT ')',''
			
			-- pk,uq create			
			SELECT CONCAT(
					'ALTER TABLE ',@OwnerName,'.',@Name
				,   ' ADD CONSTRAINT ',d.[name]
				,   CASE d.[type] WHEN 'PK' THEN ' PRIMARY KEY ' WHEN 'UQ' THEN ' UNIQUE ' END
				,   CASE i.[type] WHEN 1 THEN 'CLUSTERED' ELSE 'NONCLUSTERED' END
				,   ' (',SUBSTRING(IndexKeys,1,LEN(IndexKeys)-1),')'
				,	' WITH (FILLFACTOR=', CASE i.fill_factor WHEN 0 THEN 90 ELSE i.fill_factor END
				,	', IGNORE_DUP_KEY=', CASE i.[ignore_dup_key] WHEN 0 THEN 'OFF' ELSE 'ON' END
				,	')'
				) key_definition
			FROM sys.key_constraints d
				INNER JOIN sys.indexes i ON d.unique_index_id = i.index_id AND d.parent_object_id = i.[object_id]
				CROSS APPLY (
					SELECT '[' + c.[name] + ']' + CASE k.is_descending_key WHEN 0 THEN ' ASC' WHEN 1 THEN ' DESC' ELSE ' ' END + ','
					FROM sys.columns c
						INNER JOIN sys.index_columns k ON c.[object_id] = k.[object_id]
					WHERE i.[object_id] = c.[object_id] AND i.index_id = k.index_id AND k.column_id = c.column_id AND k.is_included_column = 0
					ORDER BY k.key_ordinal
					FOR XML PATH('')
				) c (IndexKeys)
			WHERE d.parent_object_id = @ObjectId AND d.[type] IN ('PK','UQ') 

			-- ix create
			SELECT CONCAT(
					'CREATE '
				,	CASE i.is_unique WHEN 1 THEN 'UNIQUE ' ELSE '' END
				,   CASE i.[type] WHEN 1 THEN 'CLUSTERED' WHEN 2 THEN 'NONCLUSTERED' ELSE '' END,' INDEX '
				,   i.name
				,   ' ON ', @OwnerName,'.',@Name, '(', SUBSTRING(IndexKeys,1,LEN(IndexKeys)-1), ')'
				,   CASE WHEN IndexIncludeColumns IS NOT NULL THEN CONCAT(' INCLUDE (',SUBSTRING(IndexIncludeColumns,1,LEN(IndexIncludeColumns)-1),')') ELSE '' END
				,	CASE WHEN i.filter_definition IS NOT NULL THEN CONCAT(' WHERE ', i.filter_definition) ELSE '' END
				,	' WITH (FILLFACTOR=', CASE i.fill_factor WHEN 0 THEN 100 ELSE i.fill_factor END
				,	', IGNORE_DUP_KEY=', CASE i.[ignore_dup_key] WHEN 0 THEN 'OFF' ELSE 'ON' END
				,	')'
				) index_definition
			FROM sys.indexes i
				CROSS APPLY (
					SELECT '[' + c.name + ']' + CASE k.is_descending_key WHEN 0 THEN ' ASC' WHEN 1 THEN ' DESC' ELSE ' ' END + ','
					FROM sys.columns c
						INNER JOIN sys.index_columns k ON c.[object_id] = k.[object_id]
					WHERE i.[object_id] = c.[object_id] AND i.index_id = k.index_id AND k.column_id = c.column_id AND k.is_included_column = 0
					ORDER BY k.key_ordinal
					FOR XML PATH('')
				) c (IndexKeys)
				OUTER APPLY (
					SELECT '[' + c.name + ']' + ','
					FROM sys.columns c
						INNER JOIN sys.index_columns k ON c.[object_id] = k.[object_id]
					WHERE i.[object_id] = c.[object_id] AND i.index_id = k.index_id AND k.column_id = c.column_id AND k.is_included_column = 1
					ORDER BY k.key_ordinal
					FOR XML PATH('')
				) l (IndexIncludeColumns)
				LEFT JOIN sys.key_constraints d ON d.unique_index_id = i.index_id AND d.parent_object_id = i.[object_id]
			WHERE i.[type] > 0 AND i.[object_id] = @ObjectId AND d.unique_index_id IS NULL
			
			-- df create
			SELECT CONCAT('ALTER TABLE ',@OwnerName,'.',@Name,' ADD CONSTRAINT '
				,   d.[name]
				,   ' DEFAULT ',d.[definition],' FOR [',c.[name],']'
				) default_definition
			/*,	CONCAT(
					'ALTER TABLE ',@OwnerName,'.',@Name,' ADD CONSTRAINT '
				,   d.[name]
				,   ' DEFAULT ',d.[definition],' FOR [',c.[name],']'
				) df_definition_stname*/
			FROM sys.columns c
				INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
				INNER JOIN sys.default_constraints d ON c.[object_id] = d.parent_object_id AND c.column_id = d.parent_column_id
			WHERE c.[object_id] = @ObjectId
			ORDER BY c.[name]
			
			-- ck create
			SELECT CONCAT('ALTER TABLE ',@OwnerName,'.',@Name,' ADD CONSTRAINT '
				,   d.name
				,   ' CHECK ',d.[definition]
				) check_definition
			FROM sys.columns c
				INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
				INNER JOIN sys.check_constraints d ON c.[object_id] = d.parent_object_id AND c.column_id = d.parent_column_id
			WHERE c.[object_id] = @ObjectId
			ORDER BY c.[name]

			-- property
			SELECT CONCAT(
					'EXEC sys.sp_addextendedproperty @name = N''', A.name, ''', '
				,	'@value = N''', CONVERT(NVARCHAR(MAX),value), ''', '
				,	'@level0type = N''', 'SCHEMA', ''', '
				,	'@level0name = N''', @OwnerName, ''', '
				,	'@level1type = N''', 'TABLE', ''', '
				,	'@level1name = N''', @Name, ''', '
				,	CASE A.minor_id 
						WHEN 0 THEN '@level2type = NULL, @level2name = NULL'
						ELSE CONCAT('@level2type = N''', 'COLUMN', ''', ', '@level2name = N''', B.name, '''')
					END
				--,	CHAR(10), 'GO'
				) [property add definition]
			,	CONCAT(
					'EXEC sys.sp_dropextendedproperty @name = N''', A.name, ''', '
				,	'@level0type = N''', 'SCHEMA', ''', '
				,	'@level0name = N''', @OwnerName, ''', '
				,	'@level1type = N''', 'TABLE', ''', '
				,	'@level1name = N''', @Name, ''', '
				,	CASE A.minor_id 
						WHEN 0 THEN '@level2type = NULL, @level2name = NULL'
						ELSE CONCAT('@level2type = N''', 'COLUMN', ''', ', '@level2name = N''', B.name, '''')
					END
				--,	CHAR(10), 'GO'
				) [property drop definition]
			FROM sys.extended_properties A
				LEFT JOIN sys.columns B ON A.minor_id = B.column_id AND A.major_id = B.[object_id]
			WHERE A.class = 1 AND A.major_id = @ObjectID
			UNION ALL
			SELECT CONCAT(
					'EXEC sys.sp_addextendedproperty @name = N''', A.name, ''', '
				,	'@value = N''', CONVERT(NVARCHAR(MAX),value), ''', '
				,	'@level0type = N''', 'SCHEMA', ''', '
				,	'@level0name = N''', @OwnerName, ''', '
				,	'@level1type = N''', 'TABLE', ''', '
				,	'@level1name = N''', @Name, ''', '
				,	'@level2type = N''', 'INDEX', ''', '
				,	'@level2name = N''', B.name, ''''
				--,	CHAR(10), 'GO'
				) [property add definition]
			,	CONCAT(
					'EXEC sys.sp_dropextendedproperty @name = N''', A.name, ''', '
				,	'@level0type = N''', 'SCHEMA', ''', '
				,	'@level0name = N''', @OwnerName, ''', '
				,	'@level1type = N''', 'TABLE', ''', '
				,	'@level1name = N''', @Name, ''', '
				,	'@level2type = N''', 'INDEX', ''', '
				,	'@level2name = N''', B.name, ''''
				--,	CHAR(10), 'GO'
				) [property drop definition]
			FROM sys.extended_properties A
				LEFT JOIN sys.indexes B ON A.minor_id = B.index_id AND A.major_id = B.[object_id]
			WHERE A.class = 7 AND A.major_id = @ObjectID

			-- example 
			SELECT CASE WHEN column_id = 1 THEN 'SELECT TOP (1000) ' ELSE ','+CHAR(9) END +QUOTENAME([name]) select_example
			FROM sys.columns 
			WHERE [object_id] = @ObjectId
			UNION ALL
			SELECT CONCAT('FROM ',@OwnerName,'.',@Name,' WITH (NOLOCK)')
			
			
			SELECT CONCAT('INSERT INTO ',@OwnerName,'.',@Name,' ( ',SUBSTRING(table_columns,1,LEN(table_columns)-1),' )') insert_example
			FROM (
					SELECT QUOTENAME([name])+', '
					FROM sys.columns 
					WHERE [object_id] = @ObjectId
					ORDER BY column_id
					FOR XML PATH('')
				) A (table_columns)
			UNION ALL 
			SELECT 'VALUES ( .. )'

		END

	END TRY
	BEGIN CATCH
		
		THROW;

	END CATCH
END
