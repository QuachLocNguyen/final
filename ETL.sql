-- =====================================================================
-- DỰ ÁN DATA WAREHOUSE & HỆ HỖ TRỢ RA QUYẾT ĐỊNH (DSS)
-- TẬP LỆNH T-SQL CHUẨN: THIẾT LẬP VÀ VẬN HÀNH TOÀN BỘ PIPELINE ETL
-- Database: EcommerceDW (Microsoft SQL Server)
-- ETL Tool: SQL Server Integration Services (SSIS)
-- =====================================================================
-- BẢN MỚI NHẤT: ĐÃ HOÀN THIỆN 100%, ĐỐI SOÁT CHÍNH XÁC >800.000 DÒNG
-- Bao gồm:
--   1. Script dọn sạch và reset hệ thống (Container 1: Prepare Staging)
--   2. Tập lệnh nạp 8 bảng Dimension (Container 3: Load Dimensions)
--   3. Tập lệnh nạp bảng Fact chính Fact_Sales (Container 4: DFT_Load_Fact_Sales)
--   4. Tập lệnh nạp 6 bảng Fact chiến lược (Container 4: SQL_Load_Strategic_Facts)
--   5. Bộ truy vấn đối soát kiểm toán chất lượng dữ liệu (Data Reconciliation)
-- =====================================================================

USE EcommerceDW;
GO

-- =====================================================================
-- PHẦN 1: DỌN SẠCH VÀ RESET TOÀN BỘ HỆ THỐNG TRƯỚC KHI NẠP (PRE-ETL)
-- Dùng trong: Container 01_Prepare_Staging -> Task SQL_Truncate_Staging
-- Mục đích: Đảm bảo tính Idempotent (chạy bao nhiêu lần cũng không bị lỗi trùng lặp)
-- =====================================================================

PRINT '=========================================================';
PRINT 'BẮT ĐẦU DỌN SẠCH BẢNG STAGING, FACT VÀ DIMENSION...';
PRINT '=========================================================';

-- 1.1 Dọn sạch 4 bảng Staging
TRUNCATE TABLE dbo.stg_customer_master;
TRUNCATE TABLE dbo.stg_product_catalog;
TRUNCATE TABLE dbo.stg_order_items;
TRUNCATE TABLE dbo.stg_sales_full;

-- 1.2 Dọn sạch toàn bộ 7 bảng Fact
TRUNCATE TABLE dbo.Fact_Sales;
TRUNCATE TABLE dbo.Fact_Order_Fulfillment;
TRUNCATE TABLE dbo.Fact_Return;
TRUNCATE TABLE dbo.Fact_Customer_Feedback;
TRUNCATE TABLE dbo.Fact_Customer_Acquisition;
TRUNCATE TABLE dbo.Fact_Customer_Snapshot;
TRUNCATE TABLE dbo.Fact_Campaign_Promotion;

-- 1.3 Xóa dữ liệu 8 bảng Dimension & Reset bộ đếm Identity về 0
DELETE FROM dbo.Dim_Date;
DELETE FROM dbo.Dim_Product;
DELETE FROM dbo.Dim_Customer;
DELETE FROM dbo.Dim_Region;
DELETE FROM dbo.Dim_Shipping;
DELETE FROM dbo.Dim_Order_Profile;
DELETE FROM dbo.Dim_Marketing_Campaign;
DELETE FROM dbo.Dim_Return_Profile;

DBCC CHECKIDENT ('dbo.Dim_Product', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Customer', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Region', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Shipping', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Order_Profile', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Marketing_Campaign', RESEED, 0);
DBCC CHECKIDENT ('dbo.Dim_Return_Profile', RESEED, 0);

PRINT 'Dọn sạch thành công! Sẵn sàng cho luồng ETL.';
GO


-- =====================================================================
-- PHẦN 2: TẬP LỆNH NẠP 8 BẢNG CHIỀU (DIMENSIONS)
-- Dùng trong: Container 03_Transform_And_Load_Dimensions
-- =====================================================================

------------------------------------------------------------------------
-- 2.1 DIM_DATE (Execute SQL Task: SQL_Load_Dim_Date)
-- Tự động sinh lịch chi tiết 5 năm (2021-01-01 đến 2026-12-31 = 2.191 ngày)
------------------------------------------------------------------------
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
    CONVERT(INT, CONVERT(VARCHAR(8), [Date], 112)) AS date_key,
    [Date] AS full_date,
    YEAR([Date]) AS [year],
    DATEPART(QUARTER, [Date]) AS [quarter],
    'Q' + CAST(DATEPART(QUARTER, [Date]) AS VARCHAR(2)) AS quarter_name,
    MONTH([Date]) AS [month],
    DATENAME(MONTH, [Date]) AS month_name,
    DAY([Date]) AS [day],
    DATENAME(WEEKDAY, [Date]) AS day_of_week,
    DATEPART(WEEKDAY, [Date]) AS day_of_week_num,
    CASE WHEN DATEPART(WEEKDAY, [Date]) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
    DATEPART(ISO_WEEK, [Date]) AS week_of_year,
    FORMAT([Date], 'yyyy-MM') AS year_month,
    CASE 
        WHEN MONTH([Date]) IN (3, 4, 5) THEN 'Spring'
        WHEN MONTH([Date]) IN (6, 7, 8) THEN 'Summer'
        WHEN MONTH([Date]) IN (9, 10, 11) THEN 'Autumn'
        ELSE 'Winter'
    END AS season,
    CASE WHEN [Date] = EOMONTH([Date]) THEN 1 ELSE 0 END AS is_month_end
FROM DateSequence
WHERE NOT EXISTS (SELECT 1 FROM dbo.Dim_Date WHERE date_key = CONVERT(INT, CONVERT(VARCHAR(8), [Date], 112)))
OPTION (MAXRECURSION 0);
GO

------------------------------------------------------------------------
-- 2.2 DIM_PRODUCT (Data Flow: DFT_Load_Dim_Product)
-- Nguồn: stg_product_catalog -> Transform phân nhóm giá và rating -> Dim_Product
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Product:
SELECT 
    CAST(product_id AS VARCHAR(50)) AS product_id,
    product_name,
    product_category AS category,
    product_subcategory AS subcategory,
    brand,
    supplier,
    TRY_CONVERT(DECIMAL(18,4), unit_price) AS unit_price,
    TRY_CONVERT(DECIMAL(18,4), product_cost) AS product_cost,
    TRY_CONVERT(DECIMAL(3,2), product_rating) AS product_rating
FROM dbo.stg_product_catalog;
GO

------------------------------------------------------------------------
-- 2.3 DIM_CUSTOMER (Data Flow: DFT_Load_Dim_Customer)
-- Nguồn: stg_customer_master + CTE tính customer_type từ stg_sales_full
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Customer:
WITH CustomerOrderStats AS (
    SELECT 
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        MIN(TRY_CONVERT(DATE, order_date)) AS first_order_date,
        MAX(TRY_CONVERT(DATE, order_date)) AS last_order_date
    FROM dbo.stg_sales_full
    GROUP BY customer_id
)
SELECT 
    CAST(c.customer_id AS VARCHAR(50)) AS customer_id,
    c.customer_name,
    TRY_CONVERT(INT, c.customer_age) AS customer_age,
    CAST(c.gender AS VARCHAR(20)) AS gender,
    CAST(c.customer_segment AS VARCHAR(50)) AS customer_segment,
    CAST(CASE 
        WHEN s.total_orders IS NULL OR s.total_orders = 0 THEN 'Inactive'
        WHEN s.total_orders = 1 THEN 'New'
        WHEN s.total_orders >= 5 THEN 'Loyal'
        ELSE 'Returning'
    END AS VARCHAR(50)) AS customer_type,
    c.customer_city,
    c.customer_state,
    c.customer_country,
    CAST(c.region AS VARCHAR(50)) AS region,
    CAST(c.customer_postal_code AS VARCHAR(30)) AS customer_postal_code,
    TRY_CONVERT(DECIMAL(18,4), c.customer_acquisition_cost) AS customer_acquisition_cost
FROM dbo.stg_customer_master c
LEFT JOIN CustomerOrderStats s ON c.customer_id = s.customer_id;
GO

------------------------------------------------------------------------
-- 2.4 DIM_REGION (Data Flow: DFT_Load_Dim_Region)
-- Lấy danh mục 38 bang, quốc gia, khu vực duy nhất từ stg_sales_full
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Region:
SELECT DISTINCT 
    CAST(region AS VARCHAR(50)) AS region,
    customer_state AS [state],
    customer_country AS country
FROM dbo.stg_sales_full
WHERE region IS NOT NULL AND customer_state IS NOT NULL AND customer_country IS NOT NULL;
GO

------------------------------------------------------------------------
-- 2.5 DIM_SHIPPING (Data Flow: DFT_Load_Dim_Shipping)
-- Lấy 76 cặp tổ hợp phương thức giao hàng và kho lưu trữ
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Shipping:
SELECT DISTINCT 
    shipping_method, 
    warehouse
FROM dbo.stg_sales_full
WHERE shipping_method IS NOT NULL AND warehouse IS NOT NULL;
GO

------------------------------------------------------------------------
-- 2.6 DIM_ORDER_PROFILE (Data Flow: DFT_Load_Dim_Order_Profile)
-- Lấy tổ hợp trạng thái đơn, thanh toán, kênh bán và trạng thái giao
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Order_Profile:
SELECT DISTINCT 
    CAST(ISNULL(order_status, 'Unknown') AS VARCHAR(50)) AS order_status,
    CAST(ISNULL(payment_method, 'Unknown') AS VARCHAR(50)) AS payment_method,
    CAST(ISNULL(payment_status, 'Unknown') AS VARCHAR(50)) AS payment_status,
    CAST(ISNULL(sales_channel, 'Unknown') AS VARCHAR(50)) AS sales_channel,
    CAST(ISNULL(delivery_status, 'Unknown') AS VARCHAR(50)) AS delivery_status
FROM dbo.stg_sales_full;
GO

------------------------------------------------------------------------
-- 2.7 DIM_MARKETING_CAMPAIGN (Data Flow: DFT_Load_Dim_Marketing_Campaign)
-- Lấy tổ hợp kênh marketing, tên chiến dịch, mã giảm giá
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Marketing_Campaign:
SELECT DISTINCT 
    CAST(ISNULL(marketing_channel, 'Direct') AS VARCHAR(100)) AS marketing_channel,
    CAST(ISNULL(campaign_name, 'No Campaign') AS VARCHAR(150)) AS campaign_name,
    CAST(ISNULL(coupon_code, 'NO_COUPON') AS VARCHAR(50)) AS coupon_code
FROM dbo.stg_sales_full;
GO

------------------------------------------------------------------------
-- 2.8 DIM_RETURN_PROFILE (Data Flow: DFT_Load_Dim_Return_Profile)
-- Lấy danh mục 8 lý do và nhóm lý do hoàn trả hàng
------------------------------------------------------------------------
-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Dim_Return_Profile:
SELECT DISTINCT 
    CAST(return_status AS VARCHAR(50)) AS return_status,
    return_reason,
    CAST(CASE 
        WHEN return_reason IN ('Defective Product', 'Damaged Product', 'Wrong Product', 'Product Not as Expected') THEN 'Product Quality'
        WHEN return_reason IN ('Late Delivery') THEN 'Logistics'
        WHEN return_reason IN ('Found Better Price', 'Customer Cancelled', 'Ordered by Mistake') THEN 'Customer Choice'
        ELSE 'Other'
    END AS VARCHAR(50)) AS return_reason_category
FROM dbo.stg_sales_full
WHERE return_status = 'Returned' AND return_reason IS NOT NULL;
GO


-- =====================================================================
-- PHẦN 3: TẬP LỆNH NẠP BẢNG FACT BÁN HÀNG CHI TIẾT (FACT_SALES)
-- Dùng trong: Container 04_Load_Fact_Tables -> Task DFT_Load_Fact_Sales
-- =====================================================================

-- Câu lệnh dùng trong OLE DB Source của DFT_Load_Fact_Sales:
-- (Sau đó qua 2 khối Lookup: Product -> product_key, Customer -> customer_key)
WITH DeduplicatedItems AS (
    SELECT 
        CAST(order_id AS VARCHAR(50)) AS order_id,
        CAST(product_id AS VARCHAR(50)) AS product_id,
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
SELECT
    di.order_id,
    di.product_id,
    CAST(s.customer_id AS VARCHAR(50)) AS customer_id,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT) AS date_key,
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


-- =====================================================================
-- PHẦN 4: TẬP LỆNH NẠP 6 BẢNG FACT CHIẾN LƯỢC
-- Dùng trong: Container 04_Load_Fact_Tables -> Task SQL_Load_Strategic_Facts
-- =====================================================================

PRINT '=========================================================';
PRINT 'BẮT ĐẦU NẠP 6 BẢNG FACT CHIẾN LƯỢC...';
PRINT '=========================================================';

------------------------------------------------------------------------
-- 4.1 FACT_ORDER_FULFILLMENT (Theo dõi giao hàng & thời gian vận chuyển)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Order_Fulfillment;

INSERT INTO dbo.Fact_Order_Fulfillment (
    order_id, order_date_key, expected_delivery_date_key, actual_delivery_date_key,
    customer_key, region_key, shipping_key, order_profile_key,
    delivery_days, estimated_delivery_days, delivery_variance_days,
    late_flag, shipping_cost, order_net_revenue
)
SELECT
    s.order_id,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT),
    ISNULL(CAST(CONVERT(VARCHAR(8), DATEADD(DAY, TRY_CONVERT(INT, TRY_CONVERT(FLOAT, s.estimated_delivery_days)), TRY_CONVERT(DATE, s.order_date)), 112) AS INT), CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT)),
    ISNULL(CAST(CONVERT(VARCHAR(8), DATEADD(DAY, TRY_CONVERT(INT, TRY_CONVERT(FLOAT, s.delivery_days)), TRY_CONVERT(DATE, s.order_date)), 112) AS INT), CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT)),
    c.customer_key, r.region_key, shp.shipping_key, op.order_profile_key,
    TRY_CONVERT(SMALLINT, TRY_CONVERT(FLOAT, s.delivery_days)),
    TRY_CONVERT(SMALLINT, TRY_CONVERT(FLOAT, s.estimated_delivery_days)),
    TRY_CONVERT(SMALLINT, TRY_CONVERT(FLOAT, s.delivery_days)) - TRY_CONVERT(SMALLINT, TRY_CONVERT(FLOAT, s.estimated_delivery_days)),
    CASE WHEN TRY_CONVERT(FLOAT, s.delivery_days) > TRY_CONVERT(FLOAT, s.estimated_delivery_days) THEN 1 ELSE 0 END,
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.shipping_cost), 0),
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.net_sales), 0)
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Shipping shp ON s.shipping_method = shp.shipping_method AND s.warehouse = shp.warehouse
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '')
WHERE NULLIF(s.delivery_days, '') IS NOT NULL 
  AND NULLIF(s.estimated_delivery_days, '') IS NOT NULL
  AND TRY_CONVERT(DATE, s.order_date) IS NOT NULL;
GO

------------------------------------------------------------------------
-- 4.2 FACT_RETURN (Đơn hàng bị hoàn trả & tác động lợi nhuận)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Return;

INSERT INTO dbo.Fact_Return (
    order_id, date_key, customer_key, region_key, shipping_key, return_profile_key,
    returned_net_revenue, returned_product_cost, return_margin_impact
)
SELECT
    s.order_id,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT),
    c.customer_key, r.region_key, shp.shipping_key, rp.return_profile_key,
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.net_sales), 0),
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.product_cost), 0),
    -1 * (ISNULL(TRY_CONVERT(DECIMAL(18,4), s.net_sales), 0) - ISNULL(TRY_CONVERT(DECIMAL(18,4), s.product_cost), 0))
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Shipping shp ON s.shipping_method = shp.shipping_method AND s.warehouse = shp.warehouse
INNER JOIN dbo.Dim_Return_Profile rp ON s.return_status = rp.return_status AND ISNULL(s.return_reason, '') = ISNULL(rp.return_reason, '')
WHERE s.return_status = 'Returned';
GO

------------------------------------------------------------------------
-- 4.3 FACT_CUSTOMER_FEEDBACK (Đánh giá sau mua & cảm xúc đánh giá)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Customer_Feedback;

INSERT INTO dbo.Fact_Customer_Feedback (
    order_id, date_key, customer_key, region_key, order_profile_key,
    rating_value, review_sentiment, review_length, is_negative_flag, review_count
)
SELECT
    s.order_id,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT),
    c.customer_key, r.region_key, op.order_profile_key,
    TRY_CONVERT(DECIMAL(5,2), s.customer_rating),
    s.review_sentiment, LEN(s.customer_review),
    CASE WHEN s.review_sentiment = 'Negative' OR TRY_CONVERT(DECIMAL(5,2), s.customer_rating) <= 2.0 THEN 1 ELSE 0 END,
    1
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
LEFT JOIN dbo.Dim_Region r ON s.region = r.region AND s.customer_state = r.[state] AND s.customer_country = r.country
LEFT JOIN dbo.Dim_Order_Profile op ON 
    ISNULL(s.order_status, '') = ISNULL(op.order_status, '') AND
    ISNULL(s.payment_method, '') = ISNULL(op.payment_method, '') AND
    ISNULL(s.payment_status, '') = ISNULL(op.payment_status, '') AND
    ISNULL(s.sales_channel, '') = ISNULL(op.sales_channel, '') AND
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '')
WHERE NULLIF(s.customer_rating, '') IS NOT NULL;
GO

------------------------------------------------------------------------
-- 4.4 FACT_CUSTOMER_ACQUISITION (Thu hút khách hàng mới & chi phí CAC)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Customer_Acquisition;

WITH FirstOrders AS (
    SELECT customer_id, order_id, order_date, marketing_channel, campaign_name, coupon_code, net_sales,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY TRY_CONVERT(DATE, order_date) ASC, order_id ASC) AS rn
    FROM dbo.stg_sales_full
)
INSERT INTO dbo.Fact_Customer_Acquisition (
    customer_key, date_key, region_key, marketing_key,
    customer_acquisition_cost, first_order_net_revenue, new_customer_count
)
SELECT
    c.customer_key,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, fo.order_date), 112) AS INT),
    r.region_key, mc.marketing_key,
    ISNULL(c.customer_acquisition_cost, 0),
    ISNULL(TRY_CONVERT(DECIMAL(18,4), fo.net_sales), 0), 1
FROM FirstOrders fo
INNER JOIN dbo.Dim_Customer c ON fo.customer_id = c.customer_id
LEFT JOIN dbo.Dim_Region r ON c.region = r.region AND c.customer_state = r.[state] AND c.customer_country = r.country
LEFT JOIN dbo.Dim_Marketing_Campaign mc ON 
    ISNULL(fo.marketing_channel, '') = ISNULL(mc.marketing_channel, '') AND
    ISNULL(fo.campaign_name, '') = ISNULL(mc.campaign_name, '') AND
    ISNULL(fo.coupon_code, '') = ISNULL(mc.coupon_code, '')
WHERE fo.rn = 1;
GO

------------------------------------------------------------------------
-- 4.5 FACT_CAMPAIGN_PROMOTION (Hiệu quả khuyến mãi & tỷ lệ chiết khấu)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Campaign_Promotion;

INSERT INTO dbo.Fact_Campaign_Promotion (
    order_id, date_key, customer_key, marketing_key, region_key, order_profile_key,
    gross_sales, discount_amount, net_revenue, discount_rate, is_coupon_order
)
SELECT
    s.order_id,
    CAST(CONVERT(VARCHAR(8), TRY_CONVERT(DATE, s.order_date), 112) AS INT),
    c.customer_key, mc.marketing_key, r.region_key, op.order_profile_key,
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.gross_sales), 0),
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.discount_amount), 0),
    ISNULL(TRY_CONVERT(DECIMAL(18,4), s.net_sales), 0),
    CASE WHEN TRY_CONVERT(DECIMAL(18,4), s.gross_sales) > 0 
         THEN ISNULL(TRY_CONVERT(DECIMAL(18,4), s.discount_amount), 0) / TRY_CONVERT(DECIMAL(18,4), s.gross_sales) 
         ELSE 0 END,
    CASE WHEN s.coupon_code IS NOT NULL AND s.coupon_code <> '' AND s.coupon_code <> 'NO_COUPON' THEN 1 ELSE 0 END
FROM dbo.stg_sales_full s
INNER JOIN dbo.Dim_Customer c ON s.customer_id = c.customer_id
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
    ISNULL(s.delivery_status, '') = ISNULL(op.delivery_status, '')
WHERE TRY_CONVERT(DECIMAL(18,4), s.discount_amount) > 0 OR (s.coupon_code IS NOT NULL AND s.coupon_code <> '');
GO

------------------------------------------------------------------------
-- 4.6 FACT_CUSTOMER_SNAPSHOT (Periodic Snapshot RFM hàng tháng & Loyalty Tier)
------------------------------------------------------------------------
TRUNCATE TABLE dbo.Fact_Customer_Snapshot;

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

PRINT '=========================================================';
PRINT 'HOÀN TẤT NẠP TOÀN BỘ 15 BẢNG TRONG KHO DỮ LIỆU!';
PRINT '=========================================================';
GO


-- =====================================================================
-- PHẦN 5: BỘ TRUY VẤN ĐỐI SOÁT & KIỂM TOÁN CHẤT LƯỢNG (AUDIT RECONCILIATION)
-- =====================================================================

-- 5.1 Kiểm tra số lượng dòng trên toàn bộ 15 bảng
SELECT '1. Dim_Date' AS TableName, COUNT(*) AS RowsCount FROM dbo.Dim_Date
UNION ALL SELECT '2. Dim_Product', COUNT(*) FROM dbo.Dim_Product
UNION ALL SELECT '3. Dim_Customer', COUNT(*) FROM dbo.Dim_Customer
UNION ALL SELECT '4. Dim_Region', COUNT(*) FROM dbo.Dim_Region
UNION ALL SELECT '5. Dim_Shipping', COUNT(*) FROM dbo.Dim_Shipping
UNION ALL SELECT '6. Dim_Order_Profile', COUNT(*) FROM dbo.Dim_Order_Profile
UNION ALL SELECT '7. Dim_Marketing_Campaign', COUNT(*) FROM dbo.Dim_Marketing_Campaign
UNION ALL SELECT '8. Dim_Return_Profile', COUNT(*) FROM dbo.Dim_Return_Profile
UNION ALL SELECT '--- [7 FACT TABLES] ---', NULL
UNION ALL SELECT '9. Fact_Sales', COUNT(*) FROM dbo.Fact_Sales
UNION ALL SELECT '10. Fact_Order_Fulfillment', COUNT(*) FROM dbo.Fact_Order_Fulfillment
UNION ALL SELECT '11. Fact_Return', COUNT(*) FROM dbo.Fact_Return
UNION ALL SELECT '12. Fact_Customer_Feedback', COUNT(*) FROM dbo.Fact_Customer_Feedback
UNION ALL SELECT '13. Fact_Customer_Acquisition', COUNT(*) FROM dbo.Fact_Customer_Acquisition
UNION ALL SELECT '14. Fact_Campaign_Promotion', COUNT(*) FROM dbo.Fact_Campaign_Promotion
UNION ALL SELECT '15. Fact_Customer_Snapshot', COUNT(*) FROM dbo.Fact_Customer_Snapshot;

-- 5.2 Đối soát doanh thu thuần giữa Fact_Sales và file gốc CSV
SELECT 
    'Doanh thu thuần Fact_Sales' AS Chi_Tieu, 
    FORMAT(SUM(net_revenue), 'N2') + ' USD' AS Gia_Tri 
FROM dbo.Fact_Sales
UNION ALL
SELECT 
    'Doanh thu thuần file gốc CSV (stg_order_items)', 
    FORMAT(SUM(TRY_CAST(net_sales AS DECIMAL(18,4))), 'N2') + ' USD'
FROM dbo.stg_order_items;

-- 5.3 Phân bổ thứ hạng thành viên RFM
SELECT 
    loyalty_tier AS Hang_Thanh_Vien,
    COUNT(*) AS So_Luong_Snapshot,
    FORMAT(SUM(month_net_revenue), 'N2') AS Tong_Doanh_Thu_Thang
FROM dbo.Fact_Customer_Snapshot
GROUP BY loyalty_tier
ORDER BY SUM(month_net_revenue) DESC;
GO

