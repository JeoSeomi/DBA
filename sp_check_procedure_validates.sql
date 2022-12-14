USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_check_procedure_validates]    Script Date: 2022-11-17 오전 9:20:37 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/******************************************************************************************************* 

	1. Procedure    :	sp_check_procedure_validates
	2. Process Func :	프로시저 내 트랜잭션 명령어 오류를 검사합니다.

						[Error] = 
							1: 트랜잭션 바깥에서 ROLLBACK or COMMIT 발견(CATCH문은 예외함)
							2: 트랜잭션 내 ROLLBACK or COMMIT 없는 RETURN 발견

	3. Create Date  :	
	4. Create User  :	
	5. Execute Test : 
						EXEC [dbo].[sp_check_procedure_validates] @Procedures='spBuyGachaItem_test'
						EXEC [dbo].[sp_check_procedure_validates] @Procedures=null
	6. History Info :	
						Date		Author				Description
						-----------	-------------------	-------------------------------------------

						
*******************************************************************************************************/ 
ALTER PROCEDURE [dbo].[sp_check_procedure_validates]
	@Debug bit = 0
,	@Procedures nvarchar(2000) = null
AS
BEGIN
	SET NOCOUNT ON
	SET LOCK_TIMEOUT 3000
	SET XACT_ABORT ON
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	-- 변수 선언
	DECLARE @No	int = 1
	DECLARE @Max int = 0
	DECLARE @Name nvarchar(128)
	DECLARE @Sql nvarchar(max)
	DECLARE @Result nvarchar(max)
	
	-- try-catch 시작
	BEGIN TRY
		-----------------------------------------------------------------------------------------------------------
		-- 정규식 함수 확인
		-----------------------------------------------------------------------------------------------------------
		IF OBJECT_ID('master.dbo.fnRegexContain') IS NULL
		BEGIN
			PRINT 'function "master.dbo.fnRegexContain" is not exist!'
			RETURN
		END

		IF OBJECT_ID('master.dbo.fxRegexMatches') IS NULL
		BEGIN
			PRINT 'function "master.dbo.fxRegexMatches" is not exist!'
			RETURN
		END

		-----------------------------------------------------------------------------------------------------------
		-- 검사 대상 프로시저
		-----------------------------------------------------------------------------------------------------------
		DROP TABLE IF EXISTS #Procs
		
		SELECT [No] = IDENTITY(INT,1,1), [Name] = [name], [Definition] = [definition], [Result] = CONVERT(nvarchar(10),N'정상'), [Results] = CONVERT(nvarchar(max),NULL)
		INTO #Procs
		FROM sys.procedures A
			INNER JOIN sys.sql_modules B ON A.[object_id] = B.[object_id]
		WHERE (@Procedures IS NULL) OR [name] IN (SELECT RTRIM(LTRIM([value])) FROM STRING_SPLIT(@Procedures,','))
		ORDER BY [name]
				
		CREATE UNIQUE CLUSTERED INDEX CIX__Procs ON #Procs ([No])

		SELECT TOP (1) @Max = [No], @No = 1
		FROM #Procs
		ORDER BY [No] DESC

		PRINT CONCAT(@Max,' procedures')

		-----------------------------------------------------------------------------------------------------------
		-- 검사 ㄱㄱ
		-----------------------------------------------------------------------------------------------------------
		WHILE @No <= @Max
		BEGIN
			SELECT @Name = [Name]
			,	@Sql = [Definition]
			FROM #Procs
			WHERE [No] = @No

			-----------------------------------------------------------------------------------------------------------
			-- 주요 커맨드 추출
			-----------------------------------------------------------------------------------------------------------
			DROP TABLE IF EXISTS #Commands

			SELECT [Offset] = [Position], [Command] = [Match], [PrevReturnCommand] = IIF([Match]LIKE'RETURN',LAG([Match]) OVER(ORDER BY [Position]),NULL)
			INTO #Commands
			FROM master.dbo.fxRegexMatches(@Sql,'(\bBEGIN\b\s+TRAN)|(\bCOMMIT\b(\s+TRAN)?)|(\bROLLBACK\b\s+TRAN)|(\bRETURN\b)|((\bBEGIN\b|\bEND\b)\s+\bTRY\b)|((\bBEGIN\b|\bEND\b)\s+\bCATCH\b)|(^\bBEGIN\b$)') A
				LEFT JOIN (
					SELECT [StartOffset] = [Position], [EndOffset] = [Position]+LEN([Match]), [Statement] = [Match]	
					FROM master.dbo.fxRegexMatches(@Sql,'((\/\*)([\s\S]*?)(\*\/))|(--)(.*)')
				) B ON A.[Position] >= B.StartOffset AND A.[Position] < B.EndOffset
			WHERE B.StartOffset IS NULL -- 주석(--,/**/) 예외

			CREATE CLUSTERED INDEX CIX__Commands ON #Commands([Offset])
			
			-----------------------------------------------------------------------------------------------------------
			-- 트랜잭션 시작/끝 위치 추출
			-----------------------------------------------------------------------------------------------------------
			DROP TABLE IF EXISTS #Transactions

			SELECT [No] = IDENTITY(INT,1,1), [StartOffset] = A.[Offset], [EndOffset] = B.[Offset]
			INTO #Transactions
			FROM (
					SELECT *
					FROM #Commands A
					WHERE master.dbo.fnRegexContain([Command],'(\bBEGIN\b\s+TRAN)') = 1
				) A
				CROSS APPLY (
					SELECT TOP (1) [Offset]
					FROM #Commands B
					WHERE master.dbo.fnRegexContain([Command],'(\bCOMMIT\b(\s+TRAN)?)') = 1
						AND B.[Offset] > A.[Offset]
					ORDER BY [Offset]
				) B

			
			-----------------------------------------------------------------------------------------------------------
			-- TRY 시작/끝 위치 추출
			-----------------------------------------------------------------------------------------------------------
			DROP TABLE IF EXISTS #Tryes

			SELECT [No] = IDENTITY(INT,1,1), [StartOffset] = A.[Offset], [EndOffset] = B.[Offset]
			INTO #Tryes
			FROM (
					SELECT *
					FROM #Commands A
					WHERE master.dbo.fnRegexContain([Command],'(\bBEGIN\b\s+\bTRY\b)') = 1
				) A
				CROSS APPLY (
					SELECT TOP (1) [Offset]
					FROM #Commands B
					WHERE master.dbo.fnRegexContain([Command],'(\bEND\b\s+\bTRY\b)') = 1
						AND B.[Offset] > A.[Offset]
					ORDER BY [Offset]
				) B

			
			-----------------------------------------------------------------------------------------------------------
			-- CATCH 시작/끝 위치 추출
			-----------------------------------------------------------------------------------------------------------
			DROP TABLE IF EXISTS #Catches

			SELECT [No] = IDENTITY(INT,1,1), [StartOffset] = A.[Offset], [EndOffset] = B.[Offset]
			INTO #Catches
			FROM (
					SELECT *
					FROM #Commands A
					WHERE master.dbo.fnRegexContain([Command],'(\bBEGIN\b\s+\bCATCH\b)') = 1
				) A
				CROSS APPLY (
					SELECT TOP (1) [Offset]
					FROM #Commands B
					WHERE master.dbo.fnRegexContain([Command],'(\bEND\b\s+\bCATCH\b)') = 1
						AND B.[Offset] > A.[Offset]
					ORDER BY [Offset]
				) B

			DROP TABLE IF EXISTS #Results

			;WITH [Check] AS (
				SELECT [Offset]
				,	[Command]
				,	[Error] = 
						/*	1: 트랜잭션 바깥에서 ROLLBACK or COMMIT 발견(CATCH문은 예외함)
							2: 트랜잭션 내 ROLLBACK or COMMIT 없는 RETURN 발견	*/
						CASE
							WHEN [IsTran] = 0 AND [IsCatch] = 0 AND master.dbo.fnRegexContain([Command],'(\bROLLBACK\b)|(\bCOMMIT\b)') = 1 THEN 1	
							WHEN [IsTran] = 1 AND [Command] = 'RETURN' AND master.dbo.fnRegexContain([PrevReturnCommand],'(\bROLLBACK\b)|(\bCOMMIT\b)') = 0 THEN 2	
							ELSE 0
						END
				FROM (
						SELECT [Offset]
						,	[Command]
						,	[PrevReturnCommand]
						,	[IsTran] = IIF(B.[StartOffset] IS NOT NULL,1,0)
						,	[IsTry] = IIF(C.[StartOffset] IS NOT NULL,1,0)
						,	[IsCatch] = IIF(D.[StartOffset] IS NOT NULL,1,0)
						FROM #Commands A
							LEFT JOIN #Transactions B ON A.Offset >= B.StartOffset AND A.Offset <= B.EndOffset
							LEFT JOIN #Tryes C ON A.Offset >= C.StartOffset AND A.Offset <= C.EndOffset
							LEFT JOIN #Catches D ON A.Offset >= D.StartOffset AND A.Offset <= D.EndOffset
					) A
			)
			SELECT [Offset], [Command], [Error], [OffsetStatement] = SUBSTRING(@Sql,[Offset]-50,100) 
			INTO #Results
			FROM [Check]
			WHERE [Error] > 0
			
			IF @@ROWCOUNT > 0
			BEGIN
				UPDATE #Procs
				SET	[Result] = N'이상'
				,	[Results] = (SELECT * FROM #Results FOR JSON AUTO)
				WHERE [No] = @No
			END

			SET	@No += 1
		END

		SELECT [No], [Name], [Definition] = IIF(Results IS NOT NULL,[Definition],''), [Result]
		FROM #Procs
		ORDER BY [No]

		
		SELECT [No], [Name], [Offset], [Command], [OffsetStatement]
		,	[Error] = 
				CASE [Error]
					WHEN 1 THEN N'트랜잭션 범위 밖에서 ROLLBACK/COMMIT이 선언되었습니다.'
					WHEN 2 THEN N'트랜잭션 범위 내에서 ROLLBACK/COMMIT 전에 RETURN이 선언되었습니다.'
				END
		FROM #Procs A
			CROSS APPLY OPENJSON([Results]) WITH (
				[Offset] int
			,	[Command] nvarchar(100)
			,	[OffsetStatement] nvarchar(1000)
			,	[Error] int
			) B
		ORDER BY [No]

		RETURN 0
		
	END TRY
	BEGIN CATCH		
		THROW;
		
	END CATCH
END
