# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Toàn bộ dự án (comment, nhãn giao diện, tài liệu) dùng tiếng Việt — trả lời và viết comment bằng tiếng Việt.

## Dự án là gì

Quản lý và in **Phiếu Chứng Nhận Chất Lượng / Mill Test Certificate (MTC)** cho thép cuộn cán nóng
của Hòa Phát Dung Quất, chạy trên Salesforce (sandbox alias `hpdqDev`).

Luồng nghiệp vụ: nhân viên QLCL nhập SO + danh sách ID cuộn → Apex gọi API hệ thống **BK** lấy số liệu
thí nghiệm → kiểm tra/hiệu chỉnh → lưu phiếu vào `HPDQ_Certificate__c` → sinh PDF đính vào record và in.

## Lệnh thường dùng

```powershell
# Deploy (luôn cần --ignore-conflicts: bản trên org từng bị sửa qua Developer Console)
sf project deploy start -d force-app -o hpdqDev --ignore-conflicts

# Chỉ một phần
sf project deploy start -d force-app/main/default/classes -o hpdqDev --ignore-conflicts
sf project deploy start -d force-app/main/default/lwc/qcRequestWizard -o hpdqDev --ignore-conflicts

# Validate mà không ghi lên org
sf project deploy start -d force-app -o hpdqDev --dry-run --ignore-conflicts

# Test (chỉ có 1 test class)
sf apex run test -o hpdqDev -n QCRequestControllerTest -y -w 10
```

Nhiều đường dẫn tuyệt đối chứa `OneDrive - hoaphat.com.vn` và dấu tiếng Việt — luôn bọc trong dấu ngoặc kép.
Có một thư mục `Documents\Khoa-dev\...` **không phải OneDrive** không chứa `sfdx-project.json`; chạy `sf` ở đó
sẽ báo `InvalidProjectWorkspaceError`.

## Kiến trúc

```
LWC qcRequestWizard (3 bước)
  ├─ Bước 1: form → QCRequestController.fetchData()  → HTTP callout tới BK
  ├─ Bước 2: bảng nhập liệu, sửa tại chỗ (rawRows là nguồn sự thật)
  └─ Bước 3: xem trước + Trích PDF
                ├─ saveCertificate(certJson)  → upsert HPDQ_Certificate__c   [transaction 1]
                └─ attachPdf(certId)          → getContentAsPDF + ContentVersion [transaction 2]

Visualforce HPDQ_MTC_Certificate  (controller HPDQ_CertificatePdfController)
  ├─ ?id=X&pdf=1  → renderAs="pdf", engine dựng PDF
  └─ ?id=X        → HTML (tab "Trang In"), in từ trình duyệt
  Controller CHIA TRANG CHO CẢ HAI chế độ — `renderMode` chỉ đổi cách render, không
  đổi việc cắt trang. Đo thật: phiếu 130 cuộn ra 7 khối `.pg` ở cả HTML lẫn PDF.
```

Trước đây có thư mục `preview/` (dựng lại wizard bằng dữ liệu giả để sửa giao diện không cần deploy,
kèm `cert-print-fallback.html` là bản in dự phòng). **Đã xoá ngày 03/08/2026 theo yêu cầu**; bản nén
`preview-backup-20260803.zip` còn ở thư mục gốc. Từ nay muốn xem giao diện phải deploy lên sandbox.

**Named Credential**: Apex gọi BK qua `callout:HPDQ_PL_COS` (External Credential `HPDQ_PL_COS_Authen`,
Basic auth, principal `Admin` = tài khoản `crm_api`). Không có username/password nào trong code.
User phải được cấp *External Credential Principal Access* qua permission set, kể cả admin.

**Logic hiển thị bị nhân bản ở 2 nơi** — sửa một chỗ phải sửa cả hai, và chúng ĐÃ từng lệch nhau:
`qcRequestWizard.js` (màn hình) và `HPDQ_CertificatePdfController.cls` (PDF + trang in).
Gồm: `CHEM_DIVISOR`, thông tin công ty, quy tắc format số, gom nhóm đơn vị hóa học, câu kết luận,
`docCode`, quy tắc in chữ "C" cho chiều dài.

**Logo cũng nhân bản ở 2 nơi**: Static Resource `HPDQ_MTC_LogoLeft` / `HPDQ_MTC_LogoRight` (trang
Visualforce) và hằng base64 `LOGO_LEFT` / `LOGO_RIGHT` trong `lwc/qcRequestWizard/logos.js` (màn hình).
`HPDQ_MTC_Watermark` là ảnh **dẫn xuất từ LogoLeft** — đổi logo phải sinh lại watermark.

## Giới hạn của engine PDF Salesforce — ĐÃ KIỂM CHỨNG, ĐỪNG THỬ LẠI

Đây là phần tốn nhiều thời gian nhất của dự án. Tất cả đều kiểm bằng cách sinh PDF thật rồi phân tích file.

| Thứ | Kết quả | Hệ quả |
|---|---|---|
| Nhúng font qua `@font-face` | **Không hoạt động** (thử cả Static Resource lẻ và gói ZIP; đọc `/BaseFont` trong PDF thấy vẫn là font base-14) | Tiếng Việt chỉ dùng được `Arial Unicode MS` — font Unicode duy nhất engine có |
| `font-weight: bold` | **Bị bỏ qua** — Arial Unicode MS không tồn tại bản đậm | PDF server không có chữ đậm. Font base-14 (Times/Helvetica) có bản đậm nhưng chỉ phủ WinAnsi → mất dấu ế/ứ/ậ/ượ |
| `thead { display: table-header-group }` | **Bị bỏ qua** | Không tự lặp được header → phải tự chia trang |
| `-fs-table-paginate: paginate` | **CÓ hoạt động** (thuộc tính riêng của engine) | Nhưng vỡ nếu trong `thead` có thẻ `img` hoặc bảng lồng |
| Logo làm `background-image` của ô `th` trong `thead` | **CÓ hoạt động**, lặp mọi trang | Cách duy nhất để lặp logo tự động |
| Ảnh trong `@page` margin box | **Không render** | Chữ thì được (số trang `Page x/y` đang dùng cách này) |
| `position: running()` + `content: element()` | Bị loại khỏi luồng nhưng **không vẽ ra** | Không dùng được |
| `width: 12%` trên ô bảng | **Bị bỏ qua** khi bảng gần chật (28 cột) | Cột Ghi chú từng bị bóp còn 12pt → phải dùng đơn vị tuyệt đối `70pt` |
| Bề rộng ô header, kể cả `pt` + `table-layout: fixed` | **Vẫn bị bỏ qua** | Đo: đổi % → pt → thêm `fixed`, tiêu đề chỉ dịch 282,6 → 284,7 → 286,6 thay vì ~37pt. Ô luôn co giãn theo nội dung. **Không canh chỉnh gì dựa vào bề rộng ô** |
| `height` cố định trên bảng header | **CÓ hoạt động** | Đã chứng minh: đổi logo phải 46px → 20px, mọi dòng bên dưới đứng nguyên (550/530,1/507,9/…). Nhờ vậy đổi logo không còn ảnh hưởng 4 ngân sách chia trang |
| `background-color` trên ô bảng | **Không render** | PDF sinh ra không có lệnh `re` nào. Không dùng nền màu để phân biệt ô, và cũng không đo được biên ô bằng cách này |
| `white-space: nowrap` trên `th`/`td` | Làm tổng bề rộng vượt khổ giấy | Cột cuối bị đẩy ra ngoài / bóp chết. **Không dùng** |
| `opacity` và `transform: rotate()` cho watermark | **Bị bỏ qua cả hai** | Mọi thứ phải **nung sẵn vào ảnh** |
| Watermark làm `background-image` của khối trang `.pg` | **CÓ hoạt động** | Không cần `position: fixed`. Mỗi khối `.pg` là một trang nên background tự lặp đúng mỗi trang |
| `background-repeat: repeat-x` / `repeat-y` | **CÓ hoạt động** | Đã kiểm bằng toạ độ `cm ... Do` trong content stream: `repeat-x` cho X thay đổi Y cố định, `repeat-y` thì ngược lại. **Không có** cách lặp chéo |

### Ảnh watermark `HPDQ_MTC_Watermark`

Vì engine bỏ qua cả `opacity`, `transform` lẫn lặp chéo, **cả dải watermark được vẽ sẵn vào một ảnh**:
canvas 1060×730px (khớp vùng in A4 ngang @96dpi), chứa 3 logo xoay −45° pha 30% trên nền trắng,
tâm cách nhau 315px dọc theo đường chéo. CSS chỉ cần `no-repeat` + `background-position: center`.

Sinh lại bằng PowerShell + System.Drawing (`ColorMatrix.Matrix33` = độ mờ, `RotateTransform` = góc xoay).
Đổi số lượng logo / độ mờ / góc nghiêng **phải sinh lại ảnh**, sửa CSS vô ích.
Đo sau khi đổi: 7 trang, mỗi trang 3 lệnh `Do` = 2 logo header + 1 dải watermark.

Kết luận: muốn có serif + chữ đậm giống mẫu in thì phải in từ **trình duyệt** (chế độ HTML của trang,
tab "Trang In"), hoặc mua app sinh tài liệu, hoặc render bằng service ngoài.

## Chia trang trong HPDQ_CertificatePdfController

Chỉ áp dụng cho chế độ `pdf=1`. Chế độ HTML trả về **một trang duy nhất** chứa tất cả cuộn.

- Chia trang chạy cho **cả hai** chế độ (xem sơ đồ kiến trúc), nhưng 4 ngân sách dưới đây đo theo khổ giấy
  của bản PDF.
- Đơn vị là **"chỗ"** chứ không phải số hàng: `chỗ = UNITS_ROW_BASE + UNITS_EXTRA_LINE × (số dòng ghi chú thêm)`.
  Padding ô chỉ tính một lần cho cả hàng nên hàng 4 dòng chỉ cao ~2,5 lần hàng 1 dòng, không phải 4 lần.
- **Tách 2 tham số là cố ý**: gộp thành một hệ số thì tăng độ an toàn cho hàng nhiều dòng sẽ kéo giá hàng
  1 dòng lên theo, làm phiếu ghi chú rỗng phình thêm 50% số trang.
- Số dòng ghi chú tính bằng `wrapLines()` — **mô phỏng ngắt theo TỪ**. Chia độ dài cho số ký tự thì ước hụt
  (đo thật: 84 ký tự → chia ra 4 nhưng render 5 dòng) và gây tràn trang.
- 4 ngân sách khác nhau theo loại trang (trang đầu có khối thông tin, trang cuối có kết luận + ô ký + hàng tổng).
- Ngân sách trang cuối còn bị trừ thêm theo độ dài `HPDQ_Note__c`.
- Thuật toán: lấp đầy trang hiện tại rồi mới sang trang mới; nếu lấp đầy sẽ ăn hết phần còn lại thì để lại
  tối thiểu 1 dòng cho trang cuối có chỗ in kết luận. Trang chót luôn bị ép `isLast = true`.

**Đổi cỡ chữ bảng, padding ô, chiều cao logo, hay thêm/bớt khối nào ở trang cuối → PHẢI đo lại 4 ngân sách.**
Đo từng loại trang RIÊNG LẺ; đo cả bộ cùng lúc thì không biết cái nào tràn (lỗi này từng làm ngân sách
trang giữa thấp hơn thực tế 3 hàng).

### Cách đo (kỹ thuật quan trọng)

Không thể xem PDF trực tiếp. Cách kiểm đã dùng suốt dự án:

1. Chạy Anonymous Apex gọi `Page.HPDQ_MTC_Certificate.getContentAsPDF()`, in base64 ra debug log theo
   từng khối ~3000 ký tự.
2. Ghép lại ở máy → file PDF.
3. Đếm `/Type /Page` để biết số trang; giải nén content stream (deflate, bỏ 2 byte header zlib) rồi đếm
   lệnh vẽ ảnh `Do` mỗi trang.
4. **Trang nào không vẽ logo là trang bị tràn** — vì logo chỉ được in ở đầu mỗi khối do controller tạo.
   Điều kiện đạt: `số trang PDF == số trang có logo`.

Chữ trong PDF bị mã hoá CID nên **không đọc được bằng grep** — đừng cố kiểm nội dung bằng cách tìm chuỗi
trong file PDF. Muốn kiểm nội dung thì gọi `getContent()` (bản HTML) và tìm chuỗi trong đó.

## Bẫy đã gặp

- **Visualforce parse cả trang như XML**: viết tên thẻ kèm dấu ngoặc trong comment CSS (ví dụ `<thead>`)
  làm deploy fail với lỗi "must be terminated by the matching end-tag".
- **Từ khoá Apex**: `end` và `from` là reserved word, không dùng làm tên biến.
- **BOM**: `Set-Content -Encoding UTF8` thêm BOM → `sf apex run --file` báo `Invalid identifier`.
  Dùng `[IO.File]::WriteAllText(path, text, (New-Object Text.UTF8Encoding($false)))`.
- **Đọc file UTF-8 trong PowerShell**: `Get-Content -Raw` mặc định đọc theo ANSI, làm hỏng tiếng Việt.
  Dùng `[IO.File]::ReadAllText(path, [Text.Encoding]::UTF8)`.
- **`getContentAsPDF()` hành xử như callout**: không thấy dữ liệu chưa commit và không gọi được sau DML
  trong cùng transaction. Vì thế `saveCertificate` và `attachPdf` là **2 lần gọi Apex riêng** từ LWC.
  Trong test thì nó không dùng được (uncommitted work) → `attachPdf` có nhánh `Test.isRunningTest()`.
- **`Test.setCurrentPage()`** không gọi được ngoài test context, nên không debug controller bằng Anonymous Apex.

## Ràng buộc dữ liệu trên org

- `HPDQ_Certificate__c.HPDQ_Certificate_No__c`: Unique nhưng **không phải External ID** → không `upsert`
  theo field này được; phải SOQL tìm rồi gán `Id`.
- `HPDQ_Configuration__c`: multi-select picklist **bắt buộc**, chứa danh sách nguyên tố `C;Si;Mn;...` do BK
  trả về. Đã tắt "Restrict picklist" trên org để nguyên tố lạ vẫn lưu được.
- `HPDQ_Issue_Date__c` cũng bắt buộc. Controller kiểm cả 3 field này trước khi DML để báo lỗi tiếng Việt
  thay vì để DML trả "Required fields are missing".
- `HPDQ_Data__c`: Long Text Area 131.000 ký tự (~180 cuộn) — có kiểm và báo lỗi khi vượt.
- `HPDQ_Note__c` là Rich Text → phải lọc thẻ HTML trước khi in vào PDF.
- BK thường trả `null` cho toàn bộ cột cơ tính (`yield_strength_MPa`, `tensile_strength_MPa`,
  `elongation_pct`, `hardness_HRB`) — không phải lỗi render.
- Mẫu in **chỉ** dùng dấu phẩy hàng nghìn ở cột Khối lượng; Độ rộng in `1420` không phải `1,420`.
- Số cuộn và Mẻ số là mã định danh → không format, không chèn dấu phẩy.

## Việc còn dở

- Mã biểu mẫu / ngày hiệu lực ở góc phải header: hằng số `FORM_CODE`, `FORM_EFFECTIVE_DATE` đang **để trống
  có chủ đích**, chờ P.QLCL cung cấp. Trống thì khối đó không in.
- `HPDQ_Account__c` chưa được map (khớp `Account.HPDQ_SAP_Customer_Code__c`); sandbox có **0 Account** nên
  chưa test được.
- Bản xem trước bước 3 chưa có hàng tổng, chú thích, ô ký như trang in.
- `HPDQ_CertificatePdfController` chưa có test class riêng.
- **Logo mới ("HÒA PHÁT GANG THÉP", tỉ lệ 4,82:1) làm tiêu đề gãy dòng.** CSS ghim `.logo-l` theo chiều
  cao 74px nên logo nở ngang từ 220pt lên 267pt, lấn cột tiêu đề. Đo trên PDF: vùng header từ 2 dòng chữ
  thành 3. Sửa bằng cách hạ `.logo-l { height }` xuống ~61px, rồi đo lại.
