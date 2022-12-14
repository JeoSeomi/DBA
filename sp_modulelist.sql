USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_modulelist]    Script Date: 2022-11-17 오전 9:19:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************     
    
	1. Procedure	: sp_modulelist     
	2. Process Func	: 이름에 특정 문자를 포함한 SP, UDF 목록을 반환합니다. (LIKE 검색)
	3. Create Date	: 
	4. Create User	: 
	5. Execute Test	:           
	6. return value	:
		0 = There is no error.
	7. History Info	:     
		Date		Author				Description    
		----------- ------------------- -------------------------------------------    
    
*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[sp_modulelist]
    @objName sysname = NULL --// 반환할 개체 (LIKE 검색)
--WITH ENCRYPTION
AS
 
SET NOCOUNT ON;
 
DECLARE @intReturnValue int, @nvcDatabaseName nvarchar(128);
 
/**_# Rollback and return if inside an uncommittable transaction.*/
IF XACT_STATE() = -1
BEGIN
    SET @intReturnValue = 1;
    ROLLBACK TRANSACTION;
    GOTO ErrorHandler;
END
 
SET @nvcDatabaseName = DB_NAME();
 
IF DB_ID(N'SQLSafe') IS NULL OR DB_NAME() = N'SQLSafe'
    SELECT
        CASE O.[type]
            WHEN 'P' THEN 'SP'
            WHEN 'RF' THEN 'REPLICATION FILTER PROCEDURE'
            WHEN 'TR' THEN 'DML TRIGGER'
            WHEN 'FN' THEN 'UDF'
            WHEN 'IF' THEN 'UDF'
            WHEN 'TF' THEN 'UDF'
        END AS [type], O.[name], CAST(EP.[value] AS nvarchar(max)) AS [description]
    FROM sys.objects O
        LEFT OUTER JOIN sys.extended_properties EP ON O.[object_id] = EP.major_id AND EP.minor_id = 0
    WHERE O.[type] IN ('P', 'RF', 'TR', 'FN', 'IF', 'TF')
        AND (@objName IS NULL OR O.[name] LIKE (N'%' + @objName + N'%'))
    ORDER BY
        CASE O.[type]
            WHEN 'P' THEN 6
            WHEN 'RF' THEN 1
            WHEN 'FN' THEN 2
            WHEN 'TF' THEN 3
            WHEN 'IF' THEN 4
            WHEN 'TR' THEN 5
        END, O.[name];
 
ELSE
    SELECT
        CASE O.[type]
            WHEN 'P' THEN 'SP'
            WHEN 'RF' THEN 'REPLICATION FILTER PROCEDURE'
            WHEN 'TR' THEN 'DML TRIGGER'
            WHEN 'FN' THEN 'UDF'
            WHEN 'IF' THEN 'UDF'
            WHEN 'TF' THEN 'UDF'
        END AS [type], O.[name], CAST(EP.[value] AS nvarchar(max)) AS [description]
    --  ,A.checkOutFlag, A.checkOutLoginName, A.checkOutHostName, A.checkOutDate
    --FROM SQLSafe.dbo.Objects A
    --  INNER JOIN
        FROM sys.objects O --ON A.databaseName = @nvcDatabaseName AND A.objectName COLLATE Latin1_General_CI_AS = O.[name] COLLATE Latin1_General_CI_AS
        LEFT OUTER JOIN sys.extended_properties EP ON O.[object_id] = EP.major_id AND EP.minor_id = 0 AND EP.[name] = N'MS_Description'
    WHERE O.[type] IN ('P', 'RF', 'TR', 'FN', 'IF', 'TF')
        AND (@objName IS NULL OR O.[name] LIKE (N'%' + @objName + N'%'))
    ORDER BY
        CASE O.[type]
            WHEN 'P' THEN 6
            WHEN 'RF' THEN 1
            WHEN 'FN' THEN 2
            WHEN 'TF' THEN 3
            WHEN 'IF' THEN 4
            WHEN 'TR' THEN 5
        END, O.[name];
 
RETURN 0;
 
ErrorHandler:
RETURN @intReturnValue;
