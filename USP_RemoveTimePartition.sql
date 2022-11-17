/******************************************************************************************************* 

	1. Procedure    :	USP_RemoveTimePartition
	2. Process Func :	Time 값을 Range로 사용하는 Partition과 데이터를 삭제합니다.
	3. Create Date  :	
	4. Create User  :	
	5. Execute Test : 
						EXEC [dbo].[USP_RemoveTimePartition] @Function='PF_Raw',@Range='1h'

	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------
						
						
*******************************************************************************************************/ 
CREATE PROCEDURE [dbo].[USP_RemoveTimePartition]
	@Function NVARCHAR(128)=NULL
,	@Range VARCHAR(11)
,	@IsUtc BIT = 0
,	@IsDebug BIT=0
WITH EXECUTE AS OWNER
AS
BEGIN
	SET NOCOUNT ON
	SET LOCK_TIMEOUT 3000
	SET XACT_ABORT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	-- 변수 선언
	DECLARE @CurrTime DATETIME = IIF(@IsUtc=1,GETUTCDATE(),GETDATE())
	DECLARE @Sql NVARCHAR(MAX) = ''
	DECLARE @RangeHour INT
	DECLARE @ExpireNo INT
	DECLARE @ExpireTime DATETIME
	
	-- try-catch 시작
	BEGIN TRY 		

		IF @Function IS NULL 
		BEGIN
			PRINT 'partition schema and function name is invalid'
			RETURN
		END

		IF @Range IS NULL
		BEGIN
			PRINT 'time range is invalid'		
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

		DROP TABLE IF EXISTS #CurrRange

		CREATE TABLE #CurrRange (
			[boundary_id] INT
		,	[value] VARCHAR(19)
		,	[dt_value] DATETIME
		)

		----------------------------------------------------------------------------------------------------------------
		-- check partition range values
		----------------------------------------------------------------------------------------------------------------
		BEGIN TRY
			INSERT INTO #CurrRange (boundary_id, [value], [dt_value])
			SELECT boundary_id
			,	[value] = IIF(ISNUMERIC(CONVERT(VARCHAR(128),[value]))=1,CONVERT(VARCHAR(10),[value]),CONVERT(VARCHAR(19),[value],121))
			,	dt_value = IIF(ISNUMERIC(CONVERT(VARCHAR(128),[value]))=1,DATEADD(SECOND,CONVERT(INT,[value]),25567),CONVERT(DATETIME,[value]))
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
		
		----------------------------------------------------------------------------------------------------------------
		-- check expires
		----------------------------------------------------------------------------------------------------------------
		SELECT TOP (1) @ExpireNo = boundary_id, @ExpireTime = dt_value
		FROM #CurrRange
		WHERE [dt_value] <= DATEADD(HOUR,-1*@RangeHour,@CurrTime)
		ORDER BY boundary_id DESC

		IF @@ROWCOUNT = 0
		BEGIN
			PRINT 'partition function ['+@Function+'] : expires not found'
			RETURN
		END
		
		PRINT 'partition function ['+@Function+'] : remove before '+CONVERT(VARCHAR(10),@ExpireNo)+'('+CONVERT(VARCHAR(19),@ExpireTime,121)+')'
		
		----------------------------------------------------------------------------------------------------------------
		-- truncate data
		----------------------------------------------------------------------------------------------------------------
		SELECT @Sql += CONCAT('TRUNCATE TABLE ',QUOTENAME(A.[name]),' WITH (PARTITIONS (1 TO ',@ExpireNo,'));',CHAR(10))
		FROM (
				SELECT DISTINCT A.[name]
				FROM sys.objects A
					INNER JOIN sys.indexes B ON A.[object_id] = B.[object_id]
					INNER JOIN sys.partition_schemes C ON B.data_space_id = C.data_space_id
					INNER JOIN sys.partition_functions D ON C.function_id = D.function_id
				WHERE D.[name] = @Function
			) A

		----------------------------------------------------------------------------------------------------------------
		-- remove partition range
		----------------------------------------------------------------------------------------------------------------
		SELECT @Sql += CONCAT('ALTER PARTITION FUNCTION ',QUOTENAME(@Function),'() MERGE RANGE (''',[value],''');',CHAR(10))
		FROM #CurrRange
		WHERE boundary_id <= @ExpireNo
				
		-- execute.
		PRINT @Sql

		IF @IsDebug = 1
		BEGIN
			RETURN
		END
			
		BEGIN TRY
			EXEC (@Sql)

		END TRY
		BEGIN CATCH

			PRINT 'partition function ['+@Function+'] : remove range failed.'
			RETURN;

		END CATCH

		RETURN 0
		
	END TRY
	BEGIN CATCH		
		IF @@TRANCOUNT > 0
			ROLLBACK TRAN

		THROW
		
	END CATCH
END

