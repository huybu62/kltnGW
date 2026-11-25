"""Chế độ VÒNG QUAY LIÊN SERVER: bấm "Khởi động 10 lần" liên tục, đếm số lần bấm (bảo hiểm 73).

Luật (theo người chơi):
- Mỗi lần bấm x10 tính 1. Trúng món HẠN ĐỊNH (hiện giữa màn hình) thì bộ đếm về 0; trúng món thường thì không.
- Trước lần bấm thứ 73: bấm "Tạo mới" (1 Xu) tới khi vòng quay có TƯỚNG hạn định, rồi bấm x10 → về 0.

Nhận biết:
- Vị trí vòng quay suy ra từ nút "Khởi động 1 lần" (mẫu vq_x1); 8 ô và nút x10 ở vị trí cố định so với nút đó.
- Ô hạn định: góc trên-phải ô có nhãn vàng "Hạn định" (so nét chữ với mẫu vq_tag_*).
- Rương hay tướng: ô hạn định giống hình rương (mẫu vq_ruong_*) là rương, còn lại là tướng.
- Trúng hạn định: sau khi bấm, giữa màn hình hiện hình trùng với một ô hạn định (so nhiều cỡ).
- Lần bấm có ăn không: số "Xu còn" (đọc chữ) giảm.
Không bao giờ bấm Nạp thẻ / mua; chỉ bấm Khởi động 10 lần và Tạo mới.
"""
import os
import re
import time

import cv2
import numpy as np

from bot import Bot, StopBot
from matcher import _doc_anh
from ocr import co_ocr, doc, gon

# Toạ độ trên ảnh gốc rộng 2000 (màn vòng quay); gốc là góc trên-trái mẫu nút "Khởi động 1 lần"
_GOC_X1 = (684, 1028)
_NUT_X10 = (1163, 1070)
_NUT_TAO_MOI = (996, 690)
_O = {  # góc trên-trái 8 ô (ô rộng ~110)
    "tren_trai": (876, 468), "tren_phai": (1022, 468), "trai_tren": (762, 585), "phai_tren": (1135, 585),
    "trai_duoi": (762, 725), "phai_duoi": (1135, 725), "duoi_trai": (876, 842), "duoi_phai": (1022, 842),
}
_CO_O = (110, 114)
_XU_CON = (420, 965, 690, 1045)  # vùng con số "Xu còn"
_GIUA = (560, 300, 1440, 1000)  # vùng giữa màn hình nơi món trúng hiện ra


def _canh(img):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
    return cv2.GaussianBlur(cv2.Canny(g, 60, 160).astype(np.float32), (3, 3), 0)


class VongQuayBot(Bot):
    @property
    def vq(self):
        return self.cfg.setdefault("vong_quay", {})

    # ---------- toạ độ ----------
    def neo(self, s):
        """Tìm nút "Khởi động 1 lần" → (x0, y0, k) để đổi toạ độ ảnh gốc ra màn hình; None nếu không ở màn vòng quay."""
        m = self.find(s, "vq_x1")
        if not m:
            return None
        return m.left, m.top, m.scale

    def ra(self, neo, X, Y):
        x0, y0, k = neo
        return x0 + (X - _GOC_X1[0]) * k, y0 + (Y - _GOC_X1[1]) * k

    def cat(self, s, neo, X0, Y0, X1, Y1):
        a, b = self.ra(neo, X0, Y0)
        c, d = self.ra(neo, X1, Y1)
        return s[max(0, int(b)):int(d), max(0, int(a)):int(c)]

    # ---------- đọc màn ----------
    def mau_canh(self, ten_tien_to):
        """Các mẫu (ảnh cạnh) có tên bắt đầu bằng ten_tien_to, đã co theo màn hình hiện tại."""
        ds = []
        for f in sorted(os.listdir(self.templates.folder)):
            if f.startswith(ten_tien_to) and f.endswith(".png"):
                img = _doc_anh(os.path.join(self.templates.folder, f))
                if img is not None:
                    ds.append(img)
        return ds

    def o_han_dinh(self, s, neo):
        """{tên ô: (ảnh ô, là_rương)} cho các ô đang có nhãn "Hạn định"."""
        k = neo[2]
        tags = self.mau_canh("vq_tag")  # cắt ở cỡ gốc (rộng 2000): phóng vùng ô lên cỡ gốc rồi so
        ruong = self.mau_canh("vq_ruong")
        kq = {}
        for ten, (X, Y) in _O.items():
            vung = self.cat(s, neo, X + 36, Y - 6, X + 116, Y + 34)
            if vung.size == 0:
                continue
            vung = cv2.resize(vung, None, fx=1 / k, fy=1 / k, interpolation=cv2.INTER_CUBIC)
            diem = 0.0
            for t in tags:
                if vung.shape[0] >= t.shape[0] and vung.shape[1] >= t.shape[1]:
                    diem = max(diem, cv2.minMaxLoc(cv2.matchTemplate(_canh(vung), _canh(t), cv2.TM_CCOEFF_NORMED))[1])
            # nhãn "Hạn định" = nét chữ giống mẫu VÀ có chữ vàng ở góc trên-phải ô
            hsv = cv2.cvtColor(self.cat(s, neo, X + 50, Y + 4, X + 104, Y + 24), cv2.COLOR_BGR2HSV)
            vang = float(((hsv[..., 0] >= 15) & (hsv[..., 0] <= 35) & (hsv[..., 1] > 90) & (hsv[..., 2] > 170)).mean())
            if not ((diem >= 0.33 and vang >= 0.08) or diem >= 0.45):
                continue
            o = self.cat(s, neo, X, Y, X + _CO_O[0], Y + _CO_O[1])
            la_ruong = False
            for r in ruong:  # mẫu rương là ô trên vòng quay (cỡ gốc): so phần thân ô, ảnh xám
                o2 = cv2.resize(o, (r.shape[1], r.shape[0]))
                h, w = r.shape[:2]
                th = (slice(h * 18 // 100, h * 82 // 100), slice(w * 14 // 100, w * 86 // 100))
                d = cv2.matchTemplate(cv2.cvtColor(o2[th], cv2.COLOR_BGR2GRAY), cv2.cvtColor(r[th], cv2.COLOR_BGR2GRAY),
                                      cv2.TM_CCOEFF_NORMED)[0][0]
                if d >= 0.45:
                    la_ruong = True
            kq[ten] = (o, la_ruong)
        return kq

    def doc_xu(self, s, neo):
        if not co_ocr():
            return None
        anh = self.cat(s, neo, *_XU_CON)
        if anh.size == 0:
            return None
        anh = cv2.resize(anh, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        for c in doc(anh, rong_toi_da=3000):
            # chữ số hay bị đọc thành chữ cái: O/o → 0, l/I/| → 1
            t = c.text.translate(str.maketrans({"O": "0", "o": "0", "D": "0", "l": "1", "I": "1", "|": "1"}))
            so = re.sub(r"\D", "", t)
            if len(so) >= 2:
                return int(so)
        return None

    def trung_han_dinh(self, s, neo, ds_o):
        """Giữa màn hình có hình trùng một ô hạn định (so nhiều cỡ)? Trả về tên ô hoặc None."""
        giua = self.cat(s, neo, *_GIUA)
        if giua.size == 0:
            return None
        gx0, gy0 = self.ra(neo, _GIUA[0], _GIUA[1])
        # 8 ô của chính vòng quay (kể cả khi bị làm tối sau popup) không phải món vừa trúng → bỏ qua
        hop_o = []
        for X, Y in _O.values():
            a, b = self.ra(neo, X, Y)
            c, d = self.ra(neo, X + _CO_O[0], Y + _CO_O[1])
            hop_o.append((a - gx0, b - gy0, c - gx0, d - gy0))
        cg = cv2.cvtColor(giua, cv2.COLOR_BGR2GRAY)
        nguong = self.vq.get("nguong_trung", 0.75)
        for ten, (o, la_ruong) in ds_o.items():
            than = o[o.shape[0] // 5:o.shape[0] * 4 // 5, o.shape[1] // 6:o.shape[1] * 5 // 6]  # bỏ viền + nhãn + "x1"
            for co in np.arange(0.8, 3.25, 0.1):  # món trúng hiện to hơn ô: thử nhiều cỡ
                t = cv2.resize(than, None, fx=co, fy=co)
                th, tw = t.shape[:2]
                if th >= cg.shape[0] or tw >= cg.shape[1]:
                    break
                res = cv2.matchTemplate(cg, cv2.cvtColor(t, cv2.COLOR_BGR2GRAY), cv2.TM_CCOEFF_NORMED)
                for a, b, c, d in hop_o:  # xoá các vị trí mà tâm khớp rơi vào một ô của vòng quay
                    ya, yb = int(max(0, b - th / 2)), int(max(0, d - th / 2))
                    xa, xb = int(max(0, a - tw / 2)), int(max(0, c - tw / 2))
                    res[ya:yb, xa:xb] = -1
                if cv2.minMaxLoc(res)[1] > nguong:
                    return ten
        return None

    # ---------- vòng lặp ----------
    def kiem_tra_mau(self):
        thieu = [n for n in ("vq_x1",) if not self.templates.exists(n)]
        if thieu or not self.mau_canh("vq_tag"):
            self.log("Thiếu mẫu vòng quay (vq_x1, vq_tag_*)")
            raise StopBot
        if not co_ocr():
            self.log("⚠ Chưa có bộ đọc chữ: không đọc được Xu nên không kiểm tra được lần bấm có ăn không")

    def luu(self):
        self.emit(("luu_cfg",))
        self.emit(("stats", self.device.serial, {"vq": f"{self.vq.get('dem', 0)}/{self.vq.get('moc', 73)}",
                                                 "bam": self.stats["vq_bam"]}))

    def cho_man_vong_quay(self, han=60):
        """Chờ quay về màn vòng quay (món trúng / hiệu ứng tự tắt); quá lâu thì chạm mép trên."""
        bd = time.time()
        lan_cham = 0
        while time.time() - bd < han:
            s = self.shot()
            neo = self.neo(s)
            if neo:
                return s, neo
            if time.time() - bd > 8 * (lan_cham + 1):
                gx, gy, gw, gh = self.templates.vung(s)
                self.tap(gx + 0.5 * gw, gy + 0.03 * gh)  # "chạm để tiếp tục" nếu có
                lan_cham += 1
            self.sleep(0.5)
        self.luu_anh_loi(self.shot(), "không thấy màn vòng quay")
        self.log("⛔ Không thấy màn Vòng quay (nút 'Khởi động 1 lần') → dừng")
        raise StopBot

    def tao_moi_toi_khi_co_tuong(self, s, neo):
        """Bấm "Tạo mới" tới khi vòng quay có TƯỚNG hạn định (tối đa tao_moi_toi_da lần)."""
        for lan in range(int(self.vq.get("tao_moi_toi_da", 60)) + 1):
            o = self.o_han_dinh(s, neo)
            tuong = [t for t, (_, la_ruong) in o.items() if not la_ruong]
            if tuong:
                self.log(f"  Vòng quay có tướng hạn định ({', '.join(tuong)}) sau {lan} lần Tạo mới")
                return s, neo
            self.tap(*self.ra(neo, *_NUT_TAO_MOI))
            self.stats["vq_tao_moi"] += 1
            self.sleep(self.vq.get("cho_tao_moi", 1.2))
            s, neo = self.cho_man_vong_quay()
        self.log("  ⚠ Tạo mới nhiều lần vẫn chưa ra tướng hạn định → quay luôn")
        return s, neo

    def loop(self):
        vq = self.vq
        moc = int(vq.get("moc", 73))
        bam_lan_nay = 0
        self.log(f"🎡 Vòng quay: đã bấm x10 {vq.get('dem', 0)}/{moc} (từ lần hạn định gần nhất)")
        while not self.stop_event.is_set():
            s, neo = self.cho_man_vong_quay()
            xu = self.doc_xu(s, neo)
            if xu is not None and vq.get("xu_toi_thieu", 0) and xu < vq["xu_toi_thieu"]:
                self.sleep(1.0)  # đọc lại cho chắc, tránh dừng oan vì đọc nhầm
                s, neo = self.cho_man_vong_quay()
                xu_lai = self.doc_xu(s, neo)
                if xu_lai is None or xu_lai < vq["xu_toi_thieu"]:
                    self.log(f"⛔ Xu còn {xu_lai if xu_lai is not None else xu} < mức tối thiểu {vq['xu_toi_thieu']} → dừng")
                    return
                xu = xu_lai
            if vq.get("toi_da_bam", 0) and bam_lan_nay >= vq["toi_da_bam"]:
                self.log(f"✔ Đã bấm đủ {bam_lan_nay} lần → dừng")
                return
            dem = int(vq.get("dem", 0))
            if dem + 1 >= moc:
                self.log(f"★ Lần bấm thứ {dem + 1} (mốc {moc}) → Tạo mới để ra tướng hạn định")
                s, neo = self.tao_moi_toi_khi_co_tuong(s, neo)
                xu = self.doc_xu(s, neo)
            ds_o = self.o_han_dinh(s, neo)

            # bấm x10 rồi theo dõi giữa màn hình
            self.tap(*self.ra(neo, *_NUT_X10))
            trung = None
            bd = time.time()
            da_luu = False
            thay_ket_qua = False
            while time.time() - bd < vq.get("cho_ket_qua", 6.0):
                self.sleep(0.4)
                s2 = self.shot()
                if self.neo(s2) is None:
                    thay_ket_qua = True  # màn đổi (món trúng / hiệu ứng) → lần bấm đã ăn
                neo2 = self.neo(s2) or neo
                t = self.trung_han_dinh(s2, neo2, ds_o) if ds_o else None
                if t:
                    trung = t
                    break
                if not da_luu and self.neo(s2) is None and self.stats["vq_anh"] < 5:
                    self.luu_anh_loi(s2, "kết quả vòng quay (gửi ảnh này để kiểm tra nhận diện)")
                    self.stats["vq_anh"] += 1
                    da_luu = True
            s3, neo3 = self.cho_man_vong_quay()
            xu2 = self.doc_xu(s3, neo3)
            if not thay_ket_qua and xu is not None and xu2 is not None and xu2 == xu:
                self.log("  Bấm x10 chưa ăn (màn không đổi, Xu y nguyên) → bấm lại")
                continue
            bam_lan_nay += 1
            self.stats["vq_bam"] += 1
            dem += 1
            if trung or dem >= moc:
                ly_do = f"trúng hạn định ({trung})" if trung else f"đủ mốc {moc}"
                self.log(f"🎉 Lần {dem}: {ly_do} → bộ đếm về 0")
                if trung:
                    self.stats["vq_han_dinh"] += 1
                dem = 0
                if vq.get("dung_khi_trung") and trung:
                    vq["dem"] = 0
                    self.luu()
                    self.log("✔ Đã trúng hạn định → dừng (theo tuỳ chọn)")
                    return
            elif dem % 10 == 0:
                self.log(f"  Đã bấm x10 {dem}/{moc}" + (f", Xu còn {xu2}" if xu2 is not None else ""))
            vq["dem"] = dem
            self.luu()
