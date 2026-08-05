# Hệ thống Quản lý & In Phiếu Chứng Nhận Chất Lượng (MTC)

**Tài liệu trình bày — Chủ đầu tư**
Môi trường demo: Salesforce sandbox `hpdqDev`
Cập nhật: 05/08/2026

---

## 1. Bài toán

Phiếu Chứng Nhận Chất Lượng (Mill Test Certificate) là tài liệu **bắt buộc** đi kèm mỗi lô
thép cuộn cán nóng xuất xưởng. Khách hàng dùng phiếu này để xác nhận thép đạt tiêu chuẩn
đã cam kết trong hợp đồng.

Quy trình trước đây:

| Bước | Cách làm cũ | Vấn đề |
|---|---|---|
| Lấy số liệu thí nghiệm | Tra thủ công từ hệ thống BK | Mất thời gian, dễ sai sót khi chép tay |
| Lập phiếu | Soạn trên Excel/Word | Mỗi người một mẫu, không thống nhất |
| Lưu trữ | File rời trên máy cá nhân | Không tra cứu được, mất khi đổi người |
| Gửi khách | Gửi mail thủ công | Không biết đã gửi cho ai, khi nào |

---

## 2. Giải pháp

Một màn hình duy nhất trên Salesforce, quy trình **3 bước**, tự động từ đầu tới cuối.

```
Bước 1              Bước 2                    Bước 3
Gửi yêu cầu    →    Kiểm tra & hiệu chỉnh  →  Xác nhận & phát hành
(P. Kinh doanh)     (P. QLCL)                 (P. Kinh doanh)
     │                    │                          │
     │                    │                          ├─ Trích PDF
  Gọi API BK         Sửa số liệu                     ├─ In phiếu
  lấy số liệu        Thêm ghi chú                    └─ Gửi khách hàng
  thí nghiệm         Xuất Excel
```

---

## 3. Kịch bản demo

### 3.1. Bước 1 — Gửi yêu cầu

**Thao tác:** nhập Số SO, Customer Code, dán danh sách ID cuộn → bấm **Gửi yêu cầu**

**Điểm nhấn khi trình bày:**
- Hệ thống **tự gọi API sang hệ thống BK** lấy toàn bộ số liệu thí nghiệm — không nhập tay
- Nhập danh sách ID bằng cách **dán trực tiếp** hoặc **nhập từ file CSV**
- Nút **"?"** giải thích định dạng file CSV cho người dùng mới

### 3.2. Bước 2 — Kiểm tra & hiệu chỉnh

**Thao tác:** xem bảng số liệu, sửa trực tiếp trên ô, thêm ghi chú từng cuộn

**Điểm nhấn:**
- Bảng **28 cột** — thông tin cuộn, cơ tính, thành phần hóa học
- Nút **Mở rộng** cho bảng chiếm toàn màn hình khi cần soi kỹ
- **Xuất Excel** để đối chiếu hoặc lưu hồ sơ nội bộ
- Nút **Yêu cầu hiệu chỉnh** trả phiếu về bước trước khi phát hiện sai

### 3.3. Bước 3 — Xác nhận & phát hành

**Thao tác:** xem bản xem trước → **Trích PDF** → **Gửi cho khách hàng**

**Điểm nhấn:**
- Bản xem trước **giống hệt mẫu in** đang lưu hành
- **Trích PDF**: lưu phiếu vào hệ thống + sinh file PDF + đính kèm vào hồ sơ
- **Trang In**: bản in chất lượng cao từ trình duyệt, dùng khi cần bản cứng có dấu mộc
- **Gửi cho khách hàng**: hộp xác nhận hiện tên khách, email *(sửa được)*, file đính kèm

### 3.4. Kết quả sau khi phát hành

Mở bản ghi phiếu để trình bày:

| Nơi | Nội dung |
|---|---|
| Hồ sơ phiếu | Đầy đủ thông tin, file PDF đính kèm, trạng thái *Đã gửi khách hàng* |
| Hồ sơ khách hàng | Link tới phiếu vừa gửi |
| Hộp thư khách hàng | Email song ngữ Việt–Anh kèm file PDF |

---

## 4. Tính năng đã hoàn thành

| Nhóm | Tính năng |
|---|---|
| **Tích hợp** | Kết nối API hệ thống BK, xác thực an toàn không lưu mật khẩu trong mã nguồn |
| **Nhập liệu** | Nhập tay · dán hàng loạt · nhập từ file CSV |
| **Hiệu chỉnh** | Sửa tại chỗ 28 cột · ghi chú từng cuộn · mở rộng toàn màn hình |
| **Kết xuất** | PDF tự động chia trang · trang in chất lượng cao · xuất Excel |
| **Phát hành** | Gửi email kèm PDF · mẫu email song ngữ · liên kết phiếu với khách hàng |
| **Lưu trữ** | Lưu phiếu và file vào hệ thống, tra cứu lại bất cứ lúc nào |
| **Phân quyền** | Người tạo sửa được phiếu mình · người khác chỉ xem · quản trị toàn quyền |

**Chất lượng:** 23 kiểm thử tự động, tỉ lệ đạt **100%**.

---

## 5. Vấn đề kỹ thuật đã xử lý

Phần này nên trình bày nếu chủ đầu tư quan tâm chiều sâu kỹ thuật.

### 5.1. Giới hạn bộ sinh PDF của Salesforce

Bộ sinh PDF sẵn có của Salesforce **không hỗ trợ nhúng phông chữ** và **không có chữ đậm
cho tiếng Việt**. Đây là giới hạn nền tảng, không phải lỗi lập trình — đã kiểm chứng bằng
cách sinh PDF thật rồi phân tích cấu trúc file.

**Cách xử lý:** làm **hai bản kết xuất song song**

| Bản | Dùng khi nào | Chất lượng |
|---|---|---|
| PDF do máy chủ sinh | Lưu trữ, đính kèm email | Chuẩn, nhưng phông hạn chế |
| Trang In từ trình duyệt | In bản cứng giao khách | Đẹp như mẫu, có chữ đậm |

### 5.2. Tự chia trang

Salesforce không tự lặp tiêu đề bảng qua trang. Hệ thống **tự tính toán chia trang**, có
tính cả số dòng ghi chú của từng cuộn, chừa chỗ cho phần kết luận và ô ký ở trang cuối.

**Kiểm chứng thực tế:** phiếu 130 cuộn chia đúng 7 trang, không tràn, không trang trắng.

### 5.3. Watermark chống sao chép

Logo Hòa Phát mờ nghiêng 45° trên mọi trang. Do bộ sinh PDF không hỗ trợ hiệu ứng xoay và
làm mờ, toàn bộ được **xử lý sẵn vào ảnh** — kiểm chứng bằng cách đếm lệnh vẽ trong file
PDF sinh ra.

---

## 6. Việc còn lại

### 6.1. Cần chủ đầu tư / P.QLCL quyết định

| # | Nội dung | Vì sao cần quyết |
|---|---|---|
| 1 | **Mã biểu mẫu và ngày hiệu lực** ở góc phải phiếu | Đang để trống chờ P.QLCL cung cấp |
| 2 | **Phiếu đã gửi khách có được sửa lại không?** | Hiện sửa được và ghi đè âm thầm. Ngành thép thường không cho sửa phiếu đã phát hành |
| 3 | **Ai bấm gửi — P.QLCL hay P.KD?** | Quyết định cách phân quyền |
| 4 | **Có cần lưu vết đã gửi cho ai, khi nào?** | Cần cho đối chứng khi khách khiếu nại |
| 5 | **Một SO được phát hành mấy phiếu?** | Hiện không giới hạn, có thể trùng lặp |

### 6.2. Cần chuẩn bị trước khi lên chính thức

| # | Việc | Phụ trách |
|---|---|---|
| 1 | Xác thực tên miền email `hoaphat.com.vn` (DKIM) | CNTT |
| 2 | Tạo hòm thư chung `qlcl@hoaphat.com.vn` để gửi phiếu | CNTT |
| 3 | Cấp quyền cho nhân viên QLCL theo mô hình đã thiết kế | Quản trị Salesforce |
| 4 | Bổ sung kiểm tra quyền cấp trường trong mã nguồn | Lập trình |

> **Mục 1 và 2 là bắt buộc.** Nếu không, email gửi khách hàng sẽ **rơi vào hộp thư rác**
> và khách không nhận được phiếu.

### 6.3. Chưa triển khai

| Nội dung | Trạng thái |
|---|---|
| Cổng tra cứu cho khách hàng tự đăng nhập | Đã có hạ tầng, chưa cấu hình |
| Liên kết tự động với mã khách hàng SAP | Chờ dữ liệu khách hàng thật |
| Số liệu cơ tính (giới hạn chảy, độ bền kéo…) | **Hệ thống BK đang trả về rỗng** — cần xác nhận với bên BK |

---

## 7. Câu hỏi có thể gặp khi demo

**"Số liệu có chính xác không, có bị sửa được không?"**
Số liệu lấy trực tiếp từ hệ thống BK, không nhập tay. P.QLCL được phép hiệu chỉnh ở bước 2
và mọi thay đổi đều lưu lại trong hệ thống.

**"Nếu gửi nhầm khách hàng thì sao?"**
Hộp xác nhận bắt buộc hiện tên khách hàng và email trước khi gửi, cho phép sửa. Email đã
gửi thì không thu hồi được — đây là giới hạn chung của email, không riêng hệ thống này.

**"Khách hàng có xem được phiếu trên hệ thống không?"**
Hiện khách nhận file PDF qua email. Muốn khách tự đăng nhập tra cứu thì cần triển khai
thêm cổng khách hàng — hạ tầng đã có sẵn.

**"Phiếu cũ có tra lại được không?"**
Được. Mọi phiếu lưu trong hệ thống kèm file PDF, tra theo số phiếu, khách hàng, mác thép,
ngày phát hành.

**"Bao lâu thì lập xong một phiếu?"**
Với phiếu 50–130 cuộn: nhập SO và danh sách ID khoảng 1 phút, hệ thống lấy số liệu tự động,
kiểm tra và phát hành thêm vài phút. So với cách cũ phải tra và chép tay từng cuộn.

---

## 8. Tóm tắt

| | |
|---|---|
| **Đã chạy được** | Toàn bộ quy trình từ lấy số liệu tới gửi khách hàng |
| **Đang ở** | Sandbox `hpdqDev`, sẵn sàng demo |
| **Chất lượng** | 23 kiểm thử tự động, 100% đạt |
| **Chặn lên chính thức** | Xác thực tên miền email (mục 6.2) |
| **Chờ quyết định** | 5 vấn đề nghiệp vụ ở mục 6.1 |
