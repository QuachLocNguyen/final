/* =====================================================================
   02_ETL_EcommerceDW_v2.sql
   Pipeline ETL nạp sạch dữ liệu từ Staging vào 8 Dims & 7 Facts v2
   ===================================================================== */

USE EcommerceDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT 'Bắt đầu quá trình nạp dữ liệu ETL v2...';

-- =====================================================================
-- 0. DỌN SẠCH DỮ LIỆU CŨ TRONG DWH (FACT TRƯỚC, DIM SAU)
-- =====================================================================
PRINT '0. Dọn sạch dữ liệu cũ...';
DELETE FROM dbo.Fact_Campaign_Promotion;
DELETE FROM dbo.Fact_Customer_Snapshot;
DELETE FROM dbo.Fact_Customer_Acquisition;
DELETE FROM dbo.Fact_Customer_Feedback;
DELETE FROM dbo.Fact_Return;
DELETE FROM dbo.Fact_Order_Fulfillment;
DELETE FROM dbo.Fact_Sales;

DELETE FROM dbo.Dim_Customer;
DELETE FROM dbo.Dim_Product;
DELETE FROM dbo.Dim_Shipping;
DELETE FROM dbo.Dim_Region;
DELETE FROM dbo.Dim_Order_Profile;
DELETE FROM dbo.Dim_Marketing_Campaign;
DELETE FROM dbo.Dim_Return_Profile;
DELETE FROM dbo.Dim_Date;

DBCC CHECKIDENT ('dbo.Dim_Customer', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Product', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Shipping', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Region', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Order_Profile', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Marketing_Campaign', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Return_Profile', RESEED, 0);
GO

-- =====================================================================
-- 1. NẠP 8 BẢNG CHIỀU (DIMENSIONS)
-- =====================================================================

-- 1.1 Dim_Date
PRINT '1.1 Nạp Dim_Date...';
DECLARE @StartDate DATE = '2021-01-01';
DECLARE @EndDate DATE = '2026-12-31';

WITH DateSequence AS (
    SELECT @StartDate AS [Date]
    UNION ALL
    SELECT DATEADD(DAY, 1, [Date])
    FROM DateSequence
    WHERE [Date] < @EndDate
)
INSERT INTO dbo.Dim_Date (
    date_key, full_date, [year], [quarter], quarter_name,
    [month], month_name, [day], day_of_week, day_of_week_num,
    is_weekend, week_of_year, year_month, season, is_month_end
)
SELECT
    CAST(CONVERT(VARCHAR(8), [Date], 112) AS INT) AS date_key,
    [Date] AS full_date,
    YEAR([Date]) AS [year],
    DATEPART(QUARTER, [Date]) AS [quarter],
    'Q' + CAST(DATEPART(QUARTER, [Date]) AS VARCHAR(1)) AS quarter_name,
    MONTH([Date]) AS [month],
    DATENAME(MONTH, [Date]) AS month_name,
    DAY([Date]) AS [day],
    DATENAME(WEEKDAY, [Date]) AS day_of_week,
    DATEPART(WEEKDAY, [Date]) AS day_of_week_num,
    CASE WHEN DATEPART(WEEKDAY, [Date]) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
    DATEPART(WEEK, [Date]) AS week_of_year,
    CONVERT(CHAR(7), [Date], 120) AS year_month,
    CASE 
        WHEN MONTH([Date]) IN (3, 4, 5) THEN 'Spring'
        WHEN MONTH([Date]) IN (6, 7, 8) THEN 'Summer'
        WHEN MONTH([Date]) IN (9, 10, 11) THEN 'Autumn'
        ELSE 'Winter'
    END AS season,
    CASE WHEN [Date] = EOMONTH([Date]) THEN 1 ELSE 0 END AS is_month_end
FROM DateSequence
OPTION (MAXRECURSION 0);
GO

-- 1.2 Dim_Product (Star Schema Flat)
PRINT '1.2 Nạp Dim_Product...';
INSERT INTO dbo.Dim_Product (
    product_id, product_name, brand, subcategory, category,
    supplier, unit_price, product_cost, price_tier,
    product_rating, rating_group
)
SELECT
    p.product_id,
    p.product_name,
    p.brand,
    p.product_subcategory AS subcategory,
    p.product_category AS category,
    p.supplier,
    TRY_CONVERT(DECIMAL(18,4), p.unit_price) AS unit_price,
    TRY_CONVERT(DECIMAL(18,4), p.product_cost) AS product_cost,
    CASE 
        WHEN TRY_CONVERT(DECIMAL(18,4), p.unit_price) < 100 THEN 'Budget'
        WHEN TRY_CONVERT(DECIMAL(18,4), p.unit_price) < 500 THEN 'Mid-Range'
        WHEN TRY_CONVERT(DECIMAL(18,4), p.unit_price) < 1000 THEN 'Premium'
        ELSE 'Luxury'
    END AS price_tier,
    TRY_CONVERT(DECIMAL(5,2), p.product_rating) AS product_rating,
    CASE 
        WHEN TRY_CONVERT(DECIMAL(5,2), p.product_rating) < 3.0 THEN 'Low'
        WHEN TRY_CONVERT(DECIMAL(5,2), p.product_rating) <= 4.0 THEN 'Average'
        ELSE 'High'
    END AS rating_group
FROM dbo.stg_product_catalog p;
GO

-- 1.3 Dim_Region
PRINT '1.3 Nạp Dim_Region...';
INSERT INTO dbo.Dim_Region (region, [state], country)
SELECT DISTINCT
    NULLIF(LTRIM(RTRIM(region)), ''),
    NULLIF(LTRIM(RTRIM(customer_state)), ''),
    NULLIF(LTRIM(RTRIM(customer_country)), '')
FROM dbo.stg_customer_master
WHERE region IS NOT NULL AND customer_state IS NOT NULL AND customer_country IS NOT NULL;
GO

-- 1.4 Dim_Customer
PRINT '1.4 Nạp Dim_Customer...';
WITH CustType AS (
    SELECT 
        customer_id,
        MAX(customer_type) AS customer_type
    FROM dbo.stg_sales_full
    GROUP BY customer_id
)
INSERT INTO dbo.Dim_Customer (
    customer_id, customer_name, customer_age, age_group,
    gender, customer_segment, customer_type,
    customer_city, customer_state, customer_country,
    region, customer_postal_code, customer_acquisition_cost
)
SELECT
    c.customer_id,
    c.customer_name,
    TRY_CONVERT(SMALLINT, c.customer_age) AS customer_age,
    CASE 
        WHEN TRY_CONVERT(SMALLINT, c.customer_age) < 26 THEN '18-25'
        WHEN TRY_CONVERT(SMALLINT, c.customer_age) < 36 THEN '26-35'
        WHEN TRY_CONVERT(SMALLINT, c.customer_age) < 51 THEN '36-50'
        ELSE '50+'
    END AS age_group,
    c.gender,
    c.customer_segment,
    ISNULL(ct.customer_type, 'New') AS customer_type,
    c.customer_city,
    c.customer_state,
    c.customer_country,
    c.region,
    c.customer_postal_code,
    TRY_CONVERT(DECIMAL(18,4), c.customer_acquisition_cost) AS customer_acquisition_cost
FROM dbo.stg_customer_master c
LEFT JOIN CustType ct ON c.customer_id = ct.customer_id;
GO

-- 1.5 Dim_Shipping
PRINT '1.5 Nạp Dim_Shipping...';
INSERT INTO dbo.Dim_Shipping (shipping_method, warehouse, shipping_speed_category)
SELECT DISTINCT
    NULLIF(LTRIM(RTRIM(shipping_method)), ''),
    NULLIF(LTRIM(RTRIM(warehouse)), ''),
    CASE 
        WHEN shipping_method IN ('Same Day', 'Express') THEN 'Fast'
        WHEN shipping_method = 'Standard' THEN 'Standard'
        ELSE 'Economy'
    END AS shipping_speed_category
FROM dbo.stg_sales_full
WHERE shipping_method IS NOT NULL AND warehouse IS NOT NULL;
GO

-- 1.6 Dim_Order_Profile (Junk Dimension)
PRINT '1.6 Nạp Dim_Order_Profile...';
INSERT INTO dbo.Dim_Order_Profile (
    order_status, payment_method, payment_status,
    sales_channel, delivery_status
)
SELECT DISTINCT
    NULLIF(LTRIM(RTRIM(order_status)), ''),
    NULLIF(LTRIM(RTRIM(payment_method)), ''),
    NULLIF(LTRIM(RTRIM(payment_status)), ''),
    NULLIF(LTRIM(RTRIM(sales_channel)), ''),
    NULLIF(LTRIM(RTRIM(delivery_status)), '')
FROM dbo.stg_sales_full;
GO

-- 1.7 Dim_Marketing_Campaign
PRINT '1.7 Nạp Dim_Marketing_Campaign...';
INSERT INTO dbo.Dim_Marketing_Campaign (
    marketing_channel, campaign_name, coupon_code,
    has_coupon_flag, channel_type
)
SELECT DISTINCT
    NULLIF(LTRIM(RTRIM(marketing_channel)), ''),
    NULLIF(LTRIM(RTRIM(campaign_name)), ''),
    NULLIF(LTRIM(RTRIM(coupon_code)), ''),
    CASE WHEN coupon_code IS NOT NULL AND LTRIM(RTRIM(coupon_code)) <> '' THEN 1 ELSE 0 END AS has_coupon_flag,
    CASE 
        WHEN marketing_channel IN ('Google Ads', 'Facebook Ads', 'Instagram', 'TikTok', 'YouTube', 'Affiliate') THEN 'Paid Media'
        WHEN marketing_channel IN ('Direct', 'Email Marketing') THEN 'Owned Media'
        WHEN marketing_channel IN ('Organic Search', 'Referral') THEN 'Organic Media'
        ELSE 'Other'
    END AS channel_type
FROM dbo.stg_sales_full;
GO

-- 1.8 Dim_Return_Profile
PRINT '1.8 Nạp Dim_Return_Profile...';
INSERT INTO dbo.Dim_Return_Profile (
    return_status, return_reason, return_reason_category
)
SELECT DISTINCT
    LTRIM(RTRIM(return_status)),
    LTRIM(RTRIM(return_reason)),
    CASE 
        WHEN return_reason IN ('Defective Product', 'Damaged Product', 'Wrong Product', 'Product Not as Expected') THEN 'Product Quality Issue'
        WHEN return_reason IN ('Late Delivery') THEN 'Logistics Issue'
        WHEN return_reason IN ('Changed Mind', 'Size Issue') THEN 'Customer Choice Issue'
        ELSE 'Other'
    END AS return_reason_category
FROM dbo.stg_sales_full
WHERE LTRIM(RTRIM(return_status)) = 'Returned' OR (return_reason IS NOT NULL AND LTRIM(RTRIM(return_reason)) <> '');
GO

PRINT 'Hoàn tất nạp 8 Dimension tables!';
GO

-- =====================================================================
-- 2. NẠP 7 BẢNG SỰ KIỆN (FACT TABLES)
-- =====================================================================

-- 2.1 Fact_Sales
PRINT '2.1 Nạp Fact_Sales...';
WITH DeduplicatedItems AS (
    SELECT 
        order_id,
        product_id,
        TRY_CONVERT(INT, quantity) AS quantity,
        TRY_CONVERT(DECIMAL(18,4), gross_sales) AS gross_sales,
        TRY_CONVERT(DECIMAL(18,4), discount_amount) AS discount_amount,
        TRY_CONVERT(DECIMAL(18,4), tax_amount) AS tax_amount,
        TRY_CONVERT(DECIMAL(18,4), net_sales) AS net_revenue,
        TRY_CONVERT(DECIMAL(18,4), product_cost) AS product_cost,
        TRY_CONVERT(DECIMAL(18,4), shipping_cost) AS shipping_cost_allocated,
        TRY_CONVERT(DECIMAL(18,4), profit) AS contribution_margin,
        ROW_NUMBER() OVER (PARTITION BY order_id, product_id ORDER BY TRY_CONVERT(INT, quantity) DESC) AS rn
    FROM dbo.stg_order_items
)
INSERT INTO dbo.Fact_Sales (
    order_id, product_key, date_key, customer_key,
    region_key, order_profile_key, marketing_key,
    quantity, gross_sales, discount_amount, tax_amount,
    net_revenue, product_cost, shipping_cost_allocated, contribution_margin
)
SELECT
    di.order_id,
    p.product_key,
    d.date_key,
    c.customer_key,
    r.region_key,
    op.order_profile_key,
    mc.marketing_key,
    di.quantity,
    di.gross_sales,
    di.discount_amount,
    di.tax_amount,
    di.net_revenue,
    di.product_cost,
    di.shipping_cost_allocated,
    di.contribution_margin
FROM DeduplicatedItems di
INNER JOIN dbo.stg_sales_full s ON di.order_id = s.order_id
INNER JOIN dbo.Dim_Product p ON di.product_id = p.product_id
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d ON CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) = d.date_key
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '')
LEFT JOIN dbo.Dim_Marketing_Campaign mc ON
    ISNULL(s.marketing_channel, '') = ISNULL(mc.marketing_channel, '') AND
    ISNULL(s.campaign_name, '') = ISNULL(mc.campaign_name, '') AND
    ISNULL(s.coupon_code, '') = ISNULL(mc.coupon_code, '')
WHERE di.rn = 1;
GO

-- 2.2 Fact_Order_Fulfillment
PRINT '2.2 Nạp Fact_Order_Fulfillment...';
INSERT INTO dbo.Fact_Order_Fulfillment (
    order_id, order_date_key, expected_delivery_date_key, actual_delivery_date_key,
    customer_key, region_key, shipping_key, order_profile_key,
    delivery_days, estimated_delivery_days, delivery_variance_days,
    late_flag, shipping_cost, order_net_revenue
)
SELECT
    s.order_id,
    d_ord.date_key AS order_date_key,
    CAST(CONVERT(VARCHAR(8), DATEADD(DAY, CAST(ROUND(TRY_CONVERT(FLOAT, s.estimated_delivery_days), 0) AS INT), TRY_CONVERT(DATE, s.order_date)), 112) AS INT) AS expected_delivery_date_key,
    CAST(CONVERT(VARCHAR(8), DATEADD(DAY, CAST(ROUND(TRY_CONVERT(FLOAT, s.delivery_days), 0) AS INT), TRY_CONVERT(DATE, s.order_date)), 112) AS INT) AS actual_delivery_date_key,
    c.customer_key,
    r.region_key,
    ship.shipping_key,
    op.order_profile_key,
    CAST(ROUND(TRY_CONVERT(FLOAT, s.delivery_days), 0) AS SMALLINT) AS delivery_days,
    CAST(ROUND(TRY_CONVERT(FLOAT, s.estimated_delivery_days), 0) AS SMALLINT) AS estimated_delivery_days,
    CAST(ROUND(TRY_CONVERT(FLOAT, s.delivery_days) - TRY_CONVERT(FLOAT, s.estimated_delivery_days), 0) AS SMALLINT) AS delivery_variance_days,
    CASE WHEN (TRY_CONVERT(FLOAT, s.delivery_days) - TRY_CONVERT(FLOAT, s.estimated_delivery_days)) > 0 THEN 1 ELSE 0 END AS late_flag,
    TRY_CONVERT(DECIMAL(18,4), s.shipping_cost) AS shipping_cost,
    TRY_CONVERT(DECIMAL(18,4), s.net_sales) AS order_net_revenue
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d_ord ON CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) = d_ord.date_key
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Shipping ship ON s.shipping_method = ship.shipping_method AND s.warehouse = ship.warehouse
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '');
GO

-- 2.3 Fact_Return
PRINT '2.3 Nạp Fact_Return...';
INSERT INTO dbo.Fact_Return (
    order_id, date_key, customer_key, region_key,
    shipping_key, return_profile_key,
    returned_net_revenue, returned_product_cost, return_margin_impact
)
SELECT
    s.order_id,
    d.date_key,
    c.customer_key,
    r.region_key,
    ship.shipping_key,
    rp.return_profile_key,
    TRY_CONVERT(DECIMAL(18,4), s.net_sales) AS returned_net_revenue,
    TRY_CONVERT(DECIMAL(18,4), s.product_cost) AS returned_product_cost,
    - (TRY_CONVERT(DECIMAL(18,4), s.profit)) AS return_margin_impact
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d ON CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) = d.date_key
INNER JOIN dbo.Dim_Return_Profile rp ON 
    ISNULL(LTRIM(RTRIM(s.return_status)), '') = ISNULL(rp.return_status, '') AND
    ISNULL(LTRIM(RTRIM(s.return_reason)), '') = ISNULL(rp.return_reason, '')
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Shipping ship ON s.shipping_method = ship.shipping_method AND s.warehouse = ship.warehouse
WHERE LTRIM(RTRIM(s.return_status)) = 'Returned';
GO

-- 2.4 Fact_Customer_Feedback
PRINT '2.4 Nạp Fact_Customer_Feedback...';
INSERT INTO dbo.Fact_Customer_Feedback (
    order_id, date_key, customer_key, region_key,
    order_profile_key, rating_value, review_sentiment,
    review_length, is_negative_flag, review_count
)
SELECT
    s.order_id,
    d.date_key,
    c.customer_key,
    r.region_key,
    op.order_profile_key,
    TRY_CONVERT(DECIMAL(5,2), s.customer_rating) AS rating_value,
    s.review_sentiment,
    LEN(ISNULL(s.customer_review, '')) AS review_length,
    CASE WHEN TRY_CONVERT(DECIMAL(5,2), s.customer_rating) <= 2.0 OR s.review_sentiment = 'Negative' THEN 1 ELSE 0 END AS is_negative_flag,
    1 AS review_count
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d ON CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) = d.date_key
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '')
WHERE TRY_CONVERT(DECIMAL(5,2), s.customer_rating) IS NOT NULL;
GO

-- 2.5 Fact_Customer_Acquisition
PRINT '2.5 Nạp Fact_Customer_Acquisition...';
WITH FirstOrder AS (
    SELECT
        s.customer_id,
        MIN(TRY_CONVERT(DATE, s.order_date)) AS first_order_date
    FROM dbo.stg_sales_full s
    GROUP BY s.customer_id
),
FirstOrderDetails AS (
    SELECT 
        fo.customer_id,
        fo.first_order_date,
        s.order_id,
        s.region,
        s.customer_state,
        s.customer_country,
        s.marketing_channel,
        s.campaign_name,
        s.coupon_code,
        TRY_CONVERT(DECIMAL(18,4), s.net_sales) AS first_order_net_revenue,
        ROW_NUMBER() OVER(PARTITION BY fo.customer_id ORDER BY s.order_id) AS rn
    FROM FirstOrder fo
    INNER JOIN dbo.stg_sales_full s ON fo.customer_id = s.customer_id AND fo.first_order_date = TRY_CONVERT(DATE, s.order_date)
)
INSERT INTO dbo.Fact_Customer_Acquisition (
    customer_key, date_key, region_key, marketing_key,
    customer_acquisition_cost, first_order_net_revenue, new_customer_count
)
SELECT
    c.customer_key,
    d.date_key,
    r.region_key,
    mc.marketing_key,
    ISNULL(c.customer_acquisition_cost, 0.0),
    fod.first_order_net_revenue,
    1 AS new_customer_count
FROM FirstOrderDetails fod
INNER JOIN dbo.Dim_Customer c ON fod.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d ON CAST(CONVERT(VARCHAR(8), fod.first_order_date, 112) AS INT) = d.date_key
LEFT JOIN dbo.Dim_Region r ON fod.region = r.region AND fod.customer_state = r.[state] AND fod.customer_country = r.country
LEFT JOIN dbo.Dim_Marketing_Campaign mc ON
    ISNULL(fod.marketing_channel, '') = ISNULL(mc.marketing_channel, '') AND
    ISNULL(fod.campaign_name, '') = ISNULL(mc.campaign_name, '') AND
    ISNULL(fod.coupon_code, '') = ISNULL(mc.coupon_code, '')
WHERE fod.rn = 1;
GO

-- 2.6 Fact_Customer_Snapshot
PRINT '2.6 Nạp Fact_Customer_Snapshot...';
WITH CustomerMonthly AS (
    SELECT
        s.customer_id,
        EOMONTH(TRY_CONVERT(DATE, s.order_date)) AS month_end_date,
        SUM(ISNULL(TRY_CONVERT(DECIMAL(18,4), s.net_sales), 0)) AS month_net_revenue,
        COUNT(DISTINCT s.order_id) AS month_order_count,
        SUM(ISNULL(TRY_CONVERT(INT, s.loyalty_points_earned), 0)) AS month_points_earned,
        SUM(ISNULL(TRY_CONVERT(INT, s.loyalty_points_redeemed), 0)) AS month_points_redeemed,
        MAX(TRY_CONVERT(DATE, s.order_date)) AS last_order_in_month
    FROM dbo.stg_sales_full s
    GROUP BY s.customer_id, EOMONTH(TRY_CONVERT(DATE, s.order_date))
),
CustomerMonthlyAccumulated AS (
    SELECT
        cm.customer_id,
        cm.month_end_date,
        CAST(CONVERT(VARCHAR(8), cm.month_end_date, 112) AS INT) AS snapshot_date_key,
        cm.month_net_revenue,
        cm.month_order_count,
        SUM(cm.month_net_revenue) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_end_date ROWS UNBOUNDED PRECEDING) AS cumulative_net_revenue,
        SUM(cm.month_order_count) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_end_date ROWS UNBOUNDED PRECEDING) AS cumulative_order_count,
        SUM(cm.month_points_earned) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_end_date ROWS UNBOUNDED PRECEDING) AS cumulative_points_earned,
        SUM(cm.month_points_redeemed) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_end_date ROWS UNBOUNDED PRECEDING) AS cumulative_points_redeemed,
        MAX(cm.last_order_in_month) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_end_date ROWS UNBOUNDED PRECEDING) AS max_order_date
    FROM CustomerMonthly cm
)
INSERT INTO dbo.Fact_Customer_Snapshot (
    snapshot_date_key, customer_key,
    cumulative_net_revenue, cumulative_order_count,
    cumulative_points_earned, cumulative_points_redeemed,
    active_90d_flag, customer_count,
    month_net_revenue, month_order_count,
    days_since_last_order, rfm_score, loyalty_tier
)
SELECT
    cma.snapshot_date_key,
    c.customer_key,
    ISNULL(cma.cumulative_net_revenue, 0),
    ISNULL(cma.cumulative_order_count, 0),
    ISNULL(cma.cumulative_points_earned, 0),
    ISNULL(cma.cumulative_points_redeemed, 0),
    CASE WHEN DATEDIFF(DAY, cma.max_order_date, cma.month_end_date) <= 90 THEN 1 ELSE 0 END AS active_90d_flag,
    1 AS customer_count,
    ISNULL(cma.month_net_revenue, 0),
    ISNULL(cma.month_order_count, 0),
    ISNULL(DATEDIFF(DAY, cma.max_order_date, cma.month_end_date), 0) AS days_since_last_order,
    CASE 
        WHEN DATEDIFF(DAY, cma.max_order_date, cma.month_end_date) <= 30 THEN 5
        WHEN DATEDIFF(DAY, cma.max_order_date, cma.month_end_date) <= 60 THEN 4
        WHEN DATEDIFF(DAY, cma.max_order_date, cma.month_end_date) <= 90 THEN 3
        WHEN DATEDIFF(DAY, cma.max_order_date, cma.month_end_date) <= 180 THEN 2
        ELSE 1
    END AS rfm_score,
    CASE 
        WHEN ISNULL(cma.cumulative_net_revenue, 0) >= 10000 THEN 'Platinum'
        WHEN ISNULL(cma.cumulative_net_revenue, 0) >= 5000 THEN 'Gold'
        WHEN ISNULL(cma.cumulative_net_revenue, 0) >= 2000 THEN 'Silver'
        ELSE 'Bronze'
    END AS loyalty_tier
FROM CustomerMonthlyAccumulated cma
INNER JOIN dbo.Dim_Customer c ON cma.customer_id = c.customer_id;
GO

-- 2.7 Fact_Campaign_Promotion (FACT MỚI)
PRINT '2.7 Nạp Fact_Campaign_Promotion...';
INSERT INTO dbo.Fact_Campaign_Promotion (
    order_id, date_key, customer_key, marketing_key,
    region_key, order_profile_key, gross_sales,
    discount_amount, net_revenue, discount_rate, is_coupon_order
)
SELECT
    s.order_id,
    d.date_key,
    c.customer_key,
    mc.marketing_key,
    r.region_key,
    op.order_profile_key,
    TRY_CONVERT(DECIMAL(18,4), s.gross_sales) AS gross_sales,
    TRY_CONVERT(DECIMAL(18,4), s.discount_amount) AS discount_amount,
    TRY_CONVERT(DECIMAL(18,4), s.net_sales) AS net_revenue,
    CASE 
        WHEN TRY_CONVERT(DECIMAL(18,4), s.gross_sales) > 0 
        THEN TRY_CONVERT(DECIMAL(18,4), s.discount_amount) / TRY_CONVERT(DECIMAL(18,4), s.gross_sales)
        ELSE 0.0 
    END AS discount_rate,
    CASE WHEN s.coupon_code IS NOT NULL AND LTRIM(RTRIM(s.coupon_code)) <> '' THEN 1 ELSE 0 END AS is_coupon_order
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
INNER JOIN dbo.Dim_Date d ON CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) = d.date_key
INNER JOIN dbo.Dim_Marketing_Campaign mc ON
    ISNULL(s.marketing_channel, '') = ISNULL(mc.marketing_channel, '') AND
    ISNULL(s.campaign_name, '') = ISNULL(mc.campaign_name, '') AND
    ISNULL(s.coupon_code, '') = ISNULL(mc.coupon_code, '')
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '');
GO

-- =====================================================================
-- 3. TỔNG KẾT SỐ LƯỢNG DÒNG (ROW COUNTS)
-- =====================================================================
PRINT '---------------------------------------------------------';
PRINT 'HOÀN TẤT NẠP TOÀN BỘ DATA WAREHOUSE! KIỂM TRA SỐ LƯỢNG:';
PRINT '---------------------------------------------------------';

SELECT 'Fact_Sales' AS Table_Name, COUNT(*) AS Row_Count FROM dbo.Fact_Sales
UNION ALL SELECT 'Fact_Order_Fulfillment', COUNT(*) FROM dbo.Fact_Order_Fulfillment
UNION ALL SELECT 'Fact_Campaign_Promotion', COUNT(*) FROM dbo.Fact_Campaign_Promotion
UNION ALL SELECT 'Fact_Customer_Snapshot', COUNT(*) FROM dbo.Fact_Customer_Snapshot
UNION ALL SELECT 'Fact_Customer_Feedback', COUNT(*) FROM dbo.Fact_Customer_Feedback
UNION ALL SELECT 'Fact_Customer_Acquisition', COUNT(*) FROM dbo.Fact_Customer_Acquisition
UNION ALL SELECT 'Fact_Return', COUNT(*) FROM dbo.Fact_Return
UNION ALL SELECT 'Dim_Customer', COUNT(*) FROM dbo.Dim_Customer
UNION ALL SELECT 'Dim_Date', COUNT(*) FROM dbo.Dim_Date
UNION ALL SELECT 'Dim_Marketing_Campaign', COUNT(*) FROM dbo.Dim_Marketing_Campaign
UNION ALL SELECT 'Dim_Product', COUNT(*) FROM dbo.Dim_Product
UNION ALL SELECT 'Dim_Order_Profile', COUNT(*) FROM dbo.Dim_Order_Profile
UNION ALL SELECT 'Dim_Shipping', COUNT(*) FROM dbo.Dim_Shipping
UNION ALL SELECT 'Dim_Region', COUNT(*) FROM dbo.Dim_Region
UNION ALL SELECT 'Dim_Return_Profile', COUNT(*) FROM dbo.Dim_Return_Profile
ORDER BY Row_Count DESC;
GO
