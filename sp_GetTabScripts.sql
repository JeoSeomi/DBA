USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_GetTabScripts]    Script Date: 2022-11-17 오전 9:16:13 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*

exec master.dbo.sp_MS_marksystemobject 'sp_GetTabScripts'

*/
ALTER PROC [dbo].[sp_GetTabScripts]
	@Dest NVARCHAR(128) = 'C:\Backup\Script'
	,@IsCombine BIT = 1
WITH EXECUTE AS OWNER
AS	
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	SET NOCOUNT ON

	IF NOT(LEN(@Dest) > 0)
	BEGIN
		PRINT '@Dest is invalid'
		RETURN 1
	END
	ELSE
	BEGIN 
		SET @Dest = @Dest + CASE WHEN SUBSTRING(REVERSE(@Dest),1,1) <> '\' THEN '\' ELSE '' END + CONVERT(CHAR(8),GETDATE(),112) + '\' 
	END

	DECLARE @CombineFolder NVARCHAR(1000);
	DECLARE @Cmd NVARCHAR(1000)
	DECLARE @DestFile NVARCHAR(100) 
	DECLARE @Seq INT
		

	BEGIN TRY

		-- xp_cmdshell on		
		EXEC sp_configure 'xp_cmdshell', 1;
		RECONFIGURE WITH OVERRIDE;
		
		--------------------------------------------------------------------------------
		-- create sp script
		--------------------------------------------------------------------------------
		IF OBJECT_ID('dbo.TMP_TAB') IS NOT NULL
			DROP TABLE dbo.TMP_TAB

		SELECT IDENTITY(INT,1,1) Seq
		,	[name] Tab
		,	CONCAT(
				'USE ',	DB_NAME(),CHAR(10),'GO',CHAR(10)
			,	'CREATE TABLE ',SCHEMA_NAME([schema_id]),'.',[name],'(',CHAR(10),B.Stmt,')', CASE WHEN G.[object_id] IS NOT NULL THEN 'WITH (MEMORY_OPTIMIZED=ON)' ELSE '' END, CHAR(10),'GO',CHAR(10)
			,	C.stmt
			,	REPLACE(REPLACE(D.stmt,'&lt;','<'),'&gt;','>')
			,	E.stmt
			,	REPLACE(REPLACE(F.stmt,'&lt;','<'),'&gt;','>')
			) Stmt
		INTO TMP_TAB
		FROM sys.objects A 
			/*Columns*/
			CROSS APPLY (
				SELECT CONCAT(
						CASE WHEN C.column_id = 1 THEN '' ELSE ',' END
					,   CHAR(9)
					,   '[',C.[name] ,']'
					,   ' '
					,   T.[name]
					,   CASE
							WHEN T.[name] IN ('NCHAR','NVARCHAR') AND C.max_length != -1 THEN CONCAT('(',C.max_length/2,')')
							WHEN T.[name] IN ('CHAR','VARCHAR','BINARY','VARBINARY') AND C.max_length != -1 THEN CONCAT('(',C.max_length,')')
							WHEN T.[name] IN ('CHAR','VARCHAR','NCHAR','NVARCHAR','BINARY','VARBINARY') AND C.max_length = -1 THEN '(MAX)'
							WHEN T.[name] IN ('DECIMAL','NUMERIC') THEN CONCAT('(',C.[precision],',',C.scale,')')
							ELSE ''
						END
					,   ' '
					,   CASE C.is_nullable WHEN 1 THEN 'NULL' WHEN 0 THEN 'NOT NULL' END
					,   CASE C.is_identity WHEN 1 THEN CONCAT(' IDENTITY(',CAST(N.seed_value AS VARCHAR),',',CAST(N.increment_value AS VARCHAR),')') ELSE '' END
					,	CHAR(10)
					) 
				FROM sys.columns C
					INNER JOIN sys.types T ON C.user_type_id = T.user_type_id
					LEFT JOIN sys.identity_columns N ON C.[object_id] = N.[object_id] AND C.column_id = N.column_id
				WHERE C.[object_id] = A.[object_id]
				FOR XML PATH('')
			) B (stmt)
			/*DF*/
			CROSS APPLY (
				SELECT CONCAT(
						'ALTER TABLE ',SCHEMA_NAME(A.[schema_id]),'.',A.[name],' ADD CONSTRAINT '
					,   d.name
					,   ' DEFAULT ',d.[definition],' FOR [',c.name,']'
					,	CHAR(10)
					,	'GO'
					,	CHAR(10)
					) 
				FROM sys.columns c
					INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
					INNER JOIN sys.default_constraints d ON c.[object_id] = d.parent_object_id AND c.column_id = d.parent_column_id
				WHERE C.[object_id] = A.[object_id]
				ORDER BY C.[name]
				FOR XML PATH('')
			) C (stmt)
			/*CK*/
			CROSS APPLY (
				SELECT CONCAT(
						'ALTER TABLE ',SCHEMA_NAME(A.[schema_id]),'.',A.[name],' ADD CONSTRAINT '
					,   d.name
					,   ' CHECK ',d.[definition]
					,	CHAR(10)
					,	'GO'
					,	CHAR(10)
					) stmt
				FROM sys.columns c
					INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
					INNER JOIN sys.check_constraints d ON c.[object_id] = d.parent_object_id AND c.column_id = d.parent_column_id
				WHERE C.[object_id] = A.[object_id]
				ORDER BY C.[name]
				FOR XML PATH('')
			) D (stmt)
			/*PK/UQ*/
			CROSS APPLY (	
				SELECT CONCAT(
						'ALTER TABLE ',SCHEMA_NAME(A.[schema_id]),'.',A.[name],' ADD CONSTRAINT '
					,	d.name
					,   CASE d.[type] WHEN 'PK' THEN ' PRIMARY KEY ' WHEN 'UQ' THEN ' UNIQUE ' END
					,   CASE i.[type] WHEN 1 THEN 'CLUSTERED' ELSE 'NONCLUSTERED' END
					,   ' (',SUBSTRING(IndexKeys,1,LEN(IndexKeys)-1),')'
					,	' WITH (FILLFACTOR=', CASE i.fill_factor WHEN 0 THEN 100 ELSE i.fill_factor END, ')'
					,	CHAR(10)
					,	'GO'
					,	CHAR(10)
					)
				FROM sys.key_constraints d
					INNER JOIN sys.indexes i ON d.unique_index_id = i.index_id AND d.parent_object_id = i.[object_id]
					CROSS APPLY (
						SELECT '[' + c.name + ']' + CASE k.is_descending_key WHEN 0 THEN ' ASC' WHEN 1 THEN ' DESC' ELSE ' ' END + ','
						FROM sys.columns c
							INNER JOIN sys.index_columns k ON c.[object_id] = k.[object_id]
						WHERE i.[object_id] = c.[object_id] AND i.index_id = k.index_id AND k.column_id = c.column_id AND k.is_included_column = 0
						ORDER BY k.key_ordinal
						FOR XML PATH('')
					) c (IndexKeys)
				WHERE d.parent_object_id = A.[object_id]
				FOR XML PATH('')
			) E (stmt)
			/*Columns*/
			CROSS APPLY (	
				SELECT CONCAT(
						'CREATE '
					,	CASE i.is_unique WHEN 1 THEN 'UNIQUE ' ELSE '' END
					,   CASE i.[type] WHEN 1 THEN 'CLUSTERED' WHEN 2 THEN 'NONCLUSTERED' ELSE '' END,' INDEX '
					,   i.name
					,   ' ON ', SCHEMA_NAME(A.[schema_id]),'.',A.[name], '(', SUBSTRING(IndexKeys,1,LEN(IndexKeys)-1), ')'
					,   CASE WHEN IndexIncludeColumns IS NOT NULL THEN CONCAT(' INCLUDE (',SUBSTRING(IndexIncludeColumns,1,LEN(IndexIncludeColumns)-1),')') ELSE '' END
					,	CASE WHEN i.filter_definition IS NOT NULL THEN CONCAT(' WHERE ', i.filter_definition) ELSE '' END
					,	' WITH (FILLFACTOR=', CASE i.fill_factor WHEN 0 THEN 100 ELSE i.fill_factor END, ')'
					,	CHAR(10)
					,	'GO'
					,	CHAR(10)
					)
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
				WHERE i.[type] > 0 AND i.[object_id] = A.[object_id] AND d.unique_index_id IS NULL
				FOR XML PATH('')
			) F (stmt)
			LEFT JOIN sys.dm_db_xtp_table_memory_stats G ON G.[object_id] = A.[object_id]
		WHERE A.[type] = 'U' AND A.[name] NOT IN ('TMP_TAB','TMP_SP')
		
		CREATE CLUSTERED INDEX CIX__TMP_TAB ON dbo.TMP_TAB(Seq)
	
		--------------------------------------------------------------------------------
		-- create dest directory
		--------------------------------------------------------------------------------
		SET @CombineFolder = @Dest;
		SET @Dest = CONCAT(@Dest,DB_NAME(),'\Tab\')
		SET @Cmd = CONCAT('MKDIR "',@Dest,'"')

		--PRINT @Cmd
		EXEC master..xp_cmdshell @Cmd, no_output

		--------------------------------------------------------------------------------
		-- out sp file
		--------------------------------------------------------------------------------
		IF @IsCombine = 1
		BEGIN
			SET @DestFile = CONCAT(DB_NAME(), '_TB_',FORMAT(GETDATE(), 'yyyyMMdd'), '.sql')
			SET @Cmd = CONCAT('BCP "SELECT Stmt FROM dbo.TMP_TAB ','" QUERYOUT ')
			SET @Cmd += CONCAT('"',@CombineFolder,@DestFile,'"',' -S "127.0.0.1,1433" -U "sa" -P "engksl0413!@#" -d "',DB_NAME(),'" -c -r "\n" -t "\t"')
			
			--PRINT @Cmd
			
			EXEC master..xp_cmdshell @Cmd, no_output
		END
		ELSE		
		BEGIN
			SET @Seq = (SELECT MAX(Seq) FROM dbo.TMP_TAB)			
			WHILE @Seq > 0
			BEGIN	
				SET @DestFile = (SELECT Tab+'.sql' FROM dbo.TMP_TAB WHERE Seq = @Seq)
				SET @Cmd = CONCAT('BCP "SELECT Stmt FROM dbo.TMP_TAB WHERE Seq = ',@Seq,'" QUERYOUT ')
				SET @Cmd += CONCAT('"',@Dest,@DestFile,'"',' -S "127.0.0.1,1433" -U "sa" -P "engksl0413!@#" -d "',DB_NAME(),'" -c -r "\n" -t "\t"')

				--PRINT @Cmd

				EXEC master..xp_cmdshell @Cmd, no_output
	
				SET @Seq -= 1
				WAITFOR DELAY '00:00:00.001'
			END			
		END

		-- xp_cmdshell off		
		EXEC sp_configure 'xp_cmdshell', 0;
		RECONFIGURE WITH OVERRIDE;
		
		IF OBJECT_ID('dbo.TMP_TAB') IS NOT NULL
			DROP TABLE dbo.TMP_TAB

	END TRY
	BEGIN CATCH

		SELECT ERROR_MESSAGE() ErrMsg, ERROR_NUMBER() ErrNum, ERROR_LINE() ErrLn

	END CATCH

