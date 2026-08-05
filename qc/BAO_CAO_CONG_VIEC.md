# BÁO CÁO CÔNG VIỆC — Dự án Phiếu Chứng Nhận Chất Lượng (MTC)

**Hệ thống:** Salesforce — sandbox `hpdqDev`
**Phạm vi:** Xây dựng màn hình lập & in Phiếu Chứng Nhận Chất Lượng / Mill Test Certificate cho thép cuộn cán nóng, lấy số liệu thí nghiệm từ hệ thống BK.
**Kỳ báo cáo:** 29/07/2026 – 03/08/2026
**Tổng thời lượng:** 30 giờ (28 h đã hoàn thành + 2 h sáng 03/08 đang thực hiện)

| Ngày | Thứ | Thời lượng |
|---|---|---|
| 29/07/2026 | Tư | 8,0 h |
| 30/07/2026 | Năm | 8,0 h |
| 31/07/2026 | Sáu | 8,0 h |
| 01/08/2026 | Bảy | 4,0 h (nửa ngày) |
| 03/08/2026 | Hai | 2,0 h — *đang thực hiện* |

---

## 1. Danh sách công việc

### Ngày 29/07/2026 (thứ Tư) — 8,0 h

| # | Tên task | Mô tả | Thời lượng |
|---|---|---|---|
| 1 | Dựng môi trường xem trước cục bộ | Tạo bộ `preview/` (`qc-preview.html`, `build-preview.ps1`, thư viện SLDS, `gradeStandards.js`, `logos.js`) để dựng lại toàn bộ màn hình bằng dữ liệu giả — sửa giao diện và kiểm tra ngay trên máy, không phải deploy lên org mỗi lần. Rút ngắn đáng kể vòng lặp chỉnh sửa giao diện cho cả giai đoạn sau. | 1,5 h |
| 2 | Chỉnh giao diện phiếu theo mẫu in của P.QLCL | Phóng to logo và tiêu đề, đổi "MILL TEST CERTIFICATE" sang đen/in đậm, in đậm các mục *Chỉ tiêu ngoại quan* và *Kết luận*, bổ sung các đường kẻ bảng còn thiếu so với mẫu, định dạng dấu phẩy hàng nghìn cho Tổng khối lượng. | 1,0 h |
| 3 | Xử lý lỗi hiển thị bảng dữ liệu | Khắc phục tình trạng cuộn ngang ở bước 3; bổ sung nút mở rộng bảng ra toàn màn hình ở bước 2 (bảng có tới 28 cột nên rất khó thao tác ở khổ mặc định). | 0,75 h |
| 4 | Thiết lập quy trình deploy | Chuẩn hoá lệnh `sf project deploy`; xác định và xử lý 2 lỗi chặn: `InvalidProjectWorkspaceError` (do tồn tại thư mục trùng tên không phải OneDrive, không có `sfdx-project.json`) và lỗi xung đột với bản đã sửa trực tiếp trên org. | 0,5 h |
| 5 | **Nghiên cứu cơ chế xác thực & phân quyền của Salesforce** | Tìm hiểu Named Credential, External Credential, Principal, Permission Set và cơ chế *External Credential Principal Access*; so sánh với cách gọi API kèm tài khoản/mật khẩu trong mã nguồn để chọn phương án đúng chuẩn nền tảng. | 1,75 h |
| 6 | **Bảo mật xác thực API BK** *(triển khai)* | Loại bỏ việc lưu tài khoản/mật khẩu trong mã nguồn, chuyển sang Named Credential `HPDQ_PL_COS` + External Credential (Basic auth, principal `crm_api`). Tạo permission set cấp quyền và xác lập quy trình gán quyền cho nhân viên QLCL. | 1,0 h |
| 7 | Đưa màn hình lên org | Nghiên cứu khác biệt giữa Lightning Record Page và Lightning App Builder, cấu hình để người dùng truy cập được màn hình QC. | 0,5 h |
| 8 | Nối luồng lưu phiếu và trích PDF | Đấu nối `saveCertificate` lưu vào `HPDQ_Certificate__c`; xử lý ràng buộc `HPDQ_Certificate_No__c` là Unique nhưng không phải External ID (không upsert được, phải tra cứu rồi gán Id). Chạy bộ test hồi quy. | 1,0 h |

### Ngày 30/07/2026 (thứ Năm) — 8,0 h

| # | Tên task | Mô tả | Thời lượng |
|---|---|---|---|
| 9 | Ánh xạ cấu hình nguyên tố hoá học | Xử lý `HPDQ_Configuration__c` (multi-select picklist bắt buộc) chứa danh sách nguyên tố do BK trả về; tắt "Restrict picklist" để nguyên tố lạ vẫn lưu được. Khảo sát field liên kết khách hàng trên đối tượng Account. | 0,75 h |
| 10 | **Nghiên cứu phương án sinh PDF trên Salesforce** | So sánh các hướng khả thi (in từ trình duyệt, Visualforce `renderAs="pdf"`, ứng dụng AppExchange, dịch vụ render ngoài) theo tiêu chí: có đính được vào record không, có gửi mail được không, có lưu lịch sử được không, chi phí. Chốt hướng Visualforce `renderAs="pdf"`. | 1,0 h |
| 11 | Bản in dự phòng | Tạo `cert-print-fallback.html` — bản in độc lập, chỉ cần dán dữ liệu JSON của BK là in được. Bảo đảm vẫn có đường in phiếu nếu hướng chính gặp sự cố. | 0,5 h |
| 12 | Xây bộ sinh PDF phía server | Viết `HPDQ_CertificatePdfController.cls` và trang Visualforce `HPDQ_MTC_Certificate`; đính file PDF vào record qua ContentVersion. Xử lý ràng buộc `getContentAsPDF()` hành xử như callout → phải tách thành 2 lần gọi Apex riêng (lưu trước, sinh PDF sau). | 1,5 h |
| 13 | **Kiểm chứng giới hạn engine PDF của Salesforce** | Kiểm thực nghiệm 9 kỹ thuật trình bày và ghi nhận kết quả: nhúng font qua `@font-face` **không hoạt động** (thử cả Static Resource lẻ lẫn gói ZIP); `font-weight: bold` **bị bỏ qua**; `thead` không tự lặp qua trang; `-fs-table-paginate` có tác dụng; logo chỉ lặp được khi đặt làm `background-image`. Phương pháp kiểm: sinh PDF thật, giải nén content stream, đếm số trang và số lệnh vẽ ảnh để phát hiện trang bị tràn. | 1,75 h |
| 14 | Tách 2 chế độ xuất bản | Phân tách chế độ `pdf=1` (server tự chia trang) và chế độ HTML "Trang In" (để trình duyệt tự tràn trang, giữ được serif + chữ đậm giống mẫu in) — giải pháp bù cho hạn chế của engine PDF nêu ở mục 13. | 0,75 h |
| 15 | **Hiệu chỉnh thuật toán chia trang** | Khắc phục 2 lỗi ngược nhau: bỏ trống nhiều mà đã sang trang mới, và tràn quá khổ giấy. Thay cách đếm hàng bằng đơn vị "chỗ" có tính số dòng ghi chú; mô phỏng ngắt dòng **theo từ** thay vì chia theo số ký tự (đo thật: 84 ký tự ước ra 4 dòng nhưng render 5 dòng, gây tràn); thiết lập 4 ngân sách riêng cho 4 loại trang. | 1,25 h |
| 16 | Trang thử nghiệm & tài liệu kỹ thuật | Tạo 3 trang thử `HPDQ_TestPaginateA/B/C` để đo ngân sách từng loại trang riêng lẻ. Viết tài liệu `CLAUDE.md` ghi lại kiến trúc, các giới hạn đã kiểm chứng và các bẫy đã gặp — để người tiếp nhận sau không phải thử lại các hướng đã biết là không khả thi. | 0,5 h |

### Ngày 31/07/2026 (thứ Sáu) — 8,0 h

| # | Tên task | Mô tả | Thời lượng |
|---|---|---|---|
| 17 | Rà soát phân quyền hệ thống | Kiểm tra cơ chế kiểm quyền ở bước 1 (gửi yêu cầu), xác định ai có quyền xoá phiếu, làm rõ vai trò của từng permission set đang có và nguyên nhân API vẫn chạy được với cấu hình hiện tại. | 1,0 h |
| 18 | **Nghiên cứu mô hình phân quyền Salesforce** ◇ | Hệ thống hoá Profile, Permission Set, Permission Set Group, Object/Field-Level Security và cơ chế chia sẻ bản ghi — làm cơ sở đề xuất bộ quyền cho nhân viên QLCL khi đưa lên production. | 2,0 h |
| 19 | Chuẩn hoá phông chữ tiêu đề phiếu | Đổi font tiêu đề "PHIẾU CHỨNG NHẬN CHẤT LƯỢNG / MILL TEST CERTIFICATE" sang Times New Roman ở trang in cho khớp mẫu. | 0,75 h |
| 20 | Kiểm thử phiếu trên sandbox ◇ | Chạy thử luồng đầy đủ với nhiều bộ dữ liệu, đối chiếu bản in với mẫu của P.QLCL, ghi nhận các điểm còn lệch. | 2,5 h |
| 21 | Tinh chỉnh bố cục trang in sau kiểm thử ◇ | Xử lý các điểm lệch phát hiện ở mục 20 (khoảng cách, canh lề, độ rộng cột, vị trí khối thông tin). | 1,75 h |

### Ngày 01/08/2026 (thứ Bảy) — 4,0 h *(làm nửa ngày)*

| # | Tên task | Mô tả | Thời lượng |
|---|---|---|---|
| 22 | Xuất Excel | Giữ nguyên số thô khi xuất (ví dụ `19114`, không chèn dấu phân cách) để Excel nhận đúng kiểu số thay vì kiểu chuỗi; xử lý gộp ô (merge & center) cho khớp bố cục trên màn hình. | 1,0 h |
| 23 | Chuẩn định dạng file CSV nhập ID | Xác định và tài liệu hoá định dạng file CSV cho nút Import CSV ở bước 1 (cột ID, tự bỏ dòng tiêu đề) để hướng dẫn người dùng. | 0,5 h |
| 24 | Rà soát cơ chế xuất PDF hiện hành | Kiểm tra lại toàn bộ luồng xuất PDF đang chạy, xác nhận đúng thiết kế sau các thay đổi của 2 ngày trước. | 0,75 h |
| 25 | **Nghiên cứu nền tảng Salesforce** | Hệ thống hoá các khái niệm nền tảng: Apex, Visualforce, Lightning Web Component — vai trò và ranh giới của từng lớp trong kiến trúc dự án. Phục vụ tự chủ vận hành và bàn giao sau này. | 1,75 h |

### Ngày 03/08/2026 (thứ Hai) — 2,0 h *(tính đến hết buổi sáng, đang tiếp tục)*

| # | Tên task | Mô tả | Thời lượng |
|---|---|---|---|
| 26 | **Bỏ ràng buộc bắt buộc của "Danh sách ID"** | Phát hiện quy tắc không nhất quán giữa 3 lớp: giao diện và JavaScript coi Danh sách ID là tuỳ chọn, nhưng Apex vẫn chặn khi để trống — người dùng chỉ nhận được lỗi sau khi đã bấm gửi và đã tốn một lượt gọi API. Đã bỏ chặn ở `QCRequestController`, chuyển giá trị `null` thành mảng rỗng để không gửi `"ListID": null` lên BK, bổ sung ghi chú trên giao diện, cập nhật 3 test (sửa 1, thêm 2 — trong đó có test cho nhánh thiếu SO trước đây chưa được phủ). Deploy thành công, **10/10 test pass**. | 1,25 h |
| 27 | Lập báo cáo công việc | Tổng hợp và lập báo cáo tiến độ dự án. | 0,75 h |

> **Dự kiến thời gian còn lại trong ngày:** xử lý các hạng mục nêu ở Mục 4 — ưu tiên bổ sung hàng tổng / chú thích / ô ký cho bản xem trước ở bước 3, và dọn 3 trang thử nghiệm trên org.

---

## 2. Sản phẩm đã bàn giao

| Hạng mục | Trạng thái |
|---|---|
| Màn hình LWC `qcRequestWizard` — quy trình 3 bước (nhập yêu cầu → kiểm tra/hiệu chỉnh dữ liệu → xem trước & xuất) | Đang chạy trên sandbox `hpdqDev` |
| Tích hợp API hệ thống BK qua Named Credential (không lưu mật khẩu trong mã nguồn) | Hoàn thành |
| Lưu phiếu vào đối tượng `HPDQ_Certificate__c` | Hoàn thành |
| Sinh PDF phía server, tự chia trang, đính kèm vào record | Hoàn thành |
| Chế độ "Trang In" — in trực tiếp từ trình duyệt, đạt chất lượng trình bày cao hơn PDF server | Hoàn thành |
| Xuất Excel | Hoàn thành |
| Nhập danh sách ID từ file CSV | Hoàn thành |
| Bộ test tự động `QCRequestControllerTest` | 10/10 pass |
| Môi trường xem trước cục bộ + bản in dự phòng | Hoàn thành |
| Tài liệu kỹ thuật dự án (`CLAUDE.md`) | Hoàn thành |

## 3. Vấn đề kỹ thuật đáng lưu ý — *xin ý kiến chỉ đạo*

**Engine sinh PDF của Salesforce không hỗ trợ nhúng font và không hỗ trợ chữ đậm cho tiếng Việt.** Đây là hạn chế của nền tảng, không phải lỗi lập trình — đã kiểm chứng bằng cách sinh PDF thật và phân tích cấu trúc file (mục 13). Chỉ có một font Unicode khả dụng là Arial Unicode MS, và font này không có bản đậm.

Phương án đã áp dụng: bổ sung chế độ **"Trang In"** để in trực tiếp từ trình duyệt, đạt đúng phông chữ và chữ đậm như mẫu; PDF do server sinh vẫn giữ để lưu trữ và đính kèm hồ sơ.

Nếu P.QLCL yêu cầu **file PDF lưu trữ** phải giống hệt mẫu in (serif + chữ đậm), cần cân nhắc mua ứng dụng sinh tài liệu trên AppExchange hoặc dùng dịch vụ render bên ngoài — cả hai đều phát sinh chi phí, xin ý kiến chỉ đạo.

## 4. Việc còn dở

| Nội dung | Vướng mắc |
|---|---|
| Mã biểu mẫu và ngày hiệu lực ở góc phải header | **Chờ P.QLCL cung cấp.** Đã để sẵn hằng số, khi có dữ liệu chỉ cần điền vào. |
| Liên kết phiếu với khách hàng (`HPDQ_Account__c`) | Sandbox hiện có 0 Account nên chưa kiểm thử được phần khớp mã khách hàng SAP. |
| Cột cơ tính (giới hạn chảy, độ bền kéo, độ giãn dài, độ cứng) | Hệ thống BK hiện trả về rỗng cho các cột này — **cần xác nhận với bên BK** là do chưa có số liệu hay do cấu hình API. |
| Bản xem trước ở bước 3 chưa có hàng tổng, chú thích và ô ký như trang in | Phần việc còn lại, đang xử lý. |
| Chưa có test tự động riêng cho `HPDQ_CertificatePdfController` | Nên bổ sung trước khi đưa lên production. |
| Dọn 3 trang thử nghiệm `HPDQ_TestPaginateA/B/C` trên org | Việc dọn dẹp, làm được ngay. |

---

**Ghi chú:**
- ◇ Các mục đánh dấu ◇ là công việc thực hiện trực tiếp trên giao diện Salesforce và nghiên cứu tài liệu, không để lại dấu vết trong nhật ký công cụ — thời lượng là ước tính.
- Một phần đáng kể thời lượng là công **nghiên cứu, kiểm chứng và xử lý sự cố** chứ không phải toàn bộ đều là thời gian viết mã. Với nền tảng Salesforce, phần lớn chi phí nằm ở việc xác định giới hạn của nền tảng trước khi chọn được hướng khả thi.
