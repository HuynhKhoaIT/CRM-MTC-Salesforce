@isTest
private class HPDQ_SendCertificateTest {

    private static final String MA_KH = '70000001';

    /** Phiếu tối thiểu đủ 3 field bắt buộc của object. */
    private static HPDQ_Certificate__c taoPhieu(String maKh) {
        HPDQ_Certificate__c c = new HPDQ_Certificate__c(
            Name                      = 'Phiếu test',
            HPDQ_Certificate_No__c    = 'TEST-' + maKh,
            HPDQ_Issue_Date__c        = Date.today(),
            HPDQ_Configuration__c     = 'C;Si;Mn',
            HPDQ_SAP_Customer_Code__c = maKh
        );
        insert c;
        return c;
    }

    /** Đính một file PDF giả vào phiếu, giống việc attachPdf() làm thật. */
    private static void dinhFile(Id certId) {
        // FileExtension là field chỉ đọc, Salesforce tự suy ra từ đuôi PathOnClient
        ContentVersion cv = new ContentVersion(
            Title        = 'phieu-test.pdf',
            PathOnClient = 'phieu-test.pdf',
            VersionData  = Blob.valueOf('%PDF-1.4 noi dung gia')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = certId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
    }

    @isTest
    static void testGuiThanhCong() {
        insert new Account(Name = 'Khách hàng test',
                           HPDQ_SAP_Customer_Code__c = MA_KH,
                           HPDQ_Email__c = 'khach@example.com');
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(c.Id);
        System.assertEquals(true, info.canSend, 'Phải gửi được. Lý do chặn: ' + info.message);
        System.assertEquals('khach@example.com', info.email, 'Lấy đúng email khách hàng');
        System.assertEquals('phieu-test.pdf', info.fileName, 'Lấy đúng file đính kèm');

        String kq = HPDQ_SendCertificate.sendToCustomer(c.Id, 'khach@example.com');
        Test.stopTest();

        System.assert(kq.contains('khach@example.com'), 'Thông báo có email người nhận: ' + kq);

        HPDQ_Certificate__c sau = [SELECT HPDQ_Account__c, HPDQ_Status__c
                                   FROM HPDQ_Certificate__c WHERE Id = :c.Id];
        System.assertNotEquals(null, sau.HPDQ_Account__c, 'Phải gán khách hàng vào phiếu');
        System.assertEquals('P.KD xác nhận', sau.HPDQ_Status__c, 'Gửi xong phải chốt bước 3');
    }

    // Gửi xong phải ghi link phiếu lên field trên Account khách hàng
    @isTest
    static void testGhiLinkLenAccount() {
        Account a = new Account(Name = 'Khách hàng test',
                                HPDQ_SAP_Customer_Code__c = MA_KH,
                                HPDQ_Email__c = 'khach@example.com');
        insert a;
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        HPDQ_SendCertificate.sendToCustomer(c.Id, 'khach@example.com');
        Test.stopTest();

        Account sau = [SELECT HPDQ_Certificate_Link__c FROM Account WHERE Id = :a.Id];
        System.assertNotEquals(null, sau.HPDQ_Certificate_Link__c,
            'Phải ghi link phiếu lên Account');
        // Phải là trang XEM file, không phải trang in HTML và không phải đường tải về
        System.assert(sau.HPDQ_Certificate_Link__c.contains('/lightning/r/ContentDocument/'),
            'Link phải mở trang xem file PDF. Đang là: ' + sau.HPDQ_Certificate_Link__c);
        System.assert(!sau.HPDQ_Certificate_Link__c.contains('/apex/'),
            'Không được trỏ trang Visualforce. Đang là: ' + sau.HPDQ_Certificate_Link__c);
        System.assert(!sau.HPDQ_Certificate_Link__c.contains('/download/'),
            'Không được ép tải về. Đang là: ' + sau.HPDQ_Certificate_Link__c);
    }

    // Người dùng sửa email trên hộp xác nhận -> gửi tới email đã sửa
    @isTest
    static void testGuiToiEmailDaSua() {
        insert new Account(Name = 'Khách hàng test',
                           HPDQ_SAP_Customer_Code__c = MA_KH,
                           HPDQ_Email__c = 'cu@example.com');
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        String kq = HPDQ_SendCertificate.sendToCustomer(c.Id, 'moi@example.com');
        Test.stopTest();

        System.assert(kq.contains('moi@example.com'), 'Gửi tới email đã sửa, không phải email gốc');
    }

    @isTest
    static void testKhongTimThayKhachHang() {
        HPDQ_Certificate__c c = taoPhieu('99999999');   // không tạo Account nào
        dinhFile(c.Id);

        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(c.Id);
        Test.stopTest();

        System.assertEquals(false, info.canSend, 'Không có Account thì không gửi được');
        System.assert(info.message.contains('99999999'),
            'Thông báo phải nêu mã khách hàng. Đang là: ' + info.message);
    }

    @isTest
    static void testKhachHangThieuEmail() {
        insert new Account(Name = 'Khách chưa có email',
                           HPDQ_SAP_Customer_Code__c = MA_KH);   // không có email
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(c.Id);
        Test.stopTest();

        System.assertEquals(false, info.canSend, 'Thiếu email thì không gửi được');
        System.assert(info.message.contains('chưa có email'),
            'Thông báo phải nói thiếu email. Đang là: ' + info.message);
    }

    @isTest
    static void testChuaTrichPdf() {
        insert new Account(Name = 'Khách hàng test',
                           HPDQ_SAP_Customer_Code__c = MA_KH,
                           HPDQ_Email__c = 'khach@example.com');
        HPDQ_Certificate__c c = taoPhieu(MA_KH);   // KHÔNG đính file

        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(c.Id);
        Test.stopTest();

        System.assertEquals(false, info.canSend, 'Chưa có PDF thì không gửi được');
        System.assert(info.message.contains('Trích PDF'),
            'Thông báo phải hướng dẫn bấm Trích PDF. Đang là: ' + info.message);
    }

    @isTest
    static void testEmailSaiDinhDang() {
        insert new Account(Name = 'Khách hàng test',
                           HPDQ_SAP_Customer_Code__c = MA_KH,
                           HPDQ_Email__c = 'khach@example.com');
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        try {
            HPDQ_SendCertificate.sendToCustomer(c.Id, 'khong-phai-email');
            System.assert(false, 'Phải ném lỗi khi email sai định dạng');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // Nhiều Account trùng mã -> vẫn gửi được nhưng phải cảnh báo
    @isTest
    static void testNhieuKhachHangTrungMa() {
        insert new List<Account>{
            new Account(Name = 'Khách A', HPDQ_SAP_Customer_Code__c = MA_KH,
                        HPDQ_Email__c = 'a@example.com'),
            new Account(Name = 'Khách B', HPDQ_SAP_Customer_Code__c = MA_KH,
                        HPDQ_Email__c = 'b@example.com')
        };
        HPDQ_Certificate__c c = taoPhieu(MA_KH);
        dinhFile(c.Id);

        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(c.Id);
        Test.stopTest();

        System.assertEquals(true, info.canSend, 'Trùng mã vẫn gửi được');
        System.assertNotEquals(null, info.warning, 'Phải có cảnh báo trùng mã');
    }

    @isTest
    static void testPhieuKhongTonTai() {
        Test.startTest();
        HPDQ_SendCertificate.CustomerInfo info = HPDQ_SendCertificate.getCustomerInfo(null);
        Test.stopTest();

        System.assertEquals(false, info.canSend, 'certId null thì không gửi được');
    }
}
