USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_RESTORE_DEVICE_STEP01]    Script Date: 2022-11-17 오전 10:23:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/******************************************************************************************************* 

	1. Procedure    :	USP_RESTORE_DEVICE_STEP01
	2. Process Func :	
	3. Create Date  :	2019.06.28
	4. Create User  :	LIM JONG EUN
	5. Execute Test : 						
						EXEC [USP_RESTORE_DEVICE_STEP01]
							@insSrcInstanceID = 1,
							@insDstInstanceID = 6,
							@vchRestoreDB = 'DB_ADMIN',
							@vchPrefix = NULL;
						
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						2020.06.01	LIM J				SharedFolder에서 오래된(-1d) 파일 제거

*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[USP_RESTORE_DEVICE_STEP01]
	@vchSrcSharedFolderPath VARCHAR(256)				-- 공유 폴더
,	@vchBackupFileName varchar(64)						-- 백업 파일명
,	@vchDatabaseName VARCHAR(64)						-- 복사 DB	
,	@vchDstHostIP VARCHAR(16)							-- 대상 서버 IP
,	@chrDateStr CHAR(8)									-- 날짜
,	@chrTimeStr CHAR(6)									-- 시분초
--WITH EXECUTE AS 'WIN-M11QREH11EP\sqlservice'
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
		
	DECLARE @vchSqlStr VARCHAR(256) = '', @nchCmdStr nvarchar(256) = '', @nvcRestoreStr nvarchar(2000)='';
	DECLARE @insSeq SMALLINT;

	---------------------------
	-- CMD 옵션 ON
	---------------------------
	EXEC sp_configure 'show advanced options', 1 
	RECONFIGURE WITH OVERRIDE;
	EXEC sp_configure 'xp_cmdshell', 1 
	RECONFIGURE WITH OVERRIDE;


	IF NOT EXISTS (select 1 From sys.databases where name =@vchDatabaseName)
	BEGIN		
		PRINT '########################################################'
		PRINT @vchDatabaseName + N'데이터베이스가 없어요.'
		PRINT '########################################################'
		RETURN;
	END

	---------------------------------------------------------------------------------------------------------------------------------------
	-- 백업
	---------------------------------------------------------------------------------------------------------------------------------------
	PRINT @vchDatabaseName + N' DB 백업 시작'
	SET @vchSqlStr = ''				
		
	SET @vchSqlStr +=N'BACKUP DATABASE ['+ @vchDatabaseName +']'+CHAR(10)
	SET @vchSqlStr +=N'TO DISK=''' + @vchSrcSharedFolderPath + '\'+@vchBackupFileName + ''''+CHAR(10)
	SET @vchSqlStr +=N'WITH INIT '+CHAR(10)
	SET @vchSqlStr +=N',	COMPRESSION'+CHAR(10)
	SET @vchSqlStr +=N',	NAME = '''+@vchDatabaseName+''';'+CHAR(10)
	
	--PRINT @vchSqlStr
	EXEC (@vchSqlStr)
	PRINT @vchDatabaseName + N' DB 백업 완료'
	
	---------------------------------------------------------------------------------------------------------------------------------------
	-- 복사
	---------------------------------------------------------------------------------------------------------------------------------------	
	SET @nchCmdStr  = 'robocopy '+ @vchSrcSharedFolderPath + ' \\' + @vchDstHostIP + '\SharedFolder ' + @vchBackupFileName;	
	--print @nchCmdStr		
	EXEC XP_CMDSHELL @nchCmdStr,no_output;
	--EXEC XP_CMDSHELL @nchCmdStr;	
	PRINT @vchDatabaseName + N' DB 복사 완료'
	
	---------------------------------------------------------------------------------------------------------------------------------------
	-- 삭제
	---------------------------------------------------------------------------------------------------------------------------------------	
	SET @nchCmdStr  = 'ForFiles /p "'+@vchSrcSharedFolderPath+'" /s /d -2 /c "cmd /c del @file"'
	EXEC XP_CMDSHELL @nchCmdStr,no_output;
	PRINT N'SharedFolder 삭제..'

	---------------------------------------------------------------------------------------------------------------------------------------
	-- CMD 옵션 OFF
	---------------------------------------------------------------------------------------------------------------------------------------
	EXEC sp_configure 'show advanced options', 1 
	RECONFIGURE WITH OVERRIDE;
	EXEC sp_configure 'xp_cmdshell', 0 
	RECONFIGURE WITH OVERRIDE;

END
