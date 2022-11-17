/******************************************************************************************************* 

	1. Procedure    :	USP_AddTimePartition
	2. Process Func :	Time 값을 Range로 사용하는 Partition을 생성하거나 Range 값을 추가합니다.
	3. Create Date  :	
	4. Create User  :	
	5. Execute Test : 
						EXEC [dbo].[USP_AddTimePartition] @Function='PF_Raw3',@Schema='PS_Raw3',@Count=100,@Range='1h',@IsEpoch=1

						SELECT boundary_id
						,	[value] = IIF(ISNUMERIC(CONVERT(VARCHAR(128),[value]))=1,CONVERT(VARCHAR(10),[value]),CONVERT(VARCHAR(19),[value],121))
						,	dt_value = IIF(ISNUMERIC(CONVERT(VARCHAR(128),[value]))=1,DATEADD(SECOND,CONVERT(INT,[value]),25567),CONVERT(DATETIME,[value]))
						FROM sys.partition_functions A
							INNER JOIN sys.partition_range_values B ON A.function_id = B.function_id
						WHERE A.[name] = 'PF_Daily' 


	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						
*******************************************************************************************************/ 
CREATE PROCEDURE [dbo].[USP_AddTimePartition]
	@Function NVARCHAR(128) = NULL
,	@Schema NVARCHAR(128) = NULL
,	@Count INT
,	@Range VARCHAR(11) --<n><d|h>
,	@IsRight BIT = 1
,	@IsEpoch BIT = 0
,	@IsUtc BIT = 0
,	@IsDebug BIT = 0
WITH EXECUTE AS OWNER
AS
BEGIN
	SET NOCOUNT ON
	SET LOCK_TIMEOUT 3000
	SET XACT_ABORT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	-- DECLARE @Function NVARCHAR(128)='PF_Raw2',@Schema NVARCHAR(128)='PS_Raw2',@Count INT=100,@Range VARCHAR(11)='1h',@IsDebug BIT=1,@IsEpoch BIT=1
	DECLARE @CurrTime DATETIME = IIF(@IsUtc=1,GETUTCDATE(),GETDATE())
	DECLARE @Sql NVARCHAR(MAX) = ''
	DECLARE @RangeHour INT = 0
	DECLARE @RangeCount INT = 0
	DECLARE @LastRangeTime DATETIME
	DECLARE @LastRangeValue VARCHAR(19)
	DECLARE @LoopCount INT = 0
	

	BEGIN TRY 		

		IF @Function IS NULL OR @Schema IS NULL
		BEGIN
			PRINT 'partition schema and function name is invalid'
			RETURN
		END
	
		SELECT 
			@RangeHour = [Value]*
				CASE Unit
					WHEN 'd' THEN 24
					WHEN 'h' THEN 1
				END
		FROM (SELECT SUBSTRING(@Range,1,LEN(@Range)-1), SUBSTRING(@Range,LEN(@Range),1)) A ([Value],Unit)
		WHERE ISNUMERIC([Value]) = 1 AND [Value] > 0 AND Unit IN ('d','h')

		IF @@ROWCOUNT = 0
		BEGIN
			PRINT 'time range is invalid'			
			RETURN
		END
		
		--
		DROP TABLE IF EXISTS #CurrRange

		CREATE TABLE #CurrRange (
			[boundary_id] INT
		,	[value] VARCHAR(19)
		,	[dt_value] DATETIME
		)

		----------------------------------------------------------------------------------------------------------------
		-- init partition
		----------------------------------------------------------------------------------------------------------------	
		IF NOT EXISTS (SELECT 1 FROM sys.partition_functions WHERE [name] = @Function) 
		BEGIN
			SET @LastRangeTime = DATEADD(DAY,DATEDIFF(DAY,0,@CurrTime),0)
			SET @LastRangeValue = IIF(@IsEpoch=1,CONVERT(VARCHAR(10),DATEDIFF(SECOND,25567,@LastRangeTime)),CONVERT(VARCHAR(19),@LastRangeTime,121))
			
			SET @Sql = CONCAT('CREATE PARTITION FUNCTION ',QUOTENAME(@Function),'(',IIF(@IsEpoch=1,'int','datetime'),') AS RANGE ',IIF(@IsRight=1,'RIGHT','LEFT'),' FOR VALUES (''',@LastRangeValue,''');',CHAR(10))
			SET @Sql += CONCAT('CREATE PARTITION SCHEME ',QUOTENAME(@Schema),' AS PARTITION ',QUOTENAME(@Function),' ALL TO  ([FGT1])')
			SET @RangeCount = 1

			PRINT @Sql 

			IF @IsDebug = 1
			BEGIN
				RETURN
			END

			BEGIN TRY
				EXEC (@Sql)

			END TRY
			BEGIN CATCH
				PRINT 'partition create failed!'
				RETURN

			END CATCH

		END 

		----------------------------------------------------------------------------------------------------------------
		-- check partition range values
		----------------------------------------------------------------------------------------------------------------
		BEGIN TRY
			INSERT INTO #CurrRange (boundary_id, [value], [dt_value])
			SELECT boundary_id
			,	[value] = IIF(@IsEpoch=1,CONVERT(VARCHAR(10),[value]),CONVERT(VARCHAR(19),[value],121))
			,	dt_value = IIF(@IsEpoch=1,DATEADD(SECOND,CONVERT(INT,[value]),25567),CONVERT(DATETIME,[value]))
			FROM sys.partition_functions A
				INNER JOIN sys.partition_range_values B ON A.function_id = B.function_id
			WHERE A.[name] = @Function 

			IF @@ROWCOUNT = 0
			BEGIN
				PRINT 'partition function ['+@Function+'] : invalid range values'
				RETURN
			END

		END TRY
		BEGIN CATCH
			PRINT 'partition function ['+@Function+'] : range values are invalid DateTime'
			RETURN

		END CATCH
		
		SELECT TOP (1) @LastRangeValue = [value], @LastRangeTime = [dt_value], @RangeCount = boundary_id
		FROM #CurrRange
		ORDER BY boundary_id DESC
		
		----------------------------------------------------------------------------------------------------------------
		-- create new range
		----------------------------------------------------------------------------------------------------------------
		SET @LoopCount = @Count-@RangeCount
		SET @Sql = ''

		PRINT CONCAT('--add ',@LoopCount,', after ',@LastRangeValue)
		
		IF @LoopCount <= 0
		BEGIN
			PRINT CONCAT('partition function ['+@Function+'] : range count is full on ',@RangeCount)
			RETURN;
		END

		WHILE (@LoopCount>0)
		BEGIN
			SET @LastRangeTime = DATEADD(HOUR,@RangeHour,@LastRangeTime)
			SET @LastRangeValue = IIF(@IsEpoch=1,CONVERT(VARCHAR(10),DATEDIFF(SECOND,25567,@LastRangeTime)),CONVERT(VARCHAR(19),@LastRangeTime,121))

			SET @LoopCount -= 1
			SET @Sql = 
				CONCAT(
					'ALTER PARTITION FUNCTION ',QUOTENAME(@Function),'() SPLIT RANGE (''',@LastRangeValue,''');',CHAR(10),
					'ALTER PARTITION SCHEME ',QUOTENAME(@Schema),' NEXT USED [FGT1];',CHAR(10)
				)

			-- execute.
			PRINT @Sql
			
			IF @IsDebug = 1
			BEGIN
				CONTINUE;
			END

			BEGIN TRY
				EXEC (@Sql)
			END TRY
			BEGIN CATCH

				PRINT 'partition function ['+@Function+'] : add range values failed '
				RETURN;

			END CATCH
		END


		RETURN 0
		
	END TRY
	BEGIN CATCH		
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN

		THROW
		
	END CATCH
END


