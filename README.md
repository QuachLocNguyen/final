# DỰ ÁN KHO DỮ LIỆU THƯƠNG MẠI ĐIỆN TỬ (ECOMMERCE DATA WAREHOUSE)

* **Môn học:** Kho dữ liệu & Hệ thống hỗ trợ ra quyết định (Data Warehouse & DSS)
* **Đề tài:** Xây dựng Data Warehouse & Khối phân tích OLAP cho dữ liệu Bán hàng & Hành vi Khách hàng Thương mại Điện tử (E-Commerce Sales Analytics)
* **Nền tảng công nghệ:** Microsoft SQL Server, SQL Server Integration Services (SSIS), SQL Server Analysis Services (SSAS), T-SQL, MDX.
* **Tập dữ liệu nguồn:** Kaggle E-Commerce Dataset (138.116 đơn hàng, 397.569 chi tiết dòng hàng, 25.000 khách hàng, 1.175 sản phẩm; giai đoạn 2021 – 2025).

---

## 📌 BÁO CÁO TIẾN ĐỘ THỰC HIỆN (CẬP NHẬT: 29/10/2026)

### ✅ ĐÃ HOÀN THÀNH TOÀN DIỆN (CSDL, PIPELINE ETL & 15 TRUY VẤN SQL)

#### 1. Thiết kế Mô hình Kho dữ liệu & Cơ sở dữ liệu (Database Design)
- [x] **Khảo sát dữ liệu nguồn:** Phân tích độ dài, kiểu dữ liệu, các giá trị phân biệt (distinct values) và tính toàn vẹn tham chiếu của 4 file CSV.
- [x] **Mô hình DWH chuẩn Kimball:** Xây dựng mô hình **Galaxy Schema kết hợp Star Schema (8 Dimensions + 7 Fact Tables)**:
  - Khử chuẩn hóa (Denormalization) cho `Dim_Product` và `Dim_Customer` để loại bỏ các bảng 2 cột vô nghĩa, tăng tốc truy vấn JOIN.
  - Áp dụng kỹ thuật **Junk Dimension** cho `Dim_Order_Profile` (gom 5 cờ trạng thái nhỏ lẻ), giảm 4 khóa ngoại trong `Fact_Sales`.
  - Phân loại rõ ràng 7 Fact: 3 Core Facts (`Fact_Sales`, `Fact_Order_Fulfillment`, `Fact_Return`) và 4 Strategic Facts (`Fact_Customer_Feedback`, `Fact_Customer_Acquisition`, `Fact_Customer_Snapshot`, `Fact_Campaign_Promotion`).
- [x] **Tạo CSDL & Vùng đệm Staging:**
  - `00_Create_Staging_Tables.sql`: Tạo 4 bảng Staging (`stg_sales_full`, `stg_order_items`, `stg_product_catalog`, `stg_customer_master`) hỗ trợ nạp thô an toàn.
  - `01_Create_EcommerceDW_v2.sql`: Tạo cấu trúc chuẩn 8 Dim + 7 Fact, khóa chính, khóa ngoại, ràng buộc toàn vẹn và tạo Non-Clustered Indexes tối ưu.

---

#### 2. Xây dựng & Thực thi Pipeline ETL (Nạp sạch 100% DWH)
Toàn bộ luồng ETL đã được triển khai hoàn chỉnh trên Visual Studio (SSIS Package) và Master T-SQL Script (`ETL.sql`), nạp thành công hơn 800.000 dòng dữ liệu vào CSDL `EcommerceDW`:

- [x] **Giai đoạn 1 (Prepare Staging):** Truncate 4 bảng staging trước mỗi mẻ chạy.
- [x] **Giai đoạn 2 (Extract CSV To Staging):** Nạp sạch 4 file CSV vào 4 bảng staging.
- [x] **Giai đoạn 3 (Transform & Load 8 Dimensions):**
  1. `Dim_Date`: 2.191 dòng (2021-2026), tính quý, mùa vụ, cờ cuối tháng.
  2. `Dim_Product`: 1.175 dòng, đầy đủ ngành hàng (`category`), nhóm hàng (`subcategory`), thương hiệu (`brand`), `price_tier`, `rating_group`.
  3. `Dim_Customer`: 25.000 khách hàng, phân nhóm `age_group`, `customer_segment`.
  4. `Dim_Region`: 38 vùng/bang duy nhất trên toàn cầu.
  5. `Dim_Shipping`: 76 tổ hợp phương thức giao hàng và kho bãi, phân nhóm tốc độ giao (`shipping_speed_category`).
  6. `Dim_Order_Profile`: 308 tổ hợp trạng thái đơn hàng (Junk Dimension).
  7. `Dim_Marketing_Campaign`: 1.260 chiến dịch tiếp thị và mã coupon, phân nhóm `channel_type`.
  8. `Dim_Return_Profile`: 8 tổ hợp lý do hoàn trả và phân loại nguyên nhân (`return_reason_category`).
- [x] **Giai đoạn 4 (Transform & Load 7 Fact Tables):**
  1. `Fact_Sales`: 397.482 dòng (Doanh thu thuần: 192.370.085,82 USD).
  2. `Fact_Order_Fulfillment`: 113.559 dòng (Role-playing Dimension 3 mốc ngày).
  3. `Fact_Return`: 9.462 đơn hoàn trả.
  4. `Fact_Customer_Feedback`: 113.559 lượt đánh giá & chỉ số sentiment.
  5. `Fact_Customer_Acquisition`: 24.911 khách hàng có đơn hàng đầu tiên và chi phí CAC.
  6. `Fact_Campaign_Promotion`: 14.986 đơn hàng áp dụng mã khuyến mại.
  7. `Fact_Customer_Snapshot`: 131.716 snapshot khách hàng qua từng tháng, điểm RFM và hạng thành viên.

---

#### 3. Bộ 15 Câu truy vấn Phân tích Kinh doanh SQL
- [x] `03_Queries_SQL.sql`: Đã hoàn thiện và kiểm tra chạy thành công 100% trên `EcommerceDW`, đáp ứng trọn vẹn 15 bài toán nghiệp vụ theo Rubric Tiêu chí 5.

---

### 🔄 TIẾN ĐỘ THỰC HIỆN HIỆN TẠI (ĐANG TRIỂN KHAI)

**Xây dựng Khối phân tích SSAS OLAP Cube (Visual Studio 2022 theo giáo trình `Lab_SSAS.pdf`):**
- [x] Khởi tạo dự án mới: `final/SSAS_OLAP_Project/Cube/`.
- [x] Tạo **Data Source** kết nối tới `.\SQLEXPRESS` CSDL `EcommerceDW` (Service Account impersonation).
- [x] Tạo **Data Source View (DSV)** chọn 8 Dim + Fact_Sales, chuẩn hóa FriendlyName (loại bỏ tiền tố `Fact_`, `Dim_`).
- [x] Cấu hình **`Date.dim`**: Đổi thuộc tính Attribute Type sang Date/Calendar và thiết lập cây phân cấp **`Calendar`** (`Year` -> `Quarter Name` -> `Month Name` -> `Full Date`), cấu hình Attribute Relationships.
- [ ] Tiếp tục cấu hình 7 Dimensions còn lại (`Product`, `Region`, `Marketing Campaign`, `Customer`, `Shipping`, `Order Profile`, `Return Profile`) cùng các phân cấp nghiệp vụ.
- [ ] Xây dựng Cube (`Sales.cube`), cấu hình Measure Groups, Bus Matrix (Dimension Usage) và Calculated Members (Margin Rate, AOV, Discount Rate).
- [ ] Deploy, Process và kiểm tra duyệt khối dữ liệu (Cube Browser trong Visual Studio / Excel PivotTable).

---

### 📋 KẾ HOẠCH BƯỚC TIẾP THEO (NEXT STEPS)

1. **Xây dựng bộ truy vấn đa chiều MDX (`04_Queries_MDX.mdx`):**
   - Viết 15 câu truy vấn MDX đối chiếu trực tiếp với 15 câu SQL sau khi hoàn tất khối Cube.
2. **Đóng gói sản phẩm & Báo cáo cuối kỳ:**
   - Chụp ảnh kết quả chạy ETL (tất cả task xanh).
   - Chụp ảnh duyệt khối đa chiều (Cube Browser / Excel PivotTable) minh họa cho Chương 4.
   - Hoàn thiện Báo cáo Word/PDF và Slide thuyết trình bảo vệ trước giảng viên.

---

## 📂 DANH MỤC TÀI LIỆU VÀ MÃ NGUỒN TRONG THƯ MỤC

| Tên File / Thư mục | Vai trò & Mô tả | Trạng thái |
|---|---|---|
| [`ETL.sql`](ETL.sql) | Master script T-SQL thực thi trọn vẹn 5 giai đoạn ETL | ✅ Đã kiểm thử & chạy thành công |
| [`00_Create_Staging_Tables.sql`](00_Create_Staging_Tables.sql) | DDL tạo 4 bảng Staging vùng đệm (`stg_*`) | ✅ Hoàn thành |
| [`01_Create_EcommerceDW_v2.sql`](01_Create_EcommerceDW_v2.sql) | DDL tạo CSDL DWH chuẩn 8 Dim + 7 Fact | ✅ Hoàn thành |
| [`02_ETL_EcommerceDW_v2.sql`](02_ETL_EcommerceDW_v2.sql) | Script ETL đối chiếu nguyên bản | ✅ Hoàn thành |
| [`03_Queries_SQL.sql`](03_Queries_SQL.sql) | Bộ 15 câu truy vấn phân tích kinh doanh chuẩn Rubric | ✅ Đã kiểm thử 100% |
| `04_Queries_MDX.mdx` | Bộ truy vấn đa chiều MDX trên SSAS Cube | ⏳ Đang xây dựng theo tiến độ Cube |
| `SSAS_OLAP_Project/` | Thư mục chứa Solution SSAS Multidimensional Cube | 🔄 Đang triển khai thiết kế |
| [`OUTLINE_DU_AN_DWH.txt`](OUTLINE_DU_AN_DWH.txt) | Đề cương chi tiết đối chiếu 6 tiêu chí Rubric đồ án | ✅ Đầy đủ |
| [`Bao_Cao_Tien_Do_EcommerceDW_v2.docx`](Bao_Cao_Tien_Do_EcommerceDW_v2.docx) | Bản nháp báo cáo tiến độ môn học | ✅ Đầy đủ |
| `du_lieu_csv/` | 4 file dữ liệu nguồn Kaggle | ✅ Đầy đủ |
| `tai_lieu_tham_khao/` | Giáo trình `Lab_SSAS.pdf`, Rubric, Báo cáo mẫu | ✅ Đầy đủ |

---

*Ghi chú: Toàn bộ quá trình thiết kế và hiện thực đều bám sát theo Rubric đánh giá đồ án môn học (thang điểm 100/100, chuẩn đầu ra Q1-Q4).*
