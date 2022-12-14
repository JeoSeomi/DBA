USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_print]    Script Date: 2022-11-17 오전 9:20:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************     
    
	1. Procedure	: sp_print     
	2. Process Func	: 문자열을 PRINT합니다.
	3. Create Date	: 2021-03-25
	4. Create User	: 
	5. Execute Test	:           
	6. return value	:
		0 = There is no error.
	7. History Info	:     
		Date		Author				Description    
		----------- ------------------- -------------------------------------------    
    
*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[sp_print]
    @nvcString nvarchar(max)
--WITH ENCRYPTION
AS
 
SET NOCOUNT ON;
 
DECLARE @intReturnValue int, @nvcStringBuffer nvarchar(max), @i int, @j int;
 
/**_# Rollback and return if inside an uncommittable transaction.*/
IF XACT_STATE() = -1
BEGIN
    SET @intReturnValue = 1;
    ROLLBACK TRANSACTION;
    GOTO ErrorHandler;
END
SET @nvcString = REPLACE(@nvcString, CHAR(10) + CHAR(10), CHAR(10));
SET @nvcString = REPLACE(@nvcString, CHAR(13) + CHAR(13), CHAR(13));
SET @nvcString = REPLACE(@nvcString, CHAR(13), N'');
SET @nvcString = REPLACE(@nvcString, CHAR(10), CHAR(13) + CHAR(10));
 
IF LEN(@nvcString) <= 4000 OR @nvcString IS NULL
    PRINT @nvcString;
ELSE
BEGIN
    WHILE 1 = 1
    BEGIN
        SET @nvcStringBuffer = LEFT(@nvcString, CASE ASCII(SUBSTRING(@nvcString, 4000, 1)) WHEN 13 THEN 3999 ELSE 4000 END);
 
        SET @i = CHARINDEX(CHAR(10) + CHAR(13), REVERSE(@nvcStringBuffer));
        SET @j = (DATALENGTH(@nvcStringBuffer) / 2) - CASE @i WHEN 0 THEN 0 ELSE @i + 1 END;
 
        SET @nvcStringBuffer = LEFT(@nvcStringBuffer, @j);
        PRINT @nvcStringBuffer;
 
        SET @nvcString = CASE @i WHEN 0 THEN @nvcString ELSE STUFF(@nvcString, @j + 1, 2, N'') END;
        SET @nvcString = SUBSTRING(@nvcString, @j + 1, (DATALENGTH(@nvcString) / 2) - @j);
 
        IF LEN(@nvcString) <= 4000
        BEGIN
            PRINT @nvcString;
            BREAK;
        END
    END
END
 
RETURN 0;
 
ErrorHandler:
RETURN @intReturnValue;
