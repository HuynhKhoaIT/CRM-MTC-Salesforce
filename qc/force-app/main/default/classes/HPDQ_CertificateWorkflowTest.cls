@isTest
private class HPDQ_CertificateWorkflowTest {

    private static HPDQ_Certificate__c taoPhieu(String trangThai) {
        HPDQ_Certificate__c c = new HPDQ_Certificate__c(
            Name                      = 'Phiếu test',
            HPDQ_Certificate_No__c    = 'WF-' + Math.abs(Crypto.getRandomInteger()),
            HPDQ_Issue_Date__c        = Date.today(),
            HPDQ_Configuration__c     = 'C;Si;Mn',
            HPDQ_SAP_Customer_Code__c = '70000001',
            HPDQ_Data__c              = '[{"stt":1,"coil_no":"A1"}]',
            HPDQ_Status__c            = trangThai
        );
        insert c;
        return c;
    }

    /**
     * Cho người đang chạy test vào nhóm P_QLCL để đóng vai nhân viên QLCL.
     *
     * Hai điều phải để ý:
     *  - Group là SETUP OBJECT. Chèn chung transaction với HPDQ_Certificate__c sẽ dính
     *    MIXED_DML_OPERATION -> bắt buộc bọc trong System.runAs().
     *  - Group P_QLCL ĐÃ TỒN TẠI thật trên org (test vẫn nhìn thấy setup object), nên
     *    phải tra trước rồi mới tạo, nếu không sẽ ném DUPLICATE_DEVELOPER_NAME.
     */
    private static void vaoNhomQLCL() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Group> gs = [
                SELECT Id FROM Group WHERE DeveloperName = 'P_QLCL' AND Type = 'Regular' LIMIT 1];
            Id gid;
            if (gs.isEmpty()) {
                Group g = new Group(Name = 'P. QLCL', DeveloperName = 'P_QLCL', Type = 'Regular');
                insert g;
                gid = g.Id;
            } else {
                gid = gs[0].Id;
            }
            List<GroupMember> ms = [
                SELECT Id FROM GroupMember
                WHERE GroupId = :gid AND UserOrGroupId = :UserInfo.getUserId() LIMIT 1];
            if (ms.isEmpty()) {
                insert new GroupMember(GroupId = gid, UserOrGroupId = UserInfo.getUserId());
            }
        }
    }

    // ---------- Quyền tạo yêu cầu (Bước 1) ----------

    // Người P.QLCL KHÔNG được tạo yêu cầu, dù profile có quyền Create trên object
    @isTest
    static void testQLCLKhongTaoDuocYeuCau() {
        vaoNhomQLCL();

        Test.startTest();
        Boolean duoc = HPDQ_CertificateWorkflow.taoDuocYeuCau();
        Test.stopTest();

        System.assertEquals(false, duoc,
            'Nhân viên P.QLCL không được tạo yêu cầu QC — đó là việc của P.KD');
    }

    // Người ngoài nhóm P.QLCL (P.KD, admin) thì tạo được
    @isTest
    static void testNguoiKhongThuocQLCLTaoDuocYeuCau() {
        Test.startTest();
        Boolean duoc = HPDQ_CertificateWorkflow.taoDuocYeuCau();
        Test.stopTest();

        System.assertEquals(true, duoc, 'Người ngoài P.QLCL phải tạo được yêu cầu');
    }

    // ---------- loadCertificate ----------

    @isTest
    static void testNapPhieuChoBuoc2() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.loadCertificate(c.Id);
        Test.stopTest();

        System.assertEquals(2, s.buoc, 'Trạng thái "Nhận dữ liệu từ BK" phải mở ở Bước 2');
        System.assertEquals(true, s.laNguoiTao, 'Người chạy test là người tạo phiếu');
        System.assertEquals('[{"stt":1,"coil_no":"A1"}]', s.dataJson, 'Trả lại đúng dữ liệu cuộn');
    }

    @isTest
    static void testNapPhieuChoBuoc3() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_QLCL);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.loadCertificate(c.Id);
        Test.stopTest();

        System.assertEquals(3, s.buoc, 'Trạng thái "P.QLCL xác nhận" phải mở ở Bước 3');
        System.assertEquals(true, s.xacNhanDuoc, 'Người tạo phiếu được bấm Xác nhận');
        System.assertEquals(false, s.phatHanhDuoc, 'Chưa Xác nhận thì chưa được phát hành');
    }

    // ---------- Bước 2 ----------

    @isTest
    static void testQLCLSubmitBuoc2() {
        vaoNhomQLCL();
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.submitStep2(
            c.Id, '[{"stt":1,"coil_no":"A1","remarks":"đã sửa"}]', 'Ghi chú QLCL');
        Test.stopTest();

        System.assertEquals(HPDQ_CertificateWorkflow.ST_QLCL, s.status, 'Phải sang P.QLCL xác nhận');
        System.assertEquals(3, s.buoc, 'Sau submit thì mở Bước 3');

        HPDQ_Certificate__c sau = [SELECT HPDQ_Data__c, HPDQ_Note__c
                                   FROM HPDQ_Certificate__c WHERE Id = :c.Id];
        System.assert(sau.HPDQ_Data__c.contains('đã sửa'), 'Phải lưu số liệu đã hiệu chỉnh');
        System.assertEquals('Ghi chú QLCL', sau.HPDQ_Note__c, 'Phải lưu ghi chú');
    }

    // Không thuộc nhóm QLCL thì không submit được, dù là người tạo phiếu
    @isTest
    static void testKhongPhaiQLCLThiKhongSubmitDuoc() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.submitStep2(c.Id, null, null);
            System.assert(false, 'Phải ném lỗi khi không thuộc P.QLCL');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // Phiếu đã qua bước 2 rồi thì không submit lại được
    @isTest
    static void testKhongSubmitLaiBuoc2() {
        vaoNhomQLCL();
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_QLCL);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.submitStep2(c.Id, null, null);
            System.assert(false, 'Phải ném lỗi khi phiếu không còn ở Bước 2');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // ---------- Bước 3 ----------

    @isTest
    static void testXacNhanBuoc3() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_QLCL);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.confirmStep3(c.Id);
        Test.stopTest();

        System.assertEquals(HPDQ_CertificateWorkflow.ST_KD_XU_LY, s.status,
            'Bấm Xác nhận phải sang P.KD xử lý');
        System.assertEquals(true, s.phatHanhDuoc, 'Xác nhận xong mới được Trích PDF / Gửi khách');
        System.assertEquals(false, s.xacNhanDuoc, 'Đã xác nhận rồi thì nút Xác nhận tắt đi');
    }

    // Chưa qua bước 2 thì chưa xác nhận được
    @isTest
    static void testChuaQuaBuoc2ThiChuaXacNhanDuoc() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.confirmStep3(c.Id);
            System.assert(false, 'Phải ném lỗi khi P.QLCL chưa xác nhận');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // ---------- Trả về bước trước ----------

    @isTest
    static void testTraVeBuoc2() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_QLCL);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.traVeBuocTruoc(c.Id);
        Test.stopTest();

        System.assertEquals(HPDQ_CertificateWorkflow.ST_BK, s.status, 'Phải quay lại Bước 2');
        System.assertEquals(2, s.buoc, 'Bước hiển thị phải về 2');
    }

    // P.QLCL thấy số liệu BK sai -> trả phiếu về Bước 1 cho P.KD lấy lại
    @isTest
    static void testQLCLTraVeBuoc1() {
        vaoNhomQLCL();
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        HPDQ_CertificateWorkflow.CertState s = HPDQ_CertificateWorkflow.traVeBuocTruoc(c.Id);
        Test.stopTest();

        System.assertEquals(HPDQ_CertificateWorkflow.ST_TRA_LAI, s.status,
            'Trạng thái phải là "P.QLCL yêu cầu hiệu chỉnh"');
        System.assertEquals(1, s.buoc, 'Bước hiển thị phải về 1');
        System.assertEquals(true, s.suaDuocBuoc1,
            'Người tạo phiếu phải mở lại được bước 1 để sửa yêu cầu');
        System.assertEquals(false, s.suaDuocBuoc2, 'Về bước 1 rồi thì bước 2 phải khoá');
    }

    // Không phải QLCL thì không được trả phiếu về bước 1
    @isTest
    static void testKhongPhaiQLCLThiKhongTraVeBuoc1Duoc() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_BK);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.traVeBuocTruoc(c.Id);
            System.assert(false, 'Người ngoài P.QLCL không được trả phiếu về bước 1');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // Đang ở bước 1 rồi thì không lùi thêm được nữa
    @isTest
    static void testKhongLuiQuaBuoc1() {
        vaoNhomQLCL();
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_TRA_LAI);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.traVeBuocTruoc(c.Id);
            System.assert(false, 'Phiếu đang ở bước 1 thì không lùi thêm được');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testPhieuDaPhatHanhKhongTraVeDuoc() {
        HPDQ_Certificate__c c = taoPhieu(HPDQ_CertificateWorkflow.ST_KD_XAC_NHAN);

        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.traVeBuocTruoc(c.Id);
            System.assert(false, 'Phiếu đã phát hành thì không trả về được');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testPhieuKhongTonTai() {
        Test.startTest();
        try {
            HPDQ_CertificateWorkflow.loadCertificate('a0v000000000000AAA');
            System.assert(false, 'Phải ném lỗi khi Id không tồn tại');
        } catch (Exception e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
