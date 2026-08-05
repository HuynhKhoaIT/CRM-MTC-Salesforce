/**
 * HPDQ_CertificatePdfController
 * -----------------------------
 * Controller cho trang in PDF của phiếu chứng nhận chất lượng (MTC).
 * Đọc 1 bản ghi HPDQ_Certificate__c, parse HPDQ_Data__c (JSON từng cuộn) rồi
 * dựng view model cho HPDQ_MTC_Certificate.page.
 *
 * Logic hiển thị bám theo LWC qcRequestWizard để 2 nơi ra cùng một kết quả:
 *   - length = 0/rỗng  -> in chữ "C" (dạng cuộn)
 *   - số thuần         -> chèn dấu "," hàng nghìn, giữ nguyên phần thập phân
 *   - mã định danh (số cuộn, mẻ số) -> KHÔNG format
 *
 * Dùng: /apex/HPDQ_MTC_Certificate?id=<Id bản ghi>
 */
public with sharing class HPDQ_CertificatePdfController {

    // Thông tin công ty (cố định trên phiếu in)
    /**
     * Mã biểu mẫu và ngày hiệu lực in ở góc phải header (đặc tả 6.2).
     * ĐỂ TRỐNG CÓ CHỦ ĐÍCH: hai giá trị này do P.QLCL quy định, chưa được cung cấp.
     * Trống thì khối đó không in ra — thà thiếu hơn in số bịa trên phiếu chứng nhận.
     * Điền vào đây (hoặc chuyển sang Custom Label) khi đã có giá trị chính thức.
     */
    private static final String FORM_CODE = '';
    private static final String FORM_EFFECTIVE_DATE = '';

    private static final String MILL = 'HOA PHAT DUNG QUAT STEEL JOINT STOCK COMPANY';
    private static final String ADDR = 'DUNG QUAT ECONOMIC ZONE, VAN TUONG COMMUNE, QUANG NGAI PROVINCE, VIETNAM';
    private static final String TEL  = '(+84) 246 279 7112';
    private static final String FAX  = '(+84) 246 279 7166';

    // Hệ số quy đổi hiển thị dưới nhóm cột hóa học
    private static final Map<String, String> CHEM_DIVISOR = new Map<String, String>{
        'C' => '100', 'Si' => '100', 'Mn' => '100', 'S' => '100', 'P' => '100',
        'Cu' => '1.000', 'Ni' => '1.000', 'Cr' => '1.000', 'Mo' => '1.000',
        'V' => '10.000', 'Ti' => '10.000', 'Al' => '10.000', 'B' => '10.000',
        'CA' => '100', 'Ca' => '100', 'CEV' => '100'
    };

    /**
     * VÌ SAO PHẢI TỰ CHIA TRANG:
     * Engine PDF của Salesforce KHÔNG tôn trọng `thead { display: table-header-group }`,
     * nên nếu để nó tự ngắt trang thì trang sau mất cả logo lẫn header bảng.
     * Cách xử lý: controller cắt danh sách cuộn thành từng trang, mỗi trang là một bảng
     * riêng tự in lại đầy đủ header.
     *
     * Số liệu đo trên khổ A4 ngang, bảng font 7pt / line-height 1.2 / padding 5px 6px,
     * logo 74x92px (sinh PDF thật, đếm số trang và số trang có vẽ logo):
     * Đo RIÊNG từng loại trang (đo cả bộ cùng lúc thì không biết cái nào tràn — lần đầu
     * đã mắc lỗi này và để trang giữa thấp hơn thực tế 3 hàng):
     *   phiếu chỉ 1 trang : 8 hàng -> TRÀN,  6 hàng -> vừa
     *   trang đầu         : 15 hàng -> TRÀN, 14 hàng -> vừa
     *   trang giữa        : 22 hàng -> TRÀN, 21 hàng -> vừa
     *   trang cuối        : 15 hàng -> TRÀN, 13 hàng -> vừa
     * Hai thứ ăn dung lượng nhiều nhất: padding ô (bộ cũ padding 3px 4px là 16/20/26/24)
     * và KHỐI Ô KÝ ở trang cuối (thêm vào làm phiếu 1 trang tụt từ 10 xuống 6 dòng).
     * ĐỔI cỡ chữ bảng, padding ô, hay chiều cao logo/header thì PHẢI đo lại 4 con số này,
     * nếu không sẽ sinh ra trang tràn mất logo + header (đúng lỗi đã sửa trước đó).
     */

    public HPDQ_Certificate__c cert   { get; private set; }
    public String errorMessage        { get; private set; }
    public List<String> chemCols      { get; private set; }
    public List<UnitGroup> chemUnits  { get; private set; }
    public List<CoilRow> rows         { get; private set; }
    public List<CertPage> pages       { get; private set; }
    public List<Info> infoLeft        { get; private set; }
    public List<Info> infoRight       { get; private set; }

    /** Gọi trực tiếp qua URL: /apex/HPDQ_MTC_Certificate?id=<recordId> */
    public HPDQ_CertificatePdfController() {
        init(null);
    }

    /**
     * Dùng khi trang được nhúng vào Lightning Record Page qua component Visualforce:
     * Salesforce truyền record đang mở vào standardController, không có tham số URL nào.
     * Bắt buộc phải có constructor này, nếu không `extensions=` sẽ không biên dịch.
     */
    public HPDQ_CertificatePdfController(ApexPages.StandardController std) {
        init(std == null ? null : (Id) std.getId());
    }

    private void init(Id recordIdFromController) {
        chemCols  = new List<String>();
        chemUnits = new List<UnitGroup>();
        rows      = new List<CoilRow>();
        pages     = new List<CertPage>();
        infoLeft  = new List<Info>();
        infoRight = new List<Info>();

        String recordId = (recordIdFromController != null)
            ? String.valueOf(recordIdFromController)
            : ApexPages.currentPage().getParameters().get('id');

        if (String.isBlank(recordId)) {
            errorMessage = 'Thiếu tham số id — không biết in phiếu nào.';
            return;
        }
        load(recordId);
    }

    /**
     * Chế độ render của trang.
     *  - Mặc định (không có ?pdf=1): trả null -> trang render HTML, xem được ngay trong
     *    Lightning Record Page ở tab "Trang In".
     *  - Có ?pdf=1: trả 'pdf' -> engine xuất file PDF, dùng cho nút Trích PDF.
     * Lưu ý: Apex `getContentAsPDF()` luôn ra PDF bất kể thuộc tính này.
     */
    public String renderMode {
        get {
            String p = ApexPages.currentPage().getParameters().get('pdf');
            return (p == '1' || p == 'true') ? 'pdf' : null;
        }
    }

    /* ===== Logo chứng nhận ở góc phải header =====
     * SẮP TỚI: hiện theo MÁC THÉP (grade) — ví dụ chỉ mác đạt JIS mới in dấu QUACERT.
     * Khi làm, chỉ sửa 3 getter dưới đây, KHÔNG phải đụng vào trang Visualforce:
     *     get { return cert != null && cert.HPDQ_Grade__c == '...'; }
     * Lý do phải làm bằng cờ chứ không truyền tên ảnh: Visualforce không cho tên
     * Static Resource động, `$Resource[bienSo]` là cú pháp không hợp lệ.
     * Hiện tại phiếu nào cũng in đủ 3 logo, đúng như mẫu đang lưu hành.
     */
    public Boolean showLogoBoA          { get { return true; } }
    public Boolean showLogoQuacert      { get { return true; } }
    public Boolean showLogoVietnamValue { get { return true; } }

    /**
     * Bề rộng mỗi cột logo chứng nhận = 100% / số logo đang hiện.
     * Nhờ vậy ẩn bớt logo thì các logo còn lại vẫn TRẢI ĐỀU hết ô, không dồn một phía.
     */
    public String logoCellWidth {
        get {
            Integer n = 0;
            if (showLogoBoA)          n++;
            if (showLogoQuacert)      n++;
            if (showLogoVietnamValue) n++;
            if (n == 0) return '0%';
            return String.valueOf((100 / n)) + '%';
        }
    }

    /**
     * Dung lượng dòng KHÁC NHAU theo loại trang, vì mỗi loại phải chừa chỗ cho thứ khác:
     *   - trang đầu   : logo + khối thông tin phiếu (8 dòng) + header bảng
     *   - trang giữa  : logo + header bảng  -> rộng rãi nhất
     *   - trang cuối  : logo + header bảng + phần kết luận
     * Dùng một con số chung cho cả 3 loại sẽ để trống rất nhiều ở trang giữa.
     * Các giá trị dưới đây đo bằng thực nghiệm (sinh PDF thật, đếm trang + đếm trang có logo).
     */
    /*
     * ĐƠN VỊ: nửa dòng chữ (~5.6px). Không dùng đơn vị "hàng" vì chiều cao một hàng KHÔNG
     * tỉ lệ thuận với số dòng ghi chú — padding trên/dưới chỉ tính MỘT lần cho cả hàng:
     *      hàng 1 dòng  = 10px padding + 11px chữ  ≈ 22px  -> 4 đơn vị
     *      hàng 4 dòng  = 10px padding + 45px chữ  ≈ 56px  -> 10 đơn vị (chỉ 2.5x, không phải 4x)
     * Tính theo "hàng" sẽ ước lố những hàng có ghi chú dài và cắt trang quá sớm.
     */
    /*
     * Giá một hàng = UNITS_ROW_BASE + UNITS_EXTRA_LINE x (số dòng chữ THÊM).
     * Tách 2 tham số là cố ý: nếu gộp thành "mỗi dòng x hệ số" thì tăng hệ số cho hàng
     * nhiều dòng sẽ kéo giá hàng 1 dòng lên theo, làm phiếu ghi chú rỗng phình thêm 50%
     * số trang (đo thực tế: 130 cuộn từ 8 lên 12 trang).
     *
     * UNITS_EXTRA_LINE = 5 là biên an toàn dày (lý thuyết chỉ cần ~2): bề rộng thực của ô
     * Ghi chú không đoán chính xác được, mà đoán hụt là tràn trang mất header — hậu quả
     * nặng hơn nhiều so với việc thừa chỗ ở hàng có ghi chú dài.
     */
    private static final Integer UNITS_ROW_BASE   = 4;   // một hàng chỉ có 1 dòng chữ
    private static final Integer UNITS_EXTRA_LINE = 5;   // mỗi dòng chữ thêm do wrap

    // Ngân sách = (số hàng 1 dòng đo được) x UNITS_ROW_BASE
    private static final Integer LINES_SINGLE = 24;   // 6 hàng: thông tin + kết luận + ô ký
    private static final Integer LINES_FIRST  = 56;   // 14 hàng: có khối thông tin
    private static final Integer LINES_MIDDLE = 84;   // 21 hàng: rộng rãi nhất
    private static final Integer LINES_LAST   = 56;   // 14 hàng: có kết luận + ô ký

    /**
     * Ô Ghi chú là cột duy nhất cho phép xuống dòng, nên một cuộn có thể chiếm nhiều dòng.
     * Ước lượng số ký tự vừa một dòng của cột đó — lấy hụt cho chắc, thà chia trang sớm
     * hơn là để tràn mất header.
     */
    private static final Integer REMARKS_CHARS_PER_LINE = 16;

    /** Đọc tham số ghi đè khi in thử: ?lp0=10&lp1=14&lpm=18&lpl=16 (hoặc ?lp=14 cho cả 4) */
    private Integer param(String name, Integer fallbackValue) {
        String p = ApexPages.currentPage().getParameters().get(name);
        if (String.isNotBlank(p)) {
            try {
                Integer v = Integer.valueOf(p.trim());
                if (v > 0) return v;
            } catch (Exception e) {
                // tham số sai -> dùng mặc định
            }
        }
        return fallbackValue;
    }

    /**
     * Cắt danh sách cuộn thành từng trang. Mỗi trang tự in lại logo + header bảng;
     * khối thông tin chỉ in ở trang đầu, phần kết luận chỉ in ở trang cuối.
     *
     * Đơn vị tính là SỐ DÒNG VĂN BẢN, không phải số cuộn: một cuộn có ghi chú dài sẽ
     * chiếm nhiều dòng, nếu đếm theo cuộn thì phiếu nào ghi chú dài là tràn trang.
     */
    private void buildPages() {
        Integer capSingle = param('lp0', param('lp', LINES_SINGLE));
        Integer capFirst  = param('lp1', param('lp', LINES_FIRST));
        Integer capMiddle = param('lpm', param('lp', LINES_MIDDLE));
        Integer capLast   = param('lpl', param('lp', LINES_LAST));

        // Trang cuối còn phải chứa HÀNG TỔNG và khối CHÚ THÍCH -> trừ chỗ trước.
        // Chú thích dài bao nhiêu thì trừ tương ứng, nếu không phiếu có ghi chú nội bộ dài
        // sẽ tràn sang một trang trắng không header.
        Integer tailPenalty = UNITS_ROW_BASE;                 // hàng tổng khối lượng
        String noteText = note;
        if (String.isNotBlank(noteText)) {
            Integer noteLines = (Integer) Math.ceil(noteText.length() / 150.0);  // chú thích chạy hết bề ngang
            if (noteLines < 1) noteLines = 1;
            tailPenalty += UNITS_ROW_BASE * noteLines;
        }
        capLast   = Math.max(UNITS_ROW_BASE, capLast - tailPenalty);
        capSingle = Math.max(UNITS_ROW_BASE, capSingle - tailPenalty);

        // Chia trang GIỐNG NHAU cho cả 2 chế độ (PDF và HTML) để bản xem trước trên màn hình
        // khớp đúng bản in đính kèm.
        //
        // Đã thử cho chế độ HTML chạy không chia trang, để trình duyệt tự tràn trang và tự
        // lặp thead — và đã GỠ. Lý do: phần lặp buộc phải nằm trong thead, mà thead luôn in
        // trước tbody, nên không chèn được khối thông tin (chỉ có ở trang đầu) vào giữa logo
        // và header cột. Thử đặt logo position:fixed thì nó đè lên nội dung đầu mỗi trang
        // (mất dòng "Số/ No." và "MILL", tưởng là mất header cột) và sinh thêm trang trắng.
        if (rows.isEmpty()) {
            CertPage only = new CertPage();
            only.pageNo  = 1;
            only.isFirst = true;
            only.isLast  = true;
            only.rows    = new List<CoilRow>();
            pages.add(only);
            return;
        }

        Integer idx = 0;
        Integer pageNo = 0;
        while (idx < rows.size()) {
            pageNo++;
            Boolean isFirst = (pageNo == 1);

            Integer linesLeft = 0;
            for (Integer i = idx; i < rows.size(); i++) {
                linesLeft += rows[i].lines;
            }

            // Trang này là trang cuối khi toàn bộ phần còn lại vừa dung lượng trang có kết luận
            Integer capIfLast = isFirst ? capSingle : capLast;
            Integer capIfCont = isFirst ? capFirst : capMiddle;
            Boolean isLast = (linesLeft <= capIfLast);

            // Lấp ĐẦY trang hiện tại, chỉ sang trang mới khi thật sự hết chỗ.
            Integer budget;
            if (isLast) {
                budget = capIfLast;
            } else {
                budget = capIfCont;
                // Nếu lấp đầy sẽ ăn hết phần còn lại thì trang này thành trang cuối, mà
                // trang cuối phải chừa chỗ cho phần kết luận -> để lại tối thiểu 1 dòng.
                if (budget >= linesLeft) {
                    budget = linesLeft - 1;
                }
            }

            CertPage cp = new CertPage();
            cp.pageNo  = pageNo;
            cp.isFirst = isFirst;
            cp.isLast  = isLast;
            cp.rows    = new List<CoilRow>();

            Integer used = 0;
            while (idx < rows.size() && used + rows[idx].lines <= budget) {
                used += rows[idx].lines;
                cp.rows.add(rows[idx]);
                idx++;
            }
            // Một cuộn có ghi chú dài hơn cả dung lượng trang: vẫn phải in, tránh lặp vô hạn
            if (cp.rows.isEmpty()) {
                cp.rows.add(rows[idx]);
                idx++;
            }
            pages.add(cp);
        }

        // Chốt an toàn: nhánh "cuộn quá cao" ở trên có thể ăn hết phần còn lại của một trang
        // đã bị đánh isLast = false, khi đó KHÔNG trang nào in phần kết luận và trang chót vẫn
        // mang page-break nên sinh thêm một trang trắng. Ép trang chót thành trang cuối.
        pages[pages.size() - 1].isLast = true;
    }

    private void load(String recordId) {
        List<HPDQ_Certificate__c> found;
        try {
            found = [
                SELECT Id, Name, HPDQ_Certificate_No__c, HPDQ_Issue_Date__c, HPDQ_Project__c,
                       HPDQ_Product__c, HPDQ_Grade__c, HPDQ_Standard__c, HPDQ_Contract__c,
                       HPDQ_SAP_Customer_Code__c, HPDQ_Total_Coils__c, HPDQ_Total_Weight__c,
                       HPDQ_Configuration__c, HPDQ_Data__c, HPDQ_Note__c, HPDQ_Logo__c
                FROM HPDQ_Certificate__c
                WHERE Id = :recordId LIMIT 1
            ];
        } catch (Exception e) {
            errorMessage = 'Id không hợp lệ: ' + recordId;
            return;
        }
        if (found.isEmpty()) {
            errorMessage = 'Không tìm thấy phiếu (hoặc bạn không có quyền xem).';
            return;
        }
        cert = found[0];

        buildChemCols();
        buildRows();
        buildPages();
        buildInfo();
    }

    // ===== cột hóa học =====
    private void buildChemCols() {
        for (String c : nz(cert.HPDQ_Configuration__c).split(';')) {
            if (String.isNotBlank(c)) chemCols.add(c.trim());
        }
        // Gom các cột liên tiếp cùng hệ số -> 1 ô đơn vị có colspan
        for (String c : chemCols) {
            String d = CHEM_DIVISOR.containsKey(c) ? CHEM_DIVISOR.get(c) : '';
            if (!chemUnits.isEmpty() && chemUnits[chemUnits.size() - 1].divisor == d) {
                chemUnits[chemUnits.size() - 1].span += 1;
            } else {
                UnitGroup g = new UnitGroup();
                g.divisor = d;
                g.span    = 1;
                g.label   = String.isBlank(d) ? '' : 'x ' + d;
                chemUnits.add(g);
            }
        }
    }

    // ===== từng dòng cuộn =====
    private void buildRows() {
        if (String.isBlank(cert.HPDQ_Data__c)) return;
        List<Object> raw;
        try {
            raw = (List<Object>) JSON.deserializeUntyped(cert.HPDQ_Data__c);
        } catch (Exception e) {
            errorMessage = 'Dữ liệu cuộn (HPDQ_Data__c) không phải JSON hợp lệ.';
            return;
        }

        Integer i = 0;
        for (Object o : raw) {
            i++;
            Map<String, Object> m = (Map<String, Object>) o;
            CoilRow r = new CoilRow();
            r.stt       = (m.get('stt') == null) ? String.valueOf(i) : nz(m.get('stt'));
            r.coil      = nz(m.get('coil_no'));   // mã định danh -> không format
            r.heat      = nz(m.get('heat_no'));   // mã định danh -> không format
            // Mẫu in CHỈ dùng dấu phẩy hàng nghìn ở cột Khối lượng.
            // Độ rộng in "1420" chứ không phải "1,420" -> các cột khác dùng plain().
            r.thickness = plain(m.get('thickness_mm'));
            r.width     = plain(m.get('width_mm'));
            r.len       = isCoilLength(m.get('length')) ? 'C' : plain(m.get('length'));
            r.weight    = fmt(m.get('weight_kg'));
            r.ys        = plain(m.get('yield_strength_MPa'));
            r.ts        = plain(m.get('tensile_strength_MPa'));
            r.el        = plain(m.get('elongation_pct'));
            r.hrb       = plain(m.get('hardness_HRB'));
            r.bend      = plain(m.get('bending_test'));
            r.remarks   = plain(m.get('remarks'));
            r.lines     = lineCost(r.remarks);
            r.chem      = new List<String>();
            for (String c : chemCols) {
                r.chem.add(plain(m.get(c)));
            }
            rows.add(r);
        }
    }

    /**
     * Một cuộn chiếm bao nhiêu ĐƠN VỊ chiều cao.
     * = padding cố định của hàng + số dòng chữ trong ô Ghi chú (cột duy nhất được wrap).
     */
    @TestVisible
    private static Integer lineCost(String remarks) {
        return UNITS_ROW_BASE + (UNITS_EXTRA_LINE * (wrapLines(remarks) - 1));
    }

    /**
     * Đếm số dòng khi wrap — mô phỏng đúng cách CSS ngắt dòng: theo TỪ, không theo ký tự.
     * Phép chia ký tự (ceil(len/22)) ước HỤT: đo trên dữ liệu thật, ghi chú 84 ký tự chia ra
     * 4 nhưng render thành 5 dòng, 168 ký tự chia ra 8 nhưng render 9 dòng — chính chỗ này
     * làm trang bị tràn mất header.
     */
    @TestVisible
    private static Integer wrapLines(String text) {
        if (String.isBlank(text)) return 1;
        Integer width = REMARKS_CHARS_PER_LINE;
        Integer lines = 1;
        Integer used  = 0;
        for (String word : text.trim().split(' ')) {
            Integer len = word.length();
            if (len == 0) continue;
            if (len > width) {
                // từ dài hơn cả ô: bị cắt thành nhiều dòng
                if (used > 0) lines++;
                lines += len / width;
                used = Math.mod(len, width);
            } else if (used == 0) {
                used = len;
            } else if (used + 1 + len <= width) {
                used += 1 + len;      // còn chỗ trên dòng hiện tại (kèm 1 khoảng trắng)
            } else {
                lines++;              // hết chỗ -> xuống dòng mới
                used = len;
            }
        }
        return lines < 1 ? 1 : lines;
    }

    /** length = 0 / '0' / null / rỗng -> hàng dạng cuộn, in chữ "C" */
    private Boolean isCoilLength(Object v) {
        if (v == null) return true;
        String s = String.valueOf(v).trim();
        return s == '' || s == '0' || s == '0.0' || s == '0.00';
    }

    // ===== 2 khối thông tin đầu phiếu =====
    private void buildInfo() {
        infoLeft.add(info('Số/ No.', nz(cert.HPDQ_Certificate_No__c)));
        infoLeft.add(info('Ngày/ Date', fmtDate(cert.HPDQ_Issue_Date__c)));
        infoLeft.add(info('Khách hàng/ Customer', nz(cert.HPDQ_Project__c)));
        infoLeft.add(info('Mã KH/ Customer Code', nz(cert.HPDQ_SAP_Customer_Code__c)));
        infoLeft.add(info('Dự án/ Project', ''));
        infoLeft.add(info('Loại hàng hóa/ Commodity', nz(cert.HPDQ_Product__c)));
        infoLeft.add(info('Mác thép/ Grade', nz(cert.HPDQ_Grade__c)));
        infoLeft.add(info('Tiêu chuẩn/ Standard', nz(cert.HPDQ_Standard__c)));
        infoLeft.add(info('Hợp đồng/ Contract No.', nz(cert.HPDQ_Contract__c)));

        infoRight.add(info('MILL', MILL));
        infoRight.add(info('ADD', ADDR));
        infoRight.add(info('TEL', TEL));
        infoRight.add(info('FAX', FAX));
        infoRight.add(info('Tổng số cuộn/ Total Coils', fmt(cert.HPDQ_Total_Coils__c) + ' (Cuộn/Coils)'));
        infoRight.add(info('Tổng khối lượng/ Total Weight', fmt(cert.HPDQ_Total_Weight__c) + ' (Kg/Kg)'));
    }

    // ===== chân trang =====
    /** "Sản phẩm thép cuộn cán nóng đạt JIS G3125" */
    public String resultVi {
        get {
            if (cert == null) return '';
            String vi = productPart(0);
            String std = nz(cert.HPDQ_Standard__c);
            if (String.isBlank(vi) && String.isBlank(std)) return '';
            return ('Sản phẩm ' + vi.toLowerCase() + (String.isBlank(std) ? '' : ' đạt ' + std))
                   .replaceAll('\\s{2,}', ' ');
        }
    }
    /** "Hot rolled coil product meets JIS G3125" */
    public String resultEn {
        get {
            if (cert == null) return '';
            String en = productPart(1).toLowerCase();
            if (String.isBlank(en)) return '';
            String std = nz(cert.HPDQ_Standard__c);
            return en.substring(0, 1).toUpperCase() + en.substring(1) + ' product'
                   + (String.isBlank(std) ? '' : ' meets ' + std);
        }
    }
    /** Mã góc dưới trái = phần trước dấu "/" của số phiếu */
    public String docCode {
        get {
            if (cert == null) return '';
            return nz(cert.HPDQ_Certificate_No__c).split('/')[0].trim();
        }
    }
    public String pageLabel { get { return 'Page 1/1'; } }

    // ===== các thành phần theo đặc tả 6.2 =====
    public String formCode          { get { return FORM_CODE; } }
    public String formEffectiveDate { get { return FORM_EFFECTIVE_DATE; } }

    /** Tổng khối lượng in ở HÀNG CUỐI BẢNG (đặc tả 6.4 mục 8) */
    public String totalWeightText {
        get { return (cert == null) ? '' : fmt(cert.HPDQ_Total_Weight__c); }
    }

    /** Số cột nằm sau cột Khối lượng — dùng cho colspan của hàng tổng */
    public Integer colsAfterWeight {
        get { return 7 + chemCols.size(); }   // MẺ SỐ + 5 cơ tính + N hóa học + GHI CHÚ
    }

    /**
     * Chú thích cuối bảng, lấy từ HPDQ_Note__c (đặc tả 6.2).
     * Field là Rich Text nên phải bỏ thẻ HTML: engine PDF không xử lý được HTML lồng,
     * và để nguyên thẻ thì người đọc thấy cả "<p>" trên phiếu.
     */
    public String note {
        get {
            if (cert == null || String.isBlank(cert.HPDQ_Note__c)) return '';
            String t = cert.HPDQ_Note__c
                .replaceAll('<br\\s*/?>', '\n')
                .replaceAll('</p>', '\n')
                .replaceAll('<[^>]+>', '')       // bỏ mọi thẻ còn lại
                .replace('&nbsp;', ' ')
                .replace('&amp;', '&')
                .replace('&lt;', '<')
                .replace('&gt;', '>');
            return t.trim();
        }
    }

    /** "THÉP CUỘN CÁN NÓNG/HOT ROLLED COIL" -> [0]=Việt, [1]=Anh */
    private String productPart(Integer idx) {
        List<String> parts = nz(cert.HPDQ_Product__c).split('/');
        return (parts.size() > idx) ? parts[idx].trim() : '';
    }

    // ===== tiện ích định dạng (khớp fmtVal của LWC) =====
    private static String nz(Object o) { return o == null ? '' : String.valueOf(o); }

    /** Trả về giá trị như dữ liệu gốc, chỉ dọn phần ".0" dư của Decimal. KHÔNG chèn dấu phẩy. */
    @TestVisible
    private static String plain(Object v) {
        if (v == null) return '';
        String raw = String.valueOf(v).trim();
        if (raw.endsWith('.0')) raw = raw.substring(0, raw.length() - 2);
        return raw;
    }

    /** Số thuần -> chèn dấu "," hàng nghìn, giữ nguyên phần thập phân. Còn lại trả nguyên trạng. */
    @TestVisible
    private static String fmt(Object v) {
        if (v == null) return '';
        String raw = plain(v);
        if (!Pattern.matches('-?\\d+(\\.\\d+)?', raw)) return raw;

        String sign = raw.startsWith('-') ? '-' : '';
        String body = raw.startsWith('-') ? raw.substring(1) : raw;
        String intPart = body.contains('.') ? body.substringBefore('.') : body;
        String decPart = body.contains('.') ? '.' + body.substringAfter('.') : '';

        String grouped = '';
        Integer count = 0;
        for (Integer i = intPart.length() - 1; i >= 0; i--) {
            grouped = intPart.substring(i, i + 1) + grouped;
            count++;
            if (Math.mod(count, 3) == 0 && i > 0) grouped = ',' + grouped;
        }
        return sign + grouped + decPart;
    }

    private static String fmtDate(Date d) {
        if (d == null) return '';
        return String.valueOf(d.day()).leftPad(2, '0') + '/'
             + String.valueOf(d.month()).leftPad(2, '0') + '/'
             + String.valueOf(d.year());
    }

    private static Info info(String k, String v) {
        Info i = new Info();
        i.k = k;
        i.v = v;
        return i;
    }

    // ===== view model =====
    public class Info { public String k { get; set; } public String v { get; set; } }

    /** Một trang in: chứa phần cuộn của trang đó + cờ để biết có in khối thông tin / chân trang */
    public class CertPage {
        public Integer pageNo    { get; set; }
        public Boolean isFirst   { get; set; }
        public Boolean isLast    { get; set; }
        public List<CoilRow> rows { get; set; }
    }

    public class UnitGroup {
        public String divisor { get; set; }
        public Integer span   { get; set; }
        public String label   { get; set; }
    }

    public class CoilRow {
        public String stt       { get; set; }
        public String coil      { get; set; }
        public String heat      { get; set; }
        public String thickness { get; set; }
        public String width     { get; set; }
        public String len       { get; set; }
        public String weight    { get; set; }
        public String ys        { get; set; }
        public String ts        { get; set; }
        public String el        { get; set; }
        public String hrb       { get; set; }
        public String bend      { get; set; }
        public String remarks   { get; set; }
        public Integer lines    { get; set; }   // số dòng văn bản cuộn này chiếm (do Ghi chú wrap)
        public List<String> chem { get; set; }
    }
}
