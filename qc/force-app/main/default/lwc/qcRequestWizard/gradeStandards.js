/**
 * Bảng quy định tiêu chuẩn
 * ------------------------
 * Tra theo MÁC THÉP (grade) -> Loại hàng hóa / Standard / Số License.
 *
 * Khóa được chuẩn hóa: bỏ khoảng trắng và ký tự đặc biệt, chuyển hoa.
 * Nhờ vậy 'SAE 1006', 'SAE1006', 'sae-1006' đều tra ra cùng một dòng;
 * 'S235+JR' và 'S235JR' cũng vậy.
 *
 * Thêm mác thép mới: chỉ cần thêm một dòng vào GRADE_STANDARDS.
 */

export const GRADE_STANDARDS = [
    {
        grade: 'S235+JR',
        product: 'HOT ROLLED PLATES AND STRIPS OF NON-ALLOY STRUCTURAL STEELS',
        standard: 'MS EN 10025-2 : 2011',
        license: 'PC012155'
    },
    {
        grade: 'SAE 1006',
        product: 'SAE CARBON STEEL COIL',
        standard: 'SAE J 403 : 2014',
        license: 'PC015029'
    },
    {
        grade: 'SAE 1008',
        product: 'SAE CARBON STEEL COIL',
        standard: 'SAE J 403 : 2014',
        license: 'PC015029'
    },
    {
        grade: 'SPHT 1',
        product: 'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
        standard: 'MS 1768 : 2004',
        license: 'PC012154'
    },
    {
        grade: 'SPHT 2',
        product: 'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
        standard: 'MS 1768 : 2004',
        license: 'PC012154'
    },
    {
        grade: 'SPHT 3',
        product: 'HOT ROLLED CARBON STEEL STRIP FOR PIPE AND TUBE',
        standard: 'MS 1768 : 2004',
        license: 'PC012154'
    },
    {
        grade: 'SPHC',
        product: 'HOT ROLLED CARBON STEEL STRIP AND SHEET OF COMMERCIAL AND DRAWING QUALITIES',
        standard: 'MS 1705 : 2023',
        license: 'PC012156'
    },
    {
        grade: 'SPHD',
        product: 'HOT ROLLED CARBON STEEL STRIP AND SHEET OF COMMERCIAL AND DRAWING QUALITIES',
        standard: 'MS 1705 : 2023',
        license: 'PC012156'
    }
];

/** 'SAE 1006' -> 'SAE1006', 'S235+JR' -> 'S235JR' */
export function normalizeGrade(grade) {
    return String(grade == null ? '' : grade).toUpperCase().replace(/[^A-Z0-9]/g, '');
}

const INDEX = GRADE_STANDARDS.reduce((map, row) => {
    map[normalizeGrade(row.grade)] = row;
    return map;
}, {});

/**
 * Tra 1 mác thép.
 * @param {string} grade mác thép lấy từ API (HPDQ_Grade__c)
 * @returns {{grade:string, product:string, standard:string, license:string}|null}
 *          null nếu mác thép chưa có trong bảng.
 */
export function lookupGrade(grade) {
    return INDEX[normalizeGrade(grade)] || null;
}
