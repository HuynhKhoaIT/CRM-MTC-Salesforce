import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchData from '@salesforce/apex/QCRequestController.fetchData';
import saveCertificate from '@salesforce/apex/QCRequestController.saveCertificate';
import attachPdf from '@salesforce/apex/QCRequestController.attachPdf';
import getCustomerInfo from '@salesforce/apex/HPDQ_SendCertificate.getCustomerInfo';
import sendToCustomer from '@salesforce/apex/HPDQ_SendCertificate.sendToCustomer';
import loadCertificate from '@salesforce/apex/HPDQ_CertificateWorkflow.loadCertificate';
import submitStep2 from '@salesforce/apex/HPDQ_CertificateWorkflow.submitStep2';
import confirmStep3 from '@salesforce/apex/HPDQ_CertificateWorkflow.confirmStep3';
import traVeBuocTruoc from '@salesforce/apex/HPDQ_CertificateWorkflow.traVeBuocTruoc';
import taoDuocYeuCau from '@salesforce/apex/HPDQ_CertificateWorkflow.taoDuocYeuCau';
import { LOGO_LEFT, LOGO_BOA, LOGO_QUACERT, LOGO_VIETNAMVALUE } from './logos';

// Thông tin công ty (cố định trên phiếu in)
const COMPANY = {
    mill: 'HOA PHAT DUNG QUAT STEEL JOINT STOCK COMPANY',
    add: 'DUNG QUAT ECONOMIC ZONE, VAN TUONG COMMUNE, QUANG NGAI PROVINCE, VIETNAM',
    tel: '(+84) 246 279 7112',
    fax: '(+84) 246 279 7166'
};
// Hệ số quy đổi hiển thị dưới nhóm cột hóa học
const CHEM_DIVISOR = {
    C: '100', Si: '100', Mn: '100', S: '100', P: '100',
    Cu: '1.000', Ni: '1.000', Cr: '1.000', Mo: '1.000',
    V: '10.000', Ti: '10.000', Al: '10.000', B: '10.000',
    CA: '100', Ca: '100', CEV: '100'
};

// Cột cố định (thông tin cuộn) và cột cơ tính — key khớp JSON API trả về.
// label/en/unit dùng chung cho header bảng bước 2 (3 tầng: Việt - Anh - đơn vị) và cho file CSV.
const ID_META = [
    { key: 'coil_no', label: 'SỐ CUỘN', en: 'COIL No.' },
    { key: 'heat_no', label: 'MẺ SỐ', en: 'HEAT No.' }
];
const PROD_META = [
    { key: 'thickness_mm', label: 'Độ dày', en: 'Thickness', unit: 'mm' },
    { key: 'width_mm', label: 'Độ rộng', en: 'Width', unit: 'mm' },
    { key: 'weight_kg', label: 'Khối lượng', en: 'Weight', unit: 'kg' }
];
const MECH_META = [
    { key: 'yield_strength_MPa', label: 'Giới hạn chảy', en: 'Yield strength', unit: 'MPa' },
    { key: 'tensile_strength_MPa', label: 'Giới hạn bền', en: 'Tensile strength', unit: 'MPa' },
    { key: 'elongation_pct', label: 'Độ giãn dài', en: 'Elongation', unit: '%' },
    { key: 'hardness_HRB', label: 'Độ cứng', en: 'Hardness', unit: 'HRB' },
    { key: 'bending_test', label: 'Thử uốn', en: 'Bending Test', unit: '' }
];
// Thứ tự cột dữ liệu giữ nguyên như cũ: số cuộn, mẽ số, dày, rộng, khối lượng
const FIXED_META = [...ID_META, ...PROD_META];

export default class QcRequestWizard extends LightningElement {
    currentStep = 1;

    /* Quay lại bước trước có HAI kiểu khác nhau — đừng gộp làm một:
       - Bấm vào thanh bước ở trên  -> CHỈ XEM lại, không sửa được, chỉ có nút "Tiếp tục"
         để trở về đúng chỗ đang dở. Dùng khi muốn tra lại thông tin đã nhập.
       - Bấm nút "Yêu cầu hiệu chỉnh" -> MỞ KHOÁ cho sửa rồi gửi lại từ bước đó.
         Đây là hành động nghiệp vụ: phòng sau trả phiếu về cho phòng trước sửa. */
    viewOnly = false;      // đang xem lại, không cho sửa
    returnStep = 2;        // "Tiếp tục" ở chế độ xem lại thì quay về bước này

    // form bước 1
    so = '';
    transporter = '';
    customerCode = '';
    idListText = '';

    // dữ liệu
    @track rawRows = [];       // mảng cuộn gốc (giữ để lưu lại JSON)
    @track records = [];       // view model để render/sửa
    header = {};               // thông tin header phiếu
    chemCols = [];             // cột hóa học theo Configuration
    dataJson = '[]';
    createdDate = '';
    isLoading = false;
    isTableFull = false;       // bảng bước 2 đang mở rộng full màn hình?
    showCsvHelp = false;       // đang mở hướng dẫn định dạng file CSV?
    savedRecordId = null;      // Id bản ghi HPDQ_Certificate__c sau khi lưu

    /* ===== QUY TRÌNH 3 BƯỚC LIÊN PHÒNG =====
       Phiếu được tạo NGAY ở bước 1 nên có thể đóng trình duyệt rồi vào làm tiếp,
       và bàn giao được giữa P.KD và P.QLCL.
       `wf` là trạng thái + quyền do Apex trả về, quyết định mở/khoá từng nút. */
    @api recordId;             // có giá trị khi component đặt trên trang chi tiết phiếu
    wf = {};                   // CertState từ HPDQ_CertificateWorkflow
    /* Được tạo yêu cầu mới không (bước 1 là việc của P.KD).
       null = chưa hỏi server. Để null cho tới khi có đáp án thì bước 1 chưa vẽ ra,
       tránh chớp form nhập rồi mới đổi thành thông báo cấm. */
    coQuyenTao = null;

    async connectedCallback() {
        // Mở từ danh sách phiếu -> nạp lại phiếu đang dở và nhảy tới đúng bước
        if (this.recordId) this.napPhieu(this.recordId);
        try {
            this.coQuyenTao = await taoDuocYeuCau();
        } catch (e) {
            // Không hỏi được thì coi như không có quyền: thà chặn nhầm còn hơn cho tạo nhầm
            this.coQuyenTao = false;
        }
    }

    /** Nạp phiếu từ server và dựng lại toàn bộ màn hình. */
    async napPhieu(certId) {
        this.isLoading = true;
        try {
            const s = await loadCertificate({ certId });
            this.apDungState(s);
        } catch (e) {
            this.toast('Không mở được phiếu', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /** Đổ CertState vào màn hình: dữ liệu, header, bước đang mở. */
    apDungState(s) {
        this.wf            = s;
        this.savedRecordId = s.certId;
        this.currentStep   = s.buoc;
        this.viewOnly      = false;

        this.customerCode = s.customerCode || '';
        // Dựng lại ô "Danh sách ID" để phiếu bị trả về còn thấy đã gửi BK những ID nào.
        // SO và Tên tàu không có field lưu trên object nên KHÔNG khôi phục được — phải nhập lại.
        if (s.listIdText) this.idListText = s.listIdText;
        this.dataJson     = s.dataJson || '[]';
        this.chemCols     = (s.configuration || '').split(';').map((c) => c.trim()).filter((c) => c);
        this.header = {
            ...this.header,
            certNo: s.certNo, issueDate: s.issueDate, project: s.project,
            product: s.product, grade: s.grade, standard: s.standard,
            contract: s.contract, customerCode: s.customerCode,
            totalCoils: s.totalCoils, totalWeight: s.totalWeight, note: s.note,
            // BẮT BUỘC phải có: saveCertificate (nút Trích PDF) chặn phiếu thiếu Configuration.
            // Thiếu dòng này thì mở phiếu từ trang chi tiết rồi Trích PDF sẽ báo
            // "BK không trả về danh sách thành phần phân tích".
            configuration: s.configuration
        };
        try {
            this.rawRows = JSON.parse(this.dataJson).map((r) => ({ ...r }));
        } catch (err) {
            this.rawRows = [];
        }
        this.buildRecords();
    }

    // ===== cờ điều khiển giao diện theo quyền =====
    get suaDuocBuoc1()  { return this.wf.suaDuocBuoc1 === true; }
    get suaDuocBuoc2()  { return this.wf.suaDuocBuoc2 === true; }
    get traVeDuoc()     { return this.wf.traVeDuoc === true; }
    get xacNhanDuoc()   { return this.wf.xacNhanDuoc === true; }
    get phatHanhDuoc()  { return this.wf.phatHanhDuoc === true; }
    /* Chỉ báo khi đang ở đúng bước phiếu đang chờ. Đang xem lại bước cũ mà vẫn hiện
       "phiếu đang chờ P.QLCL" thì mâu thuẫn với khung "đang xem lại" ngay bên cạnh. */
    get coThongBaoWf()  { return !!this.wf.thongBao && !this.viewOnly; }
    get thongBaoWf()    { return this.wf.thongBao; }
    /** Bảng ở bước 2 chỉ sửa được khi đúng người, đúng trạng thái */
    get khoaBang()      { return this.viewOnly || !this.suaDuocBuoc2; }

    /** P.QLCL lưu số liệu đã hiệu chỉnh và đẩy phiếu sang bước 3. */
    async handleSubmitStep2() {
        this.isLoading = true;
        try {
            const s = await submitStep2({
                certId: this.savedRecordId,
                dataJson: JSON.stringify(this.rawRows),
                note: this.header.note || null
            });
            this.apDungState(s);
            this.toast('Đã xác nhận', 'Phiếu đã chuyển sang bước 3 cho phòng kinh doanh.', 'success');
        } catch (e) {
            this.toast('Không xác nhận được', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /** Bước 3: người tạo phiếu chốt nội dung trước khi cho phát hành. */
    async handleConfirmStep3() {
        this.isLoading = true;
        try {
            const s = await confirmStep3({ certId: this.savedRecordId });
            this.apDungState(s);
            this.toast('Đã xác nhận', 'Giờ có thể trích PDF và gửi cho khách hàng.', 'success');
        } catch (e) {
            this.toast('Không xác nhận được', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /** Trả phiếu về bước trước để phòng kia sửa lại. */
    async handleTraVe() {
        this.isLoading = true;
        try {
            const s = await traVeBuocTruoc({ certId: this.savedRecordId });
            this.apDungState(s);
            // Lời nhắn theo bước phiếu VỪA lùi về, không đoán theo bước cũ
            this.toast(
                'Đã trả phiếu',
                s.buoc === 1
                    ? 'Phiếu quay lại bước 1, chờ phòng kinh doanh lấy lại dữ liệu từ BK.'
                    : 'Phiếu quay lại bước 2 chờ P.QLCL hiệu chỉnh.',
                'success'
            );
        } catch (e) {
            this.toast('Không trả về được', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ===== hiển thị bước =====
    /* Bước 1 chỉ vẽ cho người được tạo yêu cầu. Người khác (P.QLCL) thấy thông báo thay thế.
       Phiếu bị trả về bước 1 cũng qua cửa này — người tạo phiếu là P.KD nên vẫn vào được. */
    get isStep1()      { return this.currentStep === 1 && this.coQuyenTao === true; }
    get camTaoYeuCau() { return this.currentStep === 1 && this.coQuyenTao === false; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }

    // Bước 1 và 2 có 2 bộ mặt: đang làm (sửa được) và xem lại (khoá).
    // Bước 3 là bước cuối nên không có chế độ xem lại.
    /* Phiếu đã tạo rồi thì bước 1 khoá: yêu cầu gốc đã gửi sang BK và đã sinh ra phiếu.
       NGOẠI LỆ: P.QLCL yêu cầu hiệu chỉnh -> mở lại cho người tạo sửa SO / danh sách ID
       rồi bấm "Lấy dữ liệu" lần nữa để nạp lại số liệu từ BK. */
    get khoaBuoc1()   { return this.viewOnly || (!!this.savedRecordId && !this.suaDuocBuoc1); }
    get isStep1Edit() { return this.isStep1 && !this.khoaBuoc1; }
    get isStep1View() { return this.isStep1 && this.khoaBuoc1; }
    get isStep2Edit() { return this.isStep2 && this.suaDuocBuoc2; }
    get isStep2View() { return this.isStep2 && !this.suaDuocBuoc2; }

    // ===== điều hướng =====
    /** Bấm thanh bước ở trên: chỉ xem lại bước đã qua, không mở khoá sửa. */
    viewStep(n) {
        if (this.currentStep <= n) return;   // không nhảy tới trước, không bấm lại chính nó
        this.exitTableFull();
        this.returnStep = this.currentStep;
        this.viewOnly = true;
        this.currentStep = n;
    }
    viewStep1() { this.viewStep(1); }
    viewStep2() { this.viewStep(2); }

    /** Nút "Tiếp tục" ở chế độ xem lại: trả về đúng bước đang dở. */
    continueBack() {
        this.exitTableFull();
        this.viewOnly = false;
        // Mở từ danh sách phiếu thì quay về đúng bước phiếu đang chờ, không phải returnStep
        this.currentStep = this.wf.buoc || this.returnStep;
    }

    /** Nút "Yêu cầu hiệu chỉnh": trả phiếu về bước trước và MỞ KHOÁ cho sửa. */
    requestEdit(n) {
        this.exitTableFull();
        this.viewOnly = false;
        this.currentStep = n;
    }
    requestEdit1() { this.requestEdit(1); }
    requestEdit2() { this.requestEdit(2); }

    // ===== SLDS path classes =====
    pathClass(n) {
        if (n < this.currentStep) return 'slds-path__item slds-is-complete';
        if (n === this.currentStep) return 'slds-path__item slds-is-current slds-is-active';
        return 'slds-path__item slds-is-incomplete';
    }
    get path1Class() { return this.pathClass(1); }
    get path2Class() { return this.pathClass(2); }
    get path3Class() { return this.pathClass(3); }

    // ===== metadata cột cho template =====
    get idMeta() { return ID_META; }
    get prodMeta() { return PROD_META; }
    get mechMeta() { return MECH_META; }
    get prodCount() { return PROD_META.length; }
    get mechCount() { return MECH_META.length; }
    get chemCount() { return this.chemCols.length; }
    get totalRecords() { return this.records.length; }
    get infoRows() {
        const h = this.header;
        return [
            { k: 'Số (SO)', v: this.so },
            { k: 'Tên tàu', v: this.transporter },
            { k: 'Customer Code', v: h.customerCode },
            { k: 'Số phiếu', v: h.certNo },
            { k: 'Mác thép', v: h.grade },
            { k: 'Tiêu chuẩn', v: h.standard },
            { k: 'Tổng số cuộn', v: h.totalCoils },
            { k: 'Tổng KL (kg)', v: this.fmtVal(h.totalWeight) }
        ].map((r, i) => ({ id: i, ...r }));
    }

    // ================= BƯỚC 1 =================
    handleInput(e) { this[e.target.dataset.field] = e.target.value; }

    handleImportIds(e) {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            const ids = (reader.result || '')
                .split(/\r?\n/)
                .map((l) => l.split(',')[0].trim())
                .filter((v) => v && v.toLowerCase() !== 'id');
            this.idListText = ids.join(', ');
            this.toast('Đã nhập', ids.length + ' ID từ CSV', 'success');
        };
        reader.readAsText(file);
        e.target.value = null;
    }

    toggleCsvHelp() { this.showCsvHelp = !this.showCsvHelp; }

    parseIds() {
        return this.idListText.split(/[\n,]+/).map((v) => v.trim()).filter((v) => v);
    }

    async submitRequest() {
        // Bắt buộc: SO, Customer Code, Danh sách ID. Tên tàu để trống vẫn gửi được.
        const listId = this.parseIds();
        if (!this.so || !this.customerCode || listId.length === 0) {
            this.toast('Thiếu thông tin',
                'Nhập đủ Số (SO), Customer Code và Danh sách ID.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            const res = await fetchData({
                so: this.so,
                transporter: this.transporter,
                customerCode: this.customerCode,
                listId
            });
            this.applyResult(res);
            this.createdDate = this.nowString();
            this.viewOnly = false;
            this.savedRecordId = res.certId;

            // Bước 1 đã tạo record trên server. Nạp lại trạng thái + quyền để biết
            // người đang đứng đây có được làm bước 2 không (thường là KHÔNG — bước 2
            // là việc của P.QLCL, nên họ sẽ thấy màn hình chỉ đọc kèm lời nhắn chờ).
            await this.napPhieu(res.certId);

            if (res.daTonTai) {
                this.toast('Phiếu đã tồn tại',
                    'Số phiếu ' + res.certNo + ' đã có trong hệ thống, đang mở ra để làm tiếp.',
                    'info');
            } else {
                this.toast('Đã tạo phiếu',
                    'Phiếu ' + res.certNo + ' đã chuyển sang Phòng QLCL kiểm tra.', 'success');
            }
        } catch (e) {
            this.toast('Lỗi lấy dữ liệu', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    applyResult(res) {
        this.header = res || {};
        this.dataJson = res.dataJson || '[]';
        this.chemCols = (res.configuration || '').split(';').map((c) => c.trim()).filter((c) => c);
        this.rawRows = (res.rows || []).map((r) => ({ ...r }));
        this.buildRecords();
    }

    // cột hiển thị = FIXED + MECH + CHEM
    get columns() {
        return [
            ...FIXED_META,
            ...MECH_META,
            ...this.chemCols.map((c) => ({ key: c, label: c }))
        ];
    }

    buildRecords() {
        const cols = this.columns;
        this.records = this.rawRows.map((raw, idx) => ({
            idx,
            stt: raw.stt != null ? raw.stt : idx + 1,
            remarks: raw.remarks != null ? String(raw.remarks) : '',
            cells: cols.map((c) => ({
                key: c.key,
                value: raw[c.key] != null ? String(raw[c.key]) : ''
            }))
        }));
    }

    handleCancel() {
        this.so = this.transporter = this.customerCode = this.idListText = '';
        this.records = []; this.rawRows = [];
    }

    // ================= BƯỚC 2 =================
    // --- mở rộng bảng dữ liệu ra full màn hình ---
    get tableWrapClass() {
        return this.isTableFull ? 'slds-col slds-size_3-of-4 qc-full' : 'slds-col slds-size_3-of-4';
    }
    get tableFullLabel() { return this.isTableFull ? 'Thu gọn' : 'Mở rộng'; }
    get tableFullIcon() { return this.isTableFull ? 'utility:contract_alt' : 'utility:expand_alt'; }

    escHandler = (e) => { if (e.key === 'Escape') this.exitTableFull(); };

    toggleTableFull() {
        if (this.isTableFull) { this.exitTableFull(); return; }
        this.isTableFull = true;
        document.addEventListener('keydown', this.escHandler);
    }
    exitTableFull() {
        if (!this.isTableFull) return;
        this.isTableFull = false;
        document.removeEventListener('keydown', this.escHandler);
    }
    disconnectedCallback() { document.removeEventListener('keydown', this.escHandler); }

    handleCellChange(e) {
        const idx = parseInt(e.target.dataset.index, 10);
        const key = e.target.dataset.key;
        const value = e.target.value;
        if (this.rawRows[idx]) this.rawRows[idx][key] = value;
        this.records = this.records.map((r) => {
            if (r.idx !== idx) return r;
            return { ...r, cells: r.cells.map((c) => (c.key === key ? { ...c, value } : c)) };
        });
    }

    handleRemarksChange(e) {
        const idx = parseInt(e.target.dataset.index, 10);
        const value = e.target.value;
        if (this.rawRows[idx]) this.rawRows[idx].remarks = value;
        this.records = this.records.map((r) => (r.idx === idx ? { ...r, remarks: value } : r));
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            const res = await fetchData({
                so: this.so, transporter: this.transporter,
                customerCode: this.customerCode, listId: this.parseIds()
            });
            this.applyResult(res);
            this.toast('Đã làm mới', 'Tải lại dữ liệu từ BK.', 'success');
        } catch (e) {
            this.toast('Lỗi', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ===== Xuất Excel =====
    /** Escape ký tự đặc biệt của XML */
    xmlEsc(v) {
        return String(v == null ? '' : v)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    /**
     * Một ô trong SpreadsheetML.
     * @param {Object} o - {v: giá trị, s: tên style, num: true nếu là số,
     *                      across: gộp thêm N cột, down: gộp thêm N dòng, at: nhảy tới cột thứ N}
     */
    xlCell(o) {
        const a = [];
        if (o.at) a.push(' ss:Index="' + o.at + '"');
        if (o.s) a.push(' ss:StyleID="' + o.s + '"');
        if (o.across) a.push(' ss:MergeAcross="' + o.across + '"');
        if (o.down) a.push(' ss:MergeDown="' + o.down + '"');
        const type = o.num ? 'Number' : 'String';
        const val = o.v === '' || o.v == null ? '' :
            '<Data ss:Type="' + type + '">' + this.xmlEsc(o.v) + '</Data>';
        return '<Cell' + a.join('') + '>' + val + '</Cell>';
    }

    xlRow(cells) { return '<Row>' + cells.join('') + '</Row>'; }

    /**
     * Xuất file Excel giống hệt bảng trên phiếu in: cùng thứ tự cột, cùng 5 tầng tiêu đề
     * CÓ GỘP Ô và canh giữa, cùng hàng TỔNG cuối bảng.
     *
     * Dùng định dạng SpreadsheetML (XML của Excel) chứ không phải CSV: CSV là text phẳng,
     * không diễn tả được ô gộp, canh giữa, viền hay in đậm.
     *
     * Khối lượng ghi dạng SỐ (không phải chuỗi "19,114") để Excel cộng/lọc/sắp xếp được,
     * nhưng gắn định dạng hiển thị #,##0 nên nhìn vẫn có dấu phẩy như trên phiếu.
     * Số cuộn và Mẻ số cố ý để dạng CHỮ: nếu để số, Excel cắt số 0 đầu và đổi sang ký hiệu
     * khoa học khi mã dài.
     */
    handleExport() {
        const chem = this.chemCols;
        const nChem = chem.length;
        const lastCol = 13 + nChem;          // tổng số cột: 12 cột cố định + hóa học + ghi chú

        const rows = [];

        // --- Tầng 1: nhóm tiếng Việt ---
        rows.push(this.xlRow([
            this.xlCell({ v: 'STT', s: 'h', down: 4 }),
            this.xlCell({ v: 'SỐ CUỘN', s: 'h', down: 4 }),
            this.xlCell({ v: 'THÔNG TIN SẢN PHẨM', s: 'h', across: 3 }),
            this.xlCell({ v: 'MẺ SỐ', s: 'h', at: 7, down: 4 }),
            this.xlCell({ v: 'CƠ TÍNH SẢN PHẨM', s: 'h', across: 4 }),
            this.xlCell({ v: 'THÀNH PHẦN HÓA HỌC (%)', s: 'h', across: nChem - 1 }),
            this.xlCell({ v: 'GHI CHÚ', s: 'h', at: lastCol, down: 4 })
        ]));

        // --- Tầng 2: nhóm tiếng Anh (các cột gộp dọc ở tầng 1 bị bỏ qua) ---
        rows.push(this.xlRow([
            this.xlCell({ v: 'PRODUCT INFORMATION', s: 'h', at: 3, across: 3 }),
            this.xlCell({ v: 'MECHANICAL PROPERTIES', s: 'h', at: 8, across: 4 }),
            this.xlCell({ v: 'CHEMICAL COMPOSITION (%)', s: 'h', at: 13, across: nChem - 1 })
        ]));

        // --- Tầng 3: tên cột tiếng Việt + ký hiệu nguyên tố (gộp xuống tầng 4) ---
        rows.push(this.xlRow([
            this.xlCell({ v: 'Độ dày', s: 'h', at: 3 }),
            this.xlCell({ v: 'Độ rộng', s: 'h' }),
            this.xlCell({ v: 'Chiều dài', s: 'h' }),
            this.xlCell({ v: 'Khối lượng', s: 'h' }),
            this.xlCell({ v: 'Giới hạn chảy', s: 'h', at: 8 }),
            this.xlCell({ v: 'Giới hạn bền', s: 'h' }),
            this.xlCell({ v: 'Độ giãn dài', s: 'h' }),
            this.xlCell({ v: 'Độ cứng', s: 'h' }),
            this.xlCell({ v: 'Thử uốn', s: 'h' }),
            ...chem.map((c) => this.xlCell({ v: c, s: 'h', down: 1 }))
        ]));

        // --- Tầng 4: tên cột tiếng Anh ---
        rows.push(this.xlRow([
            this.xlCell({ v: 'Thickness', s: 'h', at: 3 }),
            this.xlCell({ v: 'Width', s: 'h' }),
            this.xlCell({ v: 'Length', s: 'h' }),
            this.xlCell({ v: 'Weight', s: 'h' }),
            this.xlCell({ v: 'Yield strength', s: 'h', at: 8 }),
            this.xlCell({ v: 'Tensile strength', s: 'h' }),
            this.xlCell({ v: 'Elongation', s: 'h' }),
            this.xlCell({ v: 'Hardness', s: 'h' }),
            this.xlCell({ v: 'Bending Test', s: 'h' })
        ]));

        // --- Tầng 5: đơn vị, nhóm hệ số hóa học gộp ngang đúng như phiếu ---
        const unitCells = [
            this.xlCell({ v: 'mm', s: 'h', at: 3 }),
            this.xlCell({ v: 'mm', s: 'h' }),
            this.xlCell({ v: 'mm', s: 'h' }),
            this.xlCell({ v: 'kg', s: 'h' }),
            this.xlCell({ v: 'MPa', s: 'h', at: 8 }),
            this.xlCell({ v: 'MPa', s: 'h' }),
            this.xlCell({ v: '%', s: 'h' }),
            this.xlCell({ v: 'HRB', s: 'h' }),
            this.xlCell({ v: '', s: 'h' })
        ];
        this.chemUnitGroups.forEach((g) => {
            unitCells.push(this.xlCell({ v: g.label, s: 'h', across: g.span - 1 }));
        });
        rows.push(this.xlRow(unitCells));

        // --- Dữ liệu ---
        this.certFullRows.forEach((r, i) => {
            const raw = this.rawRows[i];
            const weight = raw && raw.weight_kg != null ? raw.weight_kg : null;
            rows.push(this.xlRow([
                this.xlCell({ v: r.stt, s: 'c' }),
                this.xlCell({ v: r.coil, s: 'c' }),
                this.xlCell({ v: r.thickness, s: 'c' }),
                this.xlCell({ v: r.width, s: 'c' }),
                this.xlCell({ v: r.length, s: 'c' }),
                this.xlCell({ v: weight, s: 'n', num: weight != null }),
                this.xlCell({ v: r.heat, s: 'c' }),
                this.xlCell({ v: r.ys, s: 'c' }),
                this.xlCell({ v: r.ts, s: 'c' }),
                this.xlCell({ v: r.el, s: 'c' }),
                this.xlCell({ v: r.hrb, s: 'c' }),
                this.xlCell({ v: r.bend, s: 'c' }),
                ...r.chem.map((c) => this.xlCell({ v: c.value, s: 'c' })),
                this.xlCell({ v: r.remarks, s: 'l' })
            ]));
        });

        // --- Hàng tổng: nhãn gộp 5 cột đầu, giống phiếu ---
        const total = this.header.totalWeight;
        rows.push(this.xlRow([
            this.xlCell({ v: 'TỔNG/ TOTAL', s: 'h', across: 4 }),
            this.xlCell({ v: total == null ? '' : total, s: 'tn', num: total != null })
        ]));

        // Bề rộng cột: 2 cột mã rộng hơn, cột ghi chú rộng nhất
        const widths = [30, 80, 45, 45, 45, 60, 70, 55, 55, 55, 45, 45]
            .concat(new Array(nChem).fill(32))
            .concat([150]);

        const xml =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"' +
            ' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">' +
            '<Styles>' +
              '<Style ss:ID="h">' +
                '<Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/>' +
                '<Font ss:Bold="1" ss:Size="9"/>' +
                '<Interior ss:Color="#F2F2F2" ss:Pattern="Solid"/>' +
                '<Borders>' + ['Top', 'Bottom', 'Left', 'Right'].map((p) =>
                    '<Border ss:Position="' + p + '" ss:LineStyle="Continuous" ss:Weight="1"/>').join('') +
                '</Borders>' +
              '</Style>' +
              '<Style ss:ID="c">' +
                '<Alignment ss:Horizontal="Center" ss:Vertical="Center"/><Font ss:Size="9"/>' +
                '<Borders>' + ['Top', 'Bottom', 'Left', 'Right'].map((p) =>
                    '<Border ss:Position="' + p + '" ss:LineStyle="Continuous" ss:Weight="1"/>').join('') +
                '</Borders>' +
              '</Style>' +
              '<Style ss:ID="l">' +
                '<Alignment ss:Horizontal="Left" ss:Vertical="Center" ss:WrapText="1"/><Font ss:Size="9"/>' +
                '<Borders>' + ['Top', 'Bottom', 'Left', 'Right'].map((p) =>
                    '<Border ss:Position="' + p + '" ss:LineStyle="Continuous" ss:Weight="1"/>').join('') +
                '</Borders>' +
              '</Style>' +
              '<Style ss:ID="n" ss:Parent="c"><NumberFormat ss:Format="#,##0"/></Style>' +
              '<Style ss:ID="tn" ss:Parent="h"><NumberFormat ss:Format="#,##0"/></Style>' +
            '</Styles>' +
            '<Worksheet ss:Name="MTC">' +
              '<Table>' +
                widths.map((w) => '<Column ss:Width="' + w + '"/>').join('') +
                rows.join('') +
              '</Table>' +
              '<WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">' +
                '<PageSetup><Layout x:Orientation="Landscape"' +
                ' xmlns:x="urn:schemas-microsoft-com:office:excel"/></PageSetup>' +
                '<FreezePanes/><FrozenNoSplit/><SplitHorizontal>5</SplitHorizontal>' +
                '<TopRowBottomPane>5</TopRowBottomPane><ActivePane>2</ActivePane>' +
              '</WorksheetOptions>' +
            '</Worksheet></Workbook>';

        // Blob thay cho data URI: lô nghìn cuộn sinh file vài MB, data URI sẽ bị chặn
        const blob = new Blob(['﻿' + xml], { type: 'application/vnd.ms-excel' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'MTC_' + (this.docCode || 'export') + '.xls';
        a.click();
        URL.revokeObjectURL(url);
    }

    // ---- dữ liệu cho bản xem trước giống mẫu chuẩn ----
    get logoLeft() { return LOGO_LEFT; }

    /* 3 logo chứng nhận ở góc phải. Trả về mảng để SẮP TỚI lọc theo mác thép —
       khi đó chỉ sửa getter này, template lặp sẵn rồi.
       Bên trang in (Visualforce) phải làm bằng cờ rendered vì Visualforce không cho
       tên Static Resource động; hai bên khác cách nhưng cùng một danh sách logo. */
    get certLogos() {
        return [
            { id: 'boa',     src: LOGO_BOA,          alt: 'BoA VILAS 1190',   cls: 'qc-logo qc-logo-c qc-logo-c1' },
            { id: 'quacert', src: LOGO_QUACERT,      alt: 'QUACERT ISO 9001', cls: 'qc-logo qc-logo-c qc-logo-c2' },
            { id: 'vnvalue', src: LOGO_VIETNAMVALUE, alt: 'Vietnam Value',    cls: 'qc-logo qc-logo-c qc-logo-c3' }
        ];
    }

    get certInfoLeft() {
        const h = this.header;
        return [
            { id: 1, k: 'Số/ No.', v: h.certNo },
            { id: 2, k: 'Ngày/ Date', v: this.fmtDate(h.issueDate) },
            { id: 3, k: 'Khách hàng/ Customer', v: h.project || '' },
            { id: 4, k: 'Dự án/ Project', v: '' },
            { id: 5, k: 'Loại hàng hóa/ Commodity', v: h.product },
            { id: 6, k: 'Mác thép/ Grade', v: h.grade },
            { id: 7, k: 'Tiêu chuẩn/ Standard', v: h.standard },
            { id: 8, k: 'Hợp đồng/ Contract No.', v: h.contract }
        ];
    }
    get certInfoRight() {
        const h = this.header;
        return [
            { id: 1, k: 'MILL', v: COMPANY.mill },
            { id: 2, k: 'ADD', v: COMPANY.add },
            { id: 3, k: 'TEL', v: COMPANY.tel },
            { id: 4, k: 'FAX', v: COMPANY.fax },
            { id: 5, k: 'Tổng số cuộn/ Total Coils', v: this.fmtVal(h.totalCoils) + ' (Cuộn/Coils)' },
            { id: 6, k: 'Tổng khối lượng/ Total Weight', v: this.fmtVal(h.totalWeight) + ' (Kg/Kg)' }
        ];
    }

    // Gom cột hóa học liên tiếp cùng hệ số -> ô đơn vị có colspan
    get chemUnitGroups() {
        const groups = [];
        this.chemCols.forEach((c) => {
            const d = CHEM_DIVISOR[c] || '';
            const last = groups[groups.length - 1];
            if (last && last.divisor === d) {
                last.span += 1;
            } else {
                groups.push({ divisor: d, span: 1, label: d ? 'x ' + d : '' });
            }
        });
        return groups.map((g, i) => ({ ...g, id: i }));
    }

    // Một dòng đầy đủ cho bảng chứng chỉ
    get certFullRows() {
        return this.rawRows.map((r, i) => ({
            id: i,
            stt: r.stt != null ? r.stt : i + 1,
            // Mẫu in CHỈ chèn dấu phẩy hàng nghìn ở cột Khối lượng.
            // Độ rộng in "1420" chứ không phải "1,420" -> các cột khác giữ nguyên dữ liệu gốc.
            coil: this.s(r.coil_no),   // mã định danh -> không format
            heat: this.s(r.heat_no),   // mã định danh -> không format
            thickness: this.s(r.thickness_mm),
            width: this.s(r.width_mm),
            length: (r.length === 0 || r.length === '0' || r.length == null || r.length === '') ? 'C' : this.s(r.length),
            weight: this.fmtVal(r.weight_kg),
            ys: this.s(r.yield_strength_MPa),
            ts: this.s(r.tensile_strength_MPa),
            el: this.s(r.elongation_pct),
            hrb: this.s(r.hardness_HRB),
            bend: this.s(r.bending_test),
            remarks: this.s(r.remarks),
            chem: this.chemCols.map((c) => ({ key: c, value: this.s(r[c]) }))
        }));
    }

    // ---- chân trang phiếu (không in dấu mộc & chữ ký) ----
    // "THÉP CUỘN CÁN NÓNG / HOT ROLLED COIL" -> { vi, en }
    get productParts() {
        const parts = this.s(this.header.product).split('/');
        return { vi: (parts[0] || '').trim(), en: (parts[1] || '').trim() };
    }
    // "Sản phẩm thép cuộn cán nóng đạt JIS G3125"
    get certResultVi() {
        const vi = this.productParts.vi;
        const std = this.s(this.header.standard);
        if (!vi && !std) return '';
        return ('Sản phẩm ' + vi.toLowerCase() + (std ? ' đạt ' + std : '')).replace(/\s{2,}/g, ' ');
    }
    // "Hot rolled coil product meets JIS G3125"
    get certResultEn() {
        const en = this.productParts.en.toLowerCase();
        const std = this.s(this.header.standard);
        if (!en) return '';
        return en.charAt(0).toUpperCase() + en.slice(1) + ' product' + (std ? ' meets ' + std : '');
    }
    // mã phiếu góc trái = phần trước dấu "/" của Số phiếu
    // vd certNo "0044-070925/HOAPHAT" -> "0044-070925"
    get docCode() { return this.s(this.header.certNo).split('/')[0].trim(); }
    get pageLabel() { return 'Page 1/1'; }

    s(v) { return v == null ? '' : String(v); }
    /**
     * Định dạng chung cho MỌI giá trị hiển thị trên phiếu.
     *  - Số thuần   -> chèn dấu "," ngăn cách hàng nghìn: 1174724 -> "1,174,724"
     *  - Phần thập phân giữ nguyên như dữ liệu gốc: "4.50" -> "4.50" (không rút gọn thành 4.5)
     *  - Đã có sẵn dấu ",", có chữ, mã hiệu, rỗng -> trả về nguyên trạng
     * Không áp dụng cho STT / Số cuộn / Mẽ số vì đó là mã định danh, thêm dấu "," sẽ sai.
     */
    fmtVal(v) {
        if (v == null) return '';
        const raw = String(v).trim();
        const m = raw.match(/^(-?)(\d+)(\.\d+)?$/);
        if (!m) return raw;
        return m[1] + m[2].replace(/\B(?=(\d{3})+(?!\d))/g, ',') + (m[3] || '');
    }
    fmtDate(v) {
        if (!v) return '';
        const d = String(v).substring(0, 10).split('-');
        return d.length === 3 ? `${d[2]}/${d[1]}/${d[0]}` : String(v);
    }

    // Gói toàn bộ dữ liệu phiếu để Apex lưu vào HPDQ_Certificate__c
    get certPayload() {
        const h = this.header;
        return {
            so: this.so,
            transporter: this.transporter,
            customerCode: this.customerCode || h.customerCode,
            certNo: h.certNo,
            issueDate: h.issueDate,
            project: h.project,
            product: h.product,
            grade: h.grade,
            standard: h.standard,
            contract: h.contract,
            totalCoils: h.totalCoils,
            totalWeight: h.totalWeight,
            configuration: h.configuration,
            listIdText: this.parseIds().join(', '),
            dataJson: JSON.stringify(this.rawRows)
        };
    }

    async handleExtractPdf() {
        if (!this.header.certNo) {
            this.toast('Thiếu số phiếu', 'Chưa có số phiếu từ BK nên không lưu được.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            this.savedRecordId = await saveCertificate({
                certJson: JSON.stringify(this.certPayload)
            });

            // Đính PDF ở lần gọi Apex RIÊNG: getContentAsPDF không thấy dữ liệu chưa commit
            // nên bắt buộc phải sau khi saveCertificate kết thúc transaction.
            let attached = true;
            try {
                await attachPdf({ certId: this.savedRecordId });
            } catch (e) {
                attached = false;
                this.toast('Đã lưu phiếu, chưa đính được PDF', this.errMsg(e), 'warning');
            }
            if (attached) {
                this.toast('Xong',
                    'Phiếu ' + this.header.certNo + ' đã lưu và đính file PDF.', 'success');
            }

            // Mở bản PDF ở tab mới. Cần &pdf=1: không có tham số này trang render HTML
            // (chế độ dùng cho tab "Trang In" nhúng trong Record Page).
            window.open('/apex/HPDQ_MTC_Certificate?id=' + this.savedRecordId + '&pdf=1', '_blank');
        } catch (e) {
            this.toast('Lỗi lưu phiếu', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ===== gửi phiếu cho khách hàng =====
    /* Khách hàng KHÔNG có tài khoản Salesforce nên chỉ nhận FILE PDF ĐÍNH KÈM.
       Link trang in là link nội bộ, khách bấm vào chỉ thấy màn hình đăng nhập,
       nên không đưa vào mail. */
    showSendBox = false;       // đang mở hộp xác nhận gửi?
    sendInfo = {};             // thông tin khách hàng do Apex trả về
    sendEmail = '';            // email người dùng có thể sửa trước khi gửi

    /** Chưa Trích PDF thì chưa có phiếu lẫn file để gửi */
    get sendDisabled() { return !this.savedRecordId; }
    get sendTitle() {
        return this.savedRecordId
            ? 'Gửi phiếu cho khách hàng qua email'
            : 'Hãy bấm "Trích PDF" trước khi gửi';
    }
    // Template LWC không viết được biểu thức phủ định nên phải có getter riêng
    get sendBtnDisabled() {
        return !(this.sendInfo.canSend && this.sendEmail && this.sendEmail.includes('@'));
    }

    async handleTransfer() {
        if (!this.savedRecordId) {
            this.toast('Chưa có phiếu', 'Hãy bấm "Trích PDF" trước khi gửi.', 'warning');
            return;
        }
        this.isLoading = true;
        try {
            this.sendInfo = await getCustomerInfo({ certId: this.savedRecordId });
            this.sendEmail = this.sendInfo.email || '';
            this.showSendBox = true;
        } catch (e) {
            this.toast('Lỗi', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleSendEmailChange(e) { this.sendEmail = e.target.value; }
    closeSendBox() { this.showSendBox = false; }

    async confirmSend() {
        this.isLoading = true;
        try {
            const msg = await sendToCustomer({
                certId: this.savedRecordId,
                toEmail: this.sendEmail
            });
            this.showSendBox = false;
            this.toast('Đã gửi', msg, 'success');
            // Gửi xong server đổi trạng thái sang "P.KD xác nhận". Không nạp lại thì huy hiệu
            // trạng thái và các nút vẫn theo dữ liệu cũ — bấm vào mới báo lỗi.
            await this.napPhieu(this.savedRecordId);
        } catch (e) {
            this.toast('Không gửi được', this.errMsg(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ================= tiện ích =================
    nowString() {
        const d = new Date();
        const p = (n) => String(n).padStart(2, '0');
        return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return (e && e.body && e.body.message) ? e.body.message : ((e && e.message) || 'Đã xảy ra lỗi.');
    }
}
