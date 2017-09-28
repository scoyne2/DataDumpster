declare @DatabaseName		varchar(max) =‘TEST_DB’
, @Table_Set		varchar(max) ='outpatientCharges'



-------------------------------------------------------------------------------------------work variables
DECLARE 
  @ExecString		varchar(max)
, @MetaString		varchar(max)
, @OkGo				bit = 1
, @i				int
, @f				int

-------------------------------------------------------------------------------------------procedure specific variables
DECLARE @Table_staging			varchar(max)	= @DatabaseName+'.staging.'+@Table_set
DECLARE @Table_error			varchar(max)	= @DatabaseName+'.error.'+@Table_set
DECLARE @WHEREclause			varchar(max)
DECLARE @DataElement			varchar(max)
DECLARE @DataElementMaxLength	varchar(max)
DECLARE @DataElementDataType    varchar(max)


------------------------------------------------------------------------------------------------------ DATA LENGTH ISSUE
-- make a list of all tables, data elemetns, and max length from DataSniffer 
-- loop through to find where the length is too long 
BEGIN TRY 
	DROP TABLE #DataSniffer_Info
END TRY
BEGIN CATCH 
END CATCH

CREATE TABLE #DataSniffer_Info ( 
  RecordKey					bigint IDENTITY(1,1) NOT NULL
, DataElement				varchar(max)
, DataElementMaxLength		int 
, DataElementDataType		varchar(max)
) 

-- insert columns into temp table 
SET @ExecString = '
SELECT 
  COLUMN_NAME
, COALESCE(CHARACTER_MAXIMUM_LENGTH, ''-1'')
, DATA_TYPE
FROM '+@DatabaseName+'.INFORMATION_SCHEMA.COLUMNS				
WHERE 1=1
AND TABLE_SCHEMA = ''base''
AND TABLE_NAME = '''+@Table_set+'''

'
INSERT INTO #DataSniffer_Info(  
  DataElement 
, DataElementMaxLength
, DataElementDataType
)
EXECUTE(@ExecString) 

SET @i = 1 
SET @f = (SELECT MAX(RecordKey)  FROM #DataSniffer_Info) 
WHILE @i <= @f 

BEGIN -- WHILE @i <= @f

-- declare our variables for looping
SET @DataElement = (SELECT DataElement FROM #DataSniffer_Info WHERE RecordKey = @i) 
SET @DataElementMaxLength = (SELECT DataElementMaxLength FROM #DataSniffer_Info WHERE RecordKey = @i) 
SET @DataElementDataType = (SELECT DataElementDataType FROM #DataSniffer_Info WHERE RecordKey = @i) 

--------------------------------------------------------------------------------------------------- Length Check
			SET @WHEREclause = '
				WHERE 1=1 
				AND '+@DataElementMaxLength+' <> -1
				AND LEN('+@DataElement+') > '+@DataElementMaxLength
	
			-- copy data from staging schema to error schema 
			EXECUTE library.dbo.Inserter @Table_staging, @Table_error, 'APPEND', @WHEREclause
	
			-- delete data from staging schema
			SET @ExecString = '
				DELETE s
				FROM '+@Table_staging+' s 
				'+@WHEREclause

			EXECUTE (@ExecString)  

			---- update Error column & comments 
			SET @ExecString = '
				UPDATE '+@Table_error+'
				SET 
				  RecordError_Column	= '''+@DataElement+''' 
				, RecordError_Comments	= '''+@DataElement+' is too long to be valid''
				'+@WHEREclause

			EXECUTE (@ExecString)  
	

--------------------------------------------------------------------------------------------------- Type Check
			SET @WHEREclause = 
			'WHERE 1=1 
			  AND '+@DataElement+' IS NOT NULL 
			  AND CAST('+@DataElement+' as varchar(max)) <> CHAR(0)
			  AND '+  
				   CASE WHEN @DataElementDataType IN ('int','bigint')  THEN 'ISNUMERIC(REPLACE('+@DataElement+', '' '', '''') + ''.e0'') = 0'
						WHEN @DataElementDataType = 'float'     THEN '0 = library.work.IsNumber(REPLACE('+@DataElement+', '' '', ''''))'
						WHEN @DataElementDataType = 'money'     THEN '0 = library.work.IsNumber(REPLACE('+@DataElement+', '' '', ''''))'
						WHEN @DataElementDataType = 'bit'       THEN ''+@DataElement+' NOT IN(''1'', ''0'') '
						WHEN @DataElementDataType = 'datetime'  THEN '0 = IsDate('+@DataElement+')'
						WHEN @DataElementDataType = 'varchar'   THEN '8=9'
						ELSE '1=1' 
				   END 	  	
		
			---- copy data from staging schema to error schema 
			EXECUTE library.dbo.Inserter @Table_staging, @Table_error, 'APPEND', @WHEREclause

			---- delete data from staging schema
			SET @ExecString = '
				DELETE s
				FROM '+@Table_staging+' s 
				'+@WHEREclause

			EXECUTE (@ExecString)  

			-- update Error column & comments 
			SET @ExecString = '
				UPDATE '+@Table_error+'
				SET 
				  RecordError_Column	= '''+@DataElement+''' 
				, RecordError_Comments	= '''+@DataElement+' is not a valid '+@DataElementDataType+' value''
				'+@WHEREclause

			EXECUTE (@ExecString) 

SET @i = @i + 1 

END -- WHILE @i <= @f

BEGIN TRY 
	DROP TABLE #DataSniffer_Info
END TRY
BEGIN CATCH 
END CATCH

