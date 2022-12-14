USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_DAILYBACKUP]    Script Date: 2022-11-17 오전 10:22:00 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[USP_DAILYBACKUP]
as
BEGIN

	--백업파일 삭제 -----------------------------------------------------------------------------------------------------------------------
	DECLARE @RemoveCMD sysname
	SET @RemoveCMD = 'del E:\Backup\Daily\GameDB_Daily'+CONVERT(VARCHAR(8),GETDATE(),112)+'.bak'
	--SELECT @RemoveCMD
	EXEC master..xp_cmdshell @RemoveCMD
	SET @RemoveCMD = 'del E:\Backup\Daily\GameDataDB_Daily'+CONVERT(VARCHAR(8),GETDATE(),112)+'.bak'
    EXEC master..xp_cmdshell @RemoveCMD
	SET @RemoveCMD = 'del E:\Backup\Daily\CommonDB_Daily'+CONVERT(VARCHAR(8),GETDATE(),112)+'.bak'
	EXEC master..xp_cmdshell @RemoveCMD
	SET @RemoveCMD = 'del E:\Backup\Daily\GameLogDB_Daily'+CONVERT(VARCHAR(8),GETDATE(),112)+'.bak'
	EXEC master..xp_cmdshell @RemoveCMD

	--현재 DB 백업----------------------------------------------------------------------------------------------------
	DECLARE @BackupName NVARCHAR(MAX)

	SET @BackupName = N'E:\Backup\Daily\GameDB_Daily'+CONVERT(NVARCHAR(8),GETDATE(),112)+N'.bak'
	BACKUP DATABASE [GameDB] TO  DISK = @BackupName WITH NOFORMAT, INIT,  
	NAME = N'일일 백업', SKIP, NOREWIND, NOUNLOAD,  STATS = 10

	SET @BackupName = N'E:\Backup\Daily\GameDataDB_Daily'+CONVERT(NVARCHAR(8),GETDATE(),112)+N'.bak'
	BACKUP DATABASE [GameDataDB] TO  DISK = @BackupName WITH NOFORMAT, INIT,  
	NAME = N'일일 백업(Data)', SKIP, NOREWIND, NOUNLOAD,  STATS = 10

	SET @BackupName = N'E:\Backup\Daily\CommonDB_Daily'+CONVERT(NVARCHAR(8),GETDATE(),112)+N'.bak'
	BACKUP DATABASE [CommonDB] TO  DISK = @BackupName WITH NOFORMAT, INIT,  
	NAME = N'일일 백업(common)', SKIP, NOREWIND, NOUNLOAD,  STATS = 10

	SET @BackupName = N'E:\Backup\Daily\GameLogDB_Daily'+CONVERT(NVARCHAR(8),GETDATE(),112)+N'.bak'
	BACKUP DATABASE [GameLogDB] TO  DISK = @BackupName WITH NOFORMAT, INIT,  
	NAME = N'일일 백업(GameLogDB)', SKIP, NOREWIND, NOUNLOAD,  STATS = 10


	--백업 만들고 7일전 백업은 지우고--------------------------------------------------------------------------------------------------------
	DECLARE @SQL NVARCHAR(MAX)
	SET @SQL='master..xp_cmdshell ''forfiles /P E:\Backup\Daily /D -7 /C "cmd /c rmdir /s /q @file"'''
	EXEC(@SQL)

	SET @SQL='master..xp_cmdshell ''forfiles /P E:\Backup\Daily /D -7 /C "cmd /c rmdir /s /q @file"'''
	EXEC(@SQL)
	
	SET @SQL='master..xp_cmdshell ''forfiles /P E:\Backup\Daily /D -7 /C "cmd /c rmdir /s /q @file"'''
	EXEC(@SQL)

	SET @SQL='master..xp_cmdshell ''forfiles /P E:\Backup\Daily /D -7 /C "cmd /c rmdir /s /q @file"'''
	EXEC(@SQL)
	-----------------------------------------------------------------------------------------------------------------------------------------
END



