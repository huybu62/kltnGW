"""Kiểm tra chế độ TỰ ĐỘNG VƯỢT ẢI (cần OCR): đọc màn chương, đi ải 1 → 4, sang nước sau bằng mũi tên,
dò khu, thám hiểm khu chưa mở (bấm "Tiến lên"), càn quét bằng x5 rồi lẻ, Trở lại.
Màn chương, popup, bảng hỏi x5, trận đánh là ảnh chụp thật. Chạy: python test_vuot_ai.py
"""
import copy
import json
import os
import queue
import shutil
import tempfile
import unittest

import cv2
import numpy as np

from chuong import ChuongBot
from matcher import Templates
from ocr import co_ocr
from test_ban_do import tao_ban_do_lon
from test_sweep import ANH, GOC, HOP_DONG, HOP_LAN_NUA, HOP_X_POPUP, trong
from test_x10 import HOP_CAN_QUET_MOI, HOP_X5, HOP_XAC_DINH

HOP_THAM_HIEM = (640, 1035, 862, 1125)  # trên ảnh gốc rộng 2000 (popup mới)
NHAN = {1: (637, 262), 2: (553, 509), 3: (797, 606), 4: (904, 398)}  # tâm nhãn ải trên màn chương 1280×720
MUI_TEN = (1140, 300, 1190, 420)
TRO_LAI = (35, 10, 150, 100)
TIEN_LEN = (940, 330, 1200, 520)  # mũi tên + chữ "Tiến lên" trên ảnh trận đánh 1280×720


class Khu:
    def __init__(self, hop, ten, luot, da_mo=True):
        self.hop, self.ten, self.luot, self.da_mo = hop, ten, luot, da_mo


class FakeVuotAi:
    serial = "fake"

    def __init__(self, nuoc):
        self.chuong = cv2.imread(os.path.join(ANH, "chuong2.jpg"))
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
        self.da_quet = []  # (nước, ải, khu) mỗi lượt quét
        self.vao = []
        self.so_tien_len = 0

    # ---------- hình ----------
    def screenshot(self):
        if self.man == "chuong":
            img = self.chuong.copy()
            ten = self.nuoc[self.i_nuoc][0]
            if ten != "Singapore":
                img[12:52, 640:900] = (190, 120, 30)
                cv2.putText(img, ten, (690, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 230, 255), 3)
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
        img[402:442, 1021:1232] = (20, 30, 30)
        cv2.putText(img, f"So lan: {self.khu.luot}/99", (1026, 434), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)
        return img

    # ---------- chạm ----------
    def quet(self, n=1):
        if self.khu.luot < n:
            return False
        self.khu.luot -= n
        self.da_quet += [(self.nuoc[self.i_nuoc][0], self.ai, self.khu.ten)] * n
        return True

    def tap(self, x, y):
        if self.man == "chuong":
            if MUI_TEN[0] <= x <= MUI_TEN[2] and MUI_TEN[1] <= y <= MUI_TEN[3]:
                self.i_nuoc = min(self.i_nuoc + 1, len(self.nuoc) - 1)
                return
            for so, (cx, cy) in NHAN.items():
                if abs(x - cx) < 90 and abs(y - cy) < 18 and so in self.nuoc[self.i_nuoc][1]:
                    self.man, self.ai = "ban_do", so
                    self.vao.append((self.nuoc[self.i_nuoc][0], so))
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
                if trong(x, y, HOP_THAM_HIEM):
                    self.man, self.tran_con = "tran", 3
            elif trong(x, y, HOP_X5) and self.khu.luot >= 5:
                self.man = "hoi"
            elif trong(x, y, HOP_CAN_QUET_MOI) and self.quet():
                self.man = "ket_qua"
            return
        if self.man == "hoi":
            if trong(x, y, HOP_XAC_DINH):
                self.quet(5)
                self.man = "popup"
            return
        if self.man == "tran":
            if TIEN_LEN[0] <= x <= TIEN_LEN[2] and TIEN_LEN[1] <= y <= TIEN_LEN[3]:
                self.so_tien_len += 1
                self.tran_con -= 1
                if self.tran_con <= 0:
                    self.khu.da_mo = True
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
            self.man = "popup"


class NhanhVuotAi(ChuongBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.003))

    def cho_bam(self, ev, giay):
        return ev.wait(min(giay, 0.005))


@unittest.skipUnless(co_ocr(), "cần bộ đọc chữ rapidocr_onnxruntime")
class TestVuotAi(unittest.TestCase):
    def test_hai_nuoc_tham_hiem_va_x5(self):
        def ai(so, *khu):
            return so, [Khu(*k) for k in khu]

        sing = dict([
            ai(1, ((200, 150, 430, 330), "Kho hang", 7)),
            ai(2, ((800, 300, 1050, 480), "Nha ga cu", 6, False)),  # chưa thám hiểm
            ai(3, ((200, 150, 430, 330), "Cang bien", 5), ((800, 300, 1050, 480), "Cho dem", 3)),
            ai(4, ((500, 400, 760, 560), "San bay", 0)),  # đã hết lượt
        ])
        mala = dict([
            ai(1, ((500, 400, 760, 560), "Thap doi", 5, False)),
            ai(2, ((200, 150, 430, 330), "Rung cao su", 2)),
            ai(3, ((800, 300, 1050, 480), "Bai bien", 5)),
            ai(4, ((200, 150, 430, 330), "Den tho", 1)),
        ])
        g = FakeVuotAi([("Singapore", sing), ("Malaysia", mala)])
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = copy.deepcopy(json.load(f))
        cq = cfg["can_quet"]
        cq.update({"tu_dong_vuot_ai": True, "qua_ai": True, "tu_dong_tham_hiem": True, "kieu_quet": 5,
                   "bo_qua_the_luc": True, "ai_tu_dong": {}, "xong_tu_dong": {}})
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
            print("\n  " + "\n  ".join(l for l in logs if "══" in l or "▶" in l or "Thám hiểm" in l or "✔ Đã đi" in l))
            self.assertEqual(g.vao, [("Singapore", i) for i in (1, 2, 3, 4)] + [("Malaysia", i) for i in (1, 2, 3, 4)])
            dem = {}
            for n, a, k in g.da_quet:
                dem[k] = dem.get(k, 0) + 1
            self.assertEqual(dem, {"Kho hang": 7, "Nha ga cu": 6, "Cang bien": 5, "Cho dem": 3, "Thap doi": 5,
                                   "Rung cao su": 2, "Bai bien": 5, "Den tho": 1})
            self.assertGreaterEqual(g.so_tien_len, 6)  # 2 khu chưa thám hiểm × 3 lần "Tiến lên"
            self.assertTrue(any("Đã đi hết" in l for l in logs))
            self.assertEqual(len(cq["xong_tu_dong"]["ds"]), 8)
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
