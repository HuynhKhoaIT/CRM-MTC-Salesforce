# Kế hoạch — Chuyển sang quy trình 3 bước liên phòng

Trạng thái: **chưa code**, chờ chốt 5 vấn đề ở Mục 3.

---

## 1. Thay đổi cốt lõi

| | Hiện tại | Sau khi đổi |
|---|---|---|
| Mô hình | **Một người làm một mạch** | **Ba chặng, hai phòng, có bàn giao** |
| Record sinh ra khi | Bấm "Trích PDF" (bước 3) | **Ngay khi gửi yêu cầu (bước 1)** |
| Đóng trình duyệt giữa chừng | Mất trắng | **Còn nguyên, người khác vào làm tiếp** |
| Ai làm được gì | Ai cũng làm được cả 3 bước | **Mỗi bước một nhóm người** |
| Trạng thái phiếu | 2 giá trị được dùng | **4 giá trị, mỗi cái ứng một chặng** |

Đây là thay đổi **kiến trúc**, không phải chỉnh sửa nhỏ.

---

## 2. Đặc tả quy trình

### 2.1. Máy trạng thái

| Trạng thái phiếu | Bước đang mở | Ai được thao tác | Hành động | Trạng thái sau đó |
|---|---|---|---|---|
| *(chưa có record)* | 1 | **P. Kinh doanh** | Gửi yêu cầu | `Nhận dữ liệu từ BK` |
| `Nhận dữ liệu từ BK` | 2 | **P. QLCL** | Hiệu chỉnh xong, submit | `P.QLCL xác nhận` |
| `P.QLCL xác nhận` | 3 | **Người tạo phiếu** | Mở bước 3 | `P.KD xử lý` |
| `P.KD xử lý` | 3 | **Người tạo phiếu** | Gửi PDF cho khách | `P.KD xác nhận` |
| `P.KD xác nhận` | — | — | Hoàn tất | — |

### 2.2. Quyền theo bước

| Bước | Xem | Sửa | Chuyển bước tiếp |
|---|---|---|---|
| 1 | Mọi người | P.KD | P.KD |
| 2 | Mọi người | **Chỉ P.QLCL** | **Chỉ P.QLCL** |
| 3 | Mọi người | **Chỉ người tạo phiếu** | **Chỉ người tạo phiếu** |

### 2.3. Khi mở phiếu đang dở

Hệ thống hiện thanh 3 bước, **tự nhảy tới đúng bước đang chờ**, và:

- Có quyền ở bước đó → mở khoá cho thao tác
- Không có quyền → **chỉ xem**, kèm dòng thông báo *"Phiếu đang chờ P.QLCL hiệu chỉnh"*

---

## 3. NĂM VIỆC PHẢI CHỐT TRƯỚC KHI CODE

### 3.1. 🔴 Phòng QLCL chưa tồn tại trong hệ thống

Đã rà toàn bộ org:

| Tìm | Kết quả |
|---|---|
| Profile tên QLCL | Không có — 12 profile HPDQ, không cái nào là QLCL |
| Phòng ban (`User.Department`) | Không có — chỉ có Phòng Kinh Doanh (29), CNTT (3), Khách Hàng (1), Ban GĐ (1), Dịch vụ kỹ thuật (2) |
| User thuộc QLCL | **0 người** |

**Toàn bộ Bước 2 giao cho một phòng chưa có ai trong hệ thống.** Không có người này thì mọi phiếu sẽ **kẹt vĩnh viễn** ở bước 2.

**Cần quyết:** nhận diện người P.QLCL bằng cách nào?

| Cách | Ưu | Nhược |
|---|---|---|
| **Custom Permission + Permission Set** ← đề xuất | Cấp/thu hồi dễ, kiểm được trong code, không đụng profile | Phải tạo mới |
| Tạo profile `HPDQ - QLCL` | Rõ ràng | Nặng, phải cấu hình lại toàn bộ quyền cho profile mới |
| Dựa vào `User.Department` | Không cần tạo gì | Ô nhập tự do, sai chính tả là hỏng; hiện đang có cả *"IT"* lẫn *"Phòng CNTT"* |
| Public Group | Đơn giản | Khó kiểm trong code |

### 3.2. 🔴 Xung đột với phân quyền vừa cấu hình hôm nay

Hôm nay đã đặt **OWD = Public Read Only**: chỉ **chủ sở hữu** mới sửa được phiếu.

Nhưng quy trình mới yêu cầu **P.QLCL sửa phiếu do P.KD tạo** — người khác chủ sở hữu.
Hai điều này **loại trừ nhau**. Bắt buộc chọn một:

| Phương án | Cách làm | Đánh giá |
|---|---|---|
| **A. Criteria-Based Sharing Rule** ← **ĐỀ XUẤT** | Chia sẻ Read/Write cho nhóm P.QLCL, **điều kiện `Trạng thái = Nhận dữ liệu từ BK`** | Đúng yêu cầu tuyệt đối. Không cần code. Quyền **tự thu hồi** khi trạng thái đổi |
| B. Apex `without sharing` cho riêng bước 2 | Code vượt quyền có kiểm soát | Kiểm soát được nhưng quyền nằm trong code, admin nhìn Setup không thấy |
| C. Chuyển quyền sở hữu theo bước | Bước 2 chuyển owner sang QLCL, bước 3 trả về | Phải chọn *người QLCL nào*, lịch sử owner rối |

### Vì sao chọn A

Sharing Rule có **hai loại**, và loại thứ hai giải quyết đúng bài toán:

| Loại | Chia sẻ theo | Kết quả |
|---|---|---|
| Owner-based | Chủ sở hữu | QLCL sửa được mọi phiếu, mọi trạng thái — **không đúng yêu cầu** |
| **Criteria-based** | **Giá trị field** | QLCL chỉ sửa được phiếu khớp điều kiện — **đúng yêu cầu** |

**Cấu hình:**

```
Setup → Sharing Settings → Phiếu Chứng Nhận Chất Lượng → Sharing Rules → New
  Rule Type    : Based on criteria
  Field        : Trạng thái phiếu
  Operator     : equals
  Value        : Nhận dữ liệu từ BK
  Share with   : Public Group  "P. QLCL"
  Access Level : Read/Write
```

**Cơ chế tự thu hồi** — Salesforce tính lại quyền mỗi khi field tiêu chí đổi:

| Trạng thái | Khớp tiêu chí | P.QLCL sửa được |
|---|---|---|
| `Nhận dữ liệu từ BK` | ✅ | ✅ |
| `P.QLCL xác nhận` | ❌ | ❌ **mất quyền ngay** |
| `P.KD xử lý` · `P.KD xác nhận` | ❌ | ❌ |

P.QLCL bấm submit → trạng thái đổi → Salesforce **tự gỡ quyền sửa của chính họ**.

**Điều kiện đã sẵn sàng trên org:**

| Điều kiện | Trạng thái |
|---|---|
| OWD chặt hơn `Public Read/Write` | ✅ `Public Read Only` |
| Chưa có sharing rule gây xung đột | ✅ Trống |
| Field trạng thái dùng làm tiêu chí | ✅ Picklist hợp lệ |
| Public Group `P. QLCL` | ❌ **Chưa có**, phải tạo |

**Apex vẫn phải kiểm nghiệp vụ:** sharing rule không phân biệt được *sửa số liệu* với *đẩy sang bước sau* — cả hai đều là update. Nên code vẫn kiểm ai được bấm nút chuyển bước, và không cho nhảy cóc.

### 3.3. 🟡 Trạng thái `Đã gửi khách hàng` bị trùng vai

Hôm nay vừa thêm giá trị `Đã gửi khách hàng`. Nhưng theo đặc tả mới, gửi xong thì chuyển
sang `P.KD xác nhận`. **Hai giá trị cùng mô tả một sự kiện.**

**Cần quyết:** bỏ `Đã gửi khách hàng`, hay giữ và định nghĩa lại vai trò của nó?

### 3.4. 🟡 Người dùng vào lại phiếu dở từ đâu?

Hiện wizard là một **tab độc lập**, luôn bắt đầu từ bước 1. Muốn "vào làm tiếp" thì cần:

- **Danh sách phiếu chờ xử lý** — ví dụ list view *"Phiếu chờ P.QLCL"*, bấm vào mở phiếu
- Và wizard phải **đặt được trên trang chi tiết phiếu** để nhận biết đang mở phiếu nào

**Cần quyết:** người dùng vào qua danh sách phiếu, hay vẫn qua tab rồi chọn phiếu trong đó?

### 3.5. 🟡 Số phiếu trùng khi tạo ở bước 1

Record sinh ngay ở bước 1, khoá theo **số phiếu do BK cấp**. Nếu BK trả về một số phiếu
**đã tồn tại và đang dở dang**, hệ thống sẽ **ghi đè phiếu đang xử lý của người khác**.

**Cần quyết:** gặp số phiếu đã tồn tại thì chặn lại báo lỗi, hay cho mở phiếu cũ ra làm tiếp?

---

## 4. Danh sách thay đổi

### 4.1. Metadata

| Việc | Chi tiết |
|---|---|
| Custom Permission ×2 | `HPDQ_QLCL_Hieu_Chinh`, `HPDQ_KD_Lap_Phieu` |
| Permission Set ×2 | Gán 2 custom permission trên, cấp cho user tương ứng |
| Picklist trạng thái | Xử lý giá trị `Đã gửi khách hàng` theo kết luận Mục 3.3 |
| List view | *"Phiếu chờ P.QLCL"*, *"Phiếu chờ P.KD"*, *"Phiếu của tôi"* |
| Lightning Record Page | Đặt wizard lên trang chi tiết phiếu |

### 4.2. Apex

| Method | Việc |
|---|---|
| `fetchData` *(sửa)* | Lấy dữ liệu BK **rồi tạo record ngay**, trả về Id |
| `loadCertificate(certId)` *(mới)* | Nạp lại phiếu đang dở: dữ liệu cuộn, cấu hình cột, trạng thái, quyền của người đang xem |
| `submitStep2(certId, dataJson)` *(mới)* | P.QLCL lưu hiệu chỉnh, đổi trạng thái sang `P.QLCL xác nhận` |
| `enterStep3(certId)` *(mới)* | Đổi trạng thái sang `P.KD xử lý` |
| `sendToCustomer` *(sửa)* | Đổi trạng thái sang `P.KD xác nhận` |
| Lớp kiểm quyền *(mới)* | Kiểm custom permission + người tạo phiếu, dùng chung cho mọi method |

### 4.3. LWC

| Việc | Chi tiết |
|---|---|
| Nhận `recordId` | Để biết đang mở phiếu nào khi đặt trên Record Page |
| Nạp lại dữ liệu | Dựng lại bảng 28 cột từ JSON đã lưu |
| Tính bước hiện tại | Suy từ trạng thái phiếu |
| Khoá theo quyền | Không đủ quyền → chỉ xem + thông báo đang chờ ai |
| Sửa nút | Nút submit từng bước thay cho luồng đi thẳng hiện tại |

### 4.4. Cấu hình

- Tạo user hoặc cấp permission set cho nhân sự P.QLCL
- Chọn và áp dụng phương án xử lý xung đột quyền (Mục 3.2)

---

## 5. Ảnh hưởng tới tính năng đã có

| Tính năng | Ảnh hưởng |
|---|---|
| **Trích PDF** | Record đã tồn tại từ bước 1 → chỉ còn sinh và đính file, không tạo record nữa |
| **Gửi cho khách hàng** | Thêm việc đổi trạng thái sang `P.KD xác nhận` |
| **Nút "Yêu cầu hiệu chỉnh"** | Đổi ý nghĩa: từ "quay lại xem" thành **trả phiếu về phòng trước**, phải lùi trạng thái |
| **Chế độ chỉ xem** | Dùng lại được cơ chế đã làm, chỉ đổi điều kiện kích hoạt |
| **Xuất Excel, Import CSV, watermark, chia trang** | Không ảnh hưởng |

---

## 6. Rủi ro

| Rủi ro | Mức | Ghi chú |
|---|---|---|
| **Không có người P.QLCL** → phiếu kẹt vĩnh viễn ở bước 2 | **Cao** | Phải giải quyết trước khi bật quy trình |
| Phiếu bị bỏ dở, không ai theo dõi | Trung bình | Cần list view và có thể cần nhắc việc |
| Ghi đè phiếu đang xử lý của người khác | Trung bình | Xem Mục 3.5 |
| Hai người cùng mở một phiếu, sửa đè nhau | Trung bình | Salesforce không tự khoá bản ghi |
| Quyền nằm trong code, admin không thấy trên Setup | Thấp | Nếu chọn phương án B |

---

## 7. Thứ tự triển khai đề xuất

| Giai đoạn | Nội dung |
|---|---|
| **0** | Chốt 5 vấn đề Mục 3 — **bắt buộc trước khi code** |
| **1** | Tạo custom permission, permission set, cấp cho người dùng thật |
| **2** | Sửa Apex: tạo record ở bước 1, thêm các method chuyển bước, lớp kiểm quyền |
| **3** | Sửa LWC: nạp lại phiếu, tính bước, khoá theo quyền |
| **4** | List view + đặt wizard lên Record Page |
| **5** | Chạy thử toàn trình với người thật của cả hai phòng |

Giai đoạn 2 và 3 là phần nặng nhất. Giai đoạn 5 **bắt buộc có người thật của P.QLCL tham gia**,
không thử một mình được.

---

## 8. Nhận xét

Thay đổi này **đúng hướng** — bộ 4 trạng thái vốn đã được thiết kế cho quy trình liên phòng
nhưng chưa bao giờ được dùng. Việc này lấp đúng khoảng trống đó.

Nhưng cần lưu ý: nó **phủ định một quyết định vừa đưa ra hôm nay** (OWD Public Read Only,
chỉ chủ sở hữu sửa được). Không phải sai — mà vì lúc đó chưa biết quy trình là liên phòng.
Nên trước khi bắt tay, hãy chốt lại Mục 3.2 với người ra quyết định về phân quyền.
