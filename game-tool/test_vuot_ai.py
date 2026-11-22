"""Kiểm tra chế độ TỰ ĐỘNG VƯỢT ẢI (cần OCR) trên 2 màn chương thật (Singapore, Ai Cập):
đọc màn chương, vào ải bằng cách chạm TOÀ NHÀ phía trên nhãn (ải không có nhân vật đứng phải chạm 2 lần),
dò khu, thám hiểm khu chưa mở (bấm "Tiến lên"), quét x5 rồi bấm "Quét lại" ngay trên màn kết quả
(có bảng hỏi Xác định), quét lẻ phần còn lại, Trở lại; đi xuôi (▶) và đi ngược (◀).
Chạy: python test_vuot_ai.py
"""
import copy
import json
import os
import queue
import shutil
import tempfile
import unittest

import cv2

from chuong import ChuongBot
from matcher import Templates
from ocr import co_ocr
from test_ban_do import tao_ban_do_lon
from test_sweep import ANH, GOC, HOP_DONG, HOP_LAN_NUA, HOP_X_POPUP, trong
from test_x10 import HOP_CAN_QUET_MOI, HOP_X5, HOP_XAC_DINH

HOP_THAM_HIEM = (640, 1035, 862, 1125)  # trên ảnh gốc rộng 2000 (popup mới)
# màn chương 1280×720: ảnh, tâm nhãn ải (toà nhà ở phía trên nhãn)
CHUONG = {
    "Singapore": ("chuong2.jpg", {1: (637, 262), 2: (553, 509), 3: (797, 606), 4: (904, 398)}),
    "Ai Cap": ("chuong_ai_cap.jpg", {1: (888, 357), 2: (816, 511), 3: (543, 617), 4: (634, 328)}),
}
MUI_TEN_PHAI = (1140, 300, 1190, 420)
MUI_TEN_TRAI = (340, 300, 390, 420)
TRO_LAI = (35, 10, 150, 100)
TIEN_LEN = (940, 330, 1200, 520)  # mũi tên + chữ "Tiến lên" trên ảnh trận đánh
QUET_LAI = (1040, 225, 1250, 395)  # nút "Quét lại" trên màn kết quả x5 (chỗ nút "Càn quét lần nữa")


class Khu:
    def __init__(self, hop, ten, luot, da_mo=True):
        self.hop, self.ten, self.luot, self.da_mo = hop, ten, luot, da_mo


class FakeVuotAi:
    serial = "fake"

    def __init__(self, nuoc):
        self.anh = {t: cv2.imread(os.path.join(ANH, f)) for t, (f, _) in CHUONG.items()}
        self.popup = cv2.imread(os.path.join(ANH, "popup_x10.jpg"))
        self.hoi = cv2.imread(os.path.join(ANH, "hoi_x5.jpg"))
        self.kq = cv2.imread(os.path.join(ANH, "ket_qua.jpg"))
        self.tran = cv2.imread(os.path.join(ANH, "tran_danh.jpg"))
        self.hud = cv2.imread(os.path.join(ANH, "ban_do.jpg"))
        self.ban_do = tao_ban_do_lon()[:720, :1280].copy()
        self.nuoc = nuoc  # [(tên nước, {số ải: [Khu]})]
        self.i_nuoc = 0
        self.man, self.ai, self.khu = "chuong", None, None
        self.tran_con = 0
        self.da_quet = []
        self.vao = []
        self.so_tien_len = 0
        self.so_quet_lai = 0
        self.dung_o = 2  # ải nhân vật đang đứng: ải khác phải chạm 2 lần
        self.hoi_tu = None

    @property
    def ten_nuoc(self):
        return self.nuoc[self.i_nuoc][0]

    che_ten = False  # che dải tên nước (đọc chữ không ra)

    def screenshot(self):
        if self.man == "chuong":
            img = self.anh[self.ten_nuoc].copy()
            if self.che_ten:
                cv2.rectangle(img, (650, 10), (880, 55), (180, 110, 40), -1)
                cv2.line(img, (660, 20), (870, 48), (40, 200, 230), 3)
            return img
        if self.man == "ban_do":
            img = self.ban_do.copy()
            for x1, y1, x2, y2 in [TRO_LAI, (250, 12, 780, 60)]:
                img[y1:y2, x1:x2] = self.hud[y1:y2, x1:x2]
            img[21:47, 577:765] = (0, 129, 255)
            return img
        if self.man == "popup":
            img = self.popup.copy()
            img[78:120, 395:700] = (20, 40, 70)
            cv2.putText(img, self.khu.ten, (400, 112), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (40, 230, 240), 2)
            img[146:178, 712:910] = (40, 40, 60)
            cv2.putText(img, f"Con lai:{self.khu.luot}", (715, 172), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (200, 200, 200), 2)
            if not self.khu.da_mo:  # chưa thám hiểm: chỉ có nút Thám hiểm
                img[585:660, 570:930] = (30, 45, 70)
            return img
        if self.man == "hoi":
            return self.hoi.copy()
        if self.man == "tran":
            return self.tran.copy()
        img = self.kq.copy()
        if self.man == "kq_boi":  # màn kết quả sau x5: nút "Quét lại" thay cho "Càn quét lần nữa"
            x1, y1, x2, y2 = QUET_LAI
            img[y1:y2, x1:x2] = (25, 25, 35)
            cv2.putText(img, "Quet lai", (1065, 320), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (230, 230, 230), 3)
        img[402:442, 1021:1232] = (20, 30, 30)
        cv2.putText(img, f"So lan: {self.khu.luot}/99", (1026, 434), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)
        return img

    def quet(self, n=1):
        if self.khu.luot < n:
            return False
        self.khu.luot -= n
        self.da_quet += [(self.ten_nuoc, self.ai, self.khu.ten)] * n
        return True

    def doi_nuoc(self, buoc):
        moi = max(0, min(len(self.nuoc) - 1, self.i_nuoc + buoc))
        if moi != self.i_nuoc:
            self.i_nuoc, self.dung_o = moi, 1

    def tap(self, x, y):
        if self.man == "chuong":
            if MUI_TEN_PHAI[0] <= x <= MUI_TEN_PHAI[2] and MUI_TEN_PHAI[1] <= y <= MUI_TEN_PHAI[3]:
                return self.doi_nuoc(1)
            if MUI_TEN_TRAI[0] <= x <= MUI_TEN_TRAI[2] and MUI_TEN_TRAI[1] <= y <= MUI_TEN_TRAI[3]:
                return self.doi_nuoc(-1)
            for so, (cx, cy) in CHUONG[self.ten_nuoc][1].items():
                # chỉ chạm vào TOÀ NHÀ phía trên nhãn mới vào được (chạm vào chữ thì không)
                if abs(x - cx) < 90 and cy - 125 <= y <= cy - 50 and so in self.nuoc[self.i_nuoc][1]:
                    if self.dung_o != so:
                        self.dung_o = so  # nhân vật đi tới ải này, chưa vào
                        return
                    self.man, self.ai = "ban_do", so
                    self.vao.append((self.ten_nuoc, so))
            return
        if self.man == "ban_do":
            if TRO_LAI[0] <= x <= TRO_LAI[2] and TRO_LAI[1] <= y <= TRO_LAI[3]:
                self.man = "chuong"
                return
            for k in self.nuoc[self.i_nuoc][1][self.ai]:
                x1, y1, x2, y2 = k.hop
                if x1 <= x <= x2 and y1 <= y <= y2:
                    self.man, self.khu = "popup", k
            return
        if self.man == "popup":
            if trong(x, y, HOP_X_POPUP):
                self.man = "ban_do"
            elif not self.khu.da_mo:
                if trong(x, y, (640, 1035, 862, 1125)):
                    self.man, self.tran_con = "tran", 3
            elif trong(x, y, HOP_X5) and self.khu.luot >= 5:
                self.man, self.hoi_tu = "hoi", "popup"
            elif trong(x, y, HOP_CAN_QUET_MOI) and self.quet():
                self.man = "ket_qua"
            return
        if self.man == "hoi":
            if trong(x, y, HOP_XAC_DINH):
                self.quet(5)
                self.man = "kq_boi"
            return
        if self.man == "tran":
            if TIEN_LEN[0] <= x <= TIEN_LEN[2] and TIEN_LEN[1] <= y <= TIEN_LEN[3]:
                self.so_tien_len += 1
                self.tran_con -= 1
                if self.tran_con <= 0:
                    self.khu.da_mo = True
                    self.man = "popup"
            return
        if self.man == "kq_boi":
            if QUET_LAI[0] <= x <= QUET_LAI[2] and QUET_LAI[1] <= y <= QUET_LAI[3]:
                if self.khu.luot >= 5:
                    self.so_quet_lai += 1
                    self.man, self.hoi_tu = "hoi", "kq_boi"
            elif trong(x, y, HOP_DONG):
                self.man = "popup"
            return
        if self.man == "ket_qua":
            if trong(x, y, HOP_LAN_NUA):
                self.quet()
            elif trong(x, y, HOP_DONG):
                self.man = "ban_do"

    def swipe(self, *a):
        pass

    def back(self):
        if self.man == "hoi":
            self.man = self.hoi_tu or "popup"


class NhanhVuotAi(ChuongBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.003))

    def cho_bam(self, ev, giay):
        return ev.wait(min(giay, 0.005))


def tao_game():
    def ai(so, *khu):
        return so, [Khu(*k) for k in khu]

    sing = dict([
        ai(1, ((200, 150, 430, 330), "Kho hang", 17)),  # x5 ×3 (1 lần x5 + 2 lần "Quét lại") + 2 lẻ
        ai(2, ((800, 300, 1050, 480), "Nha ga cu", 6, False)),  # chưa thám hiểm
        ai(3, ((200, 150, 430, 330), "Cang bien", 5), ((800, 300, 1050, 480), "Cho dem", 3)),
        ai(4, ((500, 400, 760, 560), "San bay", 0)),  # đã hết lượt
    ])
    aicap = dict([
        ai(1, ((500, 400, 760, 560), "Thap doi", 5, False)),
        ai(2, ((200, 150, 430, 330), "Rung co", 2)),
        ai(3, ((800, 300, 1050, 480), "Bai cat", 10)),
        ai(4, ((200, 150, 430, 330), "Den tho", 1)),
    ])
    return FakeVuotAi([("Singapore", sing), ("Ai Cap", aicap)])


@unittest.skipUnless(co_ocr(), "cần bộ đọc chữ rapidocr_onnxruntime")
class TestVuotAi(unittest.TestCase):
    def chay(self, g, thu_tu):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = copy.deepcopy(json.load(f))
        cq = cfg["can_quet"]
        cq.update({"tu_dong_vuot_ai": True, "qua_ai": True, "tu_dong_tham_hiem": True, "kieu_quet": 5,
                   "bo_qua_the_luc": True, "ai_tu_dong": {}, "xong_tu_dong": {}, "thu_tu": thu_tu})
        tmp = tempfile.mkdtemp()
        try:
            for f in os.listdir(os.path.join(GOC, "mau")):
                p = os.path.join(GOC, "mau", f)
                if os.path.isfile(p):
                    shutil.copy(p, tmp)
            q = queue.Queue()
            b = NhanhVuotAi(g, cfg, Templates(tmp), q.put)
            b.start()
            b.join(900)
            self.assertFalse(b.is_alive())
            logs = [m[2] for m in list(q.queue) if m[0] == "log"]
            print("\n  " + "\n  ".join(l for l in logs if "══" in l or "▶" in l or "◀" in l or "Quét lại" in l
                                       or "Thám hiểm" in l or "✔ Đã đi" in l))
            return cq, logs
        finally:
            shutil.rmtree(tmp)

    def kiem_tra_quet(self, g):
        dem = {}
        for n, a, k in g.da_quet:
            dem[k] = dem.get(k, 0) + 1
        self.assertEqual(dem, {"Kho hang": 17, "Nha ga cu": 6, "Cang bien": 5, "Cho dem": 3, "Thap doi": 5,
                               "Rung co": 2, "Bai cat": 10, "Den tho": 1})
        self.assertGreaterEqual(g.so_tien_len, 6)  # 2 khu chưa thám hiểm × 3 lần "Tiến lên"
        self.assertGreaterEqual(g.so_quet_lai, 3)  # Kho hang 2 lần + Bai cat 1 lần bấm "Quét lại"

    def test_di_xuoi(self):
        g = tao_game()
        cq, logs = self.chay(g, "xuoi")
        self.assertEqual(g.vao, [("Singapore", i) for i in (1, 2, 3, 4)] + [("Ai Cap", i) for i in (1, 2, 3, 4)])
        self.kiem_tra_quet(g)
        self.assertTrue(any("Đã đi hết" in l for l in logs))
        self.assertEqual(len(cq["xong_tu_dong"]["ds"]), 8)

    def test_di_nguoc(self):
        g = tao_game()  # đang ở Singapore: tool phải bấm ▶ tới nước cuối (Ai Cập) rồi đi ngược
        cq, logs = self.chay(g, "nguoc")
        self.assertEqual(g.vao, [("Ai Cap", i) for i in (4, 3, 2, 1)] + [("Singapore", i) for i in (4, 3, 2, 1)])
        self.kiem_tra_quet(g)


@unittest.skipUnless(co_ocr(), "cần bộ đọc chữ rapidocr_onnxruntime")
class TestDuLieuLoi(TestVuotAi):
    def test_khong_doc_duoc_ten_nuoc_va_moc_sai(self):
        g = tao_game()
        g.che_ten = True  # không đọc được tên nước ở cả 2 nước
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg0 = json.load(f)
        # dữ liệu lỗi của bản cũ + một ải có mốc sai (không khớp bản đồ)
        sai = {"khu": [{"ten": "Khu sai", "bat": True, "xy_map": [0.9, 0.9]}], "moc": [{"anh": "khong_co.png", "xy": [0.5, 0.3]}]}
        self._sai = sai
        cq, logs = self.chay_voi(g, {"? 1": sai, "? 2": sai, "Nuoc1 1": sai})  # Nuoc1 1: mốc sai → phải dò lại
        self.assertEqual(len(g.vao), 8)
        self.kiem_tra_quet(g)
        khoa = list(cq["ai_tu_dong"])
        self.assertFalse(any(k.startswith("? ") for k in khoa), khoa)
        self.assertEqual(len({k.rsplit(" ", 1)[0] for k in khoa}), 2, khoa)  # 2 nước khác khoá nhau

    def chay_voi(self, g, ai_tu_dong):
        goc = TestVuotAi.chay

        def chay(self2, g2, thu_tu):
            return goc(self2, g2, thu_tu)
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = copy.deepcopy(json.load(f))
        cq = cfg["can_quet"]
        cq.update({"tu_dong_vuot_ai": True, "qua_ai": True, "tu_dong_tham_hiem": True, "kieu_quet": 5,
                   "bo_qua_the_luc": True, "ai_tu_dong": copy.deepcopy(ai_tu_dong), "xong_tu_dong": {},
                   "thu_tu": "xuoi", "hinh_nuoc": []})
        tmp = tempfile.mkdtemp()
        try:
            for f in os.listdir(os.path.join(GOC, "mau")):
                p = os.path.join(GOC, "mau", f)
                if os.path.isfile(p):
                    shutil.copy(p, tmp)
            q = queue.Queue()
            b = NhanhVuotAi(g, cfg, Templates(tmp), q.put)
            b.start()
            b.join(900)
            self.assertFalse(b.is_alive())
            logs = [m[2] for m in list(q.queue) if m[0] == "log"]
            print("\n  " + "\n  ".join(l for l in logs if "══" in l or "Nuoc" in l or "xoá" in l))
            return cq, logs
        finally:
            shutil.rmtree(tmp)

    test_di_xuoi = None
    test_di_nguoc = None


if __name__ == "__main__":
    unittest.main(verbosity=2)
