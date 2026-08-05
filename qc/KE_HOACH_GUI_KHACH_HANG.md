# Kế hoạch — Nút "Gửi cho khách hàng"

Trạng thái: **chưa code**, chờ duyệt kế hoạch.

## Quyết định đã chốt

| # | Nội dung |
|---|---|
| 1 | Khách hàng **chỉ nhận file PDF** đính kèm mail. Không gửi link |
| 2 | Nhân viên Hoà Phát xem được **cả link lẫn PDF** trong Salesforce |
| 3 | **Người tạo phiếu** là người bấm nút gửi |
| 4 | Không tìm thấy Account → **thông báo, chặn lại** |
| 5 | Nội dung mail dùng **Email Template của Salesforce** có merge field |
| 6 | Mail gửi từ **email của người bấm nút** (không dùng Org-Wide Address) |
| 7 | Không cần lưu vết ngày gửi / người gửi |

Nhờ chốt như vậy, **không cần**: ContentDistribution · Experience Cloud · đổi OWD External · thêm field trên Account.

---

## 1. Metadata cần tạo

### 1.1. Email Template `HPDQ_Gui_Phieu_Chung_Nhan`

- Loại: Classic, HTML
- Thư mục: `unfiled$public` (org chưa có thư mục Email riêng nào)
- Gắn với đối tượng: `HPDQ_Certificate__c` để dùng được merge field

Merge field dự kiến dùng:

| Merge field | Ý nghĩa |
|---|---|
| `{!HPDQ_Certificate__c.HPDQ_Certificate_No__c}` | Số phiếu |
| `{!HPDQ_Certificate__c.HPDQ_Issue_Date__c}` | Ngày phát hành |
| `{!HPDQ_Certificate__c.HPDQ_Project__c}` | Tên khách hàng |
| `{!HPDQ_Certificate__c.HPDQ_Grade__c}` | Mác thép |
| `{!HPDQ_Certificate__c.HPDQ_Total_Coils__c}` | Tổng số cuộn |
| `{!HPDQ_Certificate__c.HPDQ_Total_Weight__c}` | Tổng khối lượng |

Nội dung soạn song ngữ Việt–Anh. Sau khi deploy, **P.KD sửa trực tiếp trên Setup được, không cần deploy lại**.

### 1.2. Thêm giá trị picklist

`HPDQ_Certificate__c.HPDQ_Status__c` thêm giá trị **"Đã gửi khách hàng"**
(hiện có: *Nhận dữ liệu từ BK · P.QLCL xác nhận · P.KD xử lý · P.KD xác nhận*)

Deploy bằng metadata thay vì thêm tay, để lưu được vào mã nguồn.

---

## 2. Apex — class mới `HPDQ_SendCertificate`

Tách class riêng thay vì nhồi vào `QCRequestController` (class đó đã ~370 dòng, và gửi mail là mối quan tâm khác hẳn).

### 2.1. `getCustomerInfo(Id certId)` — gọi khi bấm nút, trước khi hiện hộp xác nhận

Việc làm:
1. Đọc phiếu: mã KH, số phiếu, lookup khách hàng hiện tại
2. Tra `Account` theo `HPDQ_SAP_Customer_Code__c`
3. Tìm `ContentVersion` mới nhất gắn với phiếu

Trả về cho màn hình: `accountId · accountName · email · fileName · fileSizeKb · canSend · message`

**Sáu nhánh phải xử lý** — trả về cờ `canSend = false` kèm thông báo tiếng Việt, **không ném exception** để màn hình hiện được hộp thoại đẹp:

| Tình huống | Thông báo |
|---|---|
| Phiếu chưa có mã khách hàng | "Phiếu không có mã khách hàng, không xác định được người nhận." |
| Không tìm thấy Account | "Chưa có khách hàng mã {X} trong hệ thống." |
| Nhiều Account trùng mã | Vẫn cho gửi, lấy Account tạo trước nhất, kèm cảnh báo |
| Account không có email | "Khách hàng {tên} chưa có email." |
| Chưa trích PDF | "Chưa có file PDF. Hãy bấm Trích PDF trước." |
| Không có quyền sửa phiếu | "Bạn không phải người tạo phiếu này nên không gửi được." |

### 2.2. `sendToCustomer(Id certId, String toEmail)` — gọi khi bấm Gửi

Thứ tự thực hiện — **quan trọng**:

1. Kiểm email hợp lệ + kiểm `isUpdateable()`
2. Lấy `ContentVersion` mới nhất
3. `Messaging.renderStoredEmailTemplate(templateId, null, certId)` → tiêu đề + nội dung đã thay merge field
4. Dựng `SingleEmailMessage`: `setToAddresses` · `setSubject` · `setHtmlBody` · `setEntityAttachments([cvId])`
5. **Gửi mail**
6. **Rồi mới** cập nhật phiếu: gán `HPDQ_Account__c`, đổi trạng thái

> **Vì sao gửi mail trước rồi mới cập nhật:** nếu cập nhật trước mà mail lỗi thì phiếu ghi "Đã gửi khách hàng" trong khi thực tế chưa gửi — sai lệch nguy hiểm. Ngược lại, gửi được mà không ghi nhận được thì chỉ là thiếu thông tin, nhẹ hơn nhiều.

**Vì sao dùng `renderStoredEmailTemplate` thay vì `setTemplateId`:**
`setTemplateId()` bắt buộc đi kèm `setTargetObjectId()` trỏ Contact/Lead/User, và khi đó mail sẽ gửi tới email của record đó — không phải email ta nhập. `renderStoredEmailTemplate()` chỉ *render* template ra chuỗi, không gửi, nên ta tự do chọn địa chỉ nhận mà vẫn dùng được template chuẩn Salesforce.

**Đính file dùng `setEntityAttachments`** (truyền Id ContentVersion) chứ không dùng `setFileAttachments` — cách sau phải đọc cả file vào bộ nhớ, giới hạn heap 6 MB, dễ vỡ khi phiếu lớn.

---

## 3. LWC `qcRequestWizard`

| Việc | Chi tiết |
|---|---|
| Nút "Chuyển đến khách hàng" | Đổi nhãn thành **"Gửi cho khách hàng"**, chỉ bật khi đã có `savedRecordId` |
| `handleTransfer()` | Gọi `getCustomerInfo` → mở hộp xác nhận |
| Hộp xác nhận | Hiện tên khách hàng · **ô email sửa được** · tên file đính kèm · cảnh báo nếu có |
| Khi `canSend = false` | Hiện thông báo lỗi, ẩn nút Gửi |
| Bấm Gửi | Gọi `sendToCustomer` → toast kết quả → đóng hộp |

---

## 4. Test — `HPDQ_SendCertificateTest`

Dữ liệu: 1 Account (có email) + 1 Account (không email) + 1 phiếu + 1 ContentVersion.

Các trường hợp:
- Gửi thành công → assert `Limits.getEmailInvocations() == 1`, trạng thái phiếu đổi, `HPDQ_Account__c` được gán
- Không tìm thấy Account → `canSend = false`, đúng thông báo
- Account thiếu email → `canSend = false`
- Chưa có PDF → `canSend = false`
- Email sai định dạng → ném lỗi

⚠️ **Điểm cần lưu ý khi viết test:** `EmailTemplate` là *setup object*, không insert chung transaction với dữ liệu thường (lỗi MIXED_DML). Nên test sẽ **truy vấn template đã deploy** thay vì tạo mới; nếu không tìm thấy thì bỏ qua phần render để test không phụ thuộc dữ liệu org.

---

## 5. Việc thủ công trên Setup — bạn làm

| # | Việc | Bắt buộc |
|---|---|---|
| 1 | **Setup → Deliverability → Access level → "All email"** | **Có.** Sandbox mặc định chặn, mail không đi mà cũng không báo lỗi |
| 2 | Thêm related list *"Quản lý in chứng chỉ chất lượng"* vào Page Layout của Account (`Domestic - Trader` và 3 layout còn lại) | Không, nhưng nên |

---

## 6. Thứ tự triển khai

1. Deploy giá trị picklist mới + Email Template
2. Deploy Apex `HPDQ_SendCertificate` + test class
3. Deploy LWC
4. Bạn bật Deliverability
5. Chạy thử: gửi phiếu tới `huynhkhoa.itc@gmail.com` (Account `60000048` đã tạo sẵn)
6. Kiểm hộp thư, mở file đính kèm, kiểm trạng thái phiếu đã đổi

---

## 7. Rủi ro đã biết

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Deliverability chưa bật → mail im lặng không đi | **Cao** | Mục 5.1, phải làm trước khi test |
| Người gửi không phải chủ phiếu → DML lỗi | Trung bình | Đã chốt người tạo phiếu bấm nút. `getCustomerInfo` kiểm trước và báo sớm |
| Nhiều Account trùng mã KH | Thấp | Lấy Account tạo trước nhất + cảnh báo trên hộp xác nhận |
| Vượt 5.000 mail/ngày | Thấp | Nghiệp vụ vài chục phiếu/ngày |
| File PDF quá 10 MB | Rất thấp | Hiện 474 KB; phiếu 130 cuộn cũng chỉ 460 KB |
| Template bị xoá/đổi tên trên Setup | Thấp | Apex tra theo `DeveloperName`, không tìm thấy thì báo lỗi tiếng Việt rõ ràng |

---

## 8. Ước lượng

| Hạng mục | Số file |
|---|---|
| Email Template + picklist | 2 |
| Apex class + test | 2 |
| LWC (html, js, css) | 3 |

Không đụng tới: `QCRequestController` · `HPDQ_CertificatePdfController` · trang Visualforce · watermark · logic chia trang.
