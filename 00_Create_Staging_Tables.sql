USE EcommerceDW;
GO

-- 1. XÓA BẢNG STAGING CŨ NẾU CÓ
DROP TABLE IF EXISTS dbo.stg_customer_master;
DROP TABLE IF EXISTS dbo.stg_product_catalog;
DROP TABLE IF EXISTS dbo.stg_order_items;
DROP TABLE IF EXISTS dbo.stg_sales_full;
GO

-- 2. TẠO BẢNG STAGING KHÁCH HÀNG
CREATE TABLE dbo.stg_customer_master (
    customer_id              NVARCHAR(50)  NULL,
    customer_name            NVARCHAR(150) NULL,
    customer_age             NVARCHAR(50)  NULL,
    gender                   NVARCHAR(50)  NULL,
    customer_segment         NVARCHAR(50)  NULL,
    customer_city            NVARCHAR(100) NULL,
    customer_state           NVARCHAR(100) NULL,
    customer_country         NVARCHAR(100) NULL,
    region                   NVARCHAR(50)  NULL,
    customer_postal_code     NVARCHAR(50)  NULL,
    customer_acquisition_cost NVARCHAR(50) NULL
);
GO

-- 3. TẠO BẢNG STAGING SẢN PHẨM
CREATE TABLE dbo.stg_product_catalog (
    product_id          NVARCHAR(50)  NULL,
    product_name        NVARCHAR(255) NULL,
    product_category    NVARCHAR(100) NULL,
    product_subcategory NVARCHAR(100) NULL,
    brand               NVARCHAR(100) NULL,
    supplier            NVARCHAR(150) NULL,
    unit_price          NVARCHAR(50)  NULL,
    product_cost        NVARCHAR(50)  NULL,
    product_rating      NVARCHAR(50)  NULL
);
GO

-- 4. TẠO BẢNG STAGING CHI TIẾT ĐƠN HÀNG
CREATE TABLE dbo.stg_order_items (
    order_id            NVARCHAR(50)  NULL,
    product_id          NVARCHAR(50)  NULL,
    quantity            NVARCHAR(50)  NULL,
    unit_price          NVARCHAR(50)  NULL,
    discount_percentage NVARCHAR(50)  NULL,
    discount_amount     NVARCHAR(50)  NULL,
    gross_sales         NVARCHAR(50)  NULL,
    tax_amount          NVARCHAR(50)  NULL,
    shipping_cost       NVARCHAR(50)  NULL,
    net_sales           NVARCHAR(50)  NULL,
    product_cost        NVARCHAR(50)  NULL,
    profit              NVARCHAR(50)  NULL
);
GO

-- 5. TẠO BẢNG STAGING TOÀN BỘ ĐƠN HÀNG
CREATE TABLE dbo.stg_sales_full (
    order_id                 NVARCHAR(50)   NULL,
    order_date               NVARCHAR(50)   NULL,
    order_time               NVARCHAR(50)   NULL,
    order_status             NVARCHAR(50)   NULL,
    sales_channel            NVARCHAR(50)   NULL,
    customer_id              NVARCHAR(50)   NULL,
    customer_name            NVARCHAR(150)  NULL,
    customer_age             NVARCHAR(50)   NULL,
    gender                   NVARCHAR(50)   NULL,
    customer_segment         NVARCHAR(50)   NULL,
    customer_type            NVARCHAR(50)   NULL,
    customer_city            NVARCHAR(100)  NULL,
    customer_state           NVARCHAR(100)  NULL,
    customer_country         NVARCHAR(100)  NULL,
    region                   NVARCHAR(50)   NULL,
    customer_postal_code     NVARCHAR(50)   NULL,
    payment_method           NVARCHAR(50)   NULL,
    payment_status           NVARCHAR(50)   NULL,
    currency                 NVARCHAR(50)   NULL,
    shipping_method          NVARCHAR(50)   NULL,
    warehouse                NVARCHAR(50)   NULL,
    delivery_days            NVARCHAR(50)   NULL,
    estimated_delivery_days  NVARCHAR(50)   NULL,
    delivery_status          NVARCHAR(50)   NULL,
    return_status            NVARCHAR(50)   NULL,
    return_reason            NVARCHAR(150)  NULL,
    customer_rating          NVARCHAR(50)   NULL,
    review_sentiment         NVARCHAR(50)   NULL,
    customer_review          NVARCHAR(1000) NULL,
    marketing_channel        NVARCHAR(100)  NULL,
    campaign_name            NVARCHAR(150)  NULL,
    coupon_code              NVARCHAR(50)   NULL,
    loyalty_points_earned    NVARCHAR(50)   NULL,
    loyalty_points_redeemed  NVARCHAR(50)   NULL,
    quantity                 NVARCHAR(50)   NULL,
    gross_sales              NVARCHAR(50)   NULL,
    discount_amount          NVARCHAR(50)   NULL,
    tax_amount               NVARCHAR(50)   NULL,
    shipping_cost            NVARCHAR(50)   NULL,
    net_sales                NVARCHAR(50)   NULL,
    product_cost             NVARCHAR(50)   NULL,
    profit                   NVARCHAR(50)   NULL,
    profit_margin_percentage NVARCHAR(50)   NULL,
    customer_lifetime_value  NVARCHAR(50)   NULL,
    is_repeat_customer       NVARCHAR(50)   NULL,
    customer_order_count     NVARCHAR(50)   NULL
);
GO