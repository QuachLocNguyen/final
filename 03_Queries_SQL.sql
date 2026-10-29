/* =====================================================================
   03_Queries_SQL.sql
   HỆ THỐNG TRUY VẤN PHÂN TÍCH KINH DOANH TRÊN DATA WAREHOUSE (EcommerceDW)
   Đáp ứng tiêu chí đánh giá Tiêu chí 5 (Rubric DWH - 15 Điểm)
   Mô hình: Galaxy Schema tinh gọn (8 Dimensions + 7 Fact Tables)
   ===================================================================== */

USE EcommerceDW;
GO

-- =====================================================================
-- PHẦN 1: PHÂN TÍCH BÁN HÀNG & DOANH THU (Fact_Sales)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1: Top 10 ngành hàng (category) và thương hiệu (brand) có biên lợi nhuận (Margin Rate) cao nhất?
-- Ý nghĩa: Giúp bộ phận Merchandising tập trung nguồn vốn vào các sản phẩm đem lại lợi nhuận thực tế lớn nhất.
-- ---------------------------------------------------------------------
WITH CategoryBrandPerformance AS (
    SELECT
        p.category,
        p.brand,
        SUM(fs.quantity) AS total_units_sold,
        SUM(fs.net_revenue) AS total_net_revenue,
        SUM(fs.product_cost) AS total_product_cost,
        SUM(fs.contribution_margin) AS total_contribution_margin,
        ROUND(SUM(fs.contribution_margin) * 100.0 / NULLIF(SUM(fs.net_revenue), 0), 2) AS contribution_margin_pct
    FROM dbo.Fact_Sales fs
    INNER JOIN dbo.Dim_Product p ON fs.product_key = p.product_key
    GROUP BY p.category, p.brand
)
SELECT TOP 10
    category,
    brand,
    total_units_sold,
    total_net_revenue,
    total_contribution_margin,
    contribution_margin_pct,
    DENSE_RANK() OVER (ORDER BY contribution_margin_pct DESC) AS rank_by_margin_rate
FROM CategoryBrandPerformance
WHERE total_net_revenue >= 50000 -- Lọc nhóm có quy mô doanh số đủ lớn
ORDER BY rank_by_margin_rate;
GO

-- ---------------------------------------------------------------------
-- Q2: Tỷ lệ chiết khấu ảnh hưởng như thế nào đến biên đóng góp (Contribution Margin)?
-- Ý nghĩa: Đánh giá xem chiến lược giảm giá có đang "bào mòn" lợi nhuận hay kích cầu hiệu quả.
-- ---------------------------------------------------------------------
SELECT
    CASE 
        WHEN fs.gross_sales = 0 THEN '0% Free'
        WHEN (fs.discount_amount / fs.gross_sales) = 0 THEN '0% Không chiết khấu'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.10 THEN '1% - 10%'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.25 THEN '11% - 25%'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.50 THEN '26% - 50%'
        ELSE '> 50% Xả hàng sâu'
    END AS discount_tier,
    COUNT(DISTINCT fs.order_id) AS total_orders,
    SUM(fs.gross_sales) AS total_gross_sales,
    SUM(fs.discount_amount) AS total_discount_amount,
    SUM(fs.net_revenue) AS total_net_revenue,
    SUM(fs.contribution_margin) AS total_contribution_margin,
    ROUND(SUM(fs.contribution_margin) * 100.0 / NULLIF(SUM(fs.net_revenue), 0), 2) AS margin_rate_pct
FROM dbo.Fact_Sales fs
GROUP BY 
    CASE 
        WHEN fs.gross_sales = 0 THEN '0% Free'
        WHEN (fs.discount_amount / fs.gross_sales) = 0 THEN '0% Không chiết khấu'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.10 THEN '1% - 10%'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.25 THEN '11% - 25%'
        WHEN (fs.discount_amount / fs.gross_sales) <= 0.50 THEN '26% - 50%'
        ELSE '> 50% Xả hàng sâu'
    END
ORDER BY total_net_revenue DESC;
GO

-- ---------------------------------------------------------------------
-- Q3: Phân khúc khách hàng (Segment) và độ tuổi (Age Group) nào đóng góp doanh thu lớn nhất?
-- Ý nghĩa: Định vị chân dung khách hàng mục tiêu để tối ưu chiến lược quảng cáo.
-- ---------------------------------------------------------------------
SELECT
    c.customer_segment,
    c.age_group,
    COUNT(DISTINCT fs.customer_key) AS unique_buyers,
    COUNT(DISTINCT fs.order_id) AS total_orders,
    SUM(fs.net_revenue) AS total_net_revenue,
    ROUND(SUM(fs.net_revenue) * 100.0 / SUM(SUM(fs.net_revenue)) OVER (), 2) AS revenue_share_pct,
    ROUND(SUM(fs.net_revenue) / NULLIF(COUNT(DISTINCT fs.order_id), 0), 2) AS avg_order_value_AOV
FROM dbo.Fact_Sales fs
INNER JOIN dbo.Dim_Customer c ON fs.customer_key = c.customer_key
GROUP BY c.customer_segment, c.age_group
ORDER BY total_net_revenue DESC;
GO

-- ---------------------------------------------------------------------
-- Q4: Xu hướng doanh thu theo Quý/Năm và Mùa vụ (Time Series Analysis)
-- Ý nghĩa: Nhận diện tính chu kỳ và mức tăng trưởng qua từng thời kỳ (Quarter-over-Quarter Growth).
-- ---------------------------------------------------------------------
WITH QuarterlySales AS (
    SELECT
        d.[year],
        d.[quarter],
        d.quarter_name,
        d.season,
        SUM(fs.net_revenue) AS current_net_revenue,
        COUNT(DISTINCT fs.order_id) AS total_orders
    FROM dbo.Fact_Sales fs
    INNER JOIN dbo.Dim_Date d ON fs.date_key = d.date_key
    GROUP BY d.[year], d.[quarter], d.quarter_name, d.season
)
SELECT
    [year],
    quarter_name,
    season,
    current_net_revenue,
    total_orders,
    LAG(current_net_revenue, 1) OVER (ORDER BY [year], [quarter]) AS prev_quarter_revenue,
    ROUND((current_net_revenue - LAG(current_net_revenue, 1) OVER (ORDER BY [year], [quarter])) 
          * 100.0 / NULLIF(LAG(current_net_revenue, 1) OVER (ORDER BY [year], [quarter]), 0), 2) AS qoq_growth_pct
FROM QuarterlySales
ORDER BY [year], [quarter];
GO


-- =====================================================================
-- PHẦN 2: THỰC HIỆN ĐƠN HÀNG & GIAO HÀNG (Fact_Order_Fulfillment)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q5: Kho hàng (Warehouse) & Phương thức vận chuyển nào có tỷ lệ giao trễ (Late Rate) cao nhất?
-- Ý nghĩa: Phát hiện điểm nghẽn (bottleneck) trong chuỗi cung ứng và vận hành kho.
-- ---------------------------------------------------------------------
SELECT
    s.warehouse,
    s.shipping_method,
    s.shipping_speed_category,
    COUNT(fof.order_id) AS total_orders_fulfilled,
    SUM(CAST(fof.late_flag AS INT)) AS late_orders_count,
    ROUND(SUM(CAST(fof.late_flag AS INT)) * 100.0 / NULLIF(COUNT(fof.order_id), 0), 2) AS late_rate_pct,
    ROUND(AVG(CAST(fof.delivery_days AS FLOAT)), 1) AS avg_delivery_days,
    ROUND(AVG(CAST(fof.delivery_variance_days AS FLOAT)), 1) AS avg_variance_days
FROM dbo.Fact_Order_Fulfillment fof
INNER JOIN dbo.Dim_Shipping s ON fof.shipping_key = s.shipping_key
GROUP BY s.warehouse, s.shipping_method, s.shipping_speed_category
ORDER BY late_rate_pct DESC;
GO

-- ---------------------------------------------------------------------
-- Q6: Độ trễ giao hàng trung bình theo từng Quốc gia và Vùng lãnh thổ (Region)
-- Ý nghĩa: Đánh giá chất lượng đối tác vận chuyển tại các thị trường quốc tế.
-- ---------------------------------------------------------------------
SELECT
    r.country,
    r.region,
    COUNT(fof.order_id) AS total_orders,
    ROUND(AVG(CAST(fof.delivery_days AS FLOAT)), 2) AS avg_actual_delivery_days,
    ROUND(AVG(CAST(fof.estimated_delivery_days AS FLOAT)), 2) AS avg_estimated_delivery_days,
    ROUND(AVG(CAST(fof.delivery_variance_days AS FLOAT)), 2) AS avg_variance_days,
    SUM(fof.shipping_cost) AS total_shipping_cost,
    ROUND(SUM(fof.shipping_cost) / NULLIF(SUM(fof.order_net_revenue), 0) * 100.0, 2) AS shipping_burden_rate_pct
FROM dbo.Fact_Order_Fulfillment fof
INNER JOIN dbo.Dim_Region r ON fof.region_key = r.region_key
GROUP BY r.country, r.region
ORDER BY avg_variance_days DESC;
GO


-- =====================================================================
-- PHẦN 3: PHÂN TÍCH TRẢ HÀNG & THIỆT HẠI LỢI NHUẬN (Fact_Return)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q7: Nhóm nguyên nhân trả hàng (Return Reason Category) gây thiệt hại lớn nhất?
-- Ý nghĩa: Tìm nguyên nhân cốt lõi (chất lượng sản phẩm hay lỗi vận chuyển) để cải tiến.
-- ---------------------------------------------------------------------
SELECT
    rp.return_reason_category,
    rp.return_reason,
    COUNT(fr.order_id) AS total_returned_orders,
    SUM(fr.returned_net_revenue) AS total_lost_revenue,
    SUM(fr.return_margin_impact) AS total_lost_margin,
    ROUND(SUM(fr.returned_net_revenue) * 100.0 / SUM(SUM(fr.returned_net_revenue)) OVER (), 2) AS share_of_lost_revenue_pct
FROM dbo.Fact_Return fr
INNER JOIN dbo.Dim_Return_Profile rp ON fr.return_profile_key = rp.return_profile_key
GROUP BY rp.return_reason_category, rp.return_reason
ORDER BY total_lost_margin DESC;
GO

-- ---------------------------------------------------------------------
-- Q8: Tỷ lệ trả hàng (Return Rate) đối chiếu giữa Fact_Return và Fact_Sales
-- Ý nghĩa: Drill-across giữa 2 bảng Fact thông qua chiều dùng chung (Dim_Region).
-- ---------------------------------------------------------------------
WITH SalesSummary AS (
    SELECT
        r.country,
        COUNT(DISTINCT fs.order_id) AS total_sales_orders,
        SUM(fs.net_revenue) AS total_sales_revenue
    FROM dbo.Fact_Sales fs
    INNER JOIN dbo.Dim_Region r ON fs.region_key = r.region_key
    GROUP BY r.country
),
ReturnSummary AS (
    SELECT
        r.country,
        COUNT(fr.order_id) AS total_return_orders,
        SUM(fr.returned_net_revenue) AS total_return_revenue
    FROM dbo.Fact_Return fr
    INNER JOIN dbo.Dim_Region r ON fr.region_key = r.region_key
    GROUP BY r.country
)
SELECT
    s.country,
    s.total_sales_orders,
    ISNULL(ret.total_return_orders, 0) AS total_return_orders,
    ROUND(ISNULL(ret.total_return_orders, 0) * 100.0 / NULLIF(s.total_sales_orders, 0), 2) AS return_order_rate_pct,
    s.total_sales_revenue,
    ISNULL(ret.total_return_revenue, 0) AS total_return_revenue,
    ROUND(ISNULL(ret.total_return_revenue, 0) * 100.0 / NULLIF(s.total_sales_revenue, 0), 2) AS return_value_rate_pct
FROM SalesSummary s
LEFT JOIN ReturnSummary ret ON s.country = ret.country
ORDER BY return_order_rate_pct DESC;
GO


-- =====================================================================
-- PHẦN 4: ĐÁNH GIÁ & CẢM XÚC KHÁCH HÀNG (Fact_Customer_Feedback)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q9: Giao hàng trễ có làm điểm đánh giá (Rating) sụt giảm nghiêm trọng không?
-- Ý nghĩa: Kiểm chứng giả thuyết tác động của chất lượng dịch vụ vận chuyển đến sự hài lòng của khách hàng.
-- ---------------------------------------------------------------------
SELECT
    op.delivery_status,
    COUNT(fcf.order_id) AS total_reviews,
    ROUND(AVG(fcf.rating_value), 2) AS avg_rating_score,
    SUM(CAST(fcf.is_negative_flag AS INT)) AS negative_review_count,
    ROUND(SUM(CAST(fcf.is_negative_flag AS INT)) * 100.0 / NULLIF(COUNT(fcf.order_id), 0), 2) AS negative_rate_pct,
    ROUND(AVG(CAST(fcf.review_length AS FLOAT)), 0) AS avg_review_char_length
FROM dbo.Fact_Customer_Feedback fcf
INNER JOIN dbo.Dim_Order_Profile op ON fcf.order_profile_key = op.order_profile_key
GROUP BY op.delivery_status
ORDER BY avg_rating_score DESC;
GO

-- ---------------------------------------------------------------------
-- Q10: Phân bổ cảm xúc đánh giá (Sentiment) theo Kênh bán hàng (Sales Channel)
-- Ý nghĩa: So sánh trải nghiệm mua sắm trên Website, Mobile App và Sàn thương mại điện tử.
-- ---------------------------------------------------------------------
SELECT
    op.sales_channel,
    fcf.review_sentiment,
    COUNT(fcf.order_id) AS review_count,
    ROUND(COUNT(fcf.order_id) * 100.0 / SUM(COUNT(fcf.order_id)) OVER (PARTITION BY op.sales_channel), 2) AS sentiment_pct_within_channel,
    ROUND(AVG(fcf.rating_value), 2) AS avg_rating
FROM dbo.Fact_Customer_Feedback fcf
INNER JOIN dbo.Dim_Order_Profile op ON fcf.order_profile_key = op.order_profile_key
WHERE fcf.review_sentiment IS NOT NULL
GROUP BY op.sales_channel, fcf.review_sentiment
ORDER BY op.sales_channel, avg_rating DESC;
GO


-- =====================================================================
-- PHẦN 5: CHI PHÍ THU HÚT KHÁCH HÀNG MỚI (Fact_Customer_Acquisition)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q11: Kênh tiếp thị nào thu hút khách hàng mới với chi phí CAC thấp nhất?
-- Ý nghĩa: Tối ưu ngân sách Marketing (đo lường CAC và giá trị đơn hàng đầu tiên).
-- ---------------------------------------------------------------------
SELECT
    mc.marketing_channel,
    mc.channel_type,
    COUNT(fca.customer_key) AS new_customers_acquired,
    ROUND(AVG(fca.customer_acquisition_cost), 2) AS avg_cac,
    ROUND(AVG(fca.first_order_net_revenue), 2) AS avg_first_order_revenue,
    ROUND(AVG(fca.first_order_net_revenue) / NULLIF(AVG(fca.customer_acquisition_cost), 0), 2) AS first_order_payback_ratio
FROM dbo.Fact_Customer_Acquisition fca
INNER JOIN dbo.Dim_Marketing_Campaign mc ON fca.marketing_key = mc.marketing_key
GROUP BY mc.marketing_channel, mc.channel_type
ORDER BY avg_cac ASC;
GO


-- =====================================================================
-- PHẦN 6: SNAPSHOT GIÁ TRỊ VÀ HÀNH VI KHÁCH HÀNG (Fact_Customer_Snapshot)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q12: Tỷ lệ khách hàng rời bỏ (Churn Risk - Ngừng mua trên 90 ngày) tại thời điểm gần nhất
-- Ý nghĩa: Cảnh báo sớm tỷ lệ attrition để lên chiến dịch kích hoạt lại (retention campaign).
-- ---------------------------------------------------------------------
WITH LatestSnapshotDate AS (
    SELECT MAX(snapshot_date_key) AS max_date_key FROM dbo.Fact_Customer_Snapshot
)
SELECT
    fcs.loyalty_tier,
    COUNT(fcs.customer_key) AS total_customers_at_snapshot,
    SUM(CAST(fcs.active_90d_flag AS INT)) AS active_customers,
    COUNT(fcs.customer_key) - SUM(CAST(fcs.active_90d_flag AS INT)) AS churn_risk_customers,
    ROUND((COUNT(fcs.customer_key) - SUM(CAST(fcs.active_90d_flag AS INT))) * 100.0 / NULLIF(COUNT(fcs.customer_key), 0), 2) AS churn_risk_pct,
    ROUND(AVG(CAST(fcs.days_since_last_order AS FLOAT)), 0) AS avg_days_since_last_purchase
FROM dbo.Fact_Customer_Snapshot fcs
INNER JOIN LatestSnapshotDate lsd ON fcs.snapshot_date_key = lsd.max_date_key
GROUP BY fcs.loyalty_tier
ORDER BY total_customers_at_snapshot DESC;
GO

-- ---------------------------------------------------------------------
-- Q13: Phân tích phân bổ RFM Score và Doanh thu tích lũy trung bình
-- Ý nghĩa: Đánh giá chất lượng tệp khách hàng theo mô hình RFM chuẩn quốc tế.
-- ---------------------------------------------------------------------
WITH LatestSnapshotDate AS (
    SELECT MAX(snapshot_date_key) AS max_date_key FROM dbo.Fact_Customer_Snapshot
)
SELECT
    fcs.rfm_score,
    COUNT(fcs.customer_key) AS customer_count,
    ROUND(COUNT(fcs.customer_key) * 100.0 / SUM(COUNT(fcs.customer_key)) OVER (), 2) AS customer_share_pct,
    ROUND(AVG(fcs.cumulative_net_revenue), 2) AS avg_cumulative_revenue,
    ROUND(AVG(CAST(fcs.cumulative_order_count AS FLOAT)), 1) AS avg_cumulative_orders,
    ROUND(AVG(CAST(fcs.cumulative_points_earned AS FLOAT)), 0) AS avg_points_earned
FROM dbo.Fact_Customer_Snapshot fcs
INNER JOIN LatestSnapshotDate lsd ON fcs.snapshot_date_key = lsd.max_date_key
GROUP BY fcs.rfm_score
ORDER BY fcs.rfm_score DESC;
GO


-- =====================================================================
-- PHẦN 7: KHUYẾN MÃI & CHIẾN DỊCH TIẾP THỊ (Fact_Campaign_Promotion)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q14: Hiệu quả của các Chiến dịch khuyến mãi (Campaign) về Doanh thu và Chiết khấu
-- Ý nghĩa: Xác định chiến dịch tiếp thị mang lại ROI và doanh số thực tế cao nhất.
-- ---------------------------------------------------------------------
SELECT
    mc.campaign_name,
    mc.marketing_channel,
    COUNT(fcp.order_id) AS total_promotional_orders,
    SUM(fcp.gross_sales) AS total_gross_sales,
    SUM(fcp.discount_amount) AS total_discount_given,
    SUM(fcp.net_revenue) AS total_net_revenue,
    ROUND(SUM(fcp.discount_amount) * 100.0 / NULLIF(SUM(fcp.gross_sales), 0), 2) AS effective_discount_rate_pct
FROM dbo.Fact_Campaign_Promotion fcp
INNER JOIN dbo.Dim_Marketing_Campaign mc ON fcp.marketing_key = mc.marketing_key
WHERE mc.campaign_name IS NOT NULL
GROUP BY mc.campaign_name, mc.marketing_channel
ORDER BY total_net_revenue DESC;
GO

-- ---------------------------------------------------------------------
-- Q15: Đơn hàng có áp dụng mã Coupon vs Đơn hàng không áp mã: So sánh AOV
-- Ý nghĩa: Kiểm tra liệu khách hàng có mua nhiều hơn khi được cung cấp mã giảm giá hay không.
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN fcp.is_coupon_order = 1 THEN 'Có áp mã Coupon' ELSE 'Không áp mã (Giá chuẩn/Sale sàn)' END AS coupon_usage_group,
    COUNT(fcp.order_id) AS total_orders,
    SUM(fcp.net_revenue) AS total_net_revenue,
    ROUND(AVG(fcp.net_revenue), 2) AS avg_order_value_aov,
    ROUND(AVG(fcp.discount_amount), 2) AS avg_discount_per_order,
    ROUND(AVG(fcp.discount_rate) * 100.0, 2) AS avg_discount_pct
FROM dbo.Fact_Campaign_Promotion fcp
GROUP BY fcp.is_coupon_order;
GO

PRINT 'Hoàn tất thực thi 15 câu hỏi phân tích SQL chuyên sâu trên EcommerceDW!';
GO

