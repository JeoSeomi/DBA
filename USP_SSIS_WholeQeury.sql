USE [master]
GO
/****** Object:  StoredProcedure [dbo].[USP_SSIS_WholeQeury]    Script Date: 2022-11-17 오전 10:23:25 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



--EXEC [USP_WholeQeury] 'SELECT GETDATe() TT',2
ALTER proc [dbo].[USP_SSIS_WholeQeury]
							@WorldID INT,
							@Srvname NVARCHAR(50),
							@Query NVARCHAR(MAX),
							@Type INT=0
as

SET QUOTED_IDENTIFIER OFF

DECLARE @SQL NVARCHAR(MAX)

BEGIN

	IF @Type = 0
	BEGIN
		SET @SQL = '
		SELECT ' +CONVERT(NVARCHAR(10),@WorldID)+ ' WorldID,* FROM OpenQuery(['+@Srvname+'], 
				''	
						'+@Query+'
				'')'
	END
	ELSE
	BEGIN
		SET @SQL = '
		SELECT * FROM OpenQuery(['+@Srvname+'], 
				''	
						'+@Query+'
				'')'
	END
END

print @sql
EXEC(@SQL)
