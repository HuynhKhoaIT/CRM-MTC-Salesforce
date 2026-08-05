/**
 * KIỂM TRA PHÂN QUYỀN — không cần đăng nhập bằng tài khoản khác.
 *
 * Chạy:
 *   sf apex run -o hpdqDev -f scripts\kiem-quyen.apex
 * Rồi tìm các dòng có "QA|" trong log.
 *
 * UserRecordAccess là bảng Salesforce tự tính, cho biết CHÍNH XÁC một user có quyền gì
 * trên một bản ghi cụ thể — đã gộp cả quyền object (Profile/Permission Set) lẫn quyền
 * bản ghi (Org-Wide Default / Sharing Rule / Role Hierarchy).
 *
 * Chạy script này TRƯỚC và SAU khi đổi Org-Wide Default để thấy khác biệt.
 */

// Phiếu cần kiểm — để trống thì tự lấy phiếu mới nhất
Id cid = null;
if (cid == null) {
    List<HPDQ_Certificate__c> ds = [
        SELECT Id FROM HPDQ_Certificate__c ORDER BY CreatedDate DESC LIMIT 1];
    if (ds.isEmpty()) {
        System.debug('QA|Chua co phieu nao de kiem.');
        return;
    }
    cid = ds[0].Id;
}

HPDQ_Certificate__c c = [
    SELECT Name, OwnerId, Owner.Name FROM HPDQ_Certificate__c WHERE Id = :cid];
System.debug('QA|Phieu     : ' + c.Name);
System.debug('QA|Chu so huu: ' + c.Owner.Name);
System.debug('QA|' + '-'.repeat(72));

// Lấy user đang hoạt động để kiểm. Sửa danh sách này theo nhu cầu.
List<User> us = [
    SELECT Id, Name, Profile.Name
    FROM User
    WHERE IsActive = true AND UserType = 'Standard'
    ORDER BY Profile.Name, Name
    LIMIT 20];

for (User u : us) {
    List<UserRecordAccess> a = [
        SELECT RecordId, HasReadAccess, HasEditAccess, HasDeleteAccess
        FROM UserRecordAccess
        WHERE UserId = :u.Id AND RecordId = :cid];

    String q = 'khong doc duoc';
    if (!a.isEmpty()) {
        q = (a[0].HasReadAccess   ? 'XEM ' : '--- ')
          + (a[0].HasEditAccess   ? 'SUA ' : '--- ')
          + (a[0].HasDeleteAccess ? 'XOA'  : '---');
    }
    String ten = u.Name.length() > 22 ? u.Name.substring(0, 22) : u.Name.rightPad(22);
    String pro = u.Profile.Name.length() > 24
               ? u.Profile.Name.substring(0, 24) : u.Profile.Name.rightPad(24);
    System.debug('QA|' + ten + ' | ' + pro + ' | ' + q);
}
