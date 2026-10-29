# WORKSPACE RULES & CODING POLICY

## Quy tắc thực thi và tương tác hệ thống (Execution & Modification Policy)

1. **Tuyệt đối không tự ý tùy chỉnh hay can thiệp trực tiếp vào hệ thống:**
   - Trợ lý AI không được tự ý thực thi các lệnh DDL, DML can thiệp vào cơ sở dữ liệu hoặc tự động chỉnh sửa các tệp dự án (SSIS, SSAS, Solution Visual Studio) trừ khi được chỉ định rõ ràng.

2. **Chế độ Review và Hướng dẫn (Review-First, User Executes):**
   - Trợ lý AI chỉ đưa ra các nhận xét, phân tích, đánh giá (Review), giải thích và cung cấp đoạn code / kịch bản mẫu rõ ràng.
   - **Người dùng (USER) là người trực tiếp kiểm tra (Review) và tự tay thực thi mã nguồn** trên các công cụ như SQL Server Management Studio (SSMS), Visual Studio hoặc PowerShell.

3. **Bảo toàn cấu trúc chuẩn của Kho dữ liệu:**
   - Giữ nguyên cấu trúc chuẩn 8 Dimensions + 7 Facts theo tài liệu `Lab_SSAS.pdf`, `ETL.sql` và Rubric đồ án.

## Operating Standards & Execution Ladder

### 1. Execution Ladder (Proportional Effort)
- **Tier 1 (1-2 files, <20 LOC):** Direct edit -> test/verify -> ship. No plans or subagent overhead.
- **Tier 2 (3-8 files / new feature):** State brief plan, trace symbol impact, run tests, verify reachability.
- **Tier 3 (>8 files / architecture / DB schema):** Stop and grill design first with user (`/plan`), execute in vertical slices.

### 2. Truth & Anti-Cheating Invariants
- **VERIFY BEFORE CLAIMING:** Always run checks via `run_command` or inspect real files before declaring success. Never guess or assume.
- **IMMUTABLE TEST INVARIANT:** When a test fails, modify the SOURCE CODE, never the test assertions. Do not weaken tests or add skip flags to pass.
- **CALL-GRAPH REACHABILITY:** After adding a new function/module, verify it is actually imported and called by entry points. 0 callers = unwired.
- **NO SILENT FAILURES:** Do not suppress stderr or ignore non-zero exit codes.

### 3. Communication & Context Economy
- **BREVITY:** Keep answers concise and direct (under 4 lines unless detailed explanation is explicitly asked). Avoid fluff, generic pleasantries, and unsolicited summaries.
- **CODE REFERENCES:** Use clickable links in format: `[filename](file:///path/to/file#L10-L20)`.
- **ENVIRONMENT:** Running on Windows (PowerShell). Use platform-compatible commands.
