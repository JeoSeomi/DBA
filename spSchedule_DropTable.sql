/******************************************************************************************************* 

	1. Procedure    :	spSchedule_DropTable
	2. Process Func :	
	3. Create Date  :	
	4. Create User  :	
	5. Execute Test : 						
						EXEC [spSchedule_DropTable]  @vchPrefix = 'HST', @IsDebug = 1, @IntRetentionPeriod = 30
						
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						

*******************************************************************************************************/ 
CREATE PROCEDURE [dbo].[spSchedule_DropTable]		
	@vchPrefix varchar(32)	= ''										-- 삭제할 테이블 프리픽스
,	@IntRetentionPeriod INT = 32
,	@IsDebug BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	
	BEGIN TRY 	
		
		DECLARE @nvcQuerySTR NVARCHAR(1000) = '';		

		DECLARE @nvcTableName NVARCHAR(260);
		DECLARE ColumnCursor CURSOR LOCAL FAST_FORWARD FOR
		
			SELECT [name]
			FROM sys.tables
			WHERE [name] LIKE CONCAT('%', @vchPrefix, '%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]')
				AND create_date <= DATEADD(DAY, @IntRetentionPeriod * (-1), GETDATE())
					
			FOR READ ONLY;
		OPEN ColumnCursor;
		FETCH NEXT FROM ColumnCursor INTO @nvcTableName;
		
		WHILE @@FETCH_STATUS = 0
		BEGIN
		  
			SET @nvcQuerySTR = CONCAT('DROP TABLE [GameWorkDB].DBO.[', @nvcTableName + '];')
			IF @IsDebug = 0
				EXEC (@nvcQuerySTR);
			ELSE
				PRINT @nvcQuerySTR;

			WAITFOR DELAY '00:00:00.002';
									  
		  FETCH NEXT FROM ColumnCursor INTO @nvcTableName;
		END
		
		CLOSE ColumnCursor;
		DEALLOCATE ColumnCursor;


		--일부 뷰 갱신
		EXEC [GameWorkDB].[dbo].[USP_MergeToView] @ViewName='ArenaWeek_HST', @TableName='ArenaWeek_HST', @TablePattern = 'ArenaWeek_HST[0-9]%';
		
	END TRY
	BEGIN CATCH		

		IF @@TRANCOUNT > 0
			ROLLBACK TRAN			
			
		;THROW;
		
	END CATCH
END



