/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/


CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME , @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY
		SET @batch_start_time = GETDATE();
		PRINT '===================================================================================';
		PRINT ' Loading Silver Layer';
		PRINT '===================================================================================';
	
		PRINT '-----------------------------------------------------------------------------------';
		PRINT ' Loading CRM Tables';
		PRINT '-----------------------------------------------------------------------------------';

		SET @start_time = GETDATE();



	PRINT '>> Truncating Table: silver.crm_cust_info';
			TRUNCATE TABLE silver.crm_cust_info;
	PRINT '>> Insering Data into: silver.crm_cust_info';


	INSERT INTO silver.crm_cust_info (
			cst_id, 
			cst_key, 
			cst_firstname, 
			cst_lastname, 
			cst_marital_status, 
			cst_gndr,
			cst_create_date
		)
		SELECT
			cst_id,
			cst_key,
			TRIM(cst_firstname) AS cst_firstname,
			TRIM(cst_lastname) AS cst_lastname,
			CASE 
				WHEN UPPER(TRIM(cst_material_status)) = 'S' THEN 'Single'
				WHEN UPPER(TRIM(cst_material_status)) = 'M' THEN 'Married'
				ELSE 'n/a'
			END AS cst_material_status, -- Normalize marital status values to readable format
			CASE 
				WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
				WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
				ELSE 'n/a'
			END AS cst_gndr, -- Normalize gender values to readable format
			cst_create_date
		FROM (
			SELECT
				*,
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
			FROM bronze.crm_cust_info
			WHERE cst_id IS NOT NULL
		) t
		WHERE flag_last = 1;
	SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';
		
		SET @start_time = GETDATE();

	PRINT '>> Truncating Table: silver.crm_prd_info';
			TRUNCATE TABLE silver.crm_prd_info;
	PRINT '>> Insering Data into: silver.crm_prd_info';

	INSERT INTO silver.crm_prd_info(
	prd_id,
	cat_id,
	prd_key,
	prd_nm,
	prd_cost,
	prd_line,
	prd_start_dt,
	prd_end_dt
	)
	SELECT
		prd_id,
		replace(substring (prd_key, 1, 5), '-','_') as cat_id,
		substring(prd_key,7,len(prd_key)) as prd_key,
		prd_nm,
		isnull(prd_cost,0) AS prd_cost,
		case upper(trim(prd_line))
			when 'M' THEN 'Mountain'
			when 'R' THEN 'Road'
			when 'S' THEN 'Other Sales'
			when 'T' THEN 'Touring'
			else 'n/a'
		end as prd_line,
		cast(prd_start_dt as date) as prd_start_dt,
		cast(lead(prd_start_dt) over(partition by prd_key order by prd_start_dt)-1 as date)as prd_end_dt
	  FROM bronze.crm_prd_info
		
		SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';

		SET @start_time = GETDATE();
 
	PRINT '>> Truncating Table: silver.crm_sales_details';
			TRUNCATE TABLE silver.crm_sales_details;
	PRINT '>> Insering Data into: silver.crm_sales_details';

	INSERT INTO silver.crm_sales_details(
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	sls_order_dt,
	sls_ship_dt,
	sls_due_dt,
	sls_sales,
	sls_quantity,
	sls_price)

	select
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	case when sls_order_dt= 0 or len(sls_order_dt) !=8 then null
		else cast(cast(sls_order_dt as varchar) as date)
		end as sls_order_dt,
	case when sls_ship_dt= 0 or len(sls_ship_dt) !=8 then null
		else cast(cast(sls_ship_dt as varchar) as date)
		end as sls_ship_dt,
	case when sls_due_dt=0 or len(sls_due_dt) !=8 then null
		else cast(cast(sls_due_dt as varchar) as date)
		end as sls_due_dt,
	case when sls_sales is null or sls_sales <=0 or sls_sales != sls_quantity * ABS(sls_price)
		then sls_quantity * ABS(sls_price)
		else sls_sales
		end as sls_sales,
	sls_quantity,
	case when sls_price is null or sls_price <=0
		then sls_sales / nullif(sls_quantity,0)
		else sls_price
		end as sls_price
	from bronze.crm_sales_details

		SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';
		PRINT '-----------------------------------------------------------------------------------';
		PRINT ' Loading ERP Tables';
		PRINT '-----------------------------------------------------------------------------------';
	
		SET @start_time = GETDATE();

	PRINT '>> Truncating Table: silver.erp_cust_az12';
			TRUNCATE TABLE silver.erp_cust_az12;
	PRINT '>> Insering Data into: silver.erp_cust_az12';

	insert into silver.erp_cust_az12( cid, bdate, gen)
	select
	case when cid like'NAS%' THEN substring(cid, 4, LEN(cid))
		ELSE cid
	END AS cid,
	case when bdate > getdate() then null 
	else bdate
	end as bdate,
	case when upper(trim(gen)) in ( 'F', 'FEMALE') THEN 'Female'
		when UPPER(trim(gen)) in ('M', 'MALE') THEN 'Male'
		else 'n/a'
	end as gen
	from bronze.erp_cust_az12

		SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';

		SET @start_time = GETDATE();


	PRINT '>> Truncating Table: silver.erp_loc_a101';
			TRUNCATE TABLE silver.erp_loc_a101;
	PRINT '>> Insering Data into: silver.erp_loc_a101';

	INSERT INTO silver.erp_loc_a101 (cid,cntry)
	select
	replace (cid, '-','') cid,
	case when TRIM(cntry) = 'DE' THEN 'GERMANY'
		when TRIM(cntry) IN ('US' , 'USA') THEN 'UNITED STATES'
		when TRIM(cntry) = '' OR CNTRY IS NULL THEN 'N/A'
		else TRIM(cntry)
	END AS cntry
	from bronze.erp_loc_a101

		SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';

		SET @start_time = GETDATE();


	PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
			TRUNCATE TABLE silver.erp_px_cat_g1v2;
	PRINT '>> Insering Data into: silver.erp_px_cat_g1v2';

	insert into silver.erp_px_cat_g1v2
	(id, cat, subcat, maintenance)
	select 
	id,
	cat,
	subcat,
	maintenance
	from bronze.erp_px_cat_g1v2

		SET @end_time = GETDATE();
		PRINT'>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + 'seconds';
		PRINT '-----------------------------------';

		SET @batch_end_time = GETDATE();
		PRINT '======================================';
		PRINT 'Loading Silver Layer is Complete';
		PRINT ' - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + 'seconds';
	END TRY
	BEGIN CATCH
		PRINT '========================================================================================';
		PRINT 'ERROR OCCURE DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '========================================================================================';
	END CATCH
END


