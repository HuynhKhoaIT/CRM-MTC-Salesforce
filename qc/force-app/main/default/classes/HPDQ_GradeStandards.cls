/**
 * Bảng quy định tiêu chuẩn — tra theo MÁC THÉP (grade).
 *
 * grade -> Loại hàng hóa (product) / Tiêu chuẩn (standard) / Số License.
 *
 * ĐẶT Ở APEX CHỨ KHÔNG ĐẶT Ở LWC là có lý do: bảng này phục vụ CẢ HAI phía —
 * màn hình wizard (qua QCRequestController.fetchData) và trang in/PDF
 * (HPDQ_CertificatePdfController, sắp tới dùng license để chọn logo chứng nhận).
 * Để hai bản sao ở hai nơi thì chắc chắn sẽ lệch nhau — đúng lỗi đã gặp nhiều lần
 * ở dự án này. Bản cũ `lwc/qcRequestWizard/gradeStandards.js` không còn dùng.
 *
 * Khóa tra được CHUẨN HÓA: bỏ mọi ký tự không phải chữ/số rồi chuyển hoa.
 * Nhờ vậy 'SAE 1006', 'SAE1006', 'sae-1006' cùng ra một dòng; 'S235+JR' = 'S235JR'.
 *
 * THÊM MÁC THÉP MỚI: chỉ cần thêm một dòng vào ROWS bên dưới.
 */
public with sharing class HPDQ_GradeStandards {

    /** Một dòng của bảng. @AuraEnabled để LWC đọc được nếu sau này cần. */
    public class Row {
        @AuraEnabled public String grade    { get; set; }
        @AuraEnabled public String product  { get; set; }
        @AuraEnabled public String standard { get; set; }
        @AuraEnabled public String license  { get; set; }

        public Row(String grade, String product, String standard, String license) {
            this.grade    = grade;
            this.product  = product;
            this.standard = standard;
            this.license  = license;
        }
    }

    private static final List<Row> ROWS = new List<Row>{
        new Row('S235+JR',
                'HOT ROLLED PLATES AND STRIPS OF NON-ALLOY STRUCTURAL STEELS',
                'MS EN 10025-2 : 2011', 'PC012155'),
        new Row('SAE 1006',
                'SAE CARBON STEEL COIL',
                'SAE J 403 : 2014', 'PC015029'),
        new Row('SAE 1008',
                'SAE CARBON STEEL COIL',
                'SAE J 403 : 2014', 'PC015029'),
        new Row('SPHT 1',
                'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
                'MS 1768 : 2004', 'PC012154'),
        new Row('SPHT 2',
                'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
                'MS 1768 : 2004', 'PC012154'),
        new Row('SPHT 3',
                'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
                'MS 1768 : 2004', 'PC012154'),
        new Row('SPHC',
                'HOT ROLLED CARBON STEEL STRIP AND SHEET OF COMMERCIAL AND DRAWING QUALITIES',
                'MS 1705 : 2023', 'PC012156'),
        new Row('SPHD',
                'HOT ROLLED CARBON STEEL STRIP AND SHEET OF COMMERCIAL AND DRAWING QUALITIES',
                'MS 1705 : 2023', 'PC012156')
    };

    private static Map<String, Row> indexByGrade;

    private static Map<String, Row> getIndex() {
        if (indexByGrade == null) {
            indexByGrade = new Map<String, Row>();
            for (Row r : ROWS) {
                indexByGrade.put(normalize(r.grade), r);
            }
        }
        return indexByGrade;
    }

    /** 'SAE 1006' -> 'SAE1006', 'S235+JR' -> 'S235JR' */
    public static String normalize(String grade) {
        if (String.isBlank(grade)) return '';
        return grade.toUpperCase().replaceAll('[^A-Z0-9]', '');
    }

    /**
     * Tra một mác thép.
     * @return null nếu mác thép chưa có trong bảng — người gọi phải giữ nguyên
     *         giá trị BK trả về chứ ĐỪNG xóa trắng.
     */
    public static Row lookup(String grade) {
        return getIndex().get(normalize(grade));
    }

    /** Số License của mác thép, '' nếu chưa có trong bảng. Sắp tới dùng để chọn logo. */
    public static String licenseOf(String grade) {
        Row r = lookup(grade);
        return r == null ? '' : r.license;
    }

    /** Toàn bộ bảng — để hiển thị/kiểm tra. */
    public static List<Row> all() {
        return ROWS.clone();
    }
}
