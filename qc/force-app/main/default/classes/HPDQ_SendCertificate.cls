/**
 * Gửi Phiếu Chứng Nhận Chất Lượng cho khách hàng qua email.
 *
 * Khách hàng KHÔNG có tài khoản Salesforce nên chỉ nhận được FILE PDF ĐÍNH KÈM.
 * Link trang in (HPDQ_Link__c) là link nội bộ, chỉ nhân viên đăng nhập mới mở được,
 * nên KHÔNG đưa vào mail gửi khách — khách bấm vào chỉ thấy màn hình đăng nhập.
 *
 * Luồng: LWC gọi getCustomerInfo() để dựng hộp xác nhận, người dùng kiểm/sửa email
 * rồi gọi sendToCustomer().
 */
public with sharing class HPDQ_SendCertificate {

    private static final String TEMPLATE_NAME = 'HPDQ_Gui_Phieu_Chung_Nhan';
    /** Gửi xong là chốt bước 3 của quy trình — dùng chung hằng số với class workflow */
    private static final String STATUS_SENT   = HPDQ_CertificateWorkflow.ST_KD_XAC_NHAN;

    /** Thông tin dựng hộp xác nhận trước khi gửi. */
    public class CustomerInfo {
        @AuraEnabled public Id      accountId    { get; set; }
        @AuraEnabled public String  accountName  { get; set; }
        @AuraEnabled public String  email        { get; set; }
        @AuraEnabled public String  certNo       { get; set; }
        @AuraEnabled public String  fileName     { get; set; }
        @AuraEnabled public Decimal fileSizeKb   { get; set; }
        /** false thì LWC ẩn nút Gửi và hiện `message` */
        @AuraEnabled public Boolean canSend      { get; set; }
        @AuraEnabled public String  message      { get; set; }
        /** Cảnh báo nhưng vẫn gửi được (ví dụ nhiều Account trùng mã) */
        @AuraEnabled public String  warning      { get; set; }
    }

    /**
     * Bước 1: tra khách hàng + kiểm điều kiện gửi.
     * KHÔNG ném exception cho các lỗi nghiệp vụ — trả canSend=false kèm message
     * để màn hình hiện hộp thoại gọn gàng thay vì toast lỗi đỏ.
     */
    @AuraEnabled
    public static CustomerInfo getCustomerInfo(Id certId) {
        CustomerInfo out = new CustomerInfo();
        out.canSend = false;

        if (certId == null) {
            out.message = 'Chưa lưu phiếu nên chưa gửi được.';
            return out;
        }

        List<HPDQ_Certificate__c> cs = [
            SELECT Id, Name, HPDQ_Certificate_No__c, HPDQ_SAP_Customer_Code__c, HPDQ_Account__c
            FROM HPDQ_Certificate__c WHERE Id = :certId LIMIT 1
        ];
        if (cs.isEmpty()) {
            out.message = 'Không tìm thấy phiếu.';
            return out;
        }
        HPDQ_Certificate__c c = cs[0];
        out.certNo = c.HPDQ_Certificate_No__c;

        // Gửi xong có cập nhật phiếu -> người không sở hữu phiếu sẽ vướng OWD
        // (Public Read Only). Báo sớm ở đây thay vì để DML nổ lúc gửi.
        if (!coQuyenSua(certId)) {
            out.message = 'Bạn không phải người tạo phiếu này nên không gửi được. '
                        + 'Nhờ người tạo phiếu gửi giúp.';
            return out;
        }

        ContentVersion cv = layFileMoiNhat(certId);
        if (cv == null) {
            out.message = 'Phiếu chưa có file PDF. Hãy bấm "Trích PDF" trước khi gửi.';
            return out;
        }
        out.fileName   = cv.Title;
        out.fileSizeKb = (cv.ContentSize / 1024.0).setScale(1);

        if (String.isBlank(c.HPDQ_SAP_Customer_Code__c)) {
            out.message = 'Phiếu không có mã khách hàng nên không xác định được người nhận.';
            return out;
        }

        String ma = c.HPDQ_SAP_Customer_Code__c.trim();
        List<Account> accs = [
            SELECT Id, Name, HPDQ_Email__c FROM Account
            WHERE HPDQ_SAP_Customer_Code__c = :ma ORDER BY CreatedDate ASC LIMIT 2
        ];
        if (accs.isEmpty()) {
            out.message = 'Chưa có khách hàng mã "' + ma + '" trong hệ thống.';
            return out;
        }
        if (accs.size() > 1) {
            // Mã KH không phải field Unique nên có thể trùng. Lấy bản ghi tạo trước nhất
            // và cảnh báo để người dùng tự kiểm, thay vì im lặng chọn bừa.
            out.warning = 'Có nhiều khách hàng cùng mã "' + ma + '". Đang dùng bản ghi tạo trước nhất.';
        }

        Account a = accs[0];
        out.accountId   = a.Id;
        out.accountName = a.Name;
        out.email       = a.HPDQ_Email__c;

        if (String.isBlank(a.HPDQ_Email__c)) {
            out.message = 'Khách hàng "' + a.Name + '" chưa có email. '
                        + 'Hãy bổ sung email cho khách hàng rồi gửi lại.';
            return out;
        }

        out.canSend = true;
        return out;
    }

    /**
     * Bước 2: gửi mail kèm file PDF rồi cập nhật phiếu.
     *
     * THỨ TỰ QUAN TRỌNG — gửi mail TRƯỚC, cập nhật phiếu SAU:
     * nếu cập nhật trước mà mail lỗi thì phiếu ghi "Đã gửi khách hàng" trong khi
     * thực tế chưa gửi — sai lệch nguy hiểm. Ngược lại chỉ là thiếu thông tin.
     *
     * @param toEmail email người dùng đã kiểm/sửa trên hộp xác nhận
     * @return câu thông báo thành công cho toast
     */
    @AuraEnabled
    public static String sendToCustomer(Id certId, String toEmail) {
        if (String.isBlank(toEmail) || !toEmail.contains('@')) {
            throw new AuraHandledException('Email không hợp lệ: "' + toEmail + '"');
        }

        CustomerInfo info = getCustomerInfo(certId);
        if (info.accountId == null) {
            throw new AuraHandledException(String.isBlank(info.message)
                ? 'Không xác định được khách hàng.' : info.message);
        }
        ContentVersion cv = layFileMoiNhat(certId);
        if (cv == null) {
            throw new AuraHandledException('Phiếu chưa có file PDF để gửi.');
        }

        // Dùng renderStoredEmailTemplate chứ KHÔNG dùng setTemplateId: setTemplateId
        // bắt buộc kèm setTargetObjectId trỏ Contact/Lead/User và sẽ gửi tới email của
        // record đó, không phải email ta nhập. Hàm render chỉ dựng nội dung, không gửi.
        Id templateId = layTemplateId();
        Messaging.SingleEmailMessage rendered =
            Messaging.renderStoredEmailTemplate(templateId, null, certId);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ toEmail.trim() });
        mail.setSubject(rendered.getSubject());
        mail.setHtmlBody(rendered.getHtmlBody());
        mail.setPlainTextBody(rendered.getPlainTextBody());
        // Đính bằng Id ContentVersion: Salesforce tự lấy file, không phải nạp cả file
        // vào heap như setFileAttachments (giới hạn 6 MB đồng bộ).
        mail.setEntityAttachments(new List<String>{ cv.Id });
        mail.setSaveAsActivity(false);

        if (!Test.isRunningTest()) {
            List<Messaging.SendEmailResult> kq =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
            if (!kq.isEmpty() && !kq[0].isSuccess()) {
                throw new AuraHandledException(
                    'Không gửi được mail: ' + kq[0].getErrors()[0].getMessage());
            }
        }

        // Gửi xong mới ghi nhận
        try {
            update new HPDQ_Certificate__c(
                Id              = certId,
                HPDQ_Account__c = info.accountId,
                HPDQ_Status__c  = STATUS_SENT
            );
        } catch (DmlException e) {
            // Mail ĐÃ gửi đi rồi, không thu hồi được -> báo cho người dùng biết rõ
            // là mail đã đi nhưng phiếu chưa ghi nhận, đừng bấm gửi lại.
            throw new AuraHandledException(
                'Đã gửi mail cho khách nhưng không cập nhật được phiếu: '
                + e.getDmlMessage(0) + '. ĐỪNG bấm gửi lại.');
        }

        String ghiChu = ghiLinkLenKhachHang(certId, info.accountId);
        return 'Đã gửi phiếu ' + info.certNo + ' tới ' + toEmail.trim() + ghiChu;
    }

    /**
     * Ghi link phiếu vừa gửi lên field Account.HPDQ_Certificate_Link__c.
     *
     * LƯU Ý VỀ BẢN CHẤT FIELD NÀY: nó chỉ giữ được link của phiếu GẦN NHẤT.
     * Một khách hàng có nhiều phiếu (mỗi lô hàng một phiếu) nên mỗi lần gửi sẽ GHI ĐÈ
     * link cũ. Muốn tra đầy đủ mọi phiếu của khách thì dùng related list qua
     * HPDQ_Account__c, không dùng field này.
     *
     * Bọc try/catch riêng và KHÔNG ném lỗi: mail đã gửi đi rồi, không được để việc ghi
     * Account thất bại (ví dụ người gửi không có quyền sửa Account) làm hỏng cả thao tác.
     * Thay vào đó trả về ghi chú để hiện kèm thông báo thành công.
     *
     * @return '' nếu ghi được, hoặc câu ghi chú nêu lý do nếu không ghi được
     */
    private static String ghiLinkLenKhachHang(Id certId, Id accountId) {
        if (accountId == null) return '';
        try {
            ContentVersion cv = layFileMoiNhat(certId);
            if (cv == null) {
                return ' (phiếu chưa có file PDF nên chưa ghi link lên khách hàng)';
            }
            // Trỏ tới TRANG XEM FILE của Salesforce, KHÔNG dùng đường
            // /sfc/servlet.shepherd/document/download/ — đường đó ép trình duyệt TẢI VỀ
            // ngay lập tức. Trang xem này mở PDF ngay trên màn hình, có sẵn nút tải/chia sẻ
            // nếu người dùng cần.
            // HPDQ_Link__c trên phiếu vẫn giữ trang in HTML, dùng để in.
            String link = Url.getOrgDomainUrl().toExternalForm()
                        + '/lightning/r/ContentDocument/' + cv.ContentDocumentId + '/view';
            update new Account(Id = accountId, HPDQ_Certificate_Link__c = link);
            return '';
        } catch (Exception e) {
            return ' (chưa ghi được link lên khách hàng: ' + e.getMessage() + ')';
        }
    }

    // ================= tiện ích =================

    /** File PDF mới nhất đính vào phiếu. null nếu chưa trích PDF. */
    private static ContentVersion layFileMoiNhat(Id certId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :certId
        ];
        if (links.isEmpty()) return null;

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);

        List<ContentVersion> vs = [
            SELECT Id, Title, ContentSize, FileExtension, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true AND FileExtension = 'pdf'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return vs.isEmpty() ? null : vs[0];
    }

    /** Người dùng hiện tại có sửa được phiếu này không (quyền object + OWD). */
    private static Boolean coQuyenSua(Id certId) {
        if (!Schema.sObjectType.HPDQ_Certificate__c.isUpdateable()) return false;
        List<UserRecordAccess> a = [
            SELECT RecordId, HasEditAccess FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId = :certId
        ];
        return !a.isEmpty() && a[0].HasEditAccess;
    }

    /** Id của Email Template. Báo lỗi rõ nếu ai đó xoá/đổi tên template trên Setup. */
    private static Id layTemplateId() {
        List<EmailTemplate> ts = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_NAME LIMIT 1
        ];
        if (ts.isEmpty()) {
            throw new AuraHandledException(
                'Không tìm thấy mẫu email "' + TEMPLATE_NAME + '". '
                + 'Có thể mẫu đã bị xoá hoặc đổi tên trong Setup.');
        }
        return ts[0].Id;
    }
}
