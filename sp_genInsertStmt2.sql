USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_genInsertStmt2]    Script Date: 2022-11-17 오전 9:18:30 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************     
    
 1. Procedure    : sp_genInsertStmt     
 2. Process Func : 특정 테이블에 대해 INSERT Script를 생성합니다. (values 처리)
 3. Create Date  : 
 4. Create User  : 
 5. Execute Test :           
       EXEC sp_genInsertStmt N'TableName';   
	   EXEC sp_genInsertStmt N'TableName', N'WHERE userID = 27';
	   EXEC sp_MSForEachTable 'EXEC sp_genInsertStmt N''?''';
 6. return value	:
		0 = There is no error.
 7. History Info :     
     Date  Author    Description    
     ----------- ------------------- -------------------------------------------    
    
*******************************************************************************************************/  
ALTER PROCEDURE [dbo].[sp_genInsertStmt2]
	@nvcTableName nvarchar(256)
,	@nvcWhereClause nvarchar(max) = N''
AS

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE
	@intReturnValue int
,	@nvcSchemaName nvarchar(128)
,	@nvcColumns nvarchar(max)
,	@nvcValues nvarchar(max)
,	@intIsIdentity int
,	@nvcStmt nvarchar(max)
,	@bitRows bit;

BEGIN TRY
	/**_# 스키마 이름과 테이블 이름을 분리합니다. 스키마 이름이 없다면 dbo를 기본값으로 합니다.*/
	SET @nvcSchemaName = QUOTENAME(ISNULL(PARSENAME(@nvcTableName, 2), N'dbo'));
	SET @nvcTableName = QUOTENAME(PARSENAME(@nvcTableName, 1));

	/**_# @nvcColumns, @nvcValues, @intIsIdentity를 초기화합니다.*/
	SET @nvcColumns = N'';
	SET @nvcValues = N'';
	SET @intIsIdentity = 0;

	/**_# 테이블의 컬럼 정보를 가져옵니다.*/
	SELECT @nvcColumns = @nvcColumns + N', ' + QUOTENAME(C.[name])
		, @nvcValues = @nvcValues + N' + N'', '' + ' +
			CASE
				WHEN TP.name IN (N'bigint', N'numeric', N'bit', N'smallint', N'decimal', N'int', N'tinyint', N'float', N'real') THEN N'ISNULL(CAST(' + QUOTENAME(C.[name]) + N' AS nvarchar(max)), ''NULL'')'
				WHEN TP.name IN (N'char', N'varchar', N'text', N'uniqueidentifier') THEN N'ISNULL(N'''''''' + ' + N'REPLACE(CAST(' + QUOTENAME(C.[name]) + N' AS nvarchar(max)), '''''''', '''''''''''')' + N' + N'''''''', ''NULL'')'
				WHEN TP.name IN (N'nchar', N'nvarchar', N'ntext', N'xml', N'sql_variant') THEN N'ISNULL(N''N'''''' + ' + N'REPLACE(CAST(' + QUOTENAME(C.[name]) + N' AS nvarchar(max)), N'''''''', N'''''''''''')' + N' + N'''''''', ''NULL'')'
				WHEN TP.name IN (N'smallmoney', N'money', N'date', N'datetimeoffset', N'datetime2', N'smalldatetime', N'datetime', N'time') THEN N'ISNULL(master.sys.fn_varbintohexstr(CAST(' + QUOTENAME(C.[name]) + N' AS varbinary(max))), ''NULL'')'
				WHEN TP.name IN (N'binary', N'varbinary', N'image') THEN N'ISNULL(master.sys.fn_varbintohexstr(CAST(' + QUOTENAME(C.[name]) + N' AS varbinary(max))), ''NULL'')'
				WHEN TP.name IN (N'timestamp') THEN N'ISNULL(CAST(master.sys.fn_varbintohexstr(CAST(' + QUOTENAME(C.[name]) + N' AS varbinary(max))) AS timestamp), ''NULL'')'
 			END
		, @intIsIdentity = @intIsIdentity + C.is_identity
	FROM sys.columns C
		INNER JOIN sys.types TP ON C.user_type_id = TP.user_type_id
	WHERE C.[object_id] = OBJECT_ID(@nvcSchemaName + N'.' + @nvcTableName) AND TP.[name] NOT IN (N'timestamp', N'rowversion')
	ORDER BY C.column_id;

	SET @nvcColumns = STUFF(@nvcColumns, 1, 2, N'');
	SET @nvcValues = STUFF(@nvcValues, 1, 11, N'');

	/**_# 주석을 출력합니다.*/
	PRINT N'

-----------------------------------------------------------------------------
-- Table Name : ' + @nvcSchemaName + N'.' + @nvcTableName + N'
-----------------------------------------------------------------------------';

	PRINT N'TRUNCATE TABLE ' + @nvcSchemaName + N'.' + @nvcTableName;

	/**_# UDT, hierarchyid 형식이 포함된 테이블이면 에러를 출력합니다.*/
	IF @nvcValues IS NULL
	BEGIN
		PRINT N'-- UDT, hierarchyid 형식은 지원하지 않습니다.';
		RETURN 0;
	END

	/**_# INSERT문을 생성할 레코드가 존재하는지 확인합니다.*/
	SET @nvcStmt = N'
IF EXISTS (
	SELECT * FROM ' + @nvcSchemaName + N'.' + @nvcTableName + N' ' + @nvcWhereClause + N'
)
	SET @bitRows = 1;
ELSE
	SET @bitRows = 0;'
	EXEC sp_executesql @nvcStmt, N'@bitRows bit OUTPUT', @bitRows = @bitRows OUTPUT;

	IF @bitRows = 0
	BEGIN
		PRINT N'-- NO RECORD!!!';
		RETURN 0;
	END

	/**_# IDENTITY 속성을 가진 컬럼이 있다면 SET IDENTITY_INSERT ON을 출력합니다.*/
	IF @intIsIdentity = 1
		PRINT N'SET IDENTITY_INSERT ' + @nvcSchemaName + N'.' + @nvcTableName + N' ON;';

	/**_# INSERT문을 출력합니다.*/
	PRINT N'INSERT ' + @nvcSchemaName + N'.' + @nvcTableName + N' (' + @nvcColumns + N')';
	PRINT N'VALUES' + CHAR(13) + CHAR(10);

	SET @nvcStmt = N' DECLARE @i int, @j int, @nvcInsertScript nvarchar(max);
DECLARE @tblTemp table (seq int IDENTITY(1, 1) NOT NULL PRIMARY KEY, stmt nvarchar(max) NOT NULL);

INSERT @tblTemp (stmt)
SELECT N'', '' + ' + @nvcValues + N' FROM ' + @nvcSchemaName + N'.' + @nvcTableName + N' ' + @nvcWhereClause + N';

SELECT @i = 1, @j = @@ROWCOUNT;

WHILE @i <= @j
BEGIN
	SELECT @nvcInsertScript = stmt + CASE WHEN @i < @j THEN N'' ),'' ELSE N'');'' END FROM @tblTemp WHERE seq = @i;
	SET @nvcInsertScript = STUFF(@nvcInsertScript, 1, 1, N''( '')
	
	EXEC sp_print @nvcInsertScript;

	SET @i += 1;
END';

	EXEC sp_executesql @nvcStmt;

	/**_# IDENTITY 속성을 가진 컬럼이 있다면 SET IDENTITY_INSERT OFF를 출력합니다.*/
	IF @intIsIdentity = 1
		PRINT N'SET IDENTITY_INSERT ' + @nvcSchemaName + N'.' + @nvcTableName + N' OFF;';
	
	PRINT N'GO ';
END TRY

BEGIN CATCH
	SET @intReturnValue = ERROR_NUMBER();
	GOTO ErrorHandler;
END CATCH;

RETURN 0;

ErrorHandler:
IF XACT_STATE() <> 0
	ROLLBACK TRANSACTION;

PRINT ERROR_MESSAGE();
