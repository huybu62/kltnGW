"""
Sinh 350 phiếu khảo sát MÔ PHỎNG (283 hợp lệ + 67 không hợp lệ) cho form
"Ảnh hưởng của nhận thức tẩy xanh đến ý định mua mỹ phẩm của Gen Z tại TP.HCM".

CHỈ DÙNG ĐỂ CHẠY THỬ (test form, tập làm sạch dữ liệu, dựng mô hình trên SmartPLS).
Không được dùng làm dữ liệu khảo sát thật trong khóa luận.

Mô hình (theo giả thuyết H1–H10):
    HNQC = +NTX (H4) + HB (H5) - UT (H6)
    YD   = -NTX (H1) + HB (H2) + UT (H3) - HNQC (H7)
    Gián tiếp qua HNQC: H8, H9, H10

Chạy:  python3 sinh_du_lieu.py
Kết quả nằm trong thư mục output/.
"""

from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 2026
N_VALID = 283
OUT = Path(__file__).parent / "output"

# Form có rẽ nhánh (chọn "Không" ở câu gạn lọc -> kết thúc form)?
# True: phiếu rớt gạn lọc Câu 1/3/4 sẽ bỏ trống phần thang đo.
FORM_CO_RE_NHANH = True

# Năm sinh hợp lệ: Gen Z (1997–2012) và đủ 18 tuổi vào năm 2026.
NAM_SINH_HOP_LE = (1997, 2008)

# Số phiếu không hợp lệ theo từng lỗi (tổng = 67)
LOI = {
    "khong_o_tphcm": 12,       # Câu 1 = Không
    "ngoai_do_tuoi": 10,       # Câu 2 ngoài 1997–2008
    "khong_dung_my_pham": 10,  # Câu 3 = Không
    "khong_thay_quang_cao": 10,  # Câu 4 = Không
    "tra_loi_mot_muc": 15,     # straight-lining: 25 câu cùng một mức
    "tra_loi_rang_cua": 10,    # zig-zag 1-5-1-5... (trả lời bừa)
}

COT_GAN_LOC = [
    "Câu 1. Anh/Chị hiện đang sinh sống, học tập hoặc làm việc tại Thành phố Hồ Chí Minh?",
    "Câu 2. Anh/Chị sinh năm nào?",
    "Câu 3. Trong 6 tháng qua, Anh/Chị có mua hoặc sử dụng mỹ phẩm (chăm sóc da, trang điểm, chăm sóc tóc, chăm sóc cơ thể…) không?",
    "Câu 4. Trong 6 tháng qua, Anh/Chị có nhìn thấy quảng cáo mỹ phẩm xanh trên nền tảng số không?",
]
COT_NHAN_KHAU = [
    "Câu 5. Giới tính của Anh/Chị:",
    "Câu 6. Nghề nghiệp hiện tại của Anh/Chị:",
    "Câu 7. Trình độ học vấn cao nhất của Anh/Chị:",
    "Câu 8. Anh/Chị thường nhìn thấy quảng cáo mỹ phẩm xanh trên những nền tảng nào?",
    "Câu 9. Trong 6 tháng qua, Anh/Chị mua mỹ phẩm khoảng bao nhiêu lần?",
]

# (mã biến, nội dung câu hỏi) — đúng thứ tự Câu 10 → Câu 34 trong form
THANG_DO = {
    "NTX": [
        "Câu 10. Các thương hiệu mỹ phẩm phóng đại những tuyên bố về môi trường của sản phẩm trong quảng cáo xanh.",
        "Câu 11. Các thông điệp về tính bền vững trong quảng cáo mỹ phẩm có vẻ dễ gây hiểu lầm.",
        "Câu 12. Anh/Chị tin rằng các thương hiệu mỹ phẩm này đang tẩy xanh.",
        "Câu 13. Các nhãn thân thiện với môi trường trên mỹ phẩm chỉ mang tính hình thức.",
        "Câu 14. Anh/Chị cho rằng các thương hiệu mỹ phẩm này không thực sự quan tâm đến môi trường.",
    ],
    "HB": [
        "Câu 15. Anh/Chị nhận biết được khi nào người có sức ảnh hưởng nhận tiền để quảng bá sản phẩm.",
        "Câu 16. Anh/Chị có thể phân biệt được nội dung ESG chân thực với nội dung ESG được trả tiền.",
        "Câu 17. Anh/Chị nhận ra được đâu là quảng cáo khi xem nội dung trên các nền tảng số.",
        "Câu 18. Anh/Chị hiểu mục đích thật sự của các quảng cáo trực tuyến về tính bền vững.",
        "Câu 19. Anh/Chị nhận ra các thủ thuật thuyết phục trong nội dung trên nền tảng số.",
    ],
    "UT": [
        "Câu 20. Bên đăng quảng cáo có vẻ am hiểu về các vấn đề môi trường và xã hội.",
        "Câu 21. Anh/Chị tin tưởng bên đăng quảng cáo khi họ truyền tải thông điệp ESG.",
        "Câu 22. Bên đăng quảng cáo có chuyên môn về nội dung mà quảng cáo đề cập.",
        "Câu 23. Anh/Chị tin rằng bên đăng quảng cáo có thiện chí khi quảng bá nội dung xanh.",
        "Câu 24. Bên đăng quảng cáo trung thực.",
    ],
    "HNQC": [
        "Câu 25. Anh/Chị hoài nghi các tuyên bố trong quảng cáo mỹ phẩm xanh.",
        "Câu 26. Anh/Chị thường nghi ngờ các cam kết về môi trường trong quảng cáo mỹ phẩm.",
        "Câu 27. Anh/Chị cho rằng các quảng cáo mỹ phẩm nói về ESG có thể không trung thực.",
        "Câu 28. Phần lớn tuyên bố về môi trường trong quảng cáo mỹ phẩm nhằm đánh lừa người tiêu dùng hơn là cung cấp thông tin.",
        "Câu 29. Anh/Chị không tin phần lớn tuyên bố về môi trường trong quảng cáo mỹ phẩm.",
    ],
    "YD": [
        "Câu 30. Anh/Chị có thể sẽ chọn một thương hiệu mỹ phẩm vì những tuyên bố về môi trường của thương hiệu đó.",
        "Câu 31. Anh/Chị dự định ủng hộ các thương hiệu mỹ phẩm có thông điệp ESG chân thực.",
        "Câu 32. Anh/Chị sẵn sàng mua mỹ phẩm của thương hiệu sau khi xem quảng cáo xanh của thương hiệu đó.",
        "Câu 33. Anh/Chị sẽ cân nhắc mua mỹ phẩm xanh vì chúng ít gây ô nhiễm hơn.",
        "Câu 34. Anh/Chị chắc chắn muốn mua mỹ phẩm xanh trong thời gian tới.",
    ],
}
COT_LIKERT = [c for cau in THANG_DO.values() for c in cau]
MA_LIKERT = [f"{bien}{i + 1}" for bien, cau in THANG_DO.items() for i in range(len(cau))]

# Lựa chọn Câu 5–9. Phải trùng CHÍNH XÁC chữ trong form nếu muốn gửi vào form
# -> mở form, sửa lại các chuỗi dưới đây cho khớp.
GIOI_TINH = (["Nữ", "Nam", "Khác"], [0.68, 0.29, 0.03])
NGHE_NGHIEP = (
    ["Học sinh, sinh viên", "Nhân viên văn phòng", "Kinh doanh tự do", "Khác"],
    [0.58, 0.25, 0.10, 0.07],
)
HOC_VAN = (["Trung học phổ thông", "Cao đẳng", "Đại học", "Sau đại học"], [0.12, 0.13, 0.69, 0.06])
NEN_TANG = (
    ["Facebook", "TikTok", "Instagram", "YouTube", "Sàn TMĐT (Shopee/Lazada/Tiki)", "Khác"],
    [0.70, 0.82, 0.45, 0.48, 0.60, 0.05],
)
SO_LAN_MUA = (["1–2 lần", "3–5 lần", "Trên 5 lần"], [0.35, 0.42, 0.23])

# Hệ số đường dẫn chuẩn hóa (dấu theo giả thuyết, độ lớn vừa phải)
B_HNQC = {"NTX": 0.38, "HB": 0.24, "UT": -0.30}
B_YD = {"NTX": -0.18, "HB": 0.17, "UT": 0.26, "HNQC": -0.34}
TUONG_QUAN_DOC_LAP = np.array([  # NTX, HB, UT
    [1.00, 0.25, -0.20],
    [0.25, 1.00, 0.10],
    [-0.20, 0.10, 1.00],
])
# Trung bình mong muốn (thang 1–5) của từng biến để dữ liệu không quá "đẹp"
TRUNG_BINH = {"NTX": 3.6, "HB": 3.5, "UT": 3.1, "HNQC": 3.5, "YD": 3.4}

rng = np.random.default_rng(SEED)


def bien_tiem_an(n):
    """Sinh điểm tiềm ẩn chuẩn hóa cho 5 biến theo mô hình cấu trúc."""
    x = rng.multivariate_normal(np.zeros(3), TUONG_QUAN_DOC_LAP, size=n)
    lv = {"NTX": x[:, 0], "HB": x[:, 1], "UT": x[:, 2]}
    hnqc = sum(b * lv[k] for k, b in B_HNQC.items())
    lv["HNQC"] = (hnqc + rng.normal(0, np.sqrt(max(1 - hnqc.var(), 0.3)), n))
    lv["HNQC"] = (lv["HNQC"] - lv["HNQC"].mean()) / lv["HNQC"].std()
    yd = sum(b * lv[k] for k, b in B_YD.items())
    lv["YD"] = yd + rng.normal(0, np.sqrt(max(1 - yd.var(), 0.3)), n)
    lv["YD"] = (lv["YD"] - lv["YD"].mean()) / lv["YD"].std()
    return lv


def sang_likert(z, trung_binh):
    """Đổi điểm liên tục -> thang 1..5, dịch tâm để có trung bình mong muốn."""
    diem = np.rint(trung_binh + 0.95 * z)
    return np.clip(diem, 1, 5).astype(int)


def sinh_likert_hop_le(n):
    lv = bien_tiem_an(n)
    cot = {}
    for bien, cau in THANG_DO.items():
        for i in range(len(cau)):
            loading = rng.uniform(0.74, 0.88)
            z = loading * lv[bien] + np.sqrt(1 - loading**2) * rng.normal(size=n)
            cot[f"{bien}{i + 1}"] = sang_likert(z, TRUNG_BINH[bien] + rng.uniform(-0.15, 0.15))
    return pd.DataFrame(cot)


def chon(lua_chon):
    ten, p = lua_chon
    return rng.choice(ten, p=np.array(p) / sum(p))


def chon_nhieu(lua_chon):
    ten, p = lua_chon
    da_chon = [t for t, pi in zip(ten, p) if rng.random() < pi]
    return ", ".join(da_chon or [ten[1]])


def nhan_khau():
    return {
        COT_NHAN_KHAU[0]: chon(GIOI_TINH),
        COT_NHAN_KHAU[1]: chon(NGHE_NGHIEP),
        COT_NHAN_KHAU[2]: chon(HOC_VAN),
        COT_NHAN_KHAU[3]: chon_nhieu(NEN_TANG),
        COT_NHAN_KHAU[4]: chon(SO_LAN_MUA),
    }


def gan_loc_dat():
    return {
        COT_GAN_LOC[0]: "Có",
        COT_GAN_LOC[1]: int(rng.integers(NAM_SINH_HOP_LE[0], NAM_SINH_HOP_LE[1] + 1)),
        COT_GAN_LOC[2]: "Có",
        COT_GAN_LOC[3]: "Có",
    }


def la_rang_cua(v):
    return np.mean(np.abs(np.diff(v)) >= 3) >= 0.8


def tao_phieu():
    phieu = []

    # 1) Phiếu hợp lệ
    likert = sinh_likert_hop_le(N_VALID)
    for _, hang in likert.iterrows():
        v = hang.to_numpy()
        assert len(set(v)) > 1 and not la_rang_cua(v)  # không trùng quy tắc loại
        p = {**gan_loc_dat(), **nhan_khau(), **dict(zip(COT_LIKERT, v)), "_loai": "hop_le"}
        phieu.append(p)

    # 2) Phiếu không hợp lệ
    likert_nhieu = sinh_likert_hop_le(sum(LOI.values()))  # nền cho các phiếu vẫn trả lời thang đo
    k = 0
    for loi, so in LOI.items():
        for _ in range(so):
            p = {**gan_loc_dat(), **nhan_khau(), "_loai": loi}
            tra_loi_thang_do = True
            if loi == "khong_o_tphcm":
                p[COT_GAN_LOC[0]] = "Không"
                tra_loi_thang_do = not FORM_CO_RE_NHANH
            elif loi == "ngoai_do_tuoi":
                p[COT_GAN_LOC[1]] = int(rng.choice([*range(1988, 1997), 2009, 2010]))
            elif loi == "khong_dung_my_pham":
                p[COT_GAN_LOC[2]] = "Không"
                tra_loi_thang_do = not FORM_CO_RE_NHANH
            elif loi == "khong_thay_quang_cao":
                p[COT_GAN_LOC[3]] = "Không"
                tra_loi_thang_do = not FORM_CO_RE_NHANH

            if not tra_loi_thang_do:
                for c in COT_NHAN_KHAU:
                    p[c] = ""
                v = [""] * len(COT_LIKERT)
            elif loi == "tra_loi_mot_muc":
                v = [int(rng.choice([3, 4, 5, 1], p=[0.4, 0.3, 0.2, 0.1]))] * len(COT_LIKERT)
            elif loi == "tra_loi_rang_cua":
                bat_dau = int(rng.choice([1, 5]))
                v = [bat_dau if i % 2 == 0 else 6 - bat_dau for i in range(len(COT_LIKERT))]
            else:
                v = likert_nhieu.iloc[k].tolist()
            k += 1
            p.update(dict(zip(COT_LIKERT, v)))
            phieu.append(p)

    df = pd.DataFrame(phieu).sample(frac=1, random_state=SEED).reset_index(drop=True)

    # Dấu thời gian rải trong ~3 tuần, giờ hoạt động 7h–23h, tăng dần
    bat_dau = datetime(2026, 11, 2, 7, 0, 0)
    tg = sorted(
        bat_dau + timedelta(days=int(rng.integers(0, 21)), hours=float(rng.uniform(0, 16)))
        for _ in range(len(df))
    )
    df.insert(0, "Dấu thời gian", [t.strftime("%d/%m/%Y %H:%M:%S") for t in tg])
    return df


def main():
    OUT.mkdir(exist_ok=True)
    df = tao_phieu()
    cot_form = ["Dấu thời gian", *COT_GAN_LOC, *COT_NHAN_KHAU, *COT_LIKERT]

    # (a) Giống hệt sheet "Câu trả lời biểu mẫu" của Google Form — 350 phiếu thô
    df[cot_form].to_csv(OUT / "MO_PHONG_350_phieu_tho.csv", index=False, encoding="utf-8-sig")
    # (b) Đáp án đúng: phiếu nào hợp lệ / lỗi gì (để đối chiếu sau khi tự làm sạch)
    df[["Dấu thời gian", "_loai"]].to_csv(OUT / "MO_PHONG_dap_an_loai_phieu.csv", index=False, encoding="utf-8-sig")
    print(f"Đã ghi {len(df)} phiếu vào {OUT}/MO_PHONG_350_phieu_tho.csv")
    print(df["_loai"].value_counts().to_string())


if __name__ == "__main__":
    main()
