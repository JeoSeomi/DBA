USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_GetSpScripts]    Script Date: 2022-11-17 오전 9:15:35 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*

exec master.dbo.sp_MS_marksystemobject 'sp_GetSpScripts'

*/
ALTER PROC [dbo].[sp_GetSpScripts]
	@Dest NVARCHAR(128) = 'C:\Backup\Script'
	,@IsCombine BIT = 1
AS	
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	SET NOCOUNT ON

	IF NOT(LEN(@Dest) > 0)
	BEGIN
		PRINT '@Dest is invalid'
		RETURN 1
	END
	ELSE
	BEGIN 
		SET @Dest = @Dest + CASE WHEN SUBSTRING(REVERSE(@Dest),1,1) <> '\' THEN '\' ELSE '' END + CONVERT(CHAR(8),GETDATE(),112) + '\' 
	END
	
	DECLARE @CombineFolder NVARCHAR(1000);
	DECLARE @Cmd NVARCHAR(1000)
	DECLARE @DestFile NVARCHAR(100) 
	DECLARE @Seq INT

	BEGIN TRY
		-- xp_cmdshell on		
		EXEC sp_configure 'xp_cmdshell', 1;
		RECONFIGURE WITH OVERRIDE;

		--------------------------------------------------------------------------------
		-- create sp script
		--------------------------------------------------------------------------------
		IF OBJECT_ID('dbo.TMP_SP') IS NOT NULL
			DROP TABLE dbo.TMP_SP

		SELECT IDENTITY(INT,1,1) Seq, [name] Sp, 
			CONCAT(
				'USE ',	DB_NAME(),
				CHAR(10),'GO',CHAR(10),
				CASE OBJECTPROPERTY([object_id],'ExecIsAnsiNullsOn') WHEN 0 THEN 'SET ANSI_NULLS IFF' WHEN 1 THEN 'SET ANSI_NULLS ON' ELSE '' END,
				CHAR(10),'GO',CHAR(10),
				CASE OBJECTPROPERTY([object_id],'ExecIsQuotedIdentOn') WHEN 0 THEN 'SET QUOTED_IDENTIFIER OFF' WHEN 1 THEN 'SET QUOTED_IDENTIFIER ON' ELSE '' END,
				CHAR(10),'GO',CHAR(10),
				'IF OBJECT_ID(''',[name],''') IS NOT NULL',
				CHAR(10),'DROP PROCEDURE ',[name],
				CHAR(10),'GO',CHAR(10),
				OBJECT_DEFINITION([object_id]),
				CHAR(10),'GO'	
			) Stmt
		INTO dbo.TMP_SP
		FROM sys.procedures
		WHERE [type] = 'P' AND [name] NOT IN ('USP_GetSpScript','USP_GetTabScript')
		ORDER BY [name]

		CREATE CLUSTERED INDEX CIX__TMP_SP ON dbo.TMP_SP(Seq)

		--------------------------------------------------------------------------------
		-- create dest directory
		--------------------------------------------------------------------------------
		SET @CombineFolder = @Dest;
		SET @Dest = CONCAT(@Dest,DB_NAME(),'\Sp\')
		SET @Cmd = CONCAT('MKDIR "',@Dest,'"')

		PRINT @Cmd
		EXEC master..xp_cmdshell @Cmd, no_output

		--------------------------------------------------------------------------------
		-- out sp file
		--------------------------------------------------------------------------------
		IF @IsCombine = 1
		BEGIN
			SET @DestFile = CONCAT(DB_NAME(), '_SP_',FORMAT(GETDATE(), 'yyyyMMdd'), '.sql')
			SET @Cmd = CONCAT('BCP "SELECT Stmt FROM dbo.TMP_SP ','" QUERYOUT ')
			SET @Cmd += CONCAT('"',@CombineFolder,@DestFile,'"',' -S "127.0.0.1,1433" -U "sa" -P "engksl0413!@#" -d "',DB_NAME(),'" -c -r "\n" -t "\t"')
			
			--PRINT @Cmd
			
			EXEC master..xp_cmdshell @Cmd, no_output
		END
		ELSE
		BEGIN
			SET @Seq = (SELECT MAX(Seq) FROM dbo.TMP_SP)

			WHILE @Seq > 0
			BEGIN	
				SET @DestFile = (SELECT Sp+'.sql' FROM dbo.TMP_SP WHERE Seq = @Seq)
				SET @Cmd = CONCAT('BCP "SELECT Stmt FROM dbo.TMP_SP WHERE Seq = ',@Seq,'" QUERYOUT ')
				SET @Cmd += CONCAT('"',@Dest,@DestFile,'"',' -S "127.0.0.1,1433" -U "sa" -P "engksl0413!@#" -d "',DB_NAME(),'" -c -r "\n" -t "\t"')

				
				PRINT @Cmd

				EXEC master..xp_cmdshell @Cmd, no_output
	
				SET @Seq -= 1
				WAITFOR DELAY '00:00:00.001'
			END
		END

		-- xp_cmdshell off		
		EXEC sp_configure 'xp_cmdshell', 0;
		RECONFIGURE WITH OVERRIDE;
			
		IF OBJECT_ID('dbo.TMP_SP') IS NOT NULL
			DROP TABLE dbo.TMP_SP
				
	END TRY
	BEGIN CATCH

		SELECT ERROR_MESSAGE() ErrMsg, ERROR_NUMBER() ErrNum, ERROR_LINE() ErrLn

	END CATCH


