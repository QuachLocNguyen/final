/* =====================================================================
   01_Create_EcommerceDW_v2.sql
   Kho dữ liệu EcommerceDW - Chuẩn Kimball Star/Galaxy Schema Tinh Gọn:
   - 8 Dimensions chất lượng cao (không còn bảng 2 cột, hỗ trợ Hierarchy, Junk Dim)
   - 7 Fact Tables (3 Fact Cơ bản + 4 Fact Chiến lược Trừu tượng)
   Nền tảng: Microsoft SQL Server (2016 trở lên)
   ===================================================================== */

USE master;
GO

IF DB_ID(N'EcommerceDW') IS NULL
    CREATE DATABASE EcommerceDW;
GO

ALTER DATABASE EcommerceDW SET RECOVERY SIMPLE;
GO

USE EcommerceDW;
GO
-- =====================================================================
-- 2. TẠO 8 BẢNG CHIỀU CHẤT LƯỢNG CAO (DIMENSIONS)
-- =====================================================================

-- 2.1 Dim_Date (Smart Key: YYYYMMDD, SCD Type 0, Role-Playing)
CREATE TABLE dbo.Dim_Date (
    date_key        INT          NOT NULL,            -- YYYYMMDD, vd 20231106
    full_date       DATE         NOT NULL,
    [year]          SMALLINT     NOT NULL,
    [quarter]       TINYINT      NOT NULL,
    quarter_name    VARCHAR(10)  NOT NULL,            -- Q1, Q2, Q3, Q4
    [month]         TINYINT      NOT NULL,
    month_name      VARCHAR(20)  NOT NULL,            -- January, February...
    [day]           TINYINT      NOT NULL,
    day_of_week     VARCHAR(20)  NOT NULL,            -- Monday, Tuesday...
    day_of_week_num TINYINT      NOT NULL,            -- 1 (Mon) -> 7 (Sun)
    is_weekend      BIT          NOT NULL,
    week_of_year    TINYINT      NOT NULL,
    year_month      CHAR(7)      NOT NULL,            -- YYYY-MM
    season          VARCHAR(20)  NOT NULL,            -- Spring, Summer, Autumn, Winter
    is_month_end    BIT          NOT NULL,            -- Dùng cho Snapshot
    CONSTRAINT PK_Dim_Date PRIMARY KEY CLUSTERED (date_key),
    CONSTRAINT UQ_Dim_Date_full_date UNIQUE (full_date)
);
GO

-- 2.2 Dim_Product (Star Schema Denormalized: Chứa trọn Hierarchy 4 tầng)
-- Khắc phục triệt để lỗi "fake dimension" 2 cột (loại bỏ Dim_Category, Dim_Brand)
CREATE TABLE dbo.Dim_Product (
    product_key        INT IDENTITY(1,1) NOT NULL,
    product_id         VARCHAR(50)       NOT NULL,    -- Business Key
    product_name       NVARCHAR(255)     NULL,
    brand              NVARCHAR(100)     NULL,
    subcategory        NVARCHAR(100)     NULL,
    category           NVARCHAR(100)     NULL,
    supplier           NVARCHAR(150)     NULL,
    unit_price         DECIMAL(18,4)     NULL,
    product_cost       DECIMAL(18,4)     NULL,
    price_tier         VARCHAR(30)       NULL,        -- Budget, Mid-Range, Premium, Luxury
    product_rating     DECIMAL(5,2)      NULL,
    rating_group       VARCHAR(30)       NULL,        -- Low (<3.0), Average (3-4), High (>4.0)
    CONSTRAINT PK_Dim_Product PRIMARY KEY CLUSTERED (product_key),
    CONSTRAINT UQ_Dim_Product_id UNIQUE (product_id)
);
GO

-- 2.3 Dim_Customer (Star Schema Denormalized: Khử chuẩn hóa Segment & Nhân khẩu học)
CREATE TABLE dbo.Dim_Customer (
    customer_key             INT IDENTITY(1,1) NOT NULL,
    customer_id              VARCHAR(50)       NOT NULL,   -- Business Key
    customer_name            NVARCHAR(150)     NULL,
    customer_age             SMALLINT          NULL,
    age_group                VARCHAR(30)       NULL,       -- 18-25, 26-35, 36-50, 50+
    gender                   VARCHAR(20)       NULL,
    customer_segment         VARCHAR(50)       NULL,       -- Consumer, Corporate, Home Office, Small Business
    customer_type            VARCHAR(50)       NULL,       -- Loyal, Returning, New
    customer_city            NVARCHAR(100)     NULL,
    customer_state           NVARCHAR(100)     NULL,
    customer_country         NVARCHAR(100)     NULL,
    region                   VARCHAR(50)       NULL,
    customer_postal_code     VARCHAR(30)       NULL,
    customer_acquisition_cost DECIMAL(18,4)    NULL,
    CONSTRAINT PK_Dim_Customer PRIMARY KEY CLUSTERED (customer_key),
    CONSTRAINT UQ_Dim_Customer_id UNIQUE (customer_id)
);
GO

-- 2.4 Dim_Region (Phân cấp Địa lý Vùng dùng chung)
CREATE TABLE dbo.Dim_Region (
    region_key INT IDENTITY(1,1) NOT NULL,
    region     VARCHAR(50)       NULL,
    [state]    NVARCHAR(100)     NULL,
    country    NVARCHAR(100)     NULL,
    CONSTRAINT PK_Dim_Region PRIMARY KEY CLUSTERED (region_key),
    CONSTRAINT UQ_Dim_Region UNIQUE (region, [state], country)
);
GO

-- 2.5 Dim_Shipping (Vận hành kho bãi & vận chuyển)
CREATE TABLE dbo.Dim_Shipping (
    shipping_key            INT IDENTITY(1,1) NOT NULL,
    shipping_method         NVARCHAR(100)     NULL,        -- Standard, Express, Economy, Same Day
    warehouse               NVARCHAR(100)     NULL,        -- WH-001 -> WH-019
    shipping_speed_category VARCHAR(50)       NULL,        -- Fast, Standard, Economy
    CONSTRAINT PK_Dim_Shipping PRIMARY KEY CLUSTERED (shipping_key),
    CONSTRAINT UQ_Dim_Shipping UNIQUE (shipping_method, warehouse)
);
GO

-- 2.6 Dim_Order_Profile (JUNK DIMENSION - Gom 5 cờ trạng thái nhỏ lẻ)
-- Kỹ thuật đỉnh cao Ralph Kimball giảm số lượng khóa ngoại trong Fact
CREATE TABLE dbo.Dim_Order_Profile (
    order_profile_key INT IDENTITY(1,1) NOT NULL,
    order_status      VARCHAR(50)       NULL,   -- Completed, Cancelled, Pending, Processing
    payment_method    VARCHAR(50)       NULL,   -- Credit Card, Digital Wallet, Debit Card...
    payment_status    VARCHAR(50)       NULL,   -- Paid, Pending, Failed, Refunded
    sales_channel     VARCHAR(50)       NULL,   -- Website, Mobile App, Store POS
    delivery_status   VARCHAR(50)       NULL,   -- On Time, Delayed, Cancelled
    CONSTRAINT PK_Dim_Order_Profile PRIMARY KEY CLUSTERED (order_profile_key),
    CONSTRAINT UQ_Dim_Order_Profile UNIQUE (order_status, payment_method, payment_status, sales_channel, delivery_status)
);
GO

-- 2.7 Dim_Marketing_Campaign (Chiều Tiếp thị & Khuyến mãi chuyên sâu)
CREATE TABLE dbo.Dim_Marketing_Campaign (
    marketing_key     INT IDENTITY(1,1) NOT NULL,
    marketing_channel VARCHAR(100)      NULL,   -- Google Ads, Facebook, Direct, Email...
    campaign_name     VARCHAR(150)      NULL,   -- Summer_Sale, Black_Friday...
    coupon_code       VARCHAR(50)       NULL,   -- Mã giảm giá hoặc 'NO_COUPON'
    has_coupon_flag   BIT               NOT NULL,
    channel_type      VARCHAR(50)       NULL,   -- Paid Media, Owned Media, Organic
    CONSTRAINT PK_Dim_Marketing_Campaign PRIMARY KEY CLUSTERED (marketing_key),
    CONSTRAINT UQ_Dim_Marketing_Campaign UNIQUE (marketing_channel, campaign_name, coupon_code)
);
GO

-- 2.8 Dim_Return_Profile (Chiều Hoàn trả hàng)
CREATE TABLE dbo.Dim_Return_Profile (
    return_profile_key     INT IDENTITY(1,1) NOT NULL,
    return_status          VARCHAR(50)       NULL,   -- Returned, Cancelled, Pending
    return_reason          NVARCHAR(150)     NULL,   -- Defective Product, Wrong Item, Late...
    return_reason_category VARCHAR(50)       NULL,   -- Product Quality, Logistics, Customer Choice
    CONSTRAINT PK_Dim_Return_Profile PRIMARY KEY CLUSTERED (return_profile_key),
    CONSTRAINT UQ_Dim_Return_Profile UNIQUE (return_status, return_reason)
);
GO

-- =====================================================================
-- 3. CÁC BẢNG SỰ KIỆN (FACT TABLES: 3 CORE + 4 STRATEGIC)
-- =====================================================================

-- 3.1 Fact_Sales (Core Transaction Fact - Grain: 1 mặt hàng trong 1 đơn)
CREATE TABLE dbo.Fact_Sales (
    order_id                VARCHAR(50)   NOT NULL,   -- Degenerate Dimension
    product_key             INT           NOT NULL,
    date_key                INT           NOT NULL,   -- Ngày đặt hàng
    customer_key            INT           NOT NULL,
    region_key              INT           NULL,
    order_profile_key       INT           NULL,       -- Junk Dim thay thế Status, Channel, Payment
    marketing_key           INT           NULL,
    quantity                INT           NOT NULL,
    gross_sales             DECIMAL(18,4) NOT NULL,
    discount_amount         DECIMAL(18,4) NOT NULL,
    tax_amount              DECIMAL(18,4) NOT NULL,
    net_revenue             DECIMAL(18,4) NOT NULL,
    product_cost            DECIMAL(18,4) NOT NULL,
    shipping_cost_allocated DECIMAL(18,4) NOT NULL,
    contribution_margin     DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_Fact_Sales PRIMARY KEY CLUSTERED (order_id, product_key),
    CONSTRAINT FK_FSales_Date    FOREIGN KEY (date_key)          REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FSales_Cust    FOREIGN KEY (customer_key)      REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FSales_Prod    FOREIGN KEY (product_key)        REFERENCES dbo.Dim_Product (product_key),
    CONSTRAINT FK_FSales_Region  FOREIGN KEY (region_key)         REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FSales_Profile FOREIGN KEY (order_profile_key)  REFERENCES dbo.Dim_Order_Profile (order_profile_key),
    CONSTRAINT FK_FSales_Mkt     FOREIGN KEY (marketing_key)      REFERENCES dbo.Dim_Marketing_Campaign (marketing_key)
);
GO

-- 3.2 Fact_Order_Fulfillment (Core Accumulating Snapshot - Grain: 1 đơn hàng hoàn chỉnh)
CREATE TABLE dbo.Fact_Order_Fulfillment (
    order_id                   VARCHAR(50)   NOT NULL,   -- Degenerate Dimension
    order_date_key             INT           NOT NULL,   -- Dim_Date (vai: ngày đặt)
    expected_delivery_date_key INT           NOT NULL,   -- Dim_Date (vai: giao dự kiến)
    actual_delivery_date_key   INT           NOT NULL,   -- Dim_Date (vai: giao thực tế)
    customer_key               INT           NOT NULL,
    region_key                 INT           NULL,
    shipping_key               INT           NULL,
    order_profile_key          INT           NULL,
    delivery_days              SMALLINT      NOT NULL,
    estimated_delivery_days    SMALLINT      NOT NULL,
    delivery_variance_days     SMALLINT      NOT NULL,   -- delivery_days - estimated_delivery_days
    late_flag                  TINYINT       NOT NULL,   -- 1 nếu giao trễ
    shipping_cost              DECIMAL(18,4) NOT NULL,
    order_net_revenue          DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_Fact_Order_Fulfillment PRIMARY KEY CLUSTERED (order_id),
    CONSTRAINT CK_FFulfil_late_flag CHECK (late_flag IN (0, 1)),
    CONSTRAINT FK_FFulfil_OrderDate  FOREIGN KEY (order_date_key)             REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FFulfil_ExpDate    FOREIGN KEY (expected_delivery_date_key) REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FFulfil_ActDate    FOREIGN KEY (actual_delivery_date_key)   REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FFulfil_Cust       FOREIGN KEY (customer_key)               REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FFulfil_Region     FOREIGN KEY (region_key)                 REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FFulfil_Ship       FOREIGN KEY (shipping_key)               REFERENCES dbo.Dim_Shipping (shipping_key),
    CONSTRAINT FK_FFulfil_Profile    FOREIGN KEY (order_profile_key)          REFERENCES dbo.Dim_Order_Profile (order_profile_key)
);
GO

-- 3.3 Fact_Return (Core Transaction Fact - Grain: 1 sự kiện trả hàng)
CREATE TABLE dbo.Fact_Return (
    order_id              VARCHAR(50)   NOT NULL,   -- Degenerate Dimension
    date_key              INT           NOT NULL,   -- Ngày đặt hàng
    customer_key          INT           NOT NULL,
    region_key            INT           NULL,
    shipping_key          INT           NULL,
    return_profile_key    INT           NULL,
    returned_net_revenue  DECIMAL(18,4) NOT NULL,
    returned_product_cost DECIMAL(18,4) NOT NULL,
    return_margin_impact  DECIMAL(18,4) NOT NULL,
    CONSTRAINT PK_Fact_Return PRIMARY KEY CLUSTERED (order_id),
    CONSTRAINT FK_FReturn_Date    FOREIGN KEY (date_key)           REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FReturn_Cust    FOREIGN KEY (customer_key)       REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FReturn_Region  FOREIGN KEY (region_key)         REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FReturn_Ship    FOREIGN KEY (shipping_key)       REFERENCES dbo.Dim_Shipping (shipping_key),
    CONSTRAINT FK_FReturn_Profile FOREIGN KEY (return_profile_key) REFERENCES dbo.Dim_Return_Profile (return_profile_key)
);
GO

-- 3.4 Fact_Customer_Feedback (Strategic Fact - Grain: 1 đơn có đánh giá sau mua)
CREATE TABLE dbo.Fact_Customer_Feedback (
    order_id            VARCHAR(50)  NOT NULL,   -- Degenerate Dimension
    date_key            INT          NOT NULL,
    customer_key        INT          NOT NULL,
    region_key          INT          NULL,
    order_profile_key   INT          NULL,
    rating_value        DECIMAL(5,2) NOT NULL,
    review_sentiment    VARCHAR(50)  NULL,
    review_length       INT          NULL,
    is_negative_flag    BIT          NOT NULL,
    review_count        TINYINT      NOT NULL CONSTRAINT DF_FFeedback_review_count DEFAULT (1),
    CONSTRAINT PK_Fact_Customer_Feedback PRIMARY KEY CLUSTERED (order_id),
    CONSTRAINT FK_FFeedback_Date    FOREIGN KEY (date_key)          REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FFeedback_Cust    FOREIGN KEY (customer_key)      REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FFeedback_Region  FOREIGN KEY (region_key)        REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FFeedback_Profile FOREIGN KEY (order_profile_key) REFERENCES dbo.Dim_Order_Profile (order_profile_key)
);
GO

-- 3.5 Fact_Customer_Acquisition (Strategic Fact - Grain: 1 khách hàng tại đơn đầu tiên)
CREATE TABLE dbo.Fact_Customer_Acquisition (
    customer_key             INT           NOT NULL,
    date_key                 INT           NOT NULL,   -- Ngày đơn đầu tiên
    region_key               INT           NULL,
    marketing_key            INT           NULL,       -- Kênh marketing thu hút đầu tiên
    customer_acquisition_cost DECIMAL(18,4) NOT NULL,
    first_order_net_revenue  DECIMAL(18,4) NOT NULL,
    new_customer_count       TINYINT       NOT NULL CONSTRAINT DF_FAcq_new_customer_count DEFAULT (1),
    CONSTRAINT PK_Fact_Customer_Acquisition PRIMARY KEY CLUSTERED (customer_key),
    CONSTRAINT FK_FAcq_Cust   FOREIGN KEY (customer_key)  REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FAcq_Date   FOREIGN KEY (date_key)      REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FAcq_Region FOREIGN KEY (region_key)    REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FAcq_Mkt    FOREIGN KEY (marketing_key) REFERENCES dbo.Dim_Marketing_Campaign (marketing_key)
);
GO

-- 3.6 Fact_Customer_Snapshot (Strategic Periodic Snapshot - Grain: 1 khách hàng x 1 cuối tháng)
CREATE TABLE dbo.Fact_Customer_Snapshot (
    snapshot_date_key          INT           NOT NULL,   -- Dim_Date (vai: ngày chụp cuối tháng)
    customer_key               INT           NOT NULL,
    cumulative_net_revenue     DECIMAL(18,4) NOT NULL,
    cumulative_order_count     INT           NOT NULL,
    cumulative_points_earned   INT           NOT NULL,
    cumulative_points_redeemed INT           NOT NULL,
    active_90d_flag            TINYINT       NOT NULL,
    customer_count             TINYINT       NOT NULL CONSTRAINT DF_FSnap_customer_count DEFAULT (1),
    month_net_revenue          DECIMAL(18,4) NOT NULL,
    month_order_count          INT           NOT NULL,
    days_since_last_order      INT           NOT NULL,
    rfm_score                  TINYINT       NOT NULL,   -- 1-5
    loyalty_tier               VARCHAR(50)   NOT NULL,   -- Bronze, Silver, Gold, Platinum
    CONSTRAINT PK_Fact_Customer_Snapshot PRIMARY KEY CLUSTERED (snapshot_date_key, customer_key),
    CONSTRAINT CK_FSnap_active_flag CHECK (active_90d_flag IN (0, 1)),
    CONSTRAINT CK_FSnap_rfm CHECK (rfm_score BETWEEN 1 AND 5),
    CONSTRAINT FK_FSnap_Date FOREIGN KEY (snapshot_date_key) REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FSnap_Cust FOREIGN KEY (customer_key)      REFERENCES dbo.Dim_Customer (customer_key)
);
GO

-- 3.7 Fact_Campaign_Promotion (FACT MỚI: Phân tích Khuyến mãi, Săn Sale & ROI Chiến dịch)
-- Grain: 1 đơn hàng có tham gia chiến dịch / mã coupon
CREATE TABLE dbo.Fact_Campaign_Promotion (
    order_id            VARCHAR(50)   NOT NULL,   -- Degenerate Dimension
    date_key            INT           NOT NULL,
    customer_key        INT           NOT NULL,
    marketing_key       INT           NOT NULL,
    region_key          INT           NULL,
    order_profile_key   INT           NULL,
    gross_sales         DECIMAL(18,4) NOT NULL,
    discount_amount     DECIMAL(18,4) NOT NULL,
    net_revenue         DECIMAL(18,4) NOT NULL,
    discount_rate       DECIMAL(18,8) NOT NULL,   -- discount_amount / gross_sales
    is_coupon_order     BIT           NOT NULL,   -- 1 = Có áp mã giảm giá
    CONSTRAINT PK_Fact_Campaign_Promotion PRIMARY KEY CLUSTERED (order_id),
    CONSTRAINT FK_FPromo_Date    FOREIGN KEY (date_key)          REFERENCES dbo.Dim_Date (date_key),
    CONSTRAINT FK_FPromo_Cust    FOREIGN KEY (customer_key)      REFERENCES dbo.Dim_Customer (customer_key),
    CONSTRAINT FK_FPromo_Mkt     FOREIGN KEY (marketing_key)      REFERENCES dbo.Dim_Marketing_Campaign (marketing_key),
    CONSTRAINT FK_FPromo_Region  FOREIGN KEY (region_key)         REFERENCES dbo.Dim_Region (region_key),
    CONSTRAINT FK_FPromo_Profile FOREIGN KEY (order_profile_key) REFERENCES dbo.Dim_Order_Profile (order_profile_key)
);
GO

-- =====================================================================
-- 4. TẠO INDEX TỐI ƯU HIỆU NĂNG CHO SSAS CUBE VÀ TRUY VẤN
-- =====================================================================
CREATE NONCLUSTERED INDEX IX_FSales_date      ON dbo.Fact_Sales (date_key);
CREATE NONCLUSTERED INDEX IX_FSales_customer  ON dbo.Fact_Sales (customer_key);
CREATE NONCLUSTERED INDEX IX_FSales_region    ON dbo.Fact_Sales (region_key);
CREATE NONCLUSTERED INDEX IX_FSales_mkt       ON dbo.Fact_Sales (marketing_key);
CREATE NONCLUSTERED INDEX IX_FFulfil_orderdate ON dbo.Fact_Order_Fulfillment (order_date_key);
CREATE NONCLUSTERED INDEX IX_FFulfil_customer  ON dbo.Fact_Order_Fulfillment (customer_key);
CREATE NONCLUSTERED INDEX IX_FReturn_date     ON dbo.Fact_Return (date_key);
CREATE NONCLUSTERED INDEX IX_FFeedback_date   ON dbo.Fact_Customer_Feedback (date_key);
CREATE NONCLUSTERED INDEX IX_FAcq_date        ON dbo.Fact_Customer_Acquisition (date_key);
CREATE NONCLUSTERED INDEX IX_FSnap_customer   ON dbo.Fact_Customer_Snapshot (customer_key);
CREATE NONCLUSTERED INDEX IX_FPromo_mkt       ON dbo.Fact_Campaign_Promotion (marketing_key);
GO

-- =====================================================================
-- 5. KIỂM TRA TỔNG QUAN HỆ THỐNG
-- =====================================================================
SELECT 
    name AS Table_Name,
    type_desc AS Object_Type,
    create_date AS Created_Time
FROM sys.tables
WHERE name LIKE 'Dim[_]%' OR name LIKE 'Fact[_]%'
ORDER BY name;
GO

