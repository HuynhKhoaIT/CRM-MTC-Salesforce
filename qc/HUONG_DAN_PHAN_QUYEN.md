# Hướng dẫn phân quyền — Quản lý in Chứng Chỉ Chất Lượng

Đối tượng: `HPDQ_Certificate__c` (Quản lý in chứng chỉ chất lượng)
Org: sandbox `hpdqDev`

## Mục tiêu

| Ai | Xem | Sửa | Xoá |
|---|---|---|---|
| Admin / Manager system | Tất cả phiếu | Tất cả phiếu | Có |
| Người tạo phiếu | Tất cả phiếu | **Chỉ phiếu mình tạo** | Không |
| Còn lại | Tất cả phiếu | Không | Không |

## Hiểu trước khi làm: Salesforce chặn ở HAI tầng

Quyền trong Salesforce không phải một tầng. Phải hiểu rõ nếu không sẽ cấu hình sai:

| Tầng | Quyết định | Cấu hình ở đâu |
|---|---|---|
| **Tầng 1 — Object** | Người này có được phép Xem / Tạo / Sửa / Xoá loại bản ghi này *nói chung* không | Profile hoặc Permission Set |
| **Tầng 2 — Bản ghi** | Trong số đó, được đụng vào *những bản ghi nào* | Org-Wide Default + Sharing Rule + Role Hierarchy |

Quy tắc: **phải qua được cả hai tầng.** Có Edit ở tầng 1 mà tầng 2 chỉ cho Read thì vẫn không sửa được.

Yêu cầu "người tạo được sửa, người khác chỉ xem" chính là bài toán **tầng 2**, giải bằng
Org-Wide Default. Đừng cố giải bằng Permission Set — Permission Set không phân biệt được
ai là người tạo.

---

## Bước 1 — Đổi Org-Wide Default (QUAN TRỌNG NHẤT)

Hiện tại đang là **Public Read/Write** → ai có Edit là sửa được phiếu của người khác.

1. **Setup** (bánh răng góc phải) → **Setup**
2. Ô Quick Find gõ `Sharing Settings` → mở **Sharing Settings**
3. Khu **Organization-Wide Defaults** → bấm **Edit**
4. Tìm dòng **Quản lý in chứng chỉ chất lượng**
5. Cột **Default Internal Access**: đổi từ `Public Read/Write` sang **`Public Read Only`**
6. Cột **Grant Access Using Hierarchies**: **để nguyên tick** (cấp trên trong Role Hierarchy
   tự thấy và sửa được phiếu của cấp dưới — thường là điều mong muốn)
7. **Save**

Sau bước này Salesforce chạy lại toàn bộ quyền chia sẻ. Org nhỏ thì vài giây, org lớn có
thể vài phút và bạn nhận email khi xong.

**Ngay lập tức bạn đã có:** mọi người xem được tất cả phiếu; chỉ **người sở hữu bản ghi**
(mặc định là người tạo) mới sửa được phiếu của mình.

---

## Bước 2 — Permission Set cho người TẠO phiếu (nhân viên QLCL)

1. **Setup** → Quick Find `Permission Sets` → **New**
2. Điền:
   - Label: `QLCL - Lập phiếu chứng chỉ`
   - API Name: `QLCL_Lap_phieu_chung_chi`
   - License: **để trống** (`--None--`) để gán được cho mọi loại user
3. **Save**

Sau đó cấu hình từng mục bên trong permission set vừa tạo:

### 2.1. Quyền trên object

**Object Settings** → **Quản lý in chứng chỉ chất lượng**  → **Edit**

Tick: `Read`, `Create`, `Edit`
**KHÔNG tick**: `Delete`, `View All`, `Modify All`

> `View All` / `Modify All` sẽ **phá vỡ** giới hạn ở Bước 1 — người đó thành sửa được
> mọi phiếu. Đây là lỗi hay gặp nhất.

Cũng trong màn hình này, kéo xuống phần **Field Permissions**: tick `Read Access` và
`Edit Access` cho tất cả field bắt đầu bằng `HPDQ_`.

### 2.2. Quyền chạy code

**Apex Class Access** → **Edit** → thêm:
- `QCRequestController`
- `HPDQ_CertificatePdfController`
- `HPDQ_GradeStandards`

**Visualforce Page Access** → **Edit** → thêm:
- `HPDQ_MTC_Certificate`

### 2.3. Quyền thấy màn hình

**Object Settings** → **Quản lý in chứng chỉ chất lượng** → mục **Tab Settings** chọn
**Available** hoặc **Visible**.

### 2.4. Quyền gọi API hệ thống BK — DỄ QUÊN NHẤT

Không có quyền này thì bấm "Gửi yêu cầu" sẽ lỗi callout, **kể cả tài khoản admin**.

Org đã có sẵn permission set tên **`External Credential Principal Access`**. Cách nhanh
nhất là gán thêm permission set đó cho user (xem Bước 5).

Nếu muốn gộp vào permission set vừa tạo: trong permission set, mục
**External Credential Principal Access** → **Edit** → thêm principal **`Admin`** của
external credential `HPDQ_PL_COS_Authen`.

---

## Bước 3 — Permission Set cho người CHỈ XEM

1. **Setup** → `Permission Sets` → **New**
   - Label: `QLCL - Xem phiếu chứng chỉ`
   - API Name: `QLCL_Xem_phieu_chung_chi`
2. **Object Settings** → **Quản lý in chứng chỉ chất lượng** → **Edit**
   - Tick **chỉ** `Read`
   - Field Permissions: **chỉ** `Read Access`
3. **Apex Class Access**: thêm `HPDQ_CertificatePdfController` và `HPDQ_GradeStandards`
   *(không cần `QCRequestController` vì họ không gửi yêu cầu)*
4. **Visualforce Page Access**: thêm `HPDQ_MTC_Certificate` *(để mở được tab "Trang In")*
5. **Tab Settings**: `Visible`

Nhóm này **không cần** External Credential Principal Access.

---

## Bước 4 — Admin và Manager system

**Admin** dùng profile *System Administrator* thì đã có sẵn `Modify All Data` — **không
phải làm gì thêm**, ngoài việc gán External Credential Principal Access nếu họ cần bấm
"Gửi yêu cầu".

**Manager system** (hoặc trưởng phòng cần thấy/sửa mọi phiếu) — tạo thêm permission set:

1. **Setup** → `Permission Sets` → **New**
   - Label: `QLCL - Quản trị phiếu chứng chỉ`
   - API Name: `QLCL_Quan_tri_phieu_chung_chi`
2. **Object Settings** → **Quản lý in chứng chỉ chất lượng** → **Edit**
   - Tick: `Read`, `Create`, `Edit`, `Delete`, **`View All`**, **`Modify All`**
   - Field Permissions: `Read` + `Edit` tất cả field
3. **Apex Class Access** và **Visualforce Page Access**: thêm như Bước 2.2

`Modify All` chính là thứ cho phép vượt qua giới hạn "chỉ sửa phiếu mình tạo".

---

## Bước 5 — Gán permission set cho người dùng

Cách gán nhiều người một lúc:

1. Mở permission set cần gán
2. Bấm **Manage Assignments** → **Add Assignment**
3. Tick những user cần gán → **Next** → **Assign**

Gán như sau:

| Nhóm người dùng | Permission set cần gán |
|---|---|
| Nhân viên QLCL lập phiếu | `QLCL - Lập phiếu chứng chỉ` **+** `External Credential Principal Access` |
| Nhân viên chỉ tra cứu | `QLCL - Xem phiếu chứng chỉ` |
| Trưởng phòng / Manager system | `QLCL - Quản trị phiếu chứng chỉ` **+** `External Credential Principal Access` |
| Admin (System Administrator) | `External Credential Principal Access` |

> **Mẹo:** nếu số người nhiều và hay thay đổi, gom các permission set vào một
> **Permission Set Group** rồi gán group cho user. Sau này sửa quyền chỉ sửa ở group.

---

## Bước 6 — Kiểm tra lại (chỉ cần MỘT tài khoản)

Bạn **không cần** và **không thể** tạo tài khoản test: sandbox đã dùng hết 38/38 giấy phép
Salesforce. Nhưng sandbox có sẵn ~38 user thật copy từ production, nên dùng luôn họ.

### Cách A — Script kiểm quyền, KHÔNG cần đăng nhập (nhanh nhất)

```powershell
sf apex run -o hpdqDev -f scripts\kiem-quyen.apex
```

Rồi tìm các dòng có `QA|` trong log. Kết quả dạng:

```
Chu so huu: Nguyen Huynh Khoa
Nguyễn Ngọc Sơn        | HPDQ - Customer Services | XEM --- ---
Chu Ngọc Quỳnh Phương  | HPDQ - Domestic Sales    | --- --- ---
CNTT Phong IT          | System Administrator     | XEM SUA XOA
```

Script đọc bảng `UserRecordAccess` — bảng Salesforce tự tính, cho biết **chính xác** một
user có quyền gì trên một bản ghi, đã gộp cả quyền object lẫn quyền bản ghi.

**Chạy trước và sau khi đổi OWD** để thấy khác biệt. Đây là cách kiểm đáng tin nhất vì nó
đọc đúng thứ Salesforce dùng để quyết định, không phải suy đoán từ cấu hình.

### Hiện trạng đo được (trước khi làm gì)

| Profile | Xem | Sửa | Xoá |
|---|---|---|---|
| System Administrator | ✅ | ✅ | ✅ |
| HPDQ - IT | ✅ | ✅ | ✅ |
| HPDQ - Manager | ✅ | ❌ | ❌ |
| HPDQ - Customer Services | ✅ | ❌ | ❌ |
| HPDQ - Domestic Sales / Export Sales / Sales Operation | ❌ | ❌ | ❌ |

Nghĩa là hiện tại **phần lớn nhân viên còn không xem được phiếu** — chưa đạt yêu cầu
"còn lại chỉ có quyền xem". Sau khi làm Bước 1–5 thì các dòng trên phải chuyển thành ✅ ở
cột Xem.

### Cách B — Đăng nhập thử dưới danh nghĩa người dùng (kiểm giao diện thật)

Cách A chỉ kiểm được quyền dữ liệu. Muốn kiểm nút Edit có ẩn không, wizard có chạy không
thì phải vào giao diện thật:

1. **Setup** → Quick Find `Login Access Policies` → tick
   **Administrators Can Log In As Any User** → **Save**
   *(chỉ cần làm một lần)*
2. **Setup** → `Users` → tìm user muốn thử → bấm chữ **Login** ở đầu dòng
3. Thử theo bảng tình huống bên dưới
4. Xong bấm **Log out** trên thanh trên cùng để quay về tài khoản của bạn

Không cần biết mật khẩu của họ.

> Nếu không thấy chữ **Login**, tài khoản của bạn thiếu quyền `Modify All Data` hoặc
> `Manage Users`. Nhờ CNTT Phòng IT (System Administrator) cấp hoặc nhờ họ thử giúp.

### Bảng tình huống cần thử

Danh sách cần thử:

| Thử với | Kết quả đúng phải là |
|---|---|
| Người chỉ xem, mở phiếu người khác tạo | Thấy đầy đủ, **không có nút Edit** |
| Người chỉ xem, mở tab "Trang In" | In được bình thường |
| Người tạo phiếu, mở **phiếu mình tạo** | Sửa được |
| Người tạo phiếu, mở **phiếu người khác tạo** | Xem được, **không sửa được** |
| Người tạo phiếu, bấm "Gửi yêu cầu" | Lấy được dữ liệu từ BK |
| Manager, mở phiếu bất kỳ | Sửa được hết |

### Mẹo: tạo phiếu do người khác sở hữu để thử

Muốn thử tình huống *"người tạo phiếu mở phiếu người khác tạo"* mà mọi phiếu hiện có đều
do bạn tạo, thì đổi chủ sở hữu một phiếu sang người khác: mở phiếu → menu ▾ góc phải →
**Change Owner** → chọn user khác. Sau đó chạy lại script Cách A để xác nhận bạn đã mất
quyền Sửa trên phiếu đó.

---

## Cảnh báo — đọc trước khi triển khai lên production

### 1. Hai người cùng làm một số phiếu sẽ bị lỗi

Code lưu phiếu theo quy tắc: **trùng số phiếu thì ghi đè bản ghi cũ**. Sau khi đổi OWD
sang Read Only, nếu nhân viên A đã tạo phiếu số `X`, rồi nhân viên B chạy lại đúng số
phiếu `X`, thì B **không ghi đè được** (B không sở hữu bản ghi) và sẽ nhận lỗi
*"Không lưu được phiếu: ..."*.

Đây là hệ quả trực tiếp của yêu cầu "chỉ người tạo được sửa". Ba cách xử lý:

- **Chấp nhận** — ai lập phiếu nào thì người đó phụ trách phiếu đó. Cần B sửa thì admin
  chuyển quyền sở hữu (nút **Change Owner** trên bản ghi).
- **Tạo Sharing Rule** cho nhóm QLCL quyền Read/Write — nhưng như vậy cả nhóm sửa được
  của nhau, **mất** ý nghĩa "chỉ người tạo được sửa".
- **Dùng Role Hierarchy** — để trưởng nhóm QLCL đứng trên các nhân viên trong cây vai trò,
  khi đó trưởng nhóm tự có quyền sửa phiếu của mọi nhân viên dưới quyền.

### 2. Code chưa kiểm quyền field

`QCRequestController` và `HPDQ_CertificatePdfController` đều khai `with sharing`, nên
**quyền theo bản ghi được áp dụng đúng** — đây là thứ bảo vệ mô hình ở trên.

Nhưng Apex **không tự kiểm quyền field (FLS)**. Hiện chỉ có một chỗ kiểm thủ công là
`isCreateable()` trước khi tạo phiếu. Nghĩa là nếu khoá quyền sửa một field cụ thể cho ai
đó, họ **vẫn ghi được vào field đó** qua màn hình wizard.

Chưa ảnh hưởng tới yêu cầu hiện tại (vì phân quyền đang ở mức cả bản ghi, không phải từng
field), nhưng **nên bổ sung trước khi lên production** — đây là điểm review bảo mật của
Salesforce sẽ soi.

### 3. Đổi OWD ảnh hưởng toàn org

Bước 1 là thiết lập cấp tổ chức, tác động tới **mọi người dùng ngay lập tức**. Nên làm
ngoài giờ cao điểm và báo trước cho P.QLCL.
