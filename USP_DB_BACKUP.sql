USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_DB_BACKUP]    Script Date: 2022-11-17 오전 10:22:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




/******************************************************************************************************* 

	1. Procedure    :	USP_DB_BACKUP
	2. Process Func :	
	3. Create Date  :	20181012
	4. Create User  :	LIM JONG EUN
	5. Execute Test : 						

						EXEC USP_DB_BACKUP 'GameDB','E:\Backup\Daily','L','24'
						
						@BackType = F:FULL / L:LOG / D:DIFFERENTIAL / M:MASTER KEY
						
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						2021-09-06  smjeon              Backup시 ldf 용량 줄이기 추가
                        2021-12-30  smjeon              오래된 Backup 파일 삭제시 젠킨스에서 생성한 파일은 삭제 못하고 있어서 삭제할 수 있도록 변경
*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[USP_DB_BACKUP]
    @BackDb NVARCHAR(100) = NULL
,	@BackDest NVARCHAR(500)
,	@BackType VARCHAR(1) 
,	@BackExpireHour INT = 0
,	@BackPwd NVARCHAR(50) = ''
,	@BufferCount INT = 10
,	@MaxTransferSize INT = 65536
,	@IsCompression BIT = 1
AS
BEGIN
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	DECLARE @CurrDate DATETIME = GETDATE()
	DECLARE @ExpireDevName NVARCHAR(1000)
	DECLARE @DevName NVARCHAR(1000)
	DECLARE @Path NVARCHAR(500)
	DECLARE @DateStr VARCHAR(8)
	DECLARE @TimeStr VARCHAR(10)
	DECLARE @ServerName NVARCHAR(128)
	DECLARE @Sql NVARCHAR(4000);
	DECLARE @Seq INT

	BEGIN TRY
		IF @BackType NOT IN ( 'F','L','D','M' )
		BEGIN
			RAISERROR ('@BackType incorrect.',16,1)
			RETURN;
		END
	
		IF @BackType IN ( 'F','L','D' ) AND NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = @BackDb)
		BEGIN
			RAISERROR ('@BackDb incorrect.',16,1)
			RETURN;
		END
	
		SET @ServerName = UPPER(REPLACE(REPLACE(@@SERVERNAME,'\','_'),'-','_'))
		SET @BackDest = REPLACE(@BackDest,'\\','\')

		IF SUBSTRING(@BackDest,LEN(@BackDest),1) = '\'
		BEGIN
			SET @BackDest = SUBSTRING(@BackDest,1,LEN(@BackDest)-1)
		END

		SET @DateStr = CONVERT(VARCHAR(8),@CurrDate,112)
		SET @TimeStr = 
			CONCAT(
				SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(HOUR,@CurrDate)),2),1,2)
			,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(MINUTE,@CurrDate)),2),1,2)
			,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(2),DATEPART(SECOND,@CurrDate)),2),1,2)
			,	'_'
			,   SUBSTRING(RIGHT('00'+CONVERT(VARCHAR(3),DATEPART(MILLISECOND,@CurrDate)),3),1,3)
			)
	
	

		IF OBJECT_ID('tempdb..#Dev') IS NOT NULL DROP TABLE #Dev

		SELECT Seq = IDENTITY(INT,1,1), DevName, DevDate
		INTO #Dev
		FROM (
				SELECT [Name] DevName
				,	DevDate = 
						CONCAT(
							SUBSTRING(RIGHT([Name],19),1,4),'-',SUBSTRING(RIGHT([Name],19),5,2),'-',SUBSTRING(RIGHT([Name],19),7,2),' '
						,	SUBSTRING(RIGHT([Name],19),10,2),':',SUBSTRING(RIGHT([Name],19),12,2),':',SUBSTRING(RIGHT([Name],19),14,2)
						)
				FROM sys.backup_devices
				WHERE [name] LIKE @ServerName+'\_'+@BackDb+'\_%'+@BackType+'\_%' ESCAPE '\'
			) A
		WHERE ISDATE(DevDate) = 1 AND (DATEDIFF(SECOND,DevDate,@CurrDate) >= @BackExpireHour*3600 AND @BackExpireHour > 0)

		CREATE CLUSTERED INDEX CIX__Dev__Seq ON #Dev(Seq)

		SET @Seq = (SELECT TOP (1) Seq FROM #Dev ORDER BY Seq DESC)

		WHILE @Seq > 0
		BEGIN
			SELECT @ExpireDevName = DevName
			FROM #Dev
			WHERE Seq = @Seq
			
			BEGIN TRY
				EXEC SP_DROPDEVICE @ExpireDevName,'DELFILE'
				PRINT '@ExpireDevName..'+@ExpireDevName
			END TRY
			BEGIN CATCH
			END CATCH

			WAITFOR DELAY '00:00:00.001'
			SET @Seq -= 1
		END

		SET @DevName = @ServerName+'_'+@BackDb+'_'+@BackType+'_'+@DateStr+'_'+@TimeStr
		SET @Path = @BackDest+'\'+@DevName+'.bak'

		--PRINT @DevName
		--PRINT @Path
		
		EXEC sp_addumpdevice @devtype='DISK',@logicalname=@DevName,@physicalname=@Path
       
		IF @BackType = 'F'
		BEGIN
            ---------------------------
			-- 로그 파일 용량 축소
			---------------------------
            EXEC master.dbo.USP_BACKUP_RESTORE_DEVICE_LDFSHRINKFILE @vchRestoreDatabaseName = @BackDb;

			WAITFOR DELAY '00:00:00.001'; 

            ---------------------------
			-- FULL Backup 진행
			---------------------------
			SET @Sql = '';
			SET @Sql +='BACKUP DATABASE ['+@BackDb+']'+CHAR(10)
			SET @Sql +='TO '+@DevName+CHAR(10)
			SET @Sql +='WITH INIT '+CHAR(10)
			SET @Sql +=',	NAME = '''+@DevName+''''+CHAR(10)
			SET @Sql +=',	NOSKIP '+CHAR(10)
			SET @Sql +=',	NOFORMAT '+CHAR(10)
         
			IF LEN(@BackPwd) > 0
				SET @Sql += ',	PASSWORD = '''+@BackPwd+''''+CHAR(10)
             
			IF @BufferCount > 0
				SET @Sql += ',	BUFFERCOUNT = '+CONVERT(VARCHAR(10),@BufferCount)+CHAR(10)

			IF @MaxTransferSize > 0
				SET @Sql += ',	MAXTRANSFERSIZE = '+CONVERT(VARCHAR(10),@MaxTransferSize)+CHAR(10)
         
			IF @IsCompression = 0
				SET @Sql += ',	NO_COMPRESSION '+CHAR(10)
			ELSE IF @IsCompression = 1
				SET @Sql += ',	COMPRESSION '+CHAR(10)
             
			PRINT @Sql;    
			EXEC (@Sql) 
		END     
		ELSE IF @BackType = 'L'
		BEGIN
			SET @Sql = '';
			SET @Sql += 'BACKUP LOG ['+@BackDb+'] TO '+@DevName+' WITH INIT'
			             
			IF @BufferCount > 0
				SET @Sql += ',	BUFFERCOUNT = '+CONVERT(VARCHAR(10),@BufferCount)+CHAR(10)

			IF @MaxTransferSize > 0
				SET @Sql += ',	MAXTRANSFERSIZE = '+CONVERT(VARCHAR(10),@MaxTransferSize)+CHAR(10)

			IF @IsCompression = 0
				SET @Sql += ', NO_COMPRESSION '+CHAR(10)
			ELSE IF @IsCompression = 1
				SET @Sql += ', COMPRESSION '+CHAR(10)

			PRINT @Sql;    
			EXEC (@Sql)  
		END     
		ELSE IF @BackType = 'D'
		BEGIN
			BACKUP DATABASE @BackDb
			TO @DevName 
				WITH INIT
			,	NAME = @DevName
			,	NOSKIP
			,	NOFORMAT
			,	DIFFERENTIAL
		END
		ELSE IF @BackType = 'M'
		BEGIN
			IF NOT(LEN(@BackPwd) > 0)
			BEGIN
				RAISERROR ('Master key backup... @BackPwd incorrect.',16,1)
				RETURN;			
			END

			SET @Sql = '';
			SET @Sql = @Sql+'BACKUP SERVICE MASTER KEY '+CHAR(10)
			SET @Sql = @Sql+'TO FILE = '''+@Path+''''+CHAR(10)
			SET @Sql = @Sql+'ENCRYPTION BY PASSWORD = '''+@BackPwd+''''

			EXEC (@Sql)        
		END
 
	END TRY
	BEGIN CATCH		
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN;

		PRINT ERROR_NUMBER();
		PRINT ERROR_MESSAGE();
		PRINT ERROR_LINE();
		PRINT ERROR_SEVERITY();

		THROW;
		
	END CATCH
END


