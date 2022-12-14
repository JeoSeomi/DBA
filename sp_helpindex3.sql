USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_helpindex3]    Script Date: 2022-11-17 오전 9:16:57 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[sp_helpindex3]
	@tblName sysname
AS

SET NOCOUNT ON

IF OBJECT_ID ('tempdb.dbo.#IndexInfo', 'U') IS NOT NULL
	DROP TABLE #IndexInfo 

CREATE TABLE #IndexInfo (
	index_name VARCHAR(256),
	index_description VARCHAR(max),
	index_keys VARCHAR(max),
	included_columns VARCHAR(max),
	filter_definition VARCHAR(max)
)

INSERT INTO #IndexInfo EXEC sp_helpindex2 @tblName

SELECT	
		@tblName AS [TableName],
		i.index_id AS [IndexID],  
		x.index_name AS [IndexName],
		x.index_keys + CASE WHEN x.included_columns IS NULL THEN '' ELSE ' [' + x.included_columns + ']' END
		             + CASE WHEN x.filter_definition IS NULL THEN '' ELSE ' || ' + x.filter_definition END AS [IndexKey[Included]]||Filtered],
		ISNULL(user_seeks, 0) AS [Seek], 
		ISNULL(user_scans, 0) AS [Scan],
		ISNULL(user_lookups, 0) AS [Lookup],
		ISNULL(user_updates, 0) AS [Update],
		x.index_description AS [Desc]
	FROM sys.indexes AS i
	LEFT JOIN sys.dm_db_index_usage_stats AS s
		ON i.object_id = s.object_id AND i.index_id = s.index_id
  		AND s.database_id = DB_ID()
	LEFT JOIN #IndexInfo AS x ON i.name = x.index_name COLLATE Korean_Wansung_CI_AS
    WHERE 1 = 1
		AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 
		AND OBJECT_NAME(i.object_id) = PARSENAME(@tblName, 1)
--		 AND (ISNULL(user_seeks, 0) + ISNULL(user_scans, 0) + ISNULL(user_lookups, 0)) = 0
    ORDER BY 1
