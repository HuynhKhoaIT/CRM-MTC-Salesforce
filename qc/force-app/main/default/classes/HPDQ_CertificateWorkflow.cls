/**
 * Quy trình 3 bước liên phòng cho Phiếu Chứng Nhận Chất Lượng.
 *
 *   Bước 1  Gửi yêu cầu          P. Kinh doanh   -> tạo record, trạng thái "Nhận dữ liệu từ BK"
 *   Bước 2  Kiểm tra & hiệu chỉnh P. QLCL        -> submit, trạng thái "P.QLCL xác nhận"
 *   Bước 3  Kiểm tra & xác nhận   Người tạo phiếu -> Xác nhận, trạng thái "P.KD xử lý"
 *                                                 -> Gửi khách, trạng thái "P.KD xác nhận"
 *
 * QUYỀN SỬA BẢN GHI do Salesforce lo, không phải code này:
 * OWD = Public Read Only (chỉ chủ sở hữu sửa) + Criteria-Based Sharing Rule mở quyền cho
 * nhóm P_QLCL khi trạng thái = "Nhận dữ liệu từ BK". Xem SETUP_QUYEN_PRODUCTION.md.
 *
 * Class này chỉ kiểm QUY TẮC NGHIỆP VỤ: ai được bấm nút nào, ở trạng thái nào.
 * Hai tầng bổ sung cho nhau — sharing rule chặn sửa dữ liệu, code chặn nhảy cóc bước.
 *
 * LƯU Ý: KHÔNG kiểm quyền bằng UserRecordAccess ngay sau khi vừa đổi trạng thái trong cùng
 * transaction — Salesforce tính lại quyền chia sẻ BẤT ĐỒNG BỘ nên kết quả sẽ là quyền cũ.
 * Vì vậy mọi kiểm tra ở đây đều dựa vào TRẠNG THÁI PHIẾU, không dựa vào quyền chia sẻ.
 */
public with sharing class HPDQ_CertificateWorkflow {

    public static final String ST_BK          = 'Nhận dữ liệu từ BK';
    public static final String ST_QLCL        = 'P.QLCL xác nhận';
    public static final String ST_KD_XU_LY    = 'P.KD xử lý';
    public static final String ST_KD_XAC_NHAN = 'P.KD xác nhận';
    /** P.QLCL trả phiếu về Bước 1 — trạng thái duy nhất ứng với Bước 1 */
    public static final String ST_TRA_LAI     = 'P.QLCL yêu cầu hiệu chỉnh';

    /** Public Group dùng cho Sharing Rule — cũng là nguồn duy nhất xác định ai là P.QLCL */
    private static final String NHOM_QLCL = 'P_QLCL';

    /** Toàn bộ trạng thái phiếu để LWC dựng lại màn hình. */
    public class CertState {
        @AuraEnabled public Id      certId        { get; set; }
        @AuraEnabled public String  certNo        { get; set; }
        @AuraEnabled public String  status        { get; set; }
        /** Bước đang mở: 1, 2 hoặc 3 */
        @AuraEnabled public Integer buoc          { get; set; }
        @AuraEnabled public String  ownerName     { get; set; }

        // Dữ liệu dựng lại bảng
        @AuraEnabled public String  dataJson      { get; set; }
        @AuraEnabled public String  configuration { get; set; }
        @AuraEnabled public String  note          { get; set; }
        /** Danh sách ID đã gửi BK — dựng lại ô nhập ở bước 1 khi phiếu bị trả về */
        @AuraEnabled public String  listIdText    { get; set; }

        // Header phiếu
        @AuraEnabled public String  issueDate     { get; set; }
        @AuraEnabled public String  project       { get; set; }
        @AuraEnabled public String  product       { get; set; }
        @AuraEnabled public String  grade         { get; set; }
        @AuraEnabled public String  standard      { get; set; }
        @AuraEnabled public String  contract      { get; set; }
        @AuraEnabled public String  customerCode  { get; set; }
        @AuraEnabled public Decimal totalCoils    { get; set; }
        @AuraEnabled public Decimal totalWeight   { get; set; }

        // Quyền của người đang xem — LWC dùng để khoá/mở nút
        @AuraEnabled public Boolean laQLCL        { get; set; }
        @AuraEnabled public Boolean laNguoiTao    { get; set; }
        /** Được sửa lại yêu cầu gốc ở bước 1 không (chỉ khi P.QLCL đã trả phiếu về) */
        @AuraEnabled public Boolean suaDuocBuoc1  { get; set; }
        /** Được hiệu chỉnh số liệu ở bước 2 không */
        @AuraEnabled public Boolean suaDuocBuoc2  { get; set; }
        /** Được trả phiếu về bước trước không */
        @AuraEnabled public Boolean traVeDuoc     { get; set; }
        /** Được bấm "Xác nhận" ở bước 3 không */
        @AuraEnabled public Boolean xacNhanDuoc   { get; set; }
        /** Được Trích PDF / Gửi khách không */
        @AuraEnabled public Boolean phatHanhDuoc  { get; set; }
        /** Câu giải thích khi không thao tác được — hiện lên màn hình */
        @AuraEnabled public String  thongBao      { get; set; }
    }

    /**
     * Người đang đăng nhập có được TẠO yêu cầu QC (Bước 1) không.
     *
     * Bước 1 là việc của Phòng Kinh doanh. Nhân viên P.QLCL vào để kiểm tra số liệu ở Bước 2,
     * không được tự phát sinh yêu cầu — làm thế là vừa đá bóng vừa thổi còi.
     *
     * Hai điều kiện, cố ý chồng lên nhau:
     *  - Quyền Create trên object (đặt ở Profile) — chặn cả những phòng khác.
     *  - Không thuộc nhóm P_QLCL — chặn P.QLCL ngay cả khi Profile lỡ mở quyền Create.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean taoDuocYeuCau() {
        return Schema.sObjectType.HPDQ_Certificate__c.isCreateable() && !laNguoiQLCL();
    }

    /** Câu báo lỗi dùng chung cho cả LWC lẫn Apex khi chặn tạo yêu cầu. */
    public static final String LOI_KHONG_TAO_DUOC =
        'Chỉ Phòng Kinh doanh mới được tạo yêu cầu QC. '
        + 'Bạn hãy mở phiếu có sẵn từ danh sách để xử lý phần việc của mình.';

    /**
     * Nạp phiếu để tiếp tục xử lý. LWC gọi khi mở một phiếu đang dở.
     */
    @AuraEnabled(cacheable=false)
    public static CertState loadCertificate(Id certId) {
        List<HPDQ_Certificate__c> cs = [
            SELECT Id, Name, HPDQ_Certificate_No__c, HPDQ_Status__c, HPDQ_Data__c,
                   HPDQ_Configuration__c, HPDQ_Note__c, HPDQ_Issue_Date__c,
                   HPDQ_Project__c, HPDQ_Product__c, HPDQ_Grade__c, HPDQ_Standard__c,
                   HPDQ_Contract__c, HPDQ_SAP_Customer_Code__c, HPDQ_LISTIDHRC__c,
                   HPDQ_Total_Coils__c, HPDQ_Total_Weight__c,
                   OwnerId, Owner.Name, CreatedById
            FROM HPDQ_Certificate__c WHERE Id = :certId LIMIT 1
        ];
        if (cs.isEmpty()) {
            throw new AuraHandledException('Không tìm thấy phiếu.');
        }
        return dungState(cs[0]);
    }

    /**
     * Bước 2: P.QLCL lưu số liệu đã hiệu chỉnh và đẩy phiếu sang bước 3.
     *
     * @param dataJson JSON toàn bộ dòng cuộn sau khi sửa
     * @param note     ghi chú nội bộ (có thể null)
     */
    @AuraEnabled
    public static CertState submitStep2(Id certId, String dataJson, String note) {
        HPDQ_Certificate__c c = layPhieu(certId);

        if (c.HPDQ_Status__c != ST_BK) {
            throw new AuraHandledException(
                'Phiếu không còn ở Bước 2 (trạng thái hiện tại: "' + c.HPDQ_Status__c + '").');
        }
        if (!laNguoiQLCL()) {
            throw new AuraHandledException(
                'Chỉ nhân viên Phòng QLCL mới được hiệu chỉnh và xác nhận ở bước này.');
        }
        if (String.isNotBlank(dataJson) && dataJson.length() > 131000) {
            throw new AuraHandledException('Dữ liệu quá lớn (' + dataJson.length() + ' ký tự).');
        }

        c.HPDQ_Status__c = ST_QLCL;
        if (String.isNotBlank(dataJson)) c.HPDQ_Data__c = dataJson;
        if (note != null)                c.HPDQ_Note__c = note;
        capNhat(c);

        return dungState(layPhieu(certId));
    }

    /**
     * Bước 3: người tạo phiếu bấm "Xác nhận" — chốt nội dung trước khi phát hành.
     * Chỉ sau bước này mới hiện nút Trích PDF và Gửi cho khách hàng.
     */
    @AuraEnabled
    public static CertState confirmStep3(Id certId) {
        HPDQ_Certificate__c c = layPhieu(certId);

        if (c.HPDQ_Status__c != ST_QLCL) {
            throw new AuraHandledException(
                'Phiếu chưa được P.QLCL xác nhận, hoặc đã xác nhận rồi (trạng thái: "'
                + c.HPDQ_Status__c + '").');
        }
        if (c.CreatedById != UserInfo.getUserId()) {
            throw new AuraHandledException(
                'Chỉ người tạo phiếu mới được xác nhận. Phiếu này do ' + c.Owner.Name + ' tạo.');
        }

        c.HPDQ_Status__c = ST_KD_XU_LY;
        capNhat(c);

        return dungState(layPhieu(certId));
    }

    /**
     * Trả phiếu về bước trước để sửa lại.
     * Bước 3 -> bước 2 (P.KD trả cho QLCL), hoặc bước 2 -> bước 1 (QLCL trả cho P.KD).
     *
     * Ở bước 2, P.QLCL thấy số liệu BK sai thì trả về bước 1: P.KD sửa lại SO / danh sách ID
     * rồi bấm "Gửi yêu cầu" lần nữa. Lúc đó QCRequestController ghi đè dữ liệu mới lên phiếu
     * và đưa trạng thái về "Nhận dữ liệu từ BK" — xem taoHoacMoPhieu().
     */
    @AuraEnabled
    public static CertState traVeBuocTruoc(Id certId) {
        HPDQ_Certificate__c c = layPhieu(certId);
        String cu = c.HPDQ_Status__c;

        if (cu == ST_QLCL || cu == ST_KD_XU_LY) {
            // đang ở bước 3 -> trả về bước 2 cho QLCL sửa
            if (c.CreatedById != UserInfo.getUserId()) {
                throw new AuraHandledException('Chỉ người tạo phiếu mới được trả về bước 2.');
            }
            c.HPDQ_Status__c = ST_BK;
        } else if (cu == ST_BK) {
            // đang ở bước 2 -> trả về bước 1 cho P.KD lấy lại dữ liệu từ BK
            if (!laNguoiQLCL()) {
                throw new AuraHandledException(
                    'Chỉ nhân viên Phòng QLCL mới được yêu cầu hiệu chỉnh ở bước này.');
            }
            c.HPDQ_Status__c = ST_TRA_LAI;
        } else if (cu == ST_TRA_LAI) {
            throw new AuraHandledException(
                'Phiếu đang ở Bước 1 chờ P.KD lấy lại dữ liệu, không lùi thêm được.');
        } else {
            throw new AuraHandledException(
                'Phiếu đã phát hành (trạng thái: "' + cu + '"), không trả về được.');
        }

        capNhat(c);
        return dungState(layPhieu(certId));
    }

    // ================= tiện ích =================

    /** Người đang đăng nhập có thuộc Public Group P_QLCL không. */
    @TestVisible
    private static Boolean laNguoiQLCL() {
        return ![
            SELECT Id FROM GroupMember
            WHERE Group.DeveloperName = :NHOM_QLCL
              AND UserOrGroupId = :UserInfo.getUserId()
            LIMIT 1
        ].isEmpty();
    }

    private static HPDQ_Certificate__c layPhieu(Id certId) {
        List<HPDQ_Certificate__c> cs = [
            SELECT Id, Name, HPDQ_Certificate_No__c, HPDQ_Status__c, HPDQ_Data__c,
                   HPDQ_Configuration__c, HPDQ_Note__c, HPDQ_Issue_Date__c,
                   HPDQ_Project__c, HPDQ_Product__c, HPDQ_Grade__c, HPDQ_Standard__c,
                   HPDQ_Contract__c, HPDQ_SAP_Customer_Code__c, HPDQ_LISTIDHRC__c,
                   HPDQ_Total_Coils__c, HPDQ_Total_Weight__c,
                   OwnerId, Owner.Name, CreatedById
            FROM HPDQ_Certificate__c WHERE Id = :certId LIMIT 1
        ];
        if (cs.isEmpty()) throw new AuraHandledException('Không tìm thấy phiếu.');
        return cs[0];
    }

    private static void capNhat(HPDQ_Certificate__c c) {
        try {
            update c;
        } catch (DmlException e) {
            // Thường gặp: quyền chia sẻ chưa cho sửa. Dịch sang câu người dùng hiểu được.
            throw new AuraHandledException('Không lưu được phiếu: ' + e.getDmlMessage(0));
        }
    }

    /** Suy ra bước đang mở từ trạng thái phiếu. */
    @TestVisible
    private static Integer buocTuTrangThai(String status) {
        if (status == ST_TRA_LAI) return 1;   // P.QLCL trả về, chờ P.KD lấy lại dữ liệu
        if (status == ST_BK)      return 2;   // đang chờ P.QLCL
        if (status == ST_QLCL)    return 3;   // chờ P.KD xác nhận
        return 3;                             // P.KD xử lý / P.KD xác nhận
    }

    private static CertState dungState(HPDQ_Certificate__c c) {
        CertState s = new CertState();
        s.certId        = c.Id;
        s.certNo        = c.HPDQ_Certificate_No__c;
        s.status        = c.HPDQ_Status__c;
        s.buoc          = buocTuTrangThai(c.HPDQ_Status__c);
        s.ownerName     = c.Owner.Name;
        s.dataJson      = c.HPDQ_Data__c;
        s.configuration = c.HPDQ_Configuration__c;
        s.note          = c.HPDQ_Note__c;
        s.listIdText    = c.HPDQ_LISTIDHRC__c;
        s.issueDate     = c.HPDQ_Issue_Date__c == null ? null : String.valueOf(c.HPDQ_Issue_Date__c);
        s.project       = c.HPDQ_Project__c;
        s.product       = c.HPDQ_Product__c;
        s.grade         = c.HPDQ_Grade__c;
        s.standard      = c.HPDQ_Standard__c;
        s.contract      = c.HPDQ_Contract__c;
        s.customerCode  = c.HPDQ_SAP_Customer_Code__c;
        s.totalCoils    = c.HPDQ_Total_Coils__c;
        s.totalWeight   = c.HPDQ_Total_Weight__c;

        s.laQLCL     = laNguoiQLCL();
        s.laNguoiTao = (c.CreatedById == UserInfo.getUserId());

        s.suaDuocBuoc1 = (c.HPDQ_Status__c == ST_TRA_LAI) && s.laNguoiTao;
        s.suaDuocBuoc2 = (c.HPDQ_Status__c == ST_BK)   && s.laQLCL;
        s.xacNhanDuoc  = (c.HPDQ_Status__c == ST_QLCL) && s.laNguoiTao;
        s.phatHanhDuoc = (c.HPDQ_Status__c == ST_KD_XU_LY || c.HPDQ_Status__c == ST_KD_XAC_NHAN)
                         && s.laNguoiTao;
        // Trả về được khi và chỉ khi đang thao tác được ở bước hiện tại
        s.traVeDuoc    = s.suaDuocBuoc2 || s.xacNhanDuoc
                         || ((c.HPDQ_Status__c == ST_KD_XU_LY) && s.laNguoiTao);

        s.thongBao = giaiThich(c, s);
        return s;
    }

    /** Câu giải thích vì sao không thao tác được — để màn hình nói rõ đang chờ ai. */
    private static String giaiThich(HPDQ_Certificate__c c, CertState s) {
        if (c.HPDQ_Status__c == ST_TRA_LAI) {
            return s.laNguoiTao
                 ? 'Phòng QLCL yêu cầu hiệu chỉnh. Hãy kiểm tra lại SO / danh sách ID rồi bấm '
                   + '"Gửi yêu cầu" để lấy lại số liệu từ BK.'
                 : 'Phòng QLCL đã trả phiếu về Bước 1, đang chờ ' + c.Owner.Name
                   + ' lấy lại dữ liệu từ BK.';
        }
        if (c.HPDQ_Status__c == ST_BK) {
            return s.laQLCL ? null
                 : 'Phiếu đang chờ Phòng QLCL kiểm tra và hiệu chỉnh số liệu.';
        }
        if (c.HPDQ_Status__c == ST_QLCL) {
            return s.laNguoiTao ? null
                 : 'Phiếu đang chờ ' + c.Owner.Name + ' (người tạo phiếu) xác nhận.';
        }
        if (c.HPDQ_Status__c == ST_KD_XU_LY) {
            return s.laNguoiTao ? null
                 : 'Phiếu đang được ' + c.Owner.Name + ' xử lý phát hành.';
        }
        if (c.HPDQ_Status__c == ST_KD_XAC_NHAN) {
            return 'Phiếu đã hoàn tất và gửi cho khách hàng.';
        }
        return null;
    }
}
