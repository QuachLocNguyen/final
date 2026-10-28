# DỰ ÁN KHO DỮ LIỆU THƯƠNG MẠI ĐIỆN TỬ (ECOMMERCE DATA WAREHOUSE)

* **Môn học:** Kho dữ liệu & Hệ thống hỗ trợ ra quyết định (Data Warehouse & DSS)
* **Đề tài:** Xây dựng Data Warehouse & Khối phân tích OLAP cho dữ liệu Bán hàng & Hành vi Khách hàng Thương mại Điện tử (E-Commerce Sales Analytics)
* **Nền tảng công nghệ:** Microsoft SQL Server, SQL Server Integration Services (SSIS), SQL Server Analysis Services (SSAS), T-SQL, MDX.
* **Tập dữ liệu nguồn:** Kaggle E-Commerce Dataset (138.116 đơn hàng, 397.569 chi tiết dòng hàng, 25.000 khách hàng, 1.175 sản phẩm; giai đoạn 2021 – 2025).

---

## 📌 BÁO CÁO TIẾN ĐỘ THỰC HIỆN (CẬP NHẬT: 27/10/2026)

### ✅ ĐÃ HOÀN THÀNH (TỪ THIẾT KẾ CSDL ĐẾN SEQUENCE CONTAINER 3 SSIS)

#### 1. Thiết kế Mô hình Kho dữ liệu & Cơ sở dữ liệu (Database Design)
- [x] **Khảo sát dữ liệu nguồn:** Phân tích độ dài, kiểu dữ liệu, các giá trị phân biệt (distinct values) và tính toàn vẹn tham chiếu của 4 file CSV.
- [x] **Mô hình DWH chuẩn Kimball:** Xây dựng mô hình **Galaxy Schema kết hợp Star Schema (8 Dimensions + 7 Fact Tables)**:
  - Khử chuẩn hóa (Denormalization) cho `Dim_Product` và `Dim_Customer` để loại bỏ các bảng 2 cột vô nghĩa (Category, Brand, Segment), giúp tăng tốc độ truy vấn JOIN.
  - Áp dụng kỹ thuật **Junk Dimension** cho `Dim_Order_Profile` (gom 5 cờ trạng thái nhỏ lẻ), giúp giảm 4 khóa ngoại trong `Fact_Sales`.
  - Phân loại rõ ràng 7 Fact: 3 Core Facts (`Fact_Sales`, `Fact_Order_Fulfillment`, `Fact_Return`) và 4 Strategic Facts (`Fact_Customer_Feedback`, `Fact_Customer_Acquisition`, `Fact_Customer_Snapshot`, `Fact_Campaign_Promotion`).
- [x] **Tạo CSDL & Vùng đệm Staging:**
  - `00_Create_Staging_Tables.sql`: Tạo 4 bảng Staging (`stg_sales_full`, `stg_order_items`, `stg_product_catalog`, `stg_customer_master`) với kiểu dữ liệu `NVARCHAR` rộng rãi, hỗ trợ nạp thô an toàn, không lỗi ép kiểu.
  - `01_Create_EcommerceDW_v2.sql`: Tạo cấu trúc 8 Dim + 7 Fact, khóa chính, khóa ngoại, kiểm tra toàn vẹn và tạo Non-Clustered Indexes tối ưu hiệu năng.

---

#### 2. Xây dựng Pipeline ETL trên Visual Studio (SSIS Package)
Đã triển khai thành công **3 Sequence Containers** đầu tiên trong file SSIS Package:

- [x] **Sequence Container 1: `01_Prepare_Staging`**
  - Sử dụng **Execute SQL Task** chạy `TRUNCATE TABLE` 4 bảng staging trước mỗi mẻ chạy, đảm bảo dữ liệu trung chuyển không bị trùng lặp (duplicate).
- [x] **Sequence Container 2: `02_Extract_CSV_To_Staging`**
  - Thiết lập 4 luồng **Data Flow Task** nạp từ Flat File CSV vào 4 bảng Staging:
    - Cấu hình tùy chọn *"Retain null values from the source as null values"* tại Flat File Source.
    - Cấu hình *"Keep nulls"* tại OLE DB Destination.
- [x] **Sequence Container 3: `03_Transform_And_Load_Dimensions`**
  - Hoàn tất nạp sạch toàn bộ **8 bảng Chiều (Dimensions)**:
    1. **`SQL_Load_Dim_Date`**: Dùng Execute SQL Task sinh chuỗi ngày tự động bằng CTE (2021-2026), tính quý, mùa vụ, cờ cuối tháng.
    2. **`DFT_Load_Dim_Product`**: Nạp từ `stg_product_catalog`, dùng **Derived Column** tính `price_tier` (`Budget`, `Mid-Range`, `Premium`, `Luxury`) và `rating_group` (`Low`, `Average`, `High`). Bỏ qua khóa IDENTITY `product_key`.
    3. **`DFT_Load_Dim_Customer`**: Nạp từ `stg_customer_master` + tổng hợp `customer_type` từ sales, dùng **Derived Column** tính `age_group` (`18-25`, `26-35`, `36-50`, `50+`).
    4. **`DFT_Load_Dim_Region`**: Trích xuất tổ hợp duy nhất `region`, `[state]`, `country`.
    5. **`DFT_Load_Dim_Shipping`**: Trích xuất tổ hợp `shipping_method`, `warehouse`, tính `shipping_speed_category` (`Fast`, `Standard`, `Economy`).
    6. **`DFT_Load_Dim_Order_Profile`**: Nạp Junk Dimension gom 5 thuộc tính trạng thái.
    7. **`DFT_Load_Dim_Marketing_Campaign`**: Trích xuất kênh tiếp thị, chiến dịch, mã coupon, tính `has_coupon_flag` và `channel_type` (`Paid Media`, `Owned Media`, `Organic Media`).
    8. **`DFT_Load_Dim_Return_Profile`**: Nạp trạng thái và lý do hoàn trả, phân nhóm `return_reason_category` (`Product Quality Issue`, `Logistics Issue`, `Customer Choice Issue`).
- [x] **Xử lý các vấn đề kỹ thuật phát sinh:**
  - Giải quyết lỗi thiếu bảng Staging (`Invalid object name 'dbo.stg_sales_full'`).
  - Giải quyết lỗi lệch kiểu dữ liệu trong SSIS Lookup (`Cannot map input column to lookup column because data types do not match` giữa `DT_WSTR` và `DT_STR`).

---

### 📋 KẾ HOẠCH BƯỚC TIẾP THEO (NEXT STEPS / TODO)

1. **Hoàn thành Sequence Container 4: `04_Load_Fact_Tables` trong SSIS:**
   - [ ] `DFT_Load_Fact_Sales`: Sử dụng Lookup Transformations tra cứu khóa thay thế từ `Dim_Product` và `Dim_Customer`, tính toán `contribution_margin`.
   - [ ] `DFT_Load_Fact_Order_Fulfillment`: Role-playing Dimension `Dim_Date` (3 mốc ngày: Ngày đặt, Ngày dự kiến, Ngày giao thực tế).
   - [ ] `DFT_Load_Fact_Return`: Nạp các đơn hàng hoàn trả (Grain: `order_id`).
   - [ ] `DFT_Load_Fact_Customer_Feedback`: Nạp đánh giá, điểm rating và phân tích sentiment.
   - [ ] `DFT_Load_Fact_Customer_Acquisition`: Nạp đơn đầu tiên và chi phí thu hút khách hàng (CAC).
   - [ ] `DFT_Load_Fact_Customer_Snapshot`: Tính toán lũy kế tháng, ngày mua gần nhất, điểm RFM và hạng thành viên (`loyalty_tier`).
   - [ ] `DFT_Load_Fact_Campaign_Promotion`: Nạp đơn áp mã coupon và ROI chiến dịch.
2. **Xây dựng Khối phân tích OLAP Cube trên SSAS (Visual Studio):**
   - [ ] Tạo Data Source & Data Source View (DSV).
   - [ ] Cấu hình 8 Dimensions, Attribute Relationships và Hierarchies phân cấp.
   - [ ] Cấu hình Cube với 7 Measure Groups, Dimension Usage (Bus Matrix) và các MDX Calculated Members.
3. **Thực thi truy vấn phân tích & Đối soát:**
   - [ ] Chạy bộ 15 truy vấn SQL kinh doanh trong `03_Queries_SQL.sql`.
   - [ ] Chạy bộ truy vấn đa chiều MDX trong `04_Queries_MDX.mdx`.
4. **Đóng gói sản phẩm nộp bài:**
   - [ ] Chụp ảnh Control Flow & Data Flow SSIS (tất cả task đều tích xanh).
   - [ ] Chụp ảnh giao diện duyệt khối Cube Browser trên SSAS.
   - [ ] Hoàn thiện file Báo cáo Word/PDF và Slide thuyết trình.

---

## 📂 DANH MỤC TÀI LIỆU VÀ MÃ NGUỒN TRONG THƯ MỤC

| Tên File | Vai trò & Mô tả | Trạng thái |
|---|---|---|
| [`00_Create_Staging_Tables.sql`](00_Create_Staging_Tables.sql) | DDL tạo 4 bảng Staging vùng đệm (`stg_*`) | ✅ Hoàn thành |
| [`01_Create_EcommerceDW_v2.sql`](01_Create_EcommerceDW_v2.sql) | DDL tạo CSDL DWH chuẩn 8 Dim + 7 Fact | ✅ Hoàn thành |
| [`02_ETL_EcommerceDW_v2.sql`](02_ETL_EcommerceDW_v2.sql) | Pipeline ETL hoàn chỉnh viết bằng T-SQL thuần | ✅ Hoàn thành |
| [`03_Queries_SQL.sql`](03_Queries_SQL.sql) | Bộ 15 câu truy vấn phân tích kinh doanh cao cấp | ✅ Hoàn thành |
| [`04_Queries_MDX.mdx`](04_Queries_MDX.mdx) | Bộ truy vấn đa chiều MDX trên SSAS Cube | ✅ Hoàn thành |
| [`OUTLINE_DU_AN_DWH.txt`](OUTLINE_DU_AN_DWH.txt) | Đề cương chi tiết đối chiếu 6 tiêu chí Rubric đồ án | ✅ Hoàn thành |
| `du_lieu_csv/` | Thư mục chứa 4 file dữ liệu nguồn Kaggle | ✅ Đầy đủ |
| `tai_lieu_tham_khao/` | Slide bài giảng, Rubric đánh giá, sách Kimball | ✅ Đầy đủ |

---

*Ghi chú: Toàn bộ quá trình thiết kế và hiện thực đều bám sát theo Rubric đánh giá đồ án môn học (thang điểm 100/100, chuẩn đầu ra Q1-Q4).*

