USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_RESTORE_DEVICE]    Script Date: 2022-11-17 오전 10:22:56 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/******************************************************************************************************* 

	1. Procedure    :	USP_RESTORE_DEVICE
	2. Process Func :	/* 개발서버의 USP_BACKUP_RESTORE_DEVICE 에서 호출 */
	3. Create Date  :	2019.06.28
	4. Create User  :	LIM JONG EUN
	5. Execute Test : 						
						EXEC [USP_RESTORE_DEVICE] --개발 서버에서 호출
						
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						22-06-07	Kim Jeong			AB->QA 스키마 동기화sp 권한 처리 추가

*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[USP_RESTORE_DEVICE]		
	@vchDstSharedFolderPath VARCHAR(256)								-- 공유폴더 위치		
,	@vchBackupFileName varchar(64)										-- 백업파일명
,	@nvcDefaultDataPathStr nvarchar(64) = NULL							-- 기본 DATA 폴더
,	@nvcDefaultLogPathStr nvarchar(64) = NULL							-- 기본 LOG 폴더
,	@vchRestoreDatabaseName varchar(256)								-- 복원대상DB
,	@vchPrefix varchar(32)	= ''										-- 복원 데이터베이스명 프리픽스
,	@vchSuffix varchar(32) = ''											-- 복원 데이터베이스명 서픽스
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	DECLARE @chrDateStr char(8) ='', @chrTimeStr char(10);
	DECLARE @vchSqlStr VARCHAR(256) = '', @nchCmdStr nvarchar(256) = '', @nvcRestoreStr nvarchar(2000)='';
	DECLARE @insSeq SMALLINT;
		
	
	SET @chrDateStr = CONVERT(VARCHAR(8),GETDATE(),112)	
	SET @chrTimeStr = 
		CONCAT(
			SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(HOUR,GETDATE())),2),1,2)
		,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(MINUTE,GETDATE())),2),1,2)
		,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(SECOND,GETDATE())),2),1,2)
		,	'_'
		,	SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(3),DATEPART(MILLISECOND,GETDATE())),3),1,3)
		)
	SET @vchRestoreDatabaseName = @vchPrefix + @vchRestoreDatabaseName + @vchSuffix

	---------------------------
	-- 복원 Physical path 처리
	---------------------------
	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @vchRestoreDatabaseName)
	BEGIN
		SET @nvcDefaultDataPathStr = ''
		SELECT @nvcDefaultDataPathStr = @nvcDefaultDataPathStr + '\' + value
		FROM STRING_SPLIT(
							(	SELECT TOP 1 Physical_Name 
								FROM sys.master_files mf 
									INNER JOIN sys.databases db		ON db.database_id = mf.database_id
								where db.name = @vchRestoreDatabaseName and type_desc = 'ROWS'
							)
						, '\')  
		WHERE RTRIM(value) <> '' AND [value] NOT LIKE '%.mdf';
		SET @nvcDefaultDataPathStr = STUFF(@nvcDefaultDataPathStr, 1, 1, '');  
		
		SET @nvcDefaultLogPathStr = ''
		SELECT @nvcDefaultLogPathStr = @nvcDefaultLogPathStr + '\' + value
		FROM STRING_SPLIT(
							(	SELECT TOP 1  Physical_Name 
								FROM sys.master_files mf 
									INNER JOIN sys.databases db		ON db.database_id = mf.database_id
								where db.name = @vchRestoreDatabaseName and type_desc = 'LOG'
							)
						, '\')  
		WHERE RTRIM(value) <> '' AND [value] NOT LIKE '%.ldf';
		SET @nvcDefaultLogPathStr = STUFF(@nvcDefaultLogPathStr, 1, 1, '');  

--		PRINT ''
--		PRINT N'원격 DB 백업 정보'
--		PRINT N'DataPath : ' + @nvcDefaultDataPathStr
--		PRINT N'LogPath : ' + @nvcDefaultLogPathStr		
		PRINT ''

		--IF @vchPrefix IS NULL OR @vchPrefix =LTRIM(RTRIM(''))
		--BEGIN
			
			---------------------------
			-- 백업
			---------------------------		
			PRINT '################################################'
			PRINT @vchRestoreDatabaseName + N' DB 백업 시작'
			DECLARE @vchRemoteBackupPath NVARCHAR(256)='', @vchRemoteBackupFileName NVARCHAR(256)='';
			
			SET @vchRemoteBackupFileName = @vchRestoreDatabaseName+'_'+@chrDateStr+'_'+@chrTimeStr+'.bak'
			--SELECT @vchRemoteBackupPath = @vchRemoteBackupPath + value + '\'		
			--FROM STRING_SPLIT(
			--					(	SELECT TOP 1 physical_device_name 
			--						FROM msdb.dbo.backupmediafamily
   --                                 WHERE device_type = 2
			--						ORDER BY media_set_id DESC
			--					)
			--				, '\')  
			--WHERE RTRIM(value) <> '' AND [value] NOT LIKE '%.BAK';
			
			--IF ISNULL(@vchRemoteBackupPath, '') = ''
   --         BEGIN
   --             SET @vchRemoteBackupPath = @vchDstSharedFolderPath+'\'
   --         END
            SET @vchRemoteBackupPath = @vchDstSharedFolderPath+'\'

            SET @vchSqlStr = ''
			SET @vchSqlStr +=N'BACKUP DATABASE ['+ @vchRestoreDatabaseName +']'+CHAR(10)
			SET @vchSqlStr +=N'TO DISK=''' + @vchRemoteBackupPath + @vchRemoteBackupFileName + ''''+CHAR(10)
			SET @vchSqlStr +=N'WITH INIT '+CHAR(10)
			SET @vchSqlStr +=N',	COMPRESSION'+CHAR(10)
			SET @vchSqlStr +=N',	NAME = '''+@vchRestoreDatabaseName+''';'+CHAR(10)

			--PRINT @vchSqlStr
			EXEC (@vchSqlStr)
			PRINT @vchRestoreDatabaseName + N' DB 백업 완료'
			PRINT ''

			---------------------------
			-- 삭제
			---------------------------
			PRINT ''
			PRINT @vchRestoreDatabaseName + N' DB 삭제 시작'
			PRINT ''

			IF OBJECT_ID('tempdb..#database_files') IS NOT NULL 
				DROP TABLE #database_files;
			
			CREATE TABLE #database_files (
				PhysicalName nvarchar(260)
			)
			
			INSERT INTO #database_files
			EXEC ('select physical_name from [' + @vchRestoreDatabaseName +'].sys.database_files;')

			---------------------------
			-- 삭제 데이터베이스 OFFLINE 처리
			---------------------------			
			SET @vchSqlStr = 'ALTER DATABASE [' + @vchRestoreDatabaseName + '] SET OFFLINE  WITH ROLLBACK IMMEDIATE;'
			EXEC (@vchSqlStr)

			---------------------------
			-- Data file 삭제
			---------------------------
			---------------------------
			-- CMD 옵션 ON
			---------------------------
			EXEC sp_configure 'show advanced options', 1;
			RECONFIGURE WITH OVERRIDE;
			EXEC sp_configure 'xp_cmdshell', 1;
			RECONFIGURE WITH OVERRIDE;
						
			DECLARE @nvcPhysicalName NVARCHAR(260);
			DECLARE ColumnCursor CURSOR LOCAL FAST_FORWARD FOR
				SELECT PhysicalName
				FROM #database_files
			
				FOR READ ONLY;
			OPEN ColumnCursor;
			FETCH NEXT FROM ColumnCursor INTO @nvcPhysicalName;
			
			WHILE @@FETCH_STATUS = 0
			BEGIN
			  
				SET @nchCmdStr  = 'del '+ @nvcPhysicalName;					
				EXEC XP_CMDSHELL @nchCmdStr,no_output;
							  
			  FETCH NEXT FROM ColumnCursor INTO @nvcPhysicalName;
			END
			
			CLOSE ColumnCursor;
			DEALLOCATE ColumnCursor;

			---------------------------
			-- CMD 옵션 OFF
			---------------------------
			EXEC sp_configure 'show advanced options', 1; 
			RECONFIGURE WITH OVERRIDE;
			EXEC sp_configure 'xp_cmdshell', 0; 
			RECONFIGURE WITH OVERRIDE;
			
			---------------------------
			-- DB 삭제
			---------------------------
			SET @vchSqlStr = 'DROP DATABASE [' + @vchRestoreDatabaseName + '];'
			EXEC (@vchSqlStr)
			PRINT @vchRestoreDatabaseName + N' DB 삭제 완료'						
		--END
	END
			

	---------------------------
	-- 복원 config 처리
	---------------------------			
	PRINT 'RESTORE HEADERONLY'
	PRINT ''

	DECLARE @inyFiles tinyint = 1;
	SET @vchSqlStr ='RESTORE HEADERONLY FROM DISK = N'''+@vchDstSharedFolderPath+'\'+ @vchBackupFileName+''''
	EXEC (@vchSqlStr);
	SET @inyFiles = @@ROWCOUNT
	PRINT @vchSqlStr
		
	-- BAK file list 저장
	IF OBJECT_ID('tempdb..#ResFileList ') IS NOT NULL 
		DROP TABLE #ResFileList
	
	CREATE TABLE #ResFileList (
		LogicalName nvarchar(128)
	,	PhysicalName nvarchar(260)
	,	Type char(1)
	,	FileGroupName nvarchar(128)
	,	Size numeric(20,0)
	,	MaxSize numeric(20,0)
	,	FileID bigint
	,	CreateLSN numeric(25,0)
	,	DropLSN numeric(25,0) NULL
	,	UniqueID uniqueidentifier
	,	ReadOnlyLSN numeric(25,0) NULL
	,	ReadWriteLSN numeric(25,0) NULL
	,	BackupSizeInBytes bigint
	,	SourceBlockSize int
	,	FileGroupID int
	,	LogGroupGUID uniqueidentifier NULL
	,	DifferentialBaseLSN numeric(25,0) NULL
	,	DifferentialBaseGUID uniqueidentifier
	,	IsReadOnly bit
	,	IsPresent bit
	,	TDEThumbprint varbinary(32)
	,	SnapshotUrl nvarchar(360)
	)
	
	PRINT 'RESTORE HEADERONLY INFO INSERT'
	INSERT INTO #ResFileList
	EXEC ('RESTORE FILELISTONLY FROM DISK = N'''+@vchDstSharedFolderPath+'\'+@vchBackupFileName+'''WITH FILE='+@inyFiles+';')
	
	---------------------------
	-- 복원 Physical query 생성
	---------------------------
	SELECT @vchRestoreDatabaseName = @vchRestoreDatabaseName
	SELECT @nvcRestoreStr += Stmt
	FROM (
			SELECT '--------------------------------------------------------------------'+CHAR(10)
			UNION ALL
			SELECT CONCAT('RESTORE DATABASE ',@vchRestoreDatabaseName, ' FROM DISK =  N''',@vchDstSharedFolderPath,'\',@vchBackupFileName,''' WITH FILE = ',@inyFiles)
			UNION ALL
			SELECT TOP 100 CONCAT(
					CHAR(10)
				,	',     MOVE ''', LogicalName, ''' TO N'''
				,   CASE [Type] 
						WHEN 'D' THEN CONCAT(@nvcDefaultDataPathStr,'\',LogicalName,'_',@chrDateStr,'_',@chrTimeStr) 
						WHEN 'L' THEN CONCAT(@nvcDefaultLogPathStr,'\',LogicalName,'_',@chrDateStr,'_',@chrTimeStr)
						WHEN 'S' THEN CONCAT(@nvcDefaultDataPathStr,'\',LogicalName,'_',@chrDateStr,'_',@chrTimeStr)
					END
				,	CASE 
						WHEN FileID = 1 THEN '.mdf''' 
						WHEN FileID = 2 THEN '.ldf'', STATS=10' 
						WHEN FileID > 2 AND [Type] = 'D' THEN '.ndf'''
						WHEN FileID > 2 AND [Type] = 'S' THEN ''''
						ELSE '.ndf''' 
					END
				)
			FROM #ResFileList
			ORDER BY (CASE [Type] WHEN 'L' THEN 1 ELSE 0 END)
			UNION ALL
			SELECT CHAR(10)+'--------------------------------------------------------------------'
		) A (Stmt)
	
	PRINT @nvcRestoreStr		
	PRINT '--------------------------------------------------------------------'
		
	---------------------------
	-- 복원 시작
	---------------------------
	EXEC (@nvcRestoreStr)
	PRINT '--------------------------------------------------------------------'

	---------------------------
	-- 권한 설정
	---------------------------
	PRINT N'권한 설정'	
    SET @nvcRestoreStr = N'USE ['+ @vchRestoreDatabaseName +'];' +CHAR(13) + CHAR(10) 
					+ 'IF USER_ID(''client_data_reader'') IS NOT NULL ' +CHAR(13) + CHAR(10) 
					+ '		DROP USER client_data_reader;' +CHAR(13) + CHAR(10)  
					+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''client_data_reader'')' +CHAR(13) + CHAR(10) 
					+ ' BEGIN ' +CHAR(13) + CHAR(10) 
					+ '		CREATE USER client_data_reader FOR LOGIN client_data_reader WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
					+ '		GRANT EXECUTE TO client_data_reader; ' +CHAR(13) + CHAR(10) 
					+ '		GRANT VIEW DEFINITION TO client_data_reader;' +CHAR(13) + CHAR(10) 
					+ '		exec sp_addrolemember ''db_datareader'', client_data_reader; ' +CHAR(13) + CHAR(10) 
					+ ' END '
    EXEC (@nvcRestoreStr)   
    PRINT '--------------------------------------------------------------------'  


	---------------------------
	-- 옵션 설정
	---------------------------
	PRINT N'데이터베이스 옵션 설정'	
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreDatabaseName +'];' + 'ALTER DATABASE ['+ @vchRestoreDatabaseName +'] SET TRUSTWORTHY ON; EXEC sp_changedbowner ''sa'';'
	EXEC (@nvcRestoreStr)	
	PRINT '--------------------------------------------------------------------'
	
	---------------------------
	-- 권한 설정
	---------------------------
	PRINT N'기타 설정'	
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreDatabaseName +'];' 
		+ 'IF NOT EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = ''AuditDB'')
				AND EXISTS (SELECT 1 FROM sys.triggers WHERE name = ''DDLTrigger'')
			BEGIN
				DROP TRIGGER DDLTrigger ON DATABASE;
			END'
	EXEC (@nvcRestoreStr)	
	PRINT '--------------------------------------------------------------------'

	-- AB->QA 스키마 동기화sp 권한 처리 추가 (AB/QA차수 에만 dbForgeDiff login 존재함)
	IF @vchRestoreDatabaseName IN ( 'GameDB', 'GameLogDB' )
	BEGIN
		DECLARE @nvcLoginName nvarchar(15) = N'dbForgeDiff';

		SET @nvcRestoreStr = N'USE ['+ @vchRestoreDatabaseName +'];' +CHAR(13) + CHAR(10)  
							+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
							+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10)  
							+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
							+ ' BEGIN ' +CHAR(13) + CHAR(10) 
							+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
							+ '		exec sp_addrolemember ''db_owner'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
							+ ' END '
		EXEC (@nvcRestoreStr);  
	END
END



