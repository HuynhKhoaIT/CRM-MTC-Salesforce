/**
 * QCRequestController
 * -------------------
 * Gọi API GetData của hệ thống BK và trả dữ liệu về cho LWC "qcRequestWizard".
 *
 * Endpoint: POST https://apiplcos.hoaphatdungquat.vn:60524/api/HRC_Product/GetData
 * Body gửi đi: { "so", "ListID": [...], "Transporter", "CustomerCode" }
 *
 * ĐIỀU KIỆN: Named Credential "HPDQ PL-COS" (API name HPDQ_PL_COS) trỏ tới
 *   https://apiplcos.hoaphatdungquat.vn:60524, dùng External Credential "HPDQ PL-COS Authen".
 *   Salesforce tự gắn header Authorization -> Apex không giữ username/password.
 *   User chạy màn hình QC phải được cấp quyền External Credential Principal Access.
 *   Không cần Remote Site Setting khi đã dùng Named Credential.
 */
public with sharing class QCRequestController {

    // 'callout:<API name của Named Credential>' — URL thật cấu hình trong Setup
    private static final String NAMED_CREDENTIAL = 'callout:HPDQ_PL_COS';
    private static final String GET_DATA_PATH    = '/api/HRC_Product/GetData';

    /**
     * Bước 1 → Bước 2: gọi BK lấy dữ liệu chứng chỉ theo danh sách ID.
     */
    @AuraEnabled
    public static CertData fetchData(String so, String transporter,
                                     String customerCode, List<String> listId) {
        // Bắt buộc: SO, Customer Code, Danh sách ID. Transporter để trống vẫn gọi được.
        // Chặn NGAY, trước khi gọi BK: giao diện đã ẩn form nhưng người dùng vẫn có thể gọi
        // thẳng phương thức Apex này. Chặn ở đây cũng khỏi tốn một lượt callout vô ích.
        if (!HPDQ_CertificateWorkflow.taoDuocYeuCau()) {
            throw new AuraHandledException(HPDQ_CertificateWorkflow.LOI_KHONG_TAO_DUOC);
        }
        if (String.isBlank(so)) {
            throw new AuraHandledException('Vui lòng nhập Số (SO).');
        }
        if (String.isBlank(customerCode)) {
            throw new AuraHandledException('Vui lòng nhập Customer Code.');
        }
        if (listId == null || listId.isEmpty()) {
            throw new AuraHandledException('Danh sách ID đang trống.');
        }

        // 1) Dựng body đúng định dạng BK yêu cầu
        Map<String, Object> body = new Map<String, Object>{
            'so'           => so,
            'ListID'       => listId,
            'Transporter'  => transporter,
            'CustomerCode' => customerCode
        };

        // 2) Gọi HTTP POST
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + GET_DATA_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        // Không set header Authorization: Named Credential tự sinh từ External Credential
        req.setBody(JSON.serialize(body));
        req.setTimeout(120000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new AuraHandledException('Không kết nối được tới BK: ' + e.getMessage());
        }

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException(
                'API trả lỗi HTTP ' + res.getStatusCode() + ' - ' + res.getStatus());
        }

        // 3) Đọc JSON trả về
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Object statusObj = root.get('status');
        if (statusObj != null && String.valueOf(statusObj) != '1') {
            String msg = (String) root.get('message');
            throw new AuraHandledException('BK báo lỗi: ' + (msg != null ? msg : String.valueOf(statusObj)));
        }
        Map<String, Object> data = (Map<String, Object>) root.get('data');
        if (data == null) {
            throw new AuraHandledException('API không trả dữ liệu (trường data rỗng).');
        }

        // 4) Map sang DTO cho LWC
        CertData out = new CertData();
        out.so            = so;
        out.transporter   = transporter;
        out.listIdText    = String.join(listId, ', ');
        out.name          = str(data.get('Name'));
        out.certNo        = str(data.get('HPDQ_Certificate_No__c'));
        out.issueDate     = str(data.get('HPDQ_Issue_Date__c'));
        out.project       = str(data.get('HPDQ_Project__c'));
        out.product       = str(data.get('HPDQ_Product__c'));
        out.grade         = str(data.get('HPDQ_Grade__c'));
        out.customerCode  = str(data.get('HPDQ_SAP_Customer_Code__c'));
        out.standard      = str(data.get('HPDQ_Standard__c'));
        out.contract      = str(data.get('HPDQ_Contract__c'));
        out.totalWeight   = num(data.get('HPDQ_Total_Weight__c'));
        out.totalCoils    = num(data.get('HPDQ_Total_Coils__c'));
        out.configuration = str(data.get('HPDQ_Configuration__c'));

        // Loại hàng hóa / Tiêu chuẩn / Số License SUY RA TỪ MÁC THÉP (bảng quy định
        // tiêu chuẩn), không lấy của BK — BK trả các trường này không đồng nhất.
        // Mác thép CHƯA có trong bảng thì GIỮ NGUYÊN giá trị BK, không xóa trắng:
        // thà in giá trị cũ còn hơn ra phiếu trống hai dòng này.
        HPDQ_GradeStandards.Row gs = HPDQ_GradeStandards.lookup(out.grade);
        if (gs != null) {
            out.product  = gs.product;
            out.standard = gs.standard;
            out.license  = gs.license;
        }

        // Mảng từng cuộn -> đưa nguyên cho LWC render (giữ nguyên số thô)
        out.rows = new List<Object>();
        Object rawData = data.get('HPDQ_Data__c');
        if (rawData instanceof List<Object>) {
            out.rows = (List<Object>) rawData;
        }
        // Giữ nguyên chuỗi JSON gốc để lưu vào HPDQ_Data__c
        out.dataJson = (rawData == null) ? '[]' : JSON.serialize(rawData);

        // ===== BƯỚC 1 TẠO RECORD NGAY =====
        // Trước đây record chỉ sinh ra khi bấm "Trích PDF" ở bước 3, nên đóng trình duyệt
        // giữa chừng là mất trắng và không bàn giao được giữa hai phòng. Nay tạo ngay để
        // P.QLCL có cái mà vào làm tiếp ở bước 2.
        taoHoacMoPhieu(out);
        return out;
    }

    /**
     * Tạo phiếu mới, hoặc mở lại phiếu đã tồn tại cùng số phiếu.
     *
     * Số phiếu do BK cấp và là khoá Unique. Gặp số đã tồn tại thì KHÔNG ghi đè —
     * mở phiếu cũ ra làm tiếp, vì phiếu đó có thể đang dở dang ở bước 2 hoặc 3 và
     * ghi đè sẽ xoá mất công hiệu chỉnh của P.QLCL.
     */
    private static void taoHoacMoPhieu(CertData out) {
        if (String.isBlank(out.certNo)) {
            throw new AuraHandledException('BK không trả về số phiếu — không tạo được phiếu.');
        }
        Date issueDate = toDate(out.issueDate);
        if (issueDate == null) {
            throw new AuraHandledException('BK không trả về Ngày phát hành phiếu.');
        }
        if (String.isBlank(out.configuration)) {
            throw new AuraHandledException(
                'BK không trả về danh sách thành phần phân tích (Configuration).');
        }

        List<HPDQ_Certificate__c> olds = [
            SELECT Id, HPDQ_Status__c, HPDQ_Data__c, HPDQ_Note__c, CreatedDate
            FROM HPDQ_Certificate__c WHERE HPDQ_Certificate_No__c = :out.certNo LIMIT 1
        ];
        if (!olds.isEmpty()) {
            HPDQ_Certificate__c cu = olds[0];

            // P.QLCL đã trả phiếu về Bước 1 -> đây chính là lần lấy lại dữ liệu.
            // Ghi đè số liệu mới của BK và đẩy phiếu trở lại Bước 2.
            if (cu.HPDQ_Status__c == HPDQ_CertificateWorkflow.ST_TRA_LAI) {
                lamMoiTuBK(cu, out);
                out.certId   = cu.Id;
                out.status   = cu.HPDQ_Status__c;
                out.daTonTai = true;
                out.note     = cu.HPDQ_Note__c;
                return;
            }

            // Còn lại: trả về nguyên trạng, KHÔNG đụng vào dữ liệu đang xử lý
            out.certId    = cu.Id;
            out.status    = cu.HPDQ_Status__c;
            out.daTonTai  = true;
            if (String.isNotBlank(cu.HPDQ_Data__c)) out.dataJson = cu.HPDQ_Data__c;
            out.note      = cu.HPDQ_Note__c;
            return;
        }

        if (!Schema.sObjectType.HPDQ_Certificate__c.isCreateable()) {
            throw new AuraHandledException(
                'Bạn không có quyền tạo phiếu chứng nhận chất lượng.');
        }

        HPDQ_Certificate__c c = new HPDQ_Certificate__c(
            Name                      = tenPhieu(out.project, out.certNo, Date.today()),
            HPDQ_Certificate_No__c    = cut(out.certNo, 255),
            HPDQ_Issue_Date__c        = issueDate,
            HPDQ_Configuration__c     = cut(out.configuration, 4099),
            HPDQ_Project__c           = cut(out.project, 255),
            HPDQ_Product__c           = cut(out.product, 255),
            HPDQ_Grade__c             = cut(out.grade, 255),
            HPDQ_Standard__c          = cut(out.standard, 255),
            HPDQ_Contract__c          = cut(out.contract, 255),
            HPDQ_SAP_Customer_Code__c = cut(out.customerCode, 255),
            HPDQ_Total_Coils__c       = out.totalCoils,
            HPDQ_Total_Weight__c      = out.totalWeight,
            HPDQ_LISTIDHRC__c         = cut(out.listIdText, 32768),
            HPDQ_Data__c              = out.dataJson,
            HPDQ_Status__c            = HPDQ_CertificateWorkflow.ST_BK
        );
        try {
            insert c;
        } catch (DmlException e) {
            throw new AuraHandledException('Không tạo được phiếu: ' + e.getDmlMessage(0));
        }
        out.certId   = c.Id;
        out.status   = HPDQ_CertificateWorkflow.ST_BK;
        out.daTonTai = false;
    }

    /**
     * Nạp lại toàn bộ số liệu BK lên phiếu đã bị P.QLCL trả về, rồi đẩy phiếu sang Bước 2.
     *
     * Chỉ gọi cho phiếu ở trạng thái "P.QLCL yêu cầu hiệu chỉnh" — đúng tình huống cần ghi đè.
     * Giữ nguyên Name và HPDQ_Note__c: tên phiếu đã dùng để tra cứu, ghi chú là của người dùng.
     */
    private static void lamMoiTuBK(HPDQ_Certificate__c c, CertData out) {
        c.HPDQ_Issue_Date__c        = toDate(out.issueDate);
        c.HPDQ_Configuration__c     = cut(out.configuration, 4099);
        c.HPDQ_Project__c           = cut(out.project, 255);
        c.HPDQ_Product__c           = cut(out.product, 255);
        c.HPDQ_Grade__c             = cut(out.grade, 255);
        c.HPDQ_Standard__c          = cut(out.standard, 255);
        c.HPDQ_Contract__c          = cut(out.contract, 255);
        c.HPDQ_SAP_Customer_Code__c = cut(out.customerCode, 255);
        c.HPDQ_Total_Coils__c       = out.totalCoils;
        c.HPDQ_Total_Weight__c      = out.totalWeight;
        c.HPDQ_LISTIDHRC__c         = cut(out.listIdText, 32768);
        c.HPDQ_Data__c              = out.dataJson;
        c.HPDQ_Status__c            = HPDQ_CertificateWorkflow.ST_BK;
        try {
            update c;
        } catch (DmlException e) {
            throw new AuraHandledException('Không cập nhật được phiếu: ' + e.getDmlMessage(0));
        }
    }

    /**
     * "Chứng chỉ chất lượng_ {Dự án}_ Ngày DD/MM/YYYY"
     *
     * NGÀY TRƯỚC THÁNG theo cách viết của Việt Nam: 05/08/2026 là ngày 5 tháng 8.
     * pad2() tự chèn số 0 nên không phụ thuộc locale của người dùng.
     *
     * Field Name chuẩn chỉ chứa 80 ký tự. Tên dự án BK trả về thường đã dài hơn phần còn lại
     * (mẫu thật 43 ký tự) nên cắt RIÊNG phần dự án, không cắt cả chuỗi — cắt cả chuỗi sẽ mất
     * đúng phần ngày ở đuôi, là thứ dùng để phân biệt các phiếu cùng khách hàng.
     *
     * @param ngayTao ngày TẠO RECORD (không phải ngày phát hành phiếu). Ghi đè phiếu cũ thì
     *                truyền ngày tạo gốc, nếu không tên sẽ đổi ngày mỗi lần lưu lại.
     */
    private static String tenPhieu(String project, String certNo, Date ngayTao) {
        String dau  = 'Chứng chỉ chất lượng_ ';
        String duoi = '_ Ngày ' + pad2(ngayTao.day()) + '/' + pad2(ngayTao.month())
                    + '/' + ngayTao.year();
        // BK có lúc không trả về dự án -> lấy số phiếu thay vào để record vẫn nhận diện được
        String than = String.isBlank(project) ? certNo : project;
        return dau + cut(than, 80 - dau.length() - duoi.length()) + duoi;
    }

    /** Giới hạn field HPDQ_Data__c (Long Text Area) */
    private static final Integer DATA_MAX_LEN = 131000;

    /**
     * Bước 3: lưu phiếu vào HPDQ_Certificate__c.
     * Trùng số phiếu thì ghi đè bản ghi cũ (HPDQ_Certificate_No__c là Unique).
     *
     * @param certJson JSON gồm toàn bộ thông tin header + listId + rows do LWC gửi lên.
     * @return Id bản ghi vừa tạo/cập nhật.
     */
    @AuraEnabled
    public static Id saveCertificate(String certJson) {
        if (String.isBlank(certJson)) {
            throw new AuraHandledException('Không có dữ liệu phiếu để lưu.');
        }
        if (!Schema.sObjectType.HPDQ_Certificate__c.isCreateable()) {
            throw new AuraHandledException(
                'Bạn không có quyền tạo bản ghi Quản lý in chứng chỉ chất lượng.');
        }

        Map<String, Object> h;
        try {
            h = (Map<String, Object>) JSON.deserializeUntyped(certJson);
        } catch (Exception e) {
            throw new AuraHandledException('Dữ liệu phiếu không hợp lệ: ' + e.getMessage());
        }

        String certNo = str(h.get('certNo'));
        if (String.isBlank(certNo)) {
            throw new AuraHandledException('Thiếu số phiếu (Certificate No) — không lưu được.');
        }

        // 3 field bắt buộc của object: Số phiếu, Ngày phát hành, Thành phần phân tích.
        // Kiểm tra trước để báo lỗi tiếng Việt rõ ràng thay vì DML "Required fields are missing".
        Date issueDate = toDate(str(h.get('issueDate')));
        if (issueDate == null) {
            throw new AuraHandledException('BK không trả về Ngày phát hành phiếu — không lưu được.');
        }
        String configuration = str(h.get('configuration'));
        if (String.isBlank(configuration)) {
            throw new AuraHandledException(
                'BK không trả về danh sách thành phần phân tích (Configuration) — không lưu được.');
        }

        String dataJson = str(h.get('dataJson'));
        if (dataJson.length() > DATA_MAX_LEN) {
            throw new AuraHandledException(
                'Dữ liệu quá lớn (' + dataJson.length() + ' ký tự, tối đa ' + DATA_MAX_LEN +
                '). Hãy chia nhỏ danh sách ID.');
        }

        HPDQ_Certificate__c c = new HPDQ_Certificate__c();
        // HPDQ_Certificate_No__c là Unique nhưng KHÔNG phải External ID nên không upsert theo field
        // được — phải tìm trước rồi gán Id để chuyển thành update.
        List<HPDQ_Certificate__c> olds = [
            SELECT Id, CreatedDate FROM HPDQ_Certificate__c
            WHERE HPDQ_Certificate_No__c = :certNo LIMIT 1
        ];
        // Ngày tạo record: bản ghi mới thì là hôm nay; ghi đè bản cũ thì GIỮ NGUYÊN ngày tạo
        // gốc, nếu không tên record sẽ đổi ngày mỗi lần lưu lại và mất ý nghĩa "ngày tạo".
        Date createdOn = Date.today();
        if (!olds.isEmpty()) {
            c.Id = olds[0].Id;
            createdOn = olds[0].CreatedDate.date();
        }

        String projectName = cut(str(h.get('project')), 255);

        // Dùng CHUNG hàm với lúc tạo phiếu ở bước 1. Trước đây công thức tên bị chép ra 2 nơi
        // và đã lệch nhau về thứ tự ngày/tháng.
        c.Name = tenPhieu(projectName, certNo, createdOn);

        c.HPDQ_Certificate_No__c    = cut(certNo, 255);
        c.HPDQ_Issue_Date__c        = issueDate;
        c.HPDQ_Project__c           = projectName;
        c.HPDQ_Product__c           = cut(str(h.get('product')), 255);
        c.HPDQ_Grade__c             = cut(str(h.get('grade')), 255);
        c.HPDQ_Standard__c          = cut(str(h.get('standard')), 255);
        c.HPDQ_Contract__c          = cut(str(h.get('contract')), 255);
        c.HPDQ_SAP_Customer_Code__c = cut(str(h.get('customerCode')), 255);
        c.HPDQ_Total_Coils__c       = num(h.get('totalCoils'));
        c.HPDQ_Total_Weight__c      = num(h.get('totalWeight'));
        c.HPDQ_LISTIDHRC__c         = cut(str(h.get('listIdText')), 32768);
        c.HPDQ_Data__c              = dataJson;
        c.HPDQ_Status__c            = 'Nhận dữ liệu từ BK';
        // Multi-select picklist lưu chuỗi ngăn cách bằng ";" — đúng định dạng BK trả về.
        // Field phải TẮT "Restrict picklist to the values defined in the value set", nếu không
        // nguyên tố lạ (Nb, Sn…) sẽ gây INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST.
        // Giới hạn giá trị của multi-select là 4.099 ký tự.
        c.HPDQ_Configuration__c     = cut(configuration, 4099);

        try {
            upsert c;   // có Id -> update, không có -> insert
        } catch (DmlException e) {
            throw new AuraHandledException('Không lưu được phiếu: ' + e.getDmlMessage(0));
        }
        return c.Id;
    }

    /**
     * Bước 3b: sinh PDF từ trang HPDQ_MTC_Certificate rồi đính vào phiếu (Files).
     *
     * PHẢI gọi ở TRANSACTION RIÊNG, sau khi saveCertificate đã commit:
     * getContentAsPDF() hành xử như một callout — nó render trang trong request khác
     * nên không thấy dữ liệu chưa commit, và không được gọi sau DML trong cùng transaction.
     *
     * In lại phiếu cũ sẽ tạo VERSION MỚI của cùng một file, giữ nguyên lịch sử bản đã in
     * trước đó thay vì sinh thêm file trùng tên.
     *
     * @return ContentDocumentId của file đã đính.
     */
    @AuraEnabled
    public static Id attachPdf(Id certId) {
        if (certId == null) {
            throw new AuraHandledException('Thiếu Id phiếu — không đính được PDF.');
        }
        List<HPDQ_Certificate__c> cs = [
            SELECT Id, HPDQ_Certificate_No__c FROM HPDQ_Certificate__c WHERE Id = :certId LIMIT 1
        ];
        if (cs.isEmpty()) {
            throw new AuraHandledException('Không tìm thấy phiếu để đính PDF.');
        }
        String certNo   = str(cs[0].HPDQ_Certificate_No__c);
        String fileName = safeFileName(certNo) + '.pdf';

        // Sinh PDF TRƯỚC mọi DML của transaction này
        Blob pdf;
        if (Test.isRunningTest()) {
            // Trong test không gọi được getContentAsPDF sau DML (uncommitted work pending)
            pdf = Blob.valueOf('%PDF-1.4 test');
        } else {
            PageReference p = Page.HPDQ_MTC_Certificate;
            p.getParameters().put('id', certId);
            p.getParameters().put('pdf', '1');   // ép chế độ in, không lấy bản HTML preview
            pdf = p.getContentAsPDF();
        }

        // Đã có file cùng tên gắn với phiếu này chưa? Có thì thêm version mới.
        List<ContentDocumentLink> olds = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :certId AND ContentDocument.Title = :fileName
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion(
            Title        = fileName,
            PathOnClient = fileName,
            VersionData  = pdf,
            Description  = 'Phiếu chứng nhận chất lượng ' + certNo +
                           ' — sinh lúc ' + Datetime.now().format('dd/MM/yyyy HH:mm')
        );
        if (!olds.isEmpty()) {
            cv.ContentDocumentId = olds[0].ContentDocumentId;   // -> version 2, 3...
        }

        try {
            insert cv;
        } catch (DmlException e) {
            throw new AuraHandledException('Không lưu được file PDF: ' + e.getDmlMessage(0));
        }

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        if (olds.isEmpty()) {
            try {
                insert new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId    = certId,
                    ShareType         = 'V',
                    Visibility        = 'AllUsers'
                );
            } catch (DmlException e) {
                throw new AuraHandledException('Không gắn được file vào phiếu: ' + e.getDmlMessage(0));
            }
        }

        // Ghi lại link trang in vào phiếu (field HPDQ_Link__c đã có trong thiết kế object)
        String printUrl = Url.getOrgDomainUrl().toExternalForm()
                        + '/apex/HPDQ_MTC_Certificate?id=' + certId;
        if (printUrl.length() <= 255) {
            update new HPDQ_Certificate__c(Id = certId, HPDQ_Link__c = printUrl);
        }
        return docId;
    }

    // ---- tiện ích ----
    private static String str(Object o) { return o == null ? '' : String.valueOf(o); }

    /** 8 -> "08". Dùng cho ngày trong tên record, không phụ thuộc locale của người dùng. */
    private static String pad2(Integer n) {
        return n < 10 ? '0' + String.valueOf(n) : String.valueOf(n);
    }

    /** "0000-070726/HOAPHAT" -> "0000-070726_HOAPHAT" (bỏ ký tự không hợp lệ trong tên file) */
    private static String safeFileName(String s) {
        if (String.isBlank(s)) return 'Phieu_chung_nhan_chat_luong';
        return s.replaceAll('[\\\\/:*?"<>|]', '_').trim();
    }
    /**
     * BK có thể trả số dạng chuỗi có dấu phẩy ("57,752") hoặc chữ ("N/A").
     * Decimal.valueOf sẽ ném TypeException — không phải AuraHandledException nên LWC chỉ
     * hiện lỗi chung chung. Vì vậy dọn dấu phẩy và trả null khi không parse được.
     */
    private static Decimal num(Object o) {
        if (o == null) return null;
        String s = String.valueOf(o).trim().replace(',', '');
        if (String.isBlank(s)) return null;
        try {
            return Decimal.valueOf(s);
        } catch (Exception e) {
            return null;
        }
    }
    private static String cut(String s, Integer max) {
        if (String.isBlank(s)) return null;
        return s.length() > max ? s.substring(0, max) : s;
    }
    /** "2025-08-30T00:00:00" hoặc "2025-08-30" -> Date; sai định dạng thì trả null */
    private static Date toDate(String s) {
        if (String.isBlank(s) || s.length() < 10) return null;
        try {
            return Date.valueOf(s.substring(0, 10));
        } catch (Exception e) {
            return null;
        }
    }

    // ---- DTO trả về LWC ----
    public class CertData {
        @AuraEnabled public String so;
        @AuraEnabled public String transporter;
        @AuraEnabled public String name;
        @AuraEnabled public String certNo;
        @AuraEnabled public String issueDate;
        @AuraEnabled public String project;
        @AuraEnabled public String product;
        @AuraEnabled public String grade;
        @AuraEnabled public String customerCode;
        @AuraEnabled public String standard;
        // Số License của mác thép (bảng quy định tiêu chuẩn). CHƯA DÙNG để in —
        // sắp tới dùng để suy ra bộ logo chứng nhận hiện ở góc phải phiếu.
        // Chưa có field trên object nên chưa lưu; khi cần lưu thì thêm field rồi
        // gán trong saveCertificate(), giá trị luôn tra lại được từ HPDQ_Grade__c.
        @AuraEnabled public String license;
        @AuraEnabled public String contract;
        @AuraEnabled public Decimal totalWeight;
        @AuraEnabled public Decimal totalCoils;
        @AuraEnabled public String configuration;
        @AuraEnabled public String dataJson;
        @AuraEnabled public List<Object> rows;

        // ===== Bước 1 tạo record ngay, các field dưới đây phục vụ việc đó =====
        /** Id phiếu vừa tạo hoặc phiếu cũ cùng số phiếu */
        @AuraEnabled public Id      certId;
        /** Trạng thái phiếu sau bước 1 */
        @AuraEnabled public String  status;
        /** true = số phiếu này đã có sẵn, đang mở lại để làm tiếp chứ không tạo mới */
        @AuraEnabled public Boolean daTonTai;
        /** Ghi chú nội bộ của phiếu cũ (nếu mở lại) */
        @AuraEnabled public String  note;
        /** Danh sách ID người dùng đã nhập, lưu vào HPDQ_LISTIDHRC__c */
        @AuraEnabled public String  listIdText;
    }
}
