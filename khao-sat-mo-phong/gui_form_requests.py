"""
Tự sinh câu trả lời ngẫu nhiên và gửi POST (requests) vào Google Form để mô phỏng
350 lượt khảo sát: 283 hợp lệ + 67 không hợp lệ (cùng tỉ lệ lỗi như sinh_du_lieu.py).

⚠️ CHỈ gửi vào BẢN SAO của form dùng để chạy thử. Gửi vào form đang thu thật thì
phiếu giả sẽ lẫn với phiếu thật và không tách ra được. Xóa sau khi thử xong:
Form > tab "Câu trả lời" > ⋮ > "Xóa tất cả câu trả lời" (và xóa dòng trong Sheet liên kết).

Script tự tải form để đọc: mã entry, đúng chữ từng đáp án, số phần (section) và
rẽ nhánh của câu gạn lọc — nên không phải sửa tay đáp án.

    pip install requests numpy pandas
    python3 gui_form_requests.py                 # chạy thử: in cấu trúc form + 3 phiếu mẫu, KHÔNG gửi
    python3 gui_form_requests.py --gui 5         # gửi 5 phiếu đầu để kiểm tra
    python3 gui_form_requests.py --gui 350       # gửi toàn bộ
    python3 gui_form_requests.py --gui 350 --nghi 2 6   # nghỉ ngẫu nhiên 2–6 giây giữa 2 phiếu

Dùng form khác (bản sao) mà không cần sửa file — đặt link trong dấu nháy đơn:
    python3 gui_form_requests.py --link 'https://docs.google.com/forms/d/e/.../viewform?usp=pp_url&entry...'
    python3 gui_form_requests.py --link '...' --gui 5
"""

import argparse
import csv
import json
import random
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import requests

from sinh_du_lieu import LOI, N_VALID, la_rang_cua, nam_sinh_hop_le, sinh_likert_hop_le

# Link điền sẵn của form (Câu 1 → Câu 34 theo đúng thứ tự entry)
PREFILL_LINK = (
    "https://docs.google.com/forms/d/e/1FAIpQLSf-etGZaDOMuNq8hMkPu-D2N7lTX3V43u_zZEDKxGIq1zvcnA/viewform?usp=pp_url"
    "&entry.1349997699=C%C3%B3&entry.2037419943=T%E1%BB%AB+n%C4%83m+2001+%C4%91%E1%BA%BFn+n%C4%83m+2004"
    "&entry.1897723091=C%C3%B3&entry.1163600371=C%C3%B3&entry.550670191=Kh%C3%A1c"
    "&entry.504583911=H%E1%BB%8Dc+sinh/Sinh+vi%C3%AAn&entry.995946019=Sau+%C4%91%E1%BA%A1i+h%E1%BB%8Dc"
    "&entry.595423339=Lazada&entry.1303881491=T%E1%BB%AB+1+%C4%91%E1%BA%BFn+2+l%E1%BA%A7n"
    "&entry.884318984=5&entry.1448181749=5&entry.1079663703=5&entry.449508234=5&entry.1558926144=5"
    "&entry.1052571930=5&entry.740106121=5&entry.1802385745=5&entry.651777125=5&entry.1506506060=5"
    "&entry.2104295249=5&entry.2045912982=5&entry.1762439896=5&entry.1743596511=5&entry.526718206=5"
    "&entry.322404482=5&entry.1377517284=5&entry.565876754=5&entry.1731892884=5&entry.49214851=5"
    "&entry.974109067=5&entry.1485922235=5&entry.1505162474=5&entry.1323511615=5&entry.1605707174=5"
)


def dat_link(link):
    """Đọc mã form và các entry từ link điền sẵn."""
    global FORM_ID, ENTRIES, VIEW_URL, POST_URL
    m = re.search(r"/forms/d/e/([\w-]+)/", link)
    if not m:
        sys.exit("Link không đúng dạng link điền sẵn (phải có /forms/d/e/.../viewform?...entry.).")
    FORM_ID = m.group(1)
    ENTRIES = list(dict.fromkeys(re.findall(r"entry\.(\d+)", link)))
    VIEW_URL = f"https://docs.google.com/forms/d/e/{FORM_ID}/viewform"
    POST_URL = f"https://docs.google.com/forms/d/e/{FORM_ID}/formResponse"


dat_link(PREFILL_LINK)
LOG = Path(__file__).parent / "output" / "MO_PHONG_nhat_ky_gui_form.csv"

# Vị trí câu trong ENTRIES (0 = Câu 1)
GAN_LOC_TPHCM, NAM_SINH, MY_PHAM, QUANG_CAO = 0, 1, 2, 3
GIOI_TINH, NGHE, HOC_VAN, NEN_TANG, SO_LAN = 4, 5, 6, 7, 8
LIKERT = list(range(9, 34))

# Trọng số chọn đáp án theo từ khóa (đáp án không khớp từ khóa nào có trọng số 1)
TRONG_SO = {
    GIOI_TINH: {"nữ": 6.5, "nam": 3.0, "khác": 0.4},
    NGHE: {"sinh viên": 6.0, "văn phòng": 2.5, "kinh doanh": 1.0, "tự do": 1.0, "khác": 0.5},
    HOC_VAN: {"đại học": 6.5, "cao đẳng": 1.3, "thpt": 1.2, "phổ thông": 1.2, "sau đại học": 0.6},
    SO_LAN: {"1 đến 2": 3.5, "3 đến 5": 4.2, "trên 5": 2.3},
}
XAC_SUAT_NEN_TANG = {"tiktok": 0.82, "facebook": 0.70, "shopee": 0.62, "youtube": 0.48,
                     "instagram": 0.45, "lazada": 0.35, "tiki": 0.15}

DI_TIEP, NOP = -2, -3  # mã điều hướng của Google Forms


# ---------------------------------------------------------------- đọc cấu trúc form
def doc_form(session):
    html = session.get(VIEW_URL, timeout=30).text
    m = re.search(r"FB_PUBLIC_LOAD_DATA_\s*=\s*(.*?);\s*</script>", html, re.S)
    if not m:
        sys.exit("Không đọc được form (form yêu cầu đăng nhập, đã đóng, hoặc link sai).")
    data = json.loads(m.group(1))
    fbzx = re.search(r'name="fbzx" value="([^"]+)"', html)
    return phan_tich(data), (fbzx.group(1) if fbzx else None)


def phan_tich(data):
    """Trả về {entry_id: câu hỏi} và danh sách id các phần (section) theo thứ tự."""
    cau_hoi, cac_phan, trang = {}, [None], 0
    for item in data[1][1]:
        loai = item[3]
        if loai == 8:  # ngắt trang = bắt đầu phần mới
            trang += 1
            cac_phan.append(item[0])
            continue
        if not item[4]:
            continue
        for o in item[4]:
            lua_chon = [
                {"chu": x[0], "di_toi": x[2] if len(x) > 2 else None, "khac": len(x) > 4 and bool(x[4])}
                for x in (o[1] or [])
            ]
            cau_hoi[str(o[0])] = {"tieu_de": item[1], "loai": loai, "trang": trang, "lua_chon": lua_chon,
                                   "bat_buoc": bool(o[2]) if len(o) > 2 else False}
    return cau_hoi, cac_phan


# ---------------------------------------------------------------- sinh câu trả lời
def tim(lua_chon, bat_dau):
    for x in lua_chon:
        if x["chu"].strip().casefold().startswith(bat_dau):
            return x["chu"]
    sys.exit(f"Không tìm thấy đáp án bắt đầu bằng '{bat_dau}' trong {[x['chu'] for x in lua_chon]}")


def chon_theo_trong_so(lua_chon, bang):
    ten = [x["chu"] for x in lua_chon if not x["khac"]]
    w = []
    for t in ten:
        # "sau đại học" chứa cả "đại học": lấy từ khóa khớp dài nhất
        khop = [k for k in bang if k in t.casefold()]
        w.append(bang[max(khop, key=len)] if khop else 1.0)
    return random.choices(ten, weights=w)[0]


def chon_nen_tang(lua_chon):
    ten = [x["chu"] for x in lua_chon if not x["khac"]]
    da_chon = [t for t in ten
               if random.random() < next((p for k, p in XAC_SUAT_NEN_TANG.items() if k in t.casefold()), 0.1)]
    return da_chon or [random.choice(ten)]


def tao_danh_sach_phieu(cau_hoi):
    q = [cau_hoi[e] for e in ENTRIES]
    co = {i: tim(q[i]["lua_chon"], "có") for i in (GAN_LOC_TPHCM, MY_PHAM, QUANG_CAO)}
    khong = {i: tim(q[i]["lua_chon"], "không") for i in (GAN_LOC_TPHCM, MY_PHAM, QUANG_CAO)}
    nam = [x["chu"] for x in q[NAM_SINH]["lua_chon"] if not x["khac"]]
    nam_dat = [x for x in nam if nam_sinh_hop_le(x)]
    nam_rot = [x for x in nam if not nam_sinh_hop_le(x)]
    if not nam_dat:
        sys.exit(f"Không có đáp án năm sinh nào thuộc Gen Z 18+: {nam}")

    loi = dict(LOI)
    if not nam_rot:  # form không có lựa chọn ngoài độ tuổi -> dồn sang lỗi gạn lọc TP.HCM
        print("! Câu 2 không có lựa chọn ngoài độ tuổi; chuyển các phiếu đó sang 'khong_o_tphcm'.")
        loi["khong_o_tphcm"] += loi.pop("ngoai_do_tuoi")

    likert = sinh_likert_hop_le(N_VALID + sum(loi.values())).to_numpy()
    phieu, k = [], 0

    def co_ban():
        return {GAN_LOC_TPHCM: co[0], NAM_SINH: random.choice(nam_dat), MY_PHAM: co[2], QUANG_CAO: co[3],
                GIOI_TINH: chon_theo_trong_so(q[GIOI_TINH]["lua_chon"], TRONG_SO[GIOI_TINH]),
                NGHE: chon_theo_trong_so(q[NGHE]["lua_chon"], TRONG_SO[NGHE]),
                HOC_VAN: chon_theo_trong_so(q[HOC_VAN]["lua_chon"], TRONG_SO[HOC_VAN]),
                NEN_TANG: chon_nen_tang(q[NEN_TANG]["lua_chon"]),
                SO_LAN: chon_theo_trong_so(q[SO_LAN]["lua_chon"], TRONG_SO[SO_LAN])}

    for _ in range(N_VALID):
        v = likert[k]; k += 1
        assert len(set(v)) > 1 and not la_rang_cua(v)
        phieu.append(("hop_le", {**co_ban(), **{i: str(x) for i, x in zip(LIKERT, v)}}))

    for ten_loi, so in loi.items():
        for _ in range(so):
            p = {**co_ban(), **{i: str(x) for i, x in zip(LIKERT, likert[k])}}; k += 1
            if ten_loi == "khong_o_tphcm":
                p[GAN_LOC_TPHCM] = khong[0]
            elif ten_loi == "ngoai_do_tuoi":
                p[NAM_SINH] = random.choice(nam_rot)
            elif ten_loi == "khong_dung_my_pham":
                p[MY_PHAM] = khong[2]
            elif ten_loi == "khong_thay_quang_cao":
                p[QUANG_CAO] = khong[3]
            elif ten_loi == "tra_loi_mot_muc":
                muc = str(random.choices([3, 4, 5, 1], weights=[4, 3, 2, 1])[0])
                p.update({i: muc for i in LIKERT})
            elif ten_loi == "tra_loi_rang_cua":
                a = random.choice(["1", "5"]); b = "5" if a == "1" else "1"
                p.update({i: (a if j % 2 == 0 else b) for j, i in enumerate(LIKERT)})
            phieu.append((ten_loi, p))

    random.shuffle(phieu)
    return phieu


# ---------------------------------------------------------------- mô phỏng điều hướng & gửi
def tao_payload(tra_loi, cau_hoi, cac_phan, fbzx):
    """Đi qua form như người thật: theo rẽ nhánh, chỉ gửi câu ở các trang đã đi qua."""
    theo_trang = {}
    for i, e in enumerate(ENTRIES):
        theo_trang.setdefault(cau_hoi[e]["trang"], []).append(i)
    so_trang = len(cac_phan)

    trang, da_qua, payload = 0, [], []
    while trang is not None and trang < so_trang:
        da_qua.append(trang)
        tiep = trang + 1
        for i in theo_trang.get(trang, []):
            e, gia_tri = ENTRIES[i], tra_loi[i]
            for g in (gia_tri if isinstance(gia_tri, list) else [gia_tri]):
                payload.append((f"entry.{e}", g))
            lc = next((x for x in cau_hoi[e]["lua_chon"] if x["chu"] == gia_tri), None)
            if lc and lc["di_toi"] not in (None, 0, DI_TIEP):
                tiep = None if lc["di_toi"] == NOP else cac_phan.index(lc["di_toi"]) \
                    if lc["di_toi"] in cac_phan else tiep
        trang = tiep

    payload += [("fvv", "1"), ("pageHistory", ",".join(map(str, da_qua)))]
    if fbzx:
        payload += [("fbzx", fbzx), ("partialResponse", json.dumps([None, None, fbzx]))]
    return payload, da_qua


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gui", type=int, default=0, help="số phiếu gửi thật (mặc định 0 = chạy thử)")
    ap.add_argument("--nghi", type=float, nargs=2, default=[3, 9], metavar=("MIN", "MAX"))
    ap.add_argument("--seed", type=int, default=2026)
    ap.add_argument("--link", help="link điền sẵn của form (đặt trong dấu nháy đơn '...')")
    args = ap.parse_args()
    if args.link:
        dat_link(args.link)
    print(f"Form: {FORM_ID}")
    random.seed(args.seed)

    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130 Safari/537.36"
    (cau_hoi, cac_phan), fbzx = doc_form(s)

    thieu = [e for e in ENTRIES if e not in cau_hoi]
    if len(ENTRIES) != 34 or thieu:
        sys.exit(f"Link điền sẵn có {len(ENTRIES)}/34 câu hoặc không khớp form (entry lạ: {thieu}). Điền đủ cả 34 câu rồi lấy lại link.")

    print(f"Form có {len(cau_hoi)} câu, {len(cac_phan)} phần.")
    for i in [GAN_LOC_TPHCM, NAM_SINH, MY_PHAM, QUANG_CAO, GIOI_TINH, NGHE, HOC_VAN, NEN_TANG, SO_LAN]:
        q = cau_hoi[ENTRIES[i]]
        dap_an = ", ".join(x["chu"] + (f" [→{x['di_toi']}]" if x["di_toi"] not in (None, 0, DI_TIEP) else "")
                           for x in q["lua_chon"])
        print(f"  Câu {i + 1} (trang {q['trang']}): {dap_an}")

    phieu = tao_danh_sach_phieu(cau_hoi)
    dem = {}
    for loai, _ in phieu:
        dem[loai] = dem.get(loai, 0) + 1
    print(f"\nĐã sinh {len(phieu)} phiếu: {dem}")

    if args.gui <= 0:
        for loai, tl in phieu[:3]:
            payload, da_qua = tao_payload(tl, cau_hoi, cac_phan, fbzx)
            print(f"\n[{loai}] trang đã qua {da_qua}, {len(payload)} trường:")
            print("  " + "&".join(f"{k}={v}" for k, v in payload[:12]) + " ...")
        print("\nChạy thử xong, chưa gửi gì. Thêm --gui N để gửi N phiếu (nhớ dùng BẢN SAO của form).")
        return

    LOG.parent.mkdir(exist_ok=True)
    moi = not LOG.exists()
    with LOG.open("a", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        if moi:
            w.writerow(["thoi_gian_gui", "stt", "loai_phieu", "http"])
        thanh_cong = 0
        for stt, (loai, tl) in enumerate(phieu[: args.gui], 1):
            payload, _ = tao_payload(tl, cau_hoi, cac_phan, fbzx)
            for lan in range(4):
                try:
                    r = s.post(POST_URL, data=payload, timeout=30)
                    break
                except requests.RequestException as ex:
                    print(f"  lỗi mạng ({ex}), thử lại sau {2 ** (lan + 1)}s")
                    time.sleep(2 ** (lan + 1))
            else:
                sys.exit("Mất kết nối, dừng lại.")
            ok = r.status_code == 200
            thanh_cong += ok
            w.writerow([datetime.now().isoformat(timespec="seconds"), stt, loai, r.status_code])
            f.flush()
            print(f"{stt:3}/{args.gui} [{loai:20}] HTTP {r.status_code}{'' if ok else '  <-- bị từ chối'}")
            if not ok and stt <= 3:
                sys.exit("Form từ chối phiếu. Kiểm tra: form có bắt đăng nhập/thu email không, "
                         "hoặc có câu bắt buộc ngoài 34 câu trong link điền sẵn.")
            time.sleep(random.uniform(*args.nghi))
    print(f"\nXong: {thanh_cong}/{args.gui} phiếu được ghi nhận. Nhật ký: {LOG}")


if __name__ == "__main__":
    main()
