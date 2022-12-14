USE [master]
GO
/****** Object:  StoredProcedure [dbo].[usp_RestoreReplace_LocalDevice]    Script Date: 2022-11-17 오전 10:25:32 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************************************************   
  
 1. Procedure    : usp_RestoreReplace_LocalDevice  
 2. Process Func : 로컬 백업파일을 replace 복원 합니다.
 3. Create Date  : 2021.03.30
 4. Create User  : Kim Jeong
 5. Execute Test :         
			dbo.usp_RestoreReplace_LocalDevice 'F:\SQL_BACKUP', 'WINDEVDB05_INS05_GameDataDB_202105101603.BAK', NULL, NULL, 'GameDataDB', 'GameDataDB', '', '', 1, 0, 0;
 6. History Info :   
					Date		Author				Description  
					----------- ------------------- -------------------------------------------  
  
*******************************************************************************************************/   
ALTER PROCEDURE [dbo].[usp_RestoreReplace_LocalDevice]
	@vchBakFileFolderPath	varchar(256)	= 'F:\SQL_BACKUP'			--// 백업파일 위치
,	@vchBackupFileName		varchar(64)		= ''	--// 백업파일명  ****** (위 2번(S3에서 라이브 서버에 다운로드)에서 다운로드 한 파일명) ******
,	@nvcDefaultDataPathStr	nvarchar(64)	= NULL			--// 주의!!!(replace), 복원 대상 DATA 폴더, (NULL = 기존 경로, 신규DB는 반드시 입력)  
,	@nvcDefaultLogPathStr	nvarchar(64)	= NULL			--// 주의!!!(replace), 복원 대상 LOG 폴더, (NULL = 기존 경로, 신규DB는 반드시 입력)  
,	@vchRestoreSourceDatabaseName	varchar(256)	= ''	--// 원본DB (@bitLogRestoreFlag = 1 일때 로그백업파일 체크용)
,	@vchRestoreTargetDatabaseName	varchar(256)	= ''	--// 복원대상DB  
,	@vchPrefix				varchar(32)		= ''			--// 복원 DB명 프리픽스  
,	@vchSuffix				varchar(32)		= ''			--// 복원 DB명 서픽스 
,	@bitBakAfterRestoreFlag	bit				= 0				--// 복원 후 백업 여부
,	@bitLogRestoreFlag		bit				= 0				--// 로그복원 여부
,	@bitExecFlag			bit				= 0				--// 실행 여부
AS  
SET NOCOUNT ON;  
SET XACT_ABORT ON;

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  

DECLARE @intReturnValue int;

DECLARE @vchSqlStr VARCHAR(256) = ''
,	@nchCmdStr nvarchar(256) = ''
,	@nvcRestoreStr nvarchar(max)=''
,	@insSeq SMALLINT
,	@i tinyint = 1
,	@chrDateStr char(19)	= ''
,	@inyFiles tinyint = 1
,	@nvcLoginName nvarchar(50) = N''
,	@nvcBakFileAfterRestore	nvarchar(100) = N''

IF XACT_STATE() = -1
BEGIN
	SET @intReturnValue = 1;
	GOTO ErrorHandler;
END

-- QA도 F 생김!
--SET @vchBakFileFolderPath = IIF(@vchBakFileFolderPath = 'F:\SQL_BACKUP', STUFF(@vchBakFileFolderPath, 1, 1, IIF(@@SERVERNAME = 'SKRG-OQDB-01', 'D', 'F') ), @vchBakFileFolderPath);		--// QA는 경로가 D.
SET @vchRestoreTargetDatabaseName = @vchPrefix + @vchRestoreTargetDatabaseName + @vchSuffix  


 BEGIN TRY

	 ---------------------------------------------------------------------------------    
	 -- 로그 복원 단계에서 처리하던걸 에러 처리를 위해 앞으로 이동시킴
	 ---------------------------------------------------------------------------------      
	IF @bitLogRestoreFlag = 1
	BEGIN

		DROP TABLE IF EXISTS #bak;

		SELECT db_id(bs.database_name) AS database_id, bs.database_name, bs.name, bs.type
		,	CASE bs.type
				WHEN 'D'   THEN 'Database'
				WHEN 'I'   THEN 'Differential Database'
				WHEN 'L'   THEN 'Log'
				WHEN 'F'   THEN 'File / File Group'
				WHEN 'G'   THEN 'Differential File'
				WHEN 'P'   THEN 'Partial'
				WHEN 'Q'   THEN 'Differential Partial'
			ELSE ''
			END + ' Backup' AS backup_type_desc
		,	CAST(bs.backup_size / 1024 / 1024 AS DECIMAL(18, 2)) AS size_mb
		,	CAST(bs.compressed_backup_size / 1024 / 1024 AS DECIMAL(18, 2)) AS compressed_size_mb
		,	bs.user_name
		,	datediff(s, bs.backup_start_date, bs.backup_finish_date) AS elapsed_time_sec
		,	bs.backup_start_date AS start_time
		,	bs.backup_finish_date AS end_time
		,	bs.database_backup_lsn
		,	bs.differential_base_lsn
		,	CASE bmf.device_type
				WHEN 2      THEN 'Disk'
				WHEN 5      THEN 'Tape'
				WHEN 7      THEN 'Virtual Device'
				WHEN 105    THEN 'A Permanent Backup Device'
			ELSE ''
			END device_type
		,	bmf.physical_device_name AS physical_backup_device_name
		,	bmf.logical_device_name AS logical_backup_device_name
		INTO #bak
		FROM msdb.dbo.backupmediafamily bmf
		INNER JOIN msdb.dbo.backupset bs ON bmf.media_set_id = bs.media_set_id
		WHERE bs.database_name = @vchRestoreSourceDatabaseName;

		IF NOT EXISTS ( SELECT 1 FROM #bak WHERE [type] = 'L')
		BEGIN
			PRINT N'Log 백업이 없습니다.'
	
			SET @intReturnValue = 10001;
			GOTO ErrorHandler;
		END
	END

	 ---------------------------  
	 -- 복원 Physical path 처리  
	 ---------------------------  
	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @vchRestoreTargetDatabaseName)  
	BEGIN
		IF @nvcDefaultDataPathStr IS NULL
		BEGIN
			SET @nvcDefaultDataPathStr = ''  
			SELECT @nvcDefaultDataPathStr = @nvcDefaultDataPathStr + '\' + value  
			FROM STRING_SPLIT(  
								( SELECT TOP 1 Physical_Name   
									FROM sys.master_files mf   
									INNER JOIN sys.databases db  ON db.database_id = mf.database_id  
									WHERE db.name = @vchRestoreTargetDatabaseName and type_desc = 'ROWS'  
								)  
						, '\')    
			WHERE RTRIM(value) <> '' AND [value] NOT LIKE '%.mdf';  
			SET @nvcDefaultDataPathStr = STUFF(@nvcDefaultDataPathStr, 1, 1, '');
		END

		IF @nvcDefaultLogPathStr IS NULL
		BEGIN
			SET @nvcDefaultLogPathStr = ''  
			SELECT @nvcDefaultLogPathStr = @nvcDefaultLogPathStr + '\' + value  
			FROM STRING_SPLIT(  
								( SELECT TOP 1  Physical_Name   
								FROM sys.master_files mf   
									INNER JOIN sys.databases db  ON db.database_id = mf.database_id  
								where db.name = @vchRestoreTargetDatabaseName and type_desc = 'LOG'  
								)  
						, '\')    
			WHERE RTRIM(value) <> '' AND [value] NOT LIKE '%.ldf';  
			SET @nvcDefaultLogPathStr = STUFF(@nvcDefaultLogPathStr, 1, 1, '');    
		END
		PRINT ''  

		PRINT ''  
	
		PRINT '-- ' + CONVERT(nchar(1), @i) + '. ' + @vchRestoreTargetDatabaseName + N' DB offline 처리'  
		PRINT ''
		---------------------------  
		-- 데이터베이스 OFFLINE 처리  
		---------------------------  
		IF (SELECT [state] FROM sys.databases WHERE name = @vchRestoreTargetDatabaseName) <> 6
		BEGIN
			SET @vchSqlStr = 'ALTER DATABASE [' + @vchRestoreTargetDatabaseName + '] SET OFFLINE  WITH ROLLBACK IMMEDIATE;'  
			PRINT (@vchSqlStr) 
			PRINT ''
			
			IF @bitExecFlag = 1
			BEGIN
				EXEC (@vchSqlStr)  
			END

			SET @i += 1;
		END
	END
	ELSE
	BEGIN
		IF (@nvcDefaultDataPathStr + @nvcDefaultLogPathStr) IS NULL
		BEGIN
			PRINT N'신규DB는 @nvcDefaultDataPathStr, @nvcDefaultLogPathStr를 명시해야 합니다.'
	
			SET @intReturnValue = 10000;
			GOTO ErrorHandler;
		END
	END
	PRINT '--------------------------------------------------------------------'   
	---------------------------  
	-- 복원 config 처리  
	---------------------------    
	PRINT '-- ' + CONVERT(nchar(1), @i) + N'. RESTORE HEADERONLY'  
	PRINT ''  
	SET @vchSqlStr = CONCAT('RESTORE HEADERONLY FROM DISK = N''' , @vchBakFileFolderPath , '\' , @vchBackupFileName , '''')
	PRINT (@vchSqlStr)
	EXEC (@vchSqlStr);  
	SET @inyFiles = @@ROWCOUNT  
	PRINT '--------------------------------------------------------------------'     
	
	-- BAK file list 저장  
	DROP TABLE IF EXISTS #ResFileList;
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
	)  ;
 
	SET @i += 1;
	PRINT '-- ' + CONVERT(nchar(1), @i) + '. RESTORE FILELISTONLY INFO INSERT' 
 
	INSERT INTO #ResFileList  
	EXEC ('RESTORE FILELISTONLY FROM DISK = N'''+@vchBakFileFolderPath+'\'+@vchBackupFileName+'''WITH FILE='+@inyFiles+';');
	PRINT '--------------------------------------------------------------------'   
	
	---------------------------  
	-- 복원 Physical query 생성  
	---------------------------  
	SET @chrDateStr = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss_fff');
 
	SELECT @nvcRestoreStr += Stmt  
	FROM (  
		SELECT CONCAT('RESTORE DATABASE ',@vchRestoreTargetDatabaseName, ' FROM DISK =  N''',@vchBakFileFolderPath,'\',@vchBackupFileName,''' WITH FILE = ',@inyFiles)  
		UNION ALL  
		SELECT TOP 100 CONCAT(  
								CHAR(10)  
							, ',     MOVE ''', LogicalName, ''' TO N'''  
							,   CASE [Type]   
								WHEN 'D' THEN CONCAT(@nvcDefaultDataPathStr,'\',LogicalName,'_', @chrDateStr)   
								WHEN 'L' THEN CONCAT(@nvcDefaultLogPathStr,'\',LogicalName,'_', @chrDateStr)  
								WHEN 'S' THEN CONCAT(@nvcDefaultDataPathStr,'\',LogicalName,'_', @chrDateStr)  
								END  
							, CASE   
									WHEN FileID = 1 THEN '.mdf'''   
									WHEN FileID = 2 THEN '.ldf'', STATS=10, REPLACE' + IIF(@bitLogRestoreFlag = 1, ', NORECOVERY;', ';' )
									WHEN FileID > 2 AND [Type] = 'D' THEN '.ndf'''  
									WHEN FileID > 2 AND [Type] = 'S' THEN ''''  
									ELSE '.ndf'''   
								END  
							)  
		FROM #ResFileList  
		ORDER BY (CASE [Type] WHEN 'L' THEN 1 ELSE 0 END)  
	) A (Stmt);
  
	---------------------------  
	-- 복원 시작  
	---------------------------  
	SET @i += 1;
	PRINT '-- ' + CONVERT(nchar(1), @i) + N'. 복원 시작'

	PRINT ''
	PRINT (@nvcRestoreStr);
	
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END
	PRINT '--------------------------------------------------------------------'  

	---------------------------  
	-- 로그 복원 시작  
	--------------------------- 
	IF @bitLogRestoreFlag = 1
	BEGIN
		SET @i += 1;
		PRINT '-- ' + CONVERT(nchar(1), @i) + N'. 로그 복원 시작';

	--SELECT * FROM #bak

		SET @nvcRestoreStr = N'';
		SELECT @nvcRestoreStr += CONCAT('RESTORE LOG ', @vchRestoreTargetDatabaseName, ' FROM DISK=N''',physical_backup_device_name,''' WITH FILE=1, STATS=10', IIF(ROW_NUMBER() OVER(ORDER BY start_time DESC)=1,';',', NORECOVERY;'),CHAR(10))
		FROM #bak
		WHERE type = 'L'
			AND database_backup_lsn > (
											SELECT TOP (1) database_backup_lsn
											FROM #bak
											WHERE type = 'D' 
												--AND name = N'004 maintenance backup'
												AND physical_backup_device_name =  CONCAT(@vchBakFileFolderPath,'\',@vchBackupFileName)
											ORDER BY start_time DESC
										)
		ORDER BY start_time ASC;

		EXEC master.dbo.sp_print @nvcRestoreStr;

		IF @bitExecFlag = 1
		BEGIN
			EXEC (@nvcRestoreStr);  
		END
		PRINT '--------------------------------------------------------------------'  
	END
/*	
	IF EXISTS ( SELECT 1 FROM sys.databases WHERE [name] = @vchRestoreTargetDatabaseName AND [state] = 1)
	BEGIN
		-- RESTORE DATABASE Z_GameDB WITH RECOVERY;
	END
*/  
	---------------------------  
	-- 권한 설정  
	---------------------------  
	SET @i += 1;
	PRINT '-- ' + CONVERT(nchar(1), @i) + N'. 권한 설정'
	PRINT ''

	SET @nvcLoginName = N'GranServiceUser';
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
						+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
						+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10)  
						+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
						+ ' BEGIN ' +CHAR(13) + CHAR(10) 
						+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
						+ '		GRANT EXECUTE TO ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ '		GRANT VIEW DEFINITION TO ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
						+ '		exec sp_addrolemember ''db_datareader'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ ' END '
	PRINT (@nvcRestoreStr);
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 
	PRINT '';
	SET @nvcLoginName = N'GranWebUser';
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10)  
						+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
						+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10)  
						+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
						+ ' BEGIN ' +CHAR(13) + CHAR(10) 
						+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
						+ '		GRANT EXECUTE TO ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ ' END '
	PRINT (@nvcRestoreStr);
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 
	PRINT '';
	SET @nvcLoginName = N'GranDevUser';
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10)  
						+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
						+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10)  
						+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
						+ ' BEGIN ' +CHAR(13) + CHAR(10) 
						+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
						+ '		GRANT VIEW DEFINITION TO ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
						+ '		exec sp_addrolemember ''db_datareader'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ ' END '
	PRINT (@nvcRestoreStr);
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 
	PRINT '';

	SET @nvcLoginName = N'GranWebDevUser';
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
						+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
						+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
						+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
						+ ' BEGIN ' +CHAR(13) + CHAR(10) 
						+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
						+ '		GRANT EXECUTE TO ' + @nvcLoginName + '; '
						+ '		GRANT VIEW DEFINITION TO ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
						+ '		exec sp_addrolemember ''db_datareader'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ ' END '
	PRINT (@nvcRestoreStr);
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 
	PRINT '';

	SET @nvcLoginName = N'las';
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
						+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
						+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
						+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
						+ ' BEGIN ' +CHAR(13) + CHAR(10) 
						+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
						+ '		exec sp_addrolemember ''db_datareader'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
						+ ' END '
	PRINT (@nvcRestoreStr);
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 
	PRINT '';

	IF @@SERVERNAME = N'SKRP-BIDB-01'
	BEGIN
		SET @nvcLoginName = N'AnalysisUser';
		SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
							+ 'IF USER_ID(''' + @nvcLoginName + ''') IS NOT NULL ' +CHAR(13) + CHAR(10) 
							+ '		DROP USER ' + @nvcLoginName + ';' +CHAR(13) + CHAR(10) 
							+ ' IF EXISTS ( SELECT 1 FROM sys.sql_logins WHERE [name] = ''' + @nvcLoginName + ''')' +CHAR(13) + CHAR(10) 
							+ ' BEGIN ' +CHAR(13) + CHAR(10) 
							+ '		CREATE USER ' + @nvcLoginName + ' FOR LOGIN ' + @nvcLoginName + ' WITH DEFAULT_SCHEMA=dbo;' +CHAR(13) + CHAR(10) 
							+ '		exec sp_addrolemember ''db_datareader'', ' + @nvcLoginName + '; ' +CHAR(13) + CHAR(10) 
							+ ' END '
		PRINT (@nvcRestoreStr);  
		IF @bitExecFlag = 1
		BEGIN
			EXEC (@nvcRestoreStr);  
		END
		PRINT '';
	END

	PRINT '--------------------------------------------------------------------'  
	---------------------------  
	-- 옵션 설정  
	---------------------------  
	SET @i += 1;
	PRINT '-- ' + CONVERT(nchar(1), @i) + N'. 데이터베이스 옵션 설정';

	IF @vchRestoreTargetDatabaseName IN ( 'GameDB', 'GameDataDB')
	BEGIN
		IF EXISTS ( SELECT 1 FROM sys.databases WHERE [name] = @vchRestoreTargetDatabaseName AND recovery_model <> 1)
		BEGIN
			PRINT ''
			SET @nvcRestoreStr = N'USE master;' +CHAR(13) + CHAR(10) 
								+' ALTER DATABASE ['+ @vchRestoreTargetDatabaseName +'] SET RECOVERY FULL;'; 
			PRINT (@nvcRestoreStr) 
			IF @bitExecFlag = 1
			BEGIN
				EXEC (@nvcRestoreStr);  
			END 
		END
	END
	PRINT ''
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
						+ ' ALTER DATABASE ['+ @vchRestoreTargetDatabaseName +'] SET TRUSTWORTHY ON;' +CHAR(13) + CHAR(10) 
	PRINT (@nvcRestoreStr) 
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END 

	PRINT ''
	SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
						+ ' EXEC sp_changedbowner ''sa'';'  
	PRINT (@nvcRestoreStr) 
	IF @bitExecFlag = 1
	BEGIN
		EXEC (@nvcRestoreStr);  
	END
	PRINT '--------------------------------------------------------------------'    
	---------------------------  
	-- 기타 설정  
	---------------------------  
	--SET @i += 1;
	--PRINT CONVERT(nchar(1), @i) + N'. 기타 설정'
	--PRINT ''
	--SET @nvcRestoreStr = N'USE ['+ @vchRestoreTargetDatabaseName +'];' +CHAR(13) + CHAR(10) 
	--			+ N'IF NOT EXISTS (SELECT 1 FROM SYS.DATABASES WHERE NAME = ''AuditDB'')' +CHAR(13) + CHAR(10) 
	--			+ N'				AND EXISTS (SELECT 1 FROM sys.triggers WHERE name = ''DDLTrigger'')' +CHAR(13) + CHAR(10) 
	--			+ N'BEGIN' +CHAR(13) + CHAR(10) 
	--			+ N'	DROP TRIGGER DDLTrigger ON DATABASE;' +CHAR(13) + CHAR(10) 
	--			+ N'END'
	--PRINT (@nvcRestoreStr)  
	--EXEC (@nvcRestoreStr)  
	--PRINT '--------------------------------------------------------------------'  

	IF @bitBakAfterRestoreFlag =  1
	BEGIN
		SET @nvcBakFileAfterRestore = CONCAT(@vchRestoreTargetDatabaseName, '_F_', FORMAT(GETDATE(), 'yyyyMMdd_HHmmss'));
		SET @nvcRestoreStr = 'BACKUP DATABASE ' + @vchRestoreTargetDatabaseName + ' TO DISK=''' + @vchBakFileFolderPath + '\' +  @nvcBakFileAfterRestore + '.bak'' WITH INIT,COMPRESSION;'
		PRINT (@nvcRestoreStr) 
		IF @bitExecFlag = 1
		BEGIN
			EXEC (@nvcRestoreStr);  
		END
	END

END TRY
BEGIN CATCH
	IF XACT_STATE() <> 0
		ROLLBACK TRANSACTION;

	IF @intReturnValue IS NULL OR @intReturnValue = 0
	BEGIN
		PRINT ERROR_MESSAGE()
		--EXEC @intReturnValue = dbo.USP_AddErrorLog;
		SET @intReturnValue = 50001;
	END
	ELSE
		GOTO ErrorHandler;

	RETURN @intReturnValue;
END CATCH;

RETURN 0;

ErrorHandler:
IF XACT_STATE() <> 0
	ROLLBACK TRANSACTION;
RETURN @intReturnValue;
