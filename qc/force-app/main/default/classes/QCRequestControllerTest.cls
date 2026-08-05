@isTest
private class QCRequestControllerTest {

    // Body đã gửi lên BK ở lần callout gần nhất — để test kiểm định dạng request
    private static String lastRequestBody;

    // Giả lập phản hồi của API BK (không gọi mạng thật khi chạy test)
    private class BKMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            lastRequestBody = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{"status":1,"message":"Success","data":{' +
                '"Name":"PHIẾU CHỨNG NHẬN CHẤT LƯỢNG",' +
                '"HPDQ_Certificate_No__c":"0000-070726/HOAPHAT",' +
                // Bắt buộc: từ khi bước 1 tạo record ngay, thiếu ngày phát hành là chặn luôn
                '"HPDQ_Issue_Date__c":"2025-08-30T00:00:00",' +
                '"HPDQ_Grade__c":"SPA-H",' +
                '"HPDQ_SAP_Customer_Code__c":"60000048",' +
                '"HPDQ_Total_Weight__c":57752,"HPDQ_Total_Coils__c":3,' +
                '"HPDQ_Configuration__c":"C;Si;Mn;S;P",' +
                '"HPDQ_Data__c":[' +
                '{"stt":1,"coil_no":"2225080293","heat_no":"25G000061","C":10,"Si":33,"Mn":48,"S":3,"P":91},' +
                '{"stt":2,"coil_no":"2225080304","heat_no":"25G000058","C":10,"Si":35,"Mn":49,"S":5,"P":87}' +
                ']},"alert":[]}'
            );
            return res;
        }
    }

    @isTest
    static void testFetchDataOk() {
        Test.setMock(HttpCalloutMock.class, new BKMock());
        Test.startTest();
        QCRequestController.CertData d = QCRequestController.fetchData(
            '2200002095', 'ĐINH GIA 79', '60000048',
            new List<String>{ '80250800890', '80250800897' });
        Test.stopTest();

        System.assertEquals('0000-070726/HOAPHAT', d.certNo, 'Số phiếu đúng');
        System.assertEquals('SPA-H', d.grade, 'Mác thép đúng');
        System.assertEquals(2, d.rows.size(), 'Có 2 cuộn');
        System.assertEquals('C;Si;Mn;S;P', d.configuration, 'Cấu hình cột đúng');
    }

    // Tên tàu KHÔNG bắt buộc: để trống vẫn gọi BK được
    @isTest
    static void testFetchDataKhongCanTenTau() {
        Test.setMock(HttpCalloutMock.class, new BKMock());
        Test.startTest();
        QCRequestController.CertData d = QCRequestController.fetchData(
            '2200002095', '', '60000048', new List<String>{ '80250800890', '80250800897' });
        Test.stopTest();

        System.assertEquals(2, d.rows.size(), 'Thiếu tên tàu vẫn lấy được dữ liệu');
        System.assert(lastRequestBody.contains('80250800890'),
            'ListID phải được gửi lên BK. Body: ' + lastRequestBody);
    }

    // 3 trường bắt buộc: SO, Customer Code, Danh sách ID
    @isTest
    static void testFetchDataThieuTruongBatBuoc() {
        List<String> ids = new List<String>{ '80250800890' };
        Test.startTest();
        assertNemLoi(null,          'T', 'C', ids,                 'thiếu SO');
        assertNemLoi('2200002095',  'T', '',  ids,                 'thiếu Customer Code');
        assertNemLoi('2200002095',  'T', 'C', new List<String>(),  'danh sách ID rỗng');
        assertNemLoi('2200002095',  'T', 'C', null,                'danh sách ID null');
        Test.stopTest();
    }

    private static void assertNemLoi(String so, String tr, String cc,
                                     List<String> ids, String truongHop) {
        try {
            QCRequestController.fetchData(so, tr, cc, ids);
            System.assert(false, 'Phải ném lỗi khi ' + truongHop);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // Bảng quy định tiêu chuẩn: mác thép -> loại hàng hóa / tiêu chuẩn / số license
    @isTest
    static void testTraBangTieuChuan() {
        HPDQ_GradeStandards.Row r = HPDQ_GradeStandards.lookup('SPHC');
        System.assertNotEquals(null, r, 'SPHC phải có trong bảng');
        System.assertEquals('MS 1705 : 2023', r.standard, 'Tiêu chuẩn của SPHC');
        System.assertEquals('PC012156', r.license, 'Số license của SPHC');

        // Khóa chuẩn hóa: khác khoảng trắng / hoa thường / ký tự đặc biệt vẫn ra 1 dòng
        System.assertEquals('SAE1006', HPDQ_GradeStandards.normalize('sae-1006'), 'Chuẩn hóa khóa');
        System.assertEquals('PC015029', HPDQ_GradeStandards.licenseOf('SAE1006'), 'SAE1006 không dấu cách');
        System.assertEquals('PC012155', HPDQ_GradeStandards.licenseOf('S235JR'), 'S235JR = S235+JR');

        System.assertEquals(null, HPDQ_GradeStandards.lookup('KHONG-CO-THAT'),
            'Mác thép lạ phải trả null để người gọi giữ giá trị BK');
        System.assertEquals('', HPDQ_GradeStandards.licenseOf(null), 'Null không được ném lỗi');
        System.assertEquals(8, HPDQ_GradeStandards.all().size(), 'Bảng có 8 mác thép');
    }

    // fetchData phải LẤY THEO BẢNG, không lấy loại hàng hóa/tiêu chuẩn của BK
    @isTest
    static void testFetchDataSuyRaTuMacThep() {
        Test.setMock(HttpCalloutMock.class, new BKMock());
        Test.startTest();
        QCRequestController.CertData d = QCRequestController.fetchData(
            '2200002095', 'ĐINH GIA 79', '60000048', new List<String>{ '80250800890' });
        Test.stopTest();

        // BKMock trả grade = 'SPA-H' -> KHÔNG có trong bảng -> giữ nguyên giá trị BK
        System.assertEquals('SPA-H', d.grade, 'Mác thép giữ nguyên');
        System.assertEquals(null, d.license, 'Mác thép ngoài bảng thì không có license');
    }

    private static String certJson(String certNo) {
        return JSON.serialize(new Map<String, Object>{
            'so'           => '2200002095',
            'transporter'  => 'ĐINH GIA 79',
            'customerCode' => '60000048',
            'certNo'       => certNo,
            'issueDate'    => '2025-08-30T00:00:00',
            'project'      => 'CÔNG TY CỔ PHẦN SẢN XUẤT CONTAINER HÒA PHÁT',
            'product'      => 'THÉP CUỘN CÁN NÓNG/HOT ROLLED COIL',
            'grade'        => 'SPA-H',
            'standard'     => 'JIS G3125',
            'contract'     => '2200002095 - 536A.T08.2025/HPDQ-HPC-KH',
            'totalCoils'    => 3,
            'totalWeight'   => 57752,
            'configuration' => 'C;Si;Mn;S;P;Cu;Ni;Cr;Mo;V;Ti;Al;B;CA;CEV',
            'listIdText'   => '2225080293, 2225080304',
            'dataJson'     => '[{"stt":1,"coil_no":"2225080293","weight_kg":19114}]'
        });
    }

    @isTest
    static void testSaveCertificateInsert() {
        Test.startTest();
        Id r = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Test.stopTest();

        System.assertNotEquals(null, r, 'Phải tạo được bản ghi');
        HPDQ_Certificate__c c = [
            SELECT HPDQ_Certificate_No__c, HPDQ_Grade__c, HPDQ_Issue_Date__c,
                   HPDQ_Total_Weight__c, HPDQ_Status__c, HPDQ_Data__c, HPDQ_Configuration__c
            FROM HPDQ_Certificate__c WHERE Id = :r];
        System.assertEquals('0000-070726/HOAPHAT', c.HPDQ_Certificate_No__c, 'Số phiếu đúng');
        System.assertEquals('SPA-H', c.HPDQ_Grade__c, 'Mác thép đúng');
        System.assertEquals(Date.newInstance(2025, 8, 30), c.HPDQ_Issue_Date__c, 'Ngày cắt từ chuỗi ISO');
        System.assertEquals(57752, c.HPDQ_Total_Weight__c, 'Tổng khối lượng đúng');
        System.assertEquals('Nhận dữ liệu từ BK', c.HPDQ_Status__c, 'Trạng thái mặc định');
        System.assertEquals('C;Si;Mn;S;P;Cu;Ni;Cr;Mo;V;Ti;Al;B;CA;CEV', c.HPDQ_Configuration__c,
            'Lưu đủ danh sách thành phần phân tích BK trả về');
    }

    /** Ngày TẠO RECORD theo định dạng DD/MM/YYYY (kiểu Việt Nam), ví dụ 05/08/2026 */
    private static String ngayTaoText(Date d) {
        String mm = d.month() < 10 ? '0' + String.valueOf(d.month()) : String.valueOf(d.month());
        String dd = d.day()   < 10 ? '0' + String.valueOf(d.day())   : String.valueOf(d.day());
        return dd + '/' + mm + '/' + d.year();
    }

    // Tên record theo format "Chứng chỉ chất lượng_ {Dự án}_ Ngày DD/MM/YYYY"
    @isTest
    static void testTenRecordDungFormat() {
        Test.startTest();
        Id r = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Test.stopTest();

        String ten = [SELECT Name FROM HPDQ_Certificate__c WHERE Id = :r].Name;
        System.assert(ten.startsWith('Chứng chỉ chất lượng_ '), 'Sai tiền tố. Tên: ' + ten);
        System.assert(ten.endsWith('_ Ngày ' + ngayTaoText(Date.today())),
            'Phải là NGÀY TẠO RECORD dạng DD/MM/YYYY, không phải ngày phát hành. Tên: ' + ten);
        System.assert(!ten.contains('30/08/2025') && !ten.contains('08/30/2025'),
            'Không được dùng ngày phát hành (30/08/2025). Tên: ' + ten);
        // Ngày đứng trước tháng: hôm nay là mùng 5 tháng 8 thì phải ra 05/08, không phải 08/05
        System.assert(ten.contains('_ Ngày ' + (Date.today().day() < 10 ? '0' : '')
                                   + Date.today().day() + '/'),
            'Ngày phải đứng TRƯỚC tháng. Tên: ' + ten);
        System.assert(ten.length() <= 80, 'Name tối đa 80 ký tự, đang ' + ten.length());
        System.assert(ten.contains('CÔNG TY CỔ PHẦN'),
            'Phải giữ được phần đầu tên dự án. Tên: ' + ten);
    }

    // Không có tên dự án thì dùng số phiếu, ngày vẫn phải còn nguyên
    @isTest
    static void testTenRecordKhiThieuDuAn() {
        Map<String, Object> m =
            (Map<String, Object>) JSON.deserializeUntyped(certJson('0000-070726/HOAPHAT'));
        m.put('project', '');

        Test.startTest();
        Id r = QCRequestController.saveCertificate(JSON.serialize(m));
        Test.stopTest();

        String ten = [SELECT Name FROM HPDQ_Certificate__c WHERE Id = :r].Name;
        System.assertEquals(
            'Chứng chỉ chất lượng_ 0000-070726/HOAPHAT_ Ngày ' + ngayTaoText(Date.today()), ten,
            'Thiếu dự án thì thay bằng số phiếu');
    }

    // Lưu lại phiếu cũ thì GIỮ ngày tạo gốc, không nhảy sang ngày lưu lại
    @isTest
    static void testTenRecordGiuNgayTaoKhiGhiDe() {
        Id first = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Date ngayGoc = [SELECT CreatedDate FROM HPDQ_Certificate__c WHERE Id = :first]
                       .CreatedDate.date();

        Test.startTest();
        QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Test.stopTest();

        String ten = [SELECT Name FROM HPDQ_Certificate__c WHERE Id = :first].Name;
        System.assert(ten.endsWith('_ Ngày ' + ngayTaoText(ngayGoc)),
            'Ghi đè phải giữ ngày tạo gốc. Tên: ' + ten);
    }

    @isTest
    static void testSaveCertificateGhiDeKhiTrungSoPhieu() {
        Id first = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Test.startTest();
        Id second = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        Test.stopTest();

        System.assertEquals(first, second, 'Trùng số phiếu thì ghi đè bản ghi cũ, không tạo mới');
        System.assertEquals(1, [SELECT COUNT() FROM HPDQ_Certificate__c], 'Chỉ có 1 bản ghi');
    }

    @isTest
    static void testAttachPdf() {
        Id certId = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));

        Test.startTest();
        Id docId = QCRequestController.attachPdf(certId);
        Test.stopTest();

        System.assertNotEquals(null, docId, 'Phải trả về ContentDocumentId');

        // File được gắn đúng vào phiếu, tên file bỏ dấu "/" của số phiếu
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink WHERE LinkedEntityId = :certId];
        System.assertEquals(1, links.size(), 'Có đúng 1 file gắn vào phiếu');
        System.assertEquals('0000-070726_HOAPHAT.pdf', links[0].ContentDocument.Title,
            'Dấu "/" trong số phiếu phải đổi thành "_" cho hợp lệ tên file');

        // Link trang in được ghi lại vào phiếu
        HPDQ_Certificate__c c = [SELECT HPDQ_Link__c FROM HPDQ_Certificate__c WHERE Id = :certId];
        System.assert(c.HPDQ_Link__c.contains('HPDQ_MTC_Certificate?id='), 'Ghi lại URL trang in');
    }

    @isTest
    static void testAttachPdfInLaiTaoVersionMoi() {
        Id certId = QCRequestController.saveCertificate(certJson('0000-070726/HOAPHAT'));
        QCRequestController.attachPdf(certId);

        Test.startTest();
        QCRequestController.attachPdf(certId);   // in lại lần 2
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :certId],
            'In lại không tạo file trùng tên, chỉ thêm version');
        System.assertEquals(2, [SELECT COUNT() FROM ContentVersion],
            'Có 2 version của cùng một file');
    }

    @isTest
    static void testAttachPdfThieuId() {
        Test.startTest();
        try {
            QCRequestController.attachPdf(null);
            System.assert(false, 'Phải ném lỗi khi thiếu Id');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveCertificateThieuSoPhieu() {
        Test.startTest();
        try {
            QCRequestController.saveCertificate(certJson(''));
            System.assert(false, 'Phải ném lỗi khi thiếu số phiếu');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
