USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_helpmodule]    Script Date: 2022-11-17 오전 9:19:43 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************     
    
	1. Procedure	: sp_helpmodule     
	2. Process Func	: 저장 프로시저, 사용자 정의 함수의 요약 정보를 반환합니다.
	3. Create Date	: 
	4. Create User	: 
	5. Execute Test	:           
	6. return value	:
		0 = There is no error.
	7. History Info	:     
		Date		Author				Description    
		----------- ------------------- -------------------------------------------    
    
*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[sp_helpmodule]
    @nvcObjectName sysname = NULL, --// 개체 이름.
    @chrObjectTypeCode char(2) = NULL, --// 개체 타입. (P, RF, TR, FN, IF, TF)
    @inyPrintFormat tinyint = 2 --// Print 포맷. 1=Media Wiki,2=HTML,3=RedCloth
--WITH ENCRYPTION
AS
 
SET NOCOUNT ON;
SET XACT_ABORT ON;
 
DECLARE @intReturnValue int;
DECLARE
    @nvcStmt nvarchar(max);
 
SELECT @chrObjectTypeCode = [type] FROM sys.objects WHERE [name] = @nvcObjectName;
 
SET @nvcStmt = N'
DECLARE
    @nvcObjectType sysname,
    @nvcPrevObjectType sysname,
    @nvcDefinition nvarchar(max),
    @i int,
    @j int,
    @k int,
    @l int,
    @m int,
    @n int,
    @o int,
    @intLength int,
    @nvcCommentLine nvarchar(max),
    @nvcCommentLineTemp nvarchar(max),
    @intDepth int,
    @intSequence int,
    @nvcParamName sysname,
    @nvcParamType sysname,
    @bitOutputFlag bit,
    @bitDefaultFlag bit,
    @nvcDefaultValue nvarchar(max),
    @nvcParamDescription nvarchar(max),
    @nvcStmt_param1 nvarchar(max),
    @nvcStmt_param2 nvarchar(max),
    @nvcStmt_param3 nvarchar(max),
    @nvcStmt_param4 nvarchar(max),
    @nvcStmt_Usage nvarchar(max),
    @nvcStmt_UsageTemp nvarchar(max),
    @intPointer int,
    @nvcSummary nvarchar(max);
 
DECLARE @tblObjectLists table (
    seq int IDENTITY(1, 1) NOT NULL,
    objName sysname NOT NULL,
    objType sysname NOT NULL,
    definition nvarchar(max) NOT NULL
);
 
DECLARE @tblParameters table (
    seq int IDENTITY(1, 1) NOT NULL,
    paramName sysname NOT NULL,
    paramType sysname NOT NULL,
    outputFlag bit NOT NULL,
    defaultFlag bit NOT NULL,
    defaultValue nvarchar(max) NOT NULL,
    paramDescription nvarchar(max) NOT NULL
);
 
DECLARE @tblSequences table (
    depth int NOT NULL DEFAULT(0),
    sequence int NOT NULL DEFAULT(1)
);
 
INSERT @tblObjectLists (objName, objType, definition)
SELECT O.[name],
    CASE O.[type]
        WHEN ''P'' THEN ''Stored Procedure''
        WHEN ''RF'' THEN ''Replication Filter Procedure''
        WHEN ''TR'' THEN ''DML Trigger''
        WHEN ''FN'' THEN ''User Defined Function - Scalar Function''
        WHEN ''IF'' THEN ''User Defined Function - Inline Table-Valued Function''
        WHEN ''TF'' THEN ''User Defined Function - Table-Valued-Function''
    END, M.definition
FROM sys.objects O
    INNER JOIN sys.sql_modules M ON O.[object_id] = M.[object_id]
WHERE O.[type] = COALESCE(@chrObjectTypeCode, O.[type]) AND O.[name] LIKE COALESCE(@nvcObjectName, O.[name])
    AND O.[type] IN (''P'', ''RF'', ''TR'', ''FN'', ''IF'', ''TF'')
ORDER BY O.[type], O.[name];
 
SELECT @l = 1, @m = @@ROWCOUNT, @nvcPrevObjectType = N'''';
 
PRINT
    CASE @inyPrintFormat
        WHEN 2 THEN N''
<html>
<head>
  <title>'' + DB_NAME() + N'' - 모듈 명세</title>
  <style>
  <!--
    .caption1 {Courier New, Gulim; font-size: 13pt; background-color:#FFFFFF; font-weight:bold}
    .caption2 {Courier New, Gulim; font-size: 10pt; background-color:#FFFFFF; font-weight:bold}
    pre {font-family: Courier New, Gulim; font-size: 9pt; background-color:#FFFFFF}
  -->
  </style>
</head>
<body>''
        ELSE N''''
    END;
 
WHILE @l <= @m
BEGIN
    SELECT @nvcObjectName = objName, @nvcObjectType = objType, @nvcDefinition = definition
    FROM @tblObjectLists
    WHERE seq = @l;
 
    IF @nvcObjectType <> @nvcPrevObjectType AND @l < @m
    BEGIN
        SET @nvcPrevObjectType = @nvcObjectType;
        PRINT
            CASE @inyPrintFormat
                WHEN 1 THEN N''== '' + @nvcObjectType + N'' ==''
                WHEN 2 THEN N''<p><div class="caption1">'' + @nvcObjectType + N''</div></p>''
                WHEN 3 THEN N''h2. '' + @nvcObjectType + REPLICATE(NCHAR(13) + NCHAR(10), 2)
                ELSE N''''
            END;
    END
 
    PRINT
        CASE @inyPrintFormat
            WHEN 1 THEN N''=== dbo.'' + @nvcObjectName + N'' ==='' + REPLICATE(NCHAR(13) + NCHAR(10), 2)
            WHEN 2 THEN N''<br><br><div class="caption2"><a name="'' + @nvcObjectName + ''">'' + @nvcObjectName + N''</a></div>''
            WHEN 3 THEN N''h3. '' + @nvcObjectName + REPLICATE(NCHAR(13) + NCHAR(10), 2)
            ELSE N''''
        END;
 
    SET @i = CHARINDEX(N''/**'', @nvcDefinition, 1) + 5;
 
    IF @i = 5
    BEGIN
        SET @l += 1;
        CONTINUE;
    END
 
    SET @j = CHARINDEX(N''**/'', @nvcDefinition, 1);
    SET @k = @j + 3
    SET @intLength = @j - @i - 2;
 
    SET @nvcSummary = LTRIM(RTRIM(SUBSTRING(@nvcDefinition, @i, @intLength)));
 
    IF CHARINDEX(N''version :'', @nvcSummary) = 0 AND DB_ID(N''SQLVN'') IS NOT NULL
        SELECT TOP (1) @nvcSummary = N''version : '' + CAST(ST.ObjectVersion AS nvarchar(10)) + NCHAR(13) + NCHAR(10) + @nvcSummary
        FROM SQLVN.dbo.Databases DB
            INNER JOIN SQLVN.dbo.Objects O ON DB.DatabaseID = O.DatabaseID
            INNER JOIN SQLVN.dbo.Statements ST ON O.ObjectID = ST.ObjectID
        WHERE DB.DatabaseName = DB_NAME()
            AND O.ObjectName = @nvcObjectName
            AND ST.ObjectVersion IS NOT NULL
        ORDER BY ST.StatementID DESC;
 
    PRINT
        N''<pre>'' + CHAR(13) + CHAR(10) + N''- Summary'' + CHAR(13) + CHAR(10)
        + N''================================================================================================'' + CHAR(13) + CHAR(10)
        + @nvcSummary + NCHAR(13) + NCHAR(10)
        + N''================================================================================================'' + REPLICATE(CHAR(13) + CHAR(10), 2);
 
    IF @nvcObjectType = N''Stored Procedure''
    BEGIN
        DELETE @tblParameters;
 
        INSERT @tblParameters (paramName, paramType, outputFlag, defaultFlag, defaultValue, paramDescription)
        SELECT P.[name],
            CASE TP.[name]
                WHEN N''char'' THEN N''char('' + CAST(P.max_length AS nvarchar(10)) + N'')''
                WHEN N''varchar'' THEN N''varchar('' + CASE P.max_length WHEN -1 THEN N''max'' ELSE CAST(P.max_length AS nvarchar(4)) END + N'')''
                WHEN N''nchar'' THEN N''nchar('' + CAST(P.max_length / 2 AS nvarchar(10)) + N'')''
                WHEN N''nvarchar'' THEN N''nvarchar('' + CASE P.max_length WHEN -1 THEN N''max'' ELSE CAST(P.max_length / 2 AS nvarchar(4)) END + N'')''
                WHEN N''numeric'' THEN N''decimal('' + CAST(P.precision AS nvarchar(10)) + N'','' + CAST(P.scale AS nvarchar(10)) + N'')''
                WHEN N''decimal'' THEN N''decimal('' + CAST(P.precision AS nvarchar(10)) + N'','' + CAST(P.scale AS nvarchar(10)) + N'')''
                WHEN N''binary'' THEN N''binary('' + CAST(P.max_length AS nvarchar(10)) + N'')''
                WHEN N''varbinary'' THEN N''varbinary('' + CASE P.max_length WHEN -1 THEN N''max'' ELSE CAST(P.max_length AS nvarchar(4)) END + N'')''
                WHEN N''datetime2'' THEN N''datetime2('' + CAST(P.scale AS nvarchar(10)) + N'')''
                WHEN N''time'' THEN N''time('' + CAST(P.scale AS nvarchar(10)) + N'')''
                WHEN N''datetimeoffset'' THEN N''datetimeoffset('' + CAST(P.scale AS nvarchar(10)) + N'')''
                ELSE TP.[name]
            END, P.is_output, P.has_default_value,
            CAST(ISNULL(P.default_value, N''NULL'') AS nvarchar(max)),
            COALESCE(CAST(EP.value AS nvarchar(max)), N'''')
        FROM sys.parameters P
            LEFT OUTER JOIN sys.types TP ON P.user_type_id = TP.user_type_id
            LEFT OUTER JOIN sys.extended_properties EP ON P.[object_id] = EP.major_id AND P.parameter_id = EP.minor_id AND EP.class = 2
        WHERE P.[object_id] = OBJECT_ID(@nvcObjectName)
        ORDER BY P.parameter_id;
 
        SELECT @n = MIN(seq), @o = MAX(seq) FROM @tblParameters;
 
        SET @nvcStmt_param1 = N'''';
        SET @nvcStmt_param2 = N'''';
        SET @nvcStmt_param3 = N'''';
        SET @nvcStmt_param4 = N'''';
 
        WHILE @n <= @o
        BEGIN
            SELECT @nvcParamName = paramName, @nvcParamType = paramType, @bitOutputFlag = outputFlag, @bitDefaultFlag = defaultFlag,
                @nvcDefaultValue = defaultValue, @nvcParamDescription = paramDescription
            FROM @tblParameters
            WHERE seq = @n;
 
            SET @nvcStmt_param1 = @nvcStmt_param1
                + CASE @nvcStmt_param1 WHEN N'''' THEN N''DECLARE'' + CHAR(13) + CHAR(10) + N''   '' ELSE CHAR(13) + CHAR(10) + N'' , '' END
                + @nvcParamName + N'' '' + @nvcParamType
                + CASE WHEN @n = @o THEN N'';'' ELSE N'''' END
                + N''   -- '' + @nvcParamDescription;
 
            SET @nvcStmt_param2 = @nvcStmt_param2
                + CASE @nvcStmt_param2 WHEN N'''' THEN N'''' ELSE CASE @bitOutputFlag WHEN 1 THEN N'''' ELSE CHAR(13) + CHAR(10) END END
                + CASE @bitOutputFlag WHEN 1 THEN N'''' ELSE N''SET '' + @nvcParamName + N'' = NULL;'' END;
 
            SET @nvcStmt_param3 = @nvcStmt_param3
                + CASE @nvcStmt_param3 WHEN N'''' THEN N''    '' ELSE CHAR(13) + CHAR(10) + N'' , '' END
                + @nvcParamName + N'' = '' + @nvcParamName + CASE @bitOutputFlag WHEN 1 THEN N'' OUTPUT'' ELSE N'''' END
                + CASE @bitDefaultFlag WHEN 1 THEN N'' -- default : '' + @nvcDefaultValue ELSE N'''' END;
 
            SET @nvcStmt_param4 = @nvcStmt_param4
                + CASE @bitOutputFlag WHEN 1 THEN CASE @nvcStmt_param4 WHEN N'''' THEN N''SELECT '' ELSE N'', '' END + @nvcParamName + N'' AS ['' + @nvcParamName + N'']'' ELSE N'''' END
 
            SET @n += 1;
        END
 
        SET @nvcStmt_Usage =
            N''- Usage'' + CHAR(13) + CHAR(10)
            + N''================================================================================================'' + CHAR(13) + CHAR(10)
            + N''DECLARE @intReturnValue int;'' + CHAR(13) + CHAR(10)
            + @nvcStmt_param1 + CASE @nvcStmt_param1 WHEN N'''' THEN N'''' ELSE REPLICATE(CHAR(13) + CHAR(10), 2) END
            + @nvcStmt_param2 + CASE @nvcStmt_param2 WHEN N'''' THEN N'''' ELSE REPLICATE(CHAR(13) + CHAR(10), 2) END
            + N''EXEC @intReturnValue = dbo.'' + @nvcObjectName + CHAR(13) + CHAR(10)
            + @nvcStmt_param3 + CASE @nvcStmt_param3 WHEN N'''' THEN N'''' ELSE N'';'' + REPLICATE(CHAR(13) + CHAR(10), 2) END
            + @nvcStmt_param4 + CASE @nvcStmt_param4 WHEN N'''' THEN N'''' ELSE N'';'' + REPLICATE(CHAR(13) + CHAR(10), 2) END
            + N''PRINT @intReturnValue;'' + CHAR(13) + CHAR(10)
            + N''================================================================================================'' + REPLICATE(CHAR(13) + CHAR(10), 2);
 
        EXEC dbo.sp_print @nvcString = @nvcStmt_Usage;
    END
 
    DELETE @tblSequences;
    INSERT @tblSequences DEFAULT VALUES;
 
    PRINT
        N''- Flow'' + CHAR(13) + CHAR(10)
        + N''================================================================================================'' + CHAR(13) + CHAR(10);
 
    WHILE 1 = 1
    BEGIN
        SET @i = CHARINDEX(N''/**_'', @nvcDefinition, @k) + 4;
 
        IF @i = 4
            BREAK;
 
        SET @j = CHARINDEX(NCHAR(13) + NCHAR(10), @nvcDefinition, @i);
        SET @k = @j + 1;
        SET @intLength = @j - @i;
        SET @nvcCommentLine = LTRIM(RTRIM(SUBSTRING(@nvcDefinition, @i, @intLength)));
        SET @nvcCommentLineTemp = REVERSE(@nvcCommentLine);
 
        SET @intDepth = LEN(@nvcCommentLine) - CHARINDEX(N''#'', @nvcCommentLineTemp);
 
        UPDATE @tblSequences
        SET @intSequence = sequence, sequence += 1
        WHERE depth = @intDepth;
 
        IF @@ROWCOUNT = 0
        BEGIN
            INSERT @tblSequences (depth, sequence) VALUES (@intDepth, 2);
            SET @intSequence = 1;
        END
 
        DELETE @tblSequences WHERE depth > @intDepth;
 
        PRINT REPLICATE(N'' '', @intDepth) + CAST(@intSequence AS nvarchar(10)) + N''. '' + RTRIM(LTRIM(REPLACE(SUBSTRING(@nvcCommentLine, @intDepth + 2, LEN(@nvcCommentLine)), N''*/'', N'''')));
    END
 
    PRINT
        N''================================================================================================'' + CHAR(13) + CHAR(10)
        + N''</pre>''
        + REPLICATE(CHAR(13) + CHAR(10), 2);
 
    SET @l += 1;
END
 
PRINT CASE @inyPrintFormat WHEN 2 THEN N''
</body></html>'' ELSE N'''' END;
'
 
EXEC sp_executesql @nvcStmt
    , N'@inyPrintFormat tinyint, @nvcObjectName sysname, @chrObjectTypeCode char(2)'
    , @inyPrintFormat = @inyPrintFormat, @nvcObjectName = @nvcObjectName, @chrObjectTypeCode = @chrObjectTypeCode;
 
RETURN 0;
