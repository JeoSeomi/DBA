USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_RESTORE]    Script Date: 2022-11-17 오전 10:24:28 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[USP_RESTORE]
	@BakFIleName NVARCHAR(256)						-- 백업 파일 이름(경로 미포함)
,	@BakFileDest NVARCHAR(128) = N'E:\Backup'		-- 백업 파일 경로
,	@ResDbName NVARCHAR(128)						-- 복원 디비 이름
,	@ResDatFileDest NVARCHAR(128) = N'C:\DB\Data'	-- 복원 디비 데이터 파일 경로
,	@ResLogFileDest NVARCHAR(128) = N'C:\DB\Log'	-- 복원 디비 로그 파일 경로
,	@PrintOnly BIT = 0
AS
BEGIN
	SET NOCOUNT ON

	DECLARE @ResStmt NVARCHAR(2000) = ''
	DECLARE @DateStr VARCHAR(8)
	DECLARE @TimeStr VARCHAR(10)
	DECLARE @CurrDate DATETIME = GETDATE()
	DECLARE @Files INT

	IF @BakFIleName IS NULL
	BEGIN
		PRINT 'USP_RESTORE:@BakFileName is incorrect'
		RETURN
	END

	IF @ResDbName IS NULL 
	BEGIN
		PRINT 'USP_RESTORE:@ResDbName is incorrect'
		RETURN
	END

	IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @ResDbName) AND @PrintOnly = 0
	BEGIN
		PRINT 'USP_RESTORE:@ResDbName database is exist'
		RETURN
	END

	IF CHARINDEX('\',@BakFIleName,1) > 0
	BEGIN
		PRINT 'USP_RESTORE:@BackFileName is incorrect'
		RETURN
	END

	-- 경로 뒤에 붙은 '\' 빼기
	IF SUBSTRING(@ResDatFileDest,LEN(@ResDatFileDest),1) = '\'
	BEGIN
		SET @ResDatFileDest = SUBSTRING(@ResDatFileDest,1,LEN(@ResDatFileDest)-1)
	END
	
	IF SUBSTRING(@ResLogFileDest,LEN(@ResLogFileDest),1) = '\'
	BEGIN
		SET @ResLogFileDest = SUBSTRING(@ResLogFileDest,1,LEN(@ResLogFileDest)-1)
	END

	-- Date string.
	SET @DateStr = CONVERT(VARCHAR(8),@CurrDate,112)
	SET @TimeStr = 
		CONCAT(
			SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(HOUR,@CurrDate)),2),1,2)
		,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(MINUTE,@CurrDate)),2),1,2)
		,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(SECOND,@CurrDate)),2),1,2)
		,	'_'
		,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(3),DATEPART(MILLISECOND,@CurrDate)),3),1,3)
		)

	-- BAK file 조사
	EXEC ('RESTORE HEADERONLY FROM DISK = N'''+@BakFileDest+'\'+@BakFIleName+'''');
	SET @Files = @@ROWCOUNT

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

	INSERT INTO #ResFileList
	EXEC ('RESTORE FILELISTONLY FROM DISK = N'''+@BakFileDest+'\'+@BakFIleName+'''WITH FILE='+@Files+';')

	SELECT @ResStmt += Stmt
	FROM (
			SELECT '--------------------------------------------------------------------'+CHAR(10)
			UNION ALL
			SELECT CONCAT('RESTORE DATABASE ',@ResDbName, ' FROM DISK =  N''',@BakFileDest,'\',@BakFIleName,''' WITH FILE = ',@Files)
			UNION ALL
			SELECT TOP 100 CONCAT(
					CHAR(10)
				,	',     MOVE ''', LogicalName, ''' TO N'''
				,   CASE [Type] 
						WHEN 'D' THEN CONCAT(@ResDatFileDest,'\',LogicalName,'_',@DateStr,'_',@TimeStr) 
						WHEN 'L' THEN CONCAT(@ResLogFileDest,'\',LogicalName,'_',@DateStr,'_',@TimeStr)
						WHEN 'S' THEN CONCAT(@ResDatFileDest,'\',LogicalName,'_',@DateStr,'_',@TimeStr)
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

	PRINT @ResStmt
	IF @PrintOnly = 1
		RETURN 0
	
	EXEC (@ResStmt)
	PRINT '--------------------------------------------------------------------'
END


