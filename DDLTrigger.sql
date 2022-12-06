USE [DB_ADMIN]
GO

/****** Object:  DdlTrigger [DDLTrigger]    Script Date: 2022-12-05 오후 4:31:20 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO








CREATE TRIGGER [DDLTrigger]
    ON DATABASE
    FOR CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE, DROP_TABLE, ALTER_TABLE, CREATE_TABLE, CREATE_FUNCTION, ALTER_FUNCTION, DROP_FUNCTION
AS
BEGIN
    SET NOCOUNT ON;
	
    DECLARE @EventData XML = EVENTDATA();
	DECLARE @nvcEventType NVARCHAR(128);
	DECLARE @nvcCommandText NVARCHAR(MAX);

	DECLARE @ip VARCHAR(32) = (
        SELECT client_net_address
            FROM sys.dm_exec_connections
            WHERE session_id = @@SPID
    );

	SET @nvcEventType = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'nvarchar(128)');
	SET @nvcCommandText = @EventData.value('(/EVENT_INSTANCE/TSQLCommand)[1]', 'NVARCHAR(MAX)')
	
	BEGIN TRY

		IF OBJECT_ID('AuditDB.dbo.DDLEvents') IS NULL
		BEGIN
			RETURN
		END

		INSERT AuditDB.dbo.DDLEvents
		(
			EventType,
			EventDDL,
			EventXML,
			DatabaseName,
			SchemaName,
			ObjectName,
			HostName,
			IPAddress,
			ProgramName,
			LoginName
		)
		SELECT *
		FROM (
			SELECT EventType = @EventData.value('(/EVENT_INSTANCE/EventType)[1]',   'NVARCHAR(100)'), 
				EventDDL = @EventData.value('(/EVENT_INSTANCE/TSQLCommand)[1]', 'NVARCHAR(MAX)'),
				EventXML = @EventData,
				DatabaseName = DB_NAME(),
				SchemaName = @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]',  'NVARCHAR(255)'), 
				ObjectName = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]',  'NVARCHAR(255)'),
				HostName = HOST_NAME(),
				IPAddress = @ip,
				ProgramName = PROGRAM_NAME(),
				LoginName = SUSER_SNAME()
			) A
		WHERE ObjectName NOT LIKE 'TMP%';

--		IF @nvcEventType IN (N'ALTER_PROCEDURE', N'CREATE_PROCEDURE')
--		BEGIN
--			IF @nvcCommandText NOT LIKE '%WITH EXECUTE AS OWNER%' AND @nvcCommandText NOT LIKE '%WITH EXECUTE AS CALLER%'
--			BEGIN
--				PRINT N'실행 컨텍스트 구문(WITH EXECUTE AS OWNER)이 없습니다
--참고 URL : https://docs.microsoft.com/ko-kr/sql/t-sql/statements/execute-as-clause-transact-sql?view=sql-server-ver15
--예>
--CREATE PROCEDURE DBO.PROCNAME
--	@TEST INT
--WITH EXECUTE AS OWNER
--AS
--.....

--DB팀 문의도 환영합니다.

--'
--				ROLLBACK;
--				RETURN;
--			END			
--		END


	END TRY
	BEGIN CATCH

	END CATCH
END



GO

ENABLE TRIGGER [DDLTrigger] ON DATABASE
GO


