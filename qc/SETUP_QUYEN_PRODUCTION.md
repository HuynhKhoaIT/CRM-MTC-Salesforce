# Hướng dẫn thiết lập quyền — tái lập trên Production

Tài liệu này ghi lại **toàn bộ cấu hình quyền** đã dựng và kiểm chứng trên sandbox `hpdqDev`
ngày 05/08/2026, để tái lập nguyên vẹn trên production.

Toàn bộ làm bằng **cấu hình Setup, không cần code**.

> **Trên production:** mọi thay đổi phải gửi email yêu cầu cho đội quản trị CRM (anh Trịnh Hiếu).
> Tài liệu này dùng làm nội dung yêu cầu — copy nguyên các bảng bên dưới.

---

## Mục tiêu

| Ai | Xem | Sửa | Điều kiện |
|---|---|---|---|
| Người tạo phiếu (P. Kinh doanh) | Mọi phiếu | Phiếu mình tạo | Luôn luôn |
| **Nhân viên P. QLCL** | Mọi phiếu | **Chỉ phiếu đang ở Bước 2** | **Chỉ khi trạng thái = `Nhận dữ liệu từ BK`** |
| Nhân viên khác | Mọi phiếu | Không | — |
| Quản trị / Ban GĐ | Mọi phiếu | Mọi phiếu | Qua `Modify All` hoặc Role Hierarchy |

Điểm cốt lõi: quyền sửa của P.QLCL **tự mở khi phiếu vào Bước 2** và **tự đóng khi phiếu rời Bước 2**.
Không cần ai thao tác, không cần trigger.

---

## Bước 0 — Org-Wide Default

```
Setup → Sharing Settings → Organization-Wide Defaults → Edit
```

| Object | Default Internal Access | Default External Access | Grant Access Using Hierarchies |
|---|---|---|---|
| Quản lý in chứng chỉ chất lượng | **Public Read Only** | Private | ✅ tick |

> Bắt buộc phải là `Public Read Only`. Nếu để `Public Read/Write` thì Sharing Rule ở Bước 4
> trở nên vô nghĩa — ai cũng sửa được mọi phiếu.

Sau khi Save, Salesforce chạy lại toàn bộ quyền chia sẻ, có thể mất vài phút trên org lớn.

---

## Bước 1 — Profile `HPDQ - QLCL`

```
Setup → Profiles → chọn "HPDQ - Sales Operation" → Clone
→ Profile Name: HPDQ - QLCL → Save
```

Chọn nhân bản từ `HPDQ - Sales Operation` vì profile đó **chưa có quyền nào** trên phiếu
chứng chỉ — cấp đúng thứ cần, không thừa.

### 1.1. Object Settings → `Quản lý in chứng chỉ chất lượng` → Edit

**Tab Settings:** `Default On`

**Object Permissions:**

| Read | Create | Edit | Delete | View All | Modify All |
|---|---|---|---|---|---|
| ✅ | ❌ | ✅ | ❌ | **❌** | **❌** |

> ⚠️ **Chỗ sai nguy hiểm nhất.** Tick `View All` hoặc `Modify All` là **vô hiệu hoá toàn bộ
> Sharing Rule** — QLCL sẽ sửa được mọi phiếu ở mọi trạng thái.

> `Create` phải **bỏ tick**: Bước 1 (gửi yêu cầu) là việc của Phòng Kinh doanh.
> Từ 05/08/2026 code có thêm chốt chặn thứ hai — `HPDQ_CertificateWorkflow.taoDuocYeuCau()`
> chặn mọi thành viên nhóm `P. QLCL` **kể cả khi Profile lỡ mở quyền Create**. Màn hình wizard
> hiện thông báo thay cho form nhập, và `fetchData()` từ chối ngay trước khi gọi BK.

**Field Permissions:** tick `Read Access` + `Edit Access` cho tất cả field bắt đầu bằng `HPDQ_`.

Các field sau **bị mờ, không tick được** — Salesforce tự cấp vì là field bắt buộc hoặc field hệ thống:
`HPDQ_Certificate_No__c` · `HPDQ_Issue_Date__c` · `HPDQ_Configuration__c` · `Name` · `OwnerId` ·
`CreatedById` · `LastModifiedById` · `CurrencyIsoCode`

*(Tuỳ chọn siết chặt: bỏ tick `Edit Access` — chỉ giữ Read — cho 4 field do hệ thống tự ghi:
`HPDQ_Link__c`, `HPDQ_Account__c`, `HPDQ_Total_Coils__c`, `HPDQ_Total_Weight__c`.)*

### 1.2. Object Settings → `Yêu cầu QC` → Edit

**Tab Settings:** `Default On`

> Đây là tab chứa màn hình 3 bước. Thiếu tab này thì QLCL đăng nhập vào không thấy gì để làm.

### 1.3. Apex Class Access → Edit → thêm

- `QCRequestController`
- `HPDQ_CertificatePdfController`
- `HPDQ_GradeStandards`
- `HPDQ_CertificateWorkflow`

> **Không cấp** `HPDQ_SendCertificate` — gửi mail cho khách là việc của P.KD ở Bước 3.

### 1.4. Visualforce Page Access → Edit → thêm

- `HPDQ_MTC_Certificate`

---

## Bước 2 — Public Group `P. QLCL`

```
Setup → Public Groups → New
```

| Ô | Giá trị |
|---|---|
| Label | `P. QLCL` |
| Group Name | `P_QLCL` |
| **Grant Access Using Hierarchies** | **❌ bỏ tick** |

> Bỏ tick để quyền sửa của QLCL **không lan ngược lên cấp trên** trong cây phân cấp.
> Nếu để tick, trưởng phòng Kinh doanh cũng sẽ sửa được phiếu đang ở Bước 2.

**Thêm thành viên:** đổi ô `Search` sang **`Users`** → tìm và Add từng nhân viên P.QLCL.

---

## Bước 3 — Gán người dùng

Mỗi nhân viên P.QLCL cần **hai thao tác**:

| # | Việc | Ở đâu |
|---|---|---|
| 1 | Gán Profile `HPDQ - QLCL` | Setup → Users → user → Edit → Profile |
| 2 | Thêm vào Public Group `P. QLCL` | Setup → Public Groups → P. QLCL → Edit |

> Quên một trong hai là họ **không làm việc được**, mà thông báo lỗi không nói rõ thiếu cái nào.
> Profile lo tầng **object**, Group lo tầng **bản ghi** — phải có cả hai.

---

## Bước 4 — Criteria-Based Sharing Rule

```
Setup → Sharing Settings
→ "Manage sharing settings for:" chọn "Phiếu Chứng Nhận Chất Lượng"
→ khu Sharing Rules → New
```

| Ô | Giá trị |
|---|---|
| Label | `QLCL sua phieu o buoc 2` |
| Rule Name | `QLCL_sua_phieu_o_buoc_2` |
| **Rule Type** | **Based on criteria** |
| Field | `Trạng thái phiếu:` |
| Operator | `equals` |
| **Value** | `Nhận dữ liệu từ BK` |
| Share with | **Public Groups** → `P. QLCL` |
| Access Level | **Read/Write** |

> ⚠️ Ô **Value** phải gõ **đúng y hệt** giá trị picklist, kể cả dấu tiếng Việt. Sai một ký tự
> thì rule không khớp phiếu nào — và triệu chứng nhìn giống hệt "cơ chế hỏng".

Save → hiện cảnh báo tính lại quyền → **OK**.

---

## Bước 5 — Nghiệm thu

Chạy Anonymous Apex sau, thay `<username>` bằng tài khoản QLCL thật:

```apex
Id u = [SELECT Id FROM User WHERE Username = '<username>'].Id;
for (HPDQ_Certificate__c c : [SELECT Id, HPDQ_Certificate_No__c, HPDQ_Status__c
                              FROM HPDQ_Certificate__c LIMIT 20]) {
    UserRecordAccess a = [SELECT RecordId, HasReadAccess, HasEditAccess
                          FROM UserRecordAccess WHERE UserId = :u AND RecordId = :c.Id];
    System.debug('QA|' + c.HPDQ_Certificate_No__c
        + ' | ' + c.HPDQ_Status__c
        + ' | XEM=' + a.HasReadAccess + ' SUA=' + a.HasEditAccess);
}
```

**Kết quả đúng:**

| Trạng thái phiếu | XEM | SUA |
|---|---|---|
| `Nhận dữ liệu từ BK` | true | **true** |
| Mọi trạng thái khác | true | **false** |

Trong đó `P.QLCL yêu cầu hiệu chỉnh` (phiếu bị trả về Bước 1) rơi vào nhóm "mọi trạng thái khác":
P.QLCL trả phiếu đi rồi thì mất luôn quyền sửa, đúng như mong muốn. Khi P.KD bấm "Gửi yêu cầu"
lần nữa, trạng thái quay về `Nhận dữ liệu từ BK` và quyền sửa của P.QLCL tự mở lại.

---

## Kết quả đã kiểm chứng trên sandbox

Đo ngày 05/08/2026 với tài khoản `huynhkhoa.itc@gmail.com` (profile `HPDQ - QLCL`, trong group `P. QLCL`):

| Phiếu | Trạng thái | XEM | SUA |
|---|---|---|---|
| `0000-070726/HOAPHAT` | Nhận dữ liệu từ BK | ✅ | ✅ |
| `TEST-3PAGE/HOAPHAT` | Nhận dữ liệu từ BK | ✅ | ✅ |
| `0000-070826/HOAPHAT` | Đã gửi khách hàng | ✅ | ❌ |

**Kiểm chứng cơ chế tự đóng/mở** trên phiếu `TEST-3PAGE`:

| Thao tác | Kết quả |
|---|---|
| Trạng thái `Nhận dữ liệu từ BK` | SUA = **có** |
| Đổi sang `P.QLCL xác nhận` | SUA = **mất** |
| Trả về `Nhận dữ liệu từ BK` | SUA = **có lại** |

---

## Lưu ý quan trọng khi vận hành

### Quyền thu hồi CHẬM vài giây

Salesforce tính lại quyền chia sẻ **bất đồng bộ**, sau khi transaction kết thúc.

Hệ quả:
- Có **độ trễ vài giây** giữa lúc P.QLCL bấm submit và lúc họ thật sự mất quyền sửa
- **Không được** kiểm `UserRecordAccess` ngay trong cùng transaction vừa đổi trạng thái — kết quả sẽ sai
- Vì vậy code kiểm quyền nghiệp vụ **dựa vào trạng thái phiếu**, không dựa vào quyền chia sẻ

### Sandbox refresh sẽ xoá sạch

Nếu sandbox được làm mới từ production, toàn bộ profile / group / sharing rule ở đây **mất hết**.
Dùng tài liệu này để dựng lại.

### Thêm người P.QLCL mới

Chỉ cần làm **Bước 3** (gán profile + thêm vào group). Không phải sửa gì khác.

### Giấy phép

Mỗi tài khoản P.QLCL tiêu tốn **một giấy phép Salesforce**. Kiểm số còn trống trước khi cấp:

```
Setup → Company Information → User Licenses
```

*(Tính đến 05/08/2026, sandbox đã dùng hết 38/38 giấy phép Salesforce.)*
