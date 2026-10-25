"""
Làm sạch 350 phiếu thô -> phiếu hợp lệ, xuất file cho SmartPLS, và kiểm tra nhanh
độ tin cậy (Cronbach's Alpha, CR, AVE) + dấu các hệ số đường dẫn H1–H10.

Dùng được cho cả dữ liệu thật tải từ Google Sheets (File > Tải xuống > .csv),
miễn là tên cột giữ nguyên như trong form.

Chạy:  python3 lam_sach_va_kiem_tra.py [đường_dẫn_csv]
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd

from sinh_du_lieu import COT_GAN_LOC, COT_LIKERT, COT_NHAN_KHAU, MA_LIKERT, THANG_DO, la_rang_cua, nam_sinh_hop_le

OUT = Path(__file__).parent / "output"


def lam_sach(df):
    ly_do = pd.Series("", index=df.index)

    def danh_dau(mask, ten):
        moi = mask & (ly_do == "")
        ly_do[moi] = ten

    danh_dau(df[COT_GAN_LOC[0]] != "Có", "Không ở TP.HCM")
    danh_dau(~df[COT_GAN_LOC[1]].map(nam_sinh_hop_le), "Ngoài độ tuổi Gen Z (18+)")
    danh_dau(df[COT_GAN_LOC[2]] != "Có", "Không dùng mỹ phẩm 6 tháng qua")
    danh_dau(df[COT_GAN_LOC[3]] != "Có", "Không thấy quảng cáo mỹ phẩm xanh")

    likert = df[COT_LIKERT].apply(pd.to_numeric, errors="coerce")
    danh_dau(likert.isna().any(axis=1), "Thiếu câu trả lời thang đo")
    danh_dau(likert.nunique(axis=1) == 1, "Chọn một mức cho tất cả các câu")
    rang_cua = likert.apply(lambda h: h.notna().all() and la_rang_cua(h.to_numpy()), axis=1)
    danh_dau(rang_cua, "Trả lời zig-zag (bừa)")

    hop_le = df[ly_do == ""].copy()
    loai = df[ly_do != ""].assign(**{"Lý do loại": ly_do[ly_do != ""]})
    return hop_le, loai


def du_lieu_smartpls(hop_le):
    out = hop_le[COT_LIKERT].astype(int).copy()
    out.columns = MA_LIKERT
    # Biến nhân khẩu học mã hóa số (dùng cho thống kê mô tả / phân tích đa nhóm)
    out.insert(0, "GioiTinh", hop_le[COT_NHAN_KHAU[0]].map({"Nam": 1, "Nữ": 2, "Khác": 3}).fillna(3).astype(int))
    out.insert(1, "NamSinh", hop_le[COT_GAN_LOC[1]].values)
    out.insert(0, "ID", range(1, len(out) + 1))
    return out


def kiem_tra(data):
    z = (data[MA_LIKERT] - data[MA_LIKERT].mean()) / data[MA_LIKERT].std()
    diem = {}
    print("\n=== Độ tin cậy & hội tụ (xấp xỉ, loading = tương quan item–tổng biến) ===")
    print(f"{'Biến':6} {'Alpha':>6} {'CR':>6} {'AVE':>6}  loading")
    for bien, cau in THANG_DO.items():
        cot = [f"{bien}{i + 1}" for i in range(len(cau))]
        x = data[cot]
        k = len(cot)
        alpha = k / (k - 1) * (1 - x.var().sum() / x.sum(axis=1).var())
        tong = z[cot].mean(axis=1)
        lam = np.array([np.corrcoef(z[c], tong)[0, 1] for c in cot])
        cr = lam.sum() ** 2 / (lam.sum() ** 2 + (1 - lam**2).sum())
        ave = (lam**2).mean()
        diem[bien] = (tong - tong.mean()) / tong.std()
        print(f"{bien:6} {alpha:6.3f} {cr:6.3f} {ave:6.3f}  " + " ".join(f"{l:.2f}" for l in lam))

    def ols(y, xs):
        X = np.column_stack([diem[x] for x in xs])
        return dict(zip(xs, np.linalg.lstsq(X, diem[y], rcond=None)[0]))

    a = ols("HNQC", ["NTX", "HB", "UT"])
    b = ols("YD", ["NTX", "HB", "UT", "HNQC"])
    print("\n=== Hệ số đường dẫn (OLS trên điểm trung bình, chỉ để kiểm tra dấu) ===")
    gia_thuyet = [
        ("H1", "NTX -> YD", b["NTX"], "-"), ("H2", "HB -> YD", b["HB"], "+"),
        ("H3", "UT -> YD", b["UT"], "+"), ("H4", "NTX -> HNQC", a["NTX"], "+"),
        ("H5", "HB -> HNQC", a["HB"], "+"), ("H6", "UT -> HNQC", a["UT"], "-"),
        ("H7", "HNQC -> YD", b["HNQC"], "-"),
        ("H8", "NTX -> HNQC -> YD", a["NTX"] * b["HNQC"], "gián tiếp"),
        ("H9", "HB -> HNQC -> YD", a["HB"] * b["HNQC"], "gián tiếp"),
        ("H10", "UT -> HNQC -> YD", a["UT"] * b["HNQC"], "gián tiếp"),
    ]
    for h, duong, he_so, ky_vong in gia_thuyet:
        print(f"{h:4} {duong:20} {he_so:+.3f}   (kỳ vọng {ky_vong})")


def main():
    nguon = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT / "MO_PHONG_350_phieu_tho.csv"
    df = pd.read_csv(nguon, dtype=str, keep_default_na=False)
    hop_le, loai = lam_sach(df)

    print(f"Tổng phiếu: {len(df)} | Hợp lệ: {len(hop_le)} | Bị loại: {len(loai)}")
    print(loai["Lý do loại"].value_counts().to_string())

    data = du_lieu_smartpls(hop_le)
    ten = "MO_PHONG_" if nguon.name.startswith("MO_PHONG") else ""
    data.to_csv(OUT / f"{ten}smartpls_hop_le.csv", index=False)
    with pd.ExcelWriter(OUT / f"{ten}du_lieu_da_lam_sach.xlsx") as w:
        data.to_excel(w, sheet_name="SmartPLS", index=False)
        hop_le.to_excel(w, sheet_name="Phieu hop le (goc)", index=False)
        loai.to_excel(w, sheet_name="Phieu bi loai", index=False)
    print(f"\nĐã ghi {OUT}/{ten}smartpls_hop_le.csv và {ten}du_lieu_da_lam_sach.xlsx")

    kiem_tra(data)


if __name__ == "__main__":
    main()
