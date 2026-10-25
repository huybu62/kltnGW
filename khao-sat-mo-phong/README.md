# Dữ liệu khảo sát MÔ PHỎNG – Tẩy xanh & ý định mua mỹ phẩm Gen Z

> ⚠️ Đây là dữ liệu **giả lập** để chạy thử form, tập làm sạch dữ liệu và dựng mô hình trên SmartPLS.
> Không dùng làm dữ liệu khảo sát thật trong khóa luận. Mọi file đều có tiền tố `MO_PHONG_`.

## Các file

| File | Nội dung |
|---|---|
| `sinh_du_lieu.py` | Sinh 350 phiếu (283 hợp lệ + 67 lỗi) theo mô hình H1–H10 |
| `lam_sach_va_kiem_tra.py` | Lọc phiếu, xuất file SmartPLS, tính Alpha/CR/AVE và dấu các hệ số đường dẫn. **Dùng được cho dữ liệu thật** tải từ Google Sheets |
| `gui_vao_form.py` | (Tùy chọn) Gửi vài phiếu vào **bản sao** của form để kiểm tra |
| `output/MO_PHONG_350_phieu_tho.csv` | 350 phiếu thô, đúng cột như sheet "Câu trả lời biểu mẫu 1" |
| `output/MO_PHONG_dap_an_loai_phieu.csv` | Đáp án: phiếu nào hợp lệ / lỗi gì |
| `output/MO_PHONG_smartpls_hop_le.csv` | 283 phiếu hợp lệ, cột `NTX1..YD5` → nạp thẳng vào SmartPLS |
| `output/MO_PHONG_du_lieu_da_lam_sach.xlsx` | 3 sheet: SmartPLS / phiếu hợp lệ gốc / phiếu bị loại kèm lý do |

## Mã hóa biến

| Mã | Biến | Câu trong form |
|---|---|---|
| NTX1–5 | Nhận thức tẩy xanh | Câu 10–14 |
| HB1–5 | Hiểu biết quảng cáo số | Câu 15–19 |
| UT1–5 | Uy tín nguồn tin | Câu 20–24 |
| HNQC1–5 | Hoài nghi quảng cáo | Câu 25–29 |
| YD1–5 | Ý định mua | Câu 30–34 |

## 67 phiếu không hợp lệ

| Lỗi | Số phiếu |
|---|---|
| Câu 1 = Không (không ở TP.HCM) | 12 |
| Câu 2 ngoài 1997–2008 (không phải Gen Z đủ 18 tuổi) | 10 |
| Câu 3 = Không (không dùng mỹ phẩm) | 10 |
| Câu 4 = Không (không thấy quảng cáo mỹ phẩm xanh) | 10 |
| Chọn cùng một mức cho cả 25 câu | 15 |
| Trả lời zig-zag 1-5-1-5 | 10 |

## Chạy

```bash
pip install numpy pandas openpyxl
python3 sinh_du_lieu.py            # tạo 350 phiếu
python3 lam_sach_va_kiem_tra.py    # lọc còn 283 phiếu + kiểm tra
# Dữ liệu thật: python3 lam_sach_va_kiem_tra.py duong_dan_file_tai_tu_google_sheets.csv
```

## SmartPLS 4

New project → Import data → chọn `MO_PHONG_smartpls_hop_le.csv` → vẽ 5 biến, nối
NTX/HB/UT → HNQC → YD và NTX/HB/UT → YD → *PLS-SEM algorithm* (outer loading, Alpha, CR, AVE, HTMT)
→ *Bootstrapping* 5000 mẫu (đọc *Specific indirect effects* cho H8–H10).

## Cần chỉnh nếu form khác giả định

- Lựa chọn của Câu 5–9 (giới tính, nghề nghiệp, học vấn, nền tảng, số lần mua) được **đoán**, sửa trong `sinh_du_lieu.py` cho khớp chữ trong form.
- `FORM_CO_RE_NHANH = True`: chọn "Không" ở câu gạn lọc thì bỏ trống phần còn lại. Đặt `False` nếu form không rẽ nhánh.
- Độ tuổi hợp lệ: `NAM_SINH_HOP_LE`.
