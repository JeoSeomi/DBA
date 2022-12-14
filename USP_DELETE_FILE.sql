USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_DELETE_FILE]    Script Date: 2022-11-17 오전 10:22:21 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/******************************************************************************************************* 

	1. Procedure    :	USP_DELETE_FILE
	2. Process Func :	
	3. Create Date  :	
	4. Create User  :	
	5. Execute Test : 						
						EXEC [USP_DELETE_FILE]
							@vchDeleteFileName		= '*.TRN',
							@vchTargetFolderPath	= 'F:\SQL_BACKUP',
							@intModifiedDate		= -1,
							@bitIsDebug				= 1;
						
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------						

*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[USP_DELETE_FILE]
	@vchDeleteFileName VARCHAR(256) = '*.bak '			-- 삭제대상
,	@vchTargetFolderPath VARCHAR(64)					-- 삭제 폴더
,	@intModifiedDate INT								-- 복사 DB	
,	@bitIsSubFolder BIT = 0
,	@bitIsDebug BIt = 0
WITH EXECUTE AS CALLER
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
		
	DECLARE @vchSqlStr VARCHAR(256) = '', @nchCmdStr nvarchar(1000) = '';
	
	---------------------------
	-- CMD 옵션 ON
	---------------------------
	EXEC sp_configure 'show advanced options', 1 
	RECONFIGURE WITH OVERRIDE;
	EXEC sp_configure 'xp_cmdshell', 1 
	RECONFIGURE WITH OVERRIDE;
	
		
	SET @nchCmdStr  = CONCAT('ForFiles /p "', @vchTargetFolderPath, '" ', IIf(@bitIsSubFolder = 1, '/s', '') ,' /m ', @vchDeleteFileName, ' /d ', @intModifiedDate, ' /c "cmd /c del @file"')
	IF @bitIsDebug = 0
		EXEC XP_CMDSHELL @nchCmdStr,no_output;
	ELSE
		PRINT @nchCmdStr;

	---------------------------------------------------------------------------------------------------------------------------------------
	-- CMD 옵션 OFF
	---------------------------------------------------------------------------------------------------------------------------------------
	EXEC sp_configure 'show advanced options', 1 
	RECONFIGURE WITH OVERRIDE;
	EXEC sp_configure 'xp_cmdshell', 0 
	RECONFIGURE WITH OVERRIDE;

END
