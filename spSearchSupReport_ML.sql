USE [Report_new]
GO
/****** Object:  StoredProcedure [dbo].[spSearchSupReport_ML]    Script Date: 2021/1/25 11:36:55 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*


SET STATISTICS IO on
SET STATISTICS TIME ON

--SupFlag正序
exec spSearchSupReport_ML '1','Derby','ML','C','Y','2020-02-01 23:59:59','2119','',100,1,'Total',0,0,0

--SupFlag倒序
exec spSearchSupReport_ML '1','Derby','ML','C','Y','2020-02-01 23:59:59','2119','',100,2,'Total',0,0,0

--SupplierId
exec spSearchSupReport_ML '0','SN000009','ML','C','Y','2020-02-01 23:59:59','2119','',100,1,'Total',1,0,0


SET STATISTICS IO on
SET STATISTICS TIME ON
--无SupplierID
exec spSearchSupReport_ML 0,'SE000366','ML','O','M','2021-01-01 23:59:59','1890','',100,1,'Total',1,0,0

SET STATISTICS IO OFF
SET STATISTICS TIME OFF



*/
ALTER PROCEDURE [dbo].[spSearchSupReport_ML]
(
	@IsSupFlag			bit=0				
	,@SupplierId		NVARCHAR(16)=NULL   --@IsSupFlag=0时，这参数传SupplierId , @IsSupFlag=1时， 这参数传集团SupFlag
	,@DataType			NVARCHAR(5)				--数据类型		ML,JYS
	,@TimeType			NVARCHAR(5)				--时间类型		C,O  --C预定时间, O 离店时间
	,@TimeLat			NVARCHAR(5)				--时间维度		Y,M,D
	,@Time				DATETIME				--时间
	,@UserName			NVARCHAR(10)			--登录人ID
	,@SupGroup          NVARCHAR(10)			--供应商分组查询
	--分页
	,@PageSize			INT	= 20				--每页显示数据行
	,@PageIndex			INT = 1					--当前页码
	,@SortField			NVARCHAR(50)			= N''					--排序字段 Total 或 1~31
	,@SortType			BIT                     --                      --0 为正序， 1为倒序
	,@TotalRecord		BIGINT=0				--记录总数,不传则重新统计记录总数
	,@RecordCount		INT					OUTPUT
)
AS
BEGIN
		SET NOCOUNT ON;
		DECLARE @StartDate DATETIME
		DECLARE @EndDate DATETIME
		--使用：>=@StartDate AND <@EndDate
		IF(@TimeLat='Y')
		BEGIN
			--按年
			SET @StartDate=dateadd(year, datediff(year, 0, @Time), 0)  --当年第一天

			SET @EndDate=dateadd(year, datediff(year, 0, dateadd(year, 1, @Time) ), 0)  --下一年第一天
		END
		ELSE IF (@TimeLat='M')
		BEGIN
			--按月
			SET @StartDate=dateadd(month, datediff(month, 0, @Time), 0)  --当月第一天
			SET @EndDate=dateadd(month, datediff(month, 0, dateadd(month, 1, @Time )), 0)  --下月第一天
		END 
		ELSE
		BEGIN
			--按日
			SET @StartDate=dateadd(day, datediff(day, 0, @Time), 0)  --当天0点
			SET @EndDate=dateadd(day, datediff(day, 0, dateadd(day, 1, @Time )), 0)  --第二天0点
		END 

IF(@IsSupFlag IS NULL OR @IsSupFlag='')
BEGIN
  SET @IsSupFlag=0; --默认值
END 

	DECLARE @SortTypeStr NVARCHAR(10)
	SET @SortTypeStr=' ASC'
   IF(@SortType=1)
   BEGIN
     SET  @SortTypeStr=' DESC'
   END 
   ELSE
   BEGIN
   SET @SortTypeStr=' ASC'
   END 

CREATE TABLE  #TbSupGroupAuth   --用户权限
(
	Authority NVARCHAR(10)  INDEX idx_Authority
)
IF(@SupGroup IS NULL OR @SupGroup='')
BEGIN
	INSERT INTO #TbSupGroupAuth
	(
		Authority
	)
	SELECT Authority FROM CBS.[dbo].[SupGroupAuth] WITH(NOLOCK) WHERE UserName=@UserName
END 
ELSE
BEGIN
	INSERT INTO #TbSupGroupAuth
	(
		Authority
	)
	SELECT Authority FROM CBS.[dbo].[SupGroupAuth] WITH(NOLOCK) WHERE UserName=@UserName
	AND Authority=@SupGroup
END


--按供应商分页
CREATE TABLE #TbSupNo
(
	Id INT IDENTITY(1,1),
	SupplierNo NVARCHAR(16)  INDEX idx_SupNo,
	Profit NUMERIC(18,4)
	PRIMARY KEY CLUSTERED(Id)
)

DECLARE @StartRecord INT 
IF(@PageIndex=1)
BEGIN
	SET @StartRecord=0
END
ELSE
BEGIN
	SET @StartRecord=(@PageIndex-1)*@PageSize
END



DECLARE @TimeCondition NVARCHAR(50)  --时间条件
DECLARE @Field   NVARCHAR(100)
IF(@TimeType IS NULL OR  @TimeType='' OR @TimeType='C')
BEGIN
  --按预定时间统计
  SET @TimeCondition=' CreateTime<@EndDate AND CreateTime>=@StartDate '
  SET @Field='TimeOfMonth,TimeOfDay,TimeOfHour'
END 
ELSE
BEGIN
     --按离店时间统计
	SET @TimeCondition=' CheckOut<@EndDate AND CheckOut>=@StartDate '
	SET @Field='CheckOutOfMonth as TimeOfMonth,CheckOutOfDay as TimeOfDay,TimeOfHour'
END

DECLARE @GetSupNoSqlStr NVARCHAR(3000)
DECLARE @GetRecordCountSqlStr NVARCHAR(3000)

SET @GetSupNoSqlStr=N'
;WITH sourceData AS 
(
	SELECT ROW_NUMBER() OVER(ORDER BY ASource.ML) AS n,ASource.SupplierId,ASource.ML
	FROM 
	(
		SELECT SupplierId,SUM(Profit) AS ML 
		FROM ReportOrderInfo ROI WITH(NOLOCK)
		WHERE '+@TimeCondition+' 
		AND EXISTS
		(
			SELECT 1 FROM #TbSupGroupAuth
			WHERE Authority=ROI.SupplierGroup
		) '

IF(@SupplierId IS NOT NULL AND @SupplierId<>'')
BEGIN

	IF(@IsSupFlag=0)
	BEGIN
		--传入的是SupplierId  不需要分页
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' AND ROI.SupplierId=@SupplierId '

	END
	ELSE    
	BEGIN
		--传入的是SupFlag 需要分页
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' 
			AND EXISTS        
			(
				SELECT 1 FROM CPSHSDB.CPS_HS.dbo.SupHotelInfo supH WITH(NOLOCK) 
				WHERE 
					ROI.SupplierId=supH.SupMenberNo
				AND supH.SupFlag=@SupplierId
			) '
	END

--统计总记录数
SET @GetRecordCountSqlStr=@GetSupNoSqlStr+' GROUP BY SupplierId  ) AS ASource
)  SELECT @TotalRecord=COUNT(*)  FROM sourceData '

SET @GetSupNoSqlStr=@GetSupNoSqlStr+'GROUP BY SupplierId  
	) AS ASource
)
INSERT INTO #TbSupNo(SupplierNo,Profit)
SELECT SupplierId,ML  FROM sourceData '

	IF(@SortField IS NULL OR @SortField='')
	BEGIN
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' ORDER BY n OFFSET @StartRecord ROW FETCH NEXT @PageSize ROWS ONLY '
		PRINT @GetSupNoSqlStr
		EXEC sp_executesql @GetSupNoSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@SupplierId NVARCHAR(16),@StartRecord INT,@PageSize INT',@EndDate,@StartDate,@SupplierId,@StartRecord,@PageSize
	END
	ELSE
	BEGIN
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' ORDER BY ['+@DataType+'] '+@SortTypeStr+' OFFSET @StartRecord ROW FETCH NEXT @PageSize ROWS ONLY '
		--PRINT @GetSupNoSqlStr
		EXEC sp_executesql @GetSupNoSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@SupplierId NVARCHAR(16),@StartRecord INT,@PageSize INT',@EndDate,@StartDate,@SupplierId,@StartRecord,@PageSize
	END

	
IF(@TotalRecord=0)
BEGIN
--统计总记录数
  SELECT @TotalRecord=COUNT(*) FROM  #TbSupNo
  EXEC sp_executesql @GetRecordCountSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@SupplierId NVARCHAR(16),@TotalRecord BIGINT OUT',@EndDate,@StartDate,@SupplierId,@TotalRecord OUT 
END

END
ELSE
BEGIN
--需要分页
SET @GetRecordCountSqlStr=@GetSupNoSqlStr+' GROUP BY SupplierId  ) AS ASource
)  SELECT @TotalRecord=COUNT(*)  FROM sourceData '

SET @GetSupNoSqlStr=@GetSupNoSqlStr+' GROUP BY SupplierId  ) AS ASource
)
INSERT INTO #TbSupNo(SupplierNo,Profit)
SELECT SupplierId,ML  FROM sourceData '
	IF(@SortField IS NULL OR @SortField='')
	BEGIN
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' ORDER BY n OFFSET @StartRecord ROW FETCH NEXT @PageSize ROWS ONLY '
		EXEC sp_executesql @GetSupNoSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@StartRecord INT,@PageSize INT',@EndDate,@StartDate,@StartRecord,@PageSize
	END
	ELSE
	BEGIN
		SET @GetSupNoSqlStr=@GetSupNoSqlStr+' ORDER BY ['+@DataType+'] '+@SortTypeStr+' OFFSET @StartRecord ROW FETCH NEXT @PageSize ROWS ONLY '
		EXEC sp_executesql @GetSupNoSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@StartRecord INT,@PageSize INT',@EndDate,@StartDate,@StartRecord,@PageSize
	END

IF(@TotalRecord=0)
BEGIN
  SELECT @TotalRecord=COUNT(*) FROM  #TbSupNo
  EXEC sp_executesql @GetRecordCountSqlStr,N'@EndDate DATETIME,@StartDate DATETIME,@TotalRecord BIGINT OUT',@EndDate,@StartDate,@TotalRecord OUT 
END

END
------------------------------------
--PRINT '总记录数'
--PRINT @TotalRecord
SELECT @RecordCount=@TotalRecord

--先按供应商分页,再统计
--SELECT * FROM #TbSupNo

DECLARE @ReportSqlStr NVARCHAR(max)

SET @ReportSqlStr=';WITH orderMainData
	AS 
	(
		SELECT MainOrderId,PurchaseOrderId,
		SupplierId,SupplierName,SupplierGroup
		,BaseAmountCNY AS BasePriceAfter,SurchargeBaseAmountCNY AS AppenBasePriceAfter
		,SellAmountCNY AS SellPriceAfter,SurchargeSellAmountCNY AS AppenSellPriceAfter,'+@Field+'
		FROM ReportOrderInfo WITH(NOLOCK) 
		WHERE '+@TimeCondition+' 
		AND EXISTS  (SELECT 1 FROM #TbSupNo WHERE SupplierNo=ReportOrderInfo.SupplierId)
	) '
IF(@TimeLat='Y')
BEGIN
SET @ReportSqlStr=@ReportSqlStr+'
	SELECT * FROM 
	(
		SELECT SupplierId,T.SupplierName, SupplierGroup,
		[1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12],
		(
		 isnull([1],0.00)+isnull([2],0.00)+isnull([3],0.00)+isnull([4],0.00)+isnull([5],0.00)+isnull([6],0.00)+isnull([7],0.00)+isnull([8],0.00)+isnull([9],0.00)+isnull([10],0.00)+isnull([11],0.00)+isnull([12],0.00)
		) AS Total
		FROM 
		(
			---------BEGIN
		 SELECT 
				sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfMonth,
				(
					SUM(sourceData.SellPriceAfter)+ SUM(ISNULL(sourceData.AppenSellPriceAfter,0.00)) -SUM(sourceData.BasePriceAfter)-SUM(ISNULL(sourceData.AppenBasePriceAfter,0.00))
				) AS ML
				FROM orderMainData AS sourceData
				GROUP BY sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfMonth

			---------END
		) AS YearDataSource
		PIVOT(Sum(ML) FOR TimeOfMonth IN([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])) AS T 
	) AS SourceData '
END
ELSE IF(@TimeLat='M')
BEGIN
	SET @ReportSqlStr=@ReportSqlStr+'
		SELECT * FROM 
		(
			SELECT SupplierId,T.SupplierName,T.SupplierGroup, 
			[1],[2],[3],[4],[5],[6],[7],[8],[9],[10]
			,[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21]
			,[22],[23],[24],[25],[26],[27],[28],[29],[30],[31]
			,
			(
			isnull([1],0.00)+isnull([2],0.00)+isnull([3],0.00)+isnull([4],0.00)+isnull([5],0.00)+isnull([6],0.00)+isnull([7],0.00)+isnull([8],0.00)+isnull([9],0.00)+isnull([10],0.00)
			+ISNULL([11],0.00)+isnull([12],0.00)+isnull([13],0.00)+isnull([14],0.00)+isnull([15],0.00)+isnull([16],0.00)+isnull([17],0.00)+isnull([18],0.00)+isnull([19],0.00)+isnull([20],0.00)+isnull([21],0.00)
			+ISNULL([22],0.00)+isnull([23],0.00)+isnull([24],0.00)+isnull([25],0.00)+isnull([26],0.00)+isnull([27],0.00)+isnull([28],0.00)+isnull([29],0.00)+isnull([30],0.00)+isnull([31],0.00)
			) AS Total
			FROM 
			(
				---------BEGIN
			 SELECT 
						sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfDay,
						(
							SUM(sourceData.SellPriceAfter)+ SUM(ISNULL(sourceData.AppenSellPriceAfter,0.00)) -SUM(sourceData.BasePriceAfter)-SUM(ISNULL(sourceData.AppenBasePriceAfter,0.00))
						) AS ML
						FROM orderMainData AS sourceData
						GROUP BY sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfDay

				---------END
			) AS YearDataSource
			PIVOT(Sum(ML) FOR TimeOfDay IN([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30],[31])) AS T 
		) AS SourceData '
END
ELSE IF(@TimeLat='D')
BEGIN
IF(@TimeType='O')
BEGIN
	SELECT @RecordCount=0; 
	SET @ReportSqlStr=@ReportSqlStr+'SELECT top 0 * FROM '
END
ELSE
BEGIN
	SET @ReportSqlStr=@ReportSqlStr+'SELECT * FROM '
END
SET @ReportSqlStr=@ReportSqlStr+'
	(
		SELECT SupplierId,T.SupplierName,T.SupplierGroup, 
			[0],[1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11]
			,[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23],
			(
			isnull([0],0.00)+isnull([1],0.00)+isnull([2],0.00)+isnull([3],0.00)+isnull([4],0.00)+isnull([5],0.00)+isnull([6],0.00)+isnull([7],0.00)+isnull([8],0.00)+isnull([9],0.00)+isnull([10],0.00)+isnull([11],0.00)
			+ISNULL([12],0.00)+isnull([13],0.00)+isnull([14],0.00)+isnull([15],0.00)+isnull([16],0.00)+isnull([17],0.00)+isnull([18],0.00)+isnull([19],0.00)+isnull([20],0.00)+isnull([21],0.00)+isnull([22],0.00)+isnull([23],0.00)
			) AS Total
			FROM 
			(
				---------BEGIN
			 SELECT 
						sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfHour,
						(
							SUM(sourceData.SellPriceAfter)+ SUM(ISNULL(sourceData.AppenSellPriceAfter,0.00)) -SUM(sourceData.BasePriceAfter)-SUM(ISNULL(sourceData.AppenBasePriceAfter,0.00))
						) AS ML
						FROM orderMainData AS sourceData
						GROUP BY sourceData.SupplierId,sourceData.SupplierName,sourceData.SupplierGroup,sourceData.TimeOfHour
				---------END
			) AS YearDataSource
			PIVOT(Sum(ML) FOR TimeOfHour IN([0],[1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12],[13],[14],[15],[16],[17],[18],[19],[20],[21],[22],[23])) AS T 
	) AS SourceData '
END
IF(@SortField IS NULL OR @SortField ='')
BEGIN
	SET @ReportSqlStr=@ReportSqlStr+' ORDER BY [Total] '
END
ELSE
BEGIN
	SET @ReportSqlStr=@ReportSqlStr+' ORDER BY ['+@SortField+'] '+@SortTypeStr
END

--PRINT @ReportSqlStr
EXEC sp_executesql @ReportSqlStr,N'@EndDate DATETIME,@StartDate DATETIME',@EndDate,@StartDate

END 
