"""Kiểm tra chế độ càn quét x10 (popup mới có nút x5/x10, bảng hỏi "Càn quét 10 lần ... Xác định").
Ảnh popup và bảng hỏi là ảnh chụp thật của game. Chạy: python test_x10.py
"""
import copy
import json
import os
import queue
import unittest

import cv2

from matcher import Templates
from test_sweep import ANH, GOC, HOP_CONG_XUONG, HOP_DONG, HOP_LAN_NUA, HOP_X_POPUP, FakeGame, NhanhSweepBot, trong

# vị trí trên ảnh gốc rộng 2000 (popup mới)
HOP_CAN_QUET_MOI = (905, 1035, 1120, 1125)
HOP_X5 = (1166, 1035, 1280, 1127)
HOP_X10 = (1322, 1035, 1437, 1127)
HOP_XAC_DINH = (858, 792, 1052, 858)


class FakeGameX10(FakeGame):
    def __init__(self, luot=25, xu=5000, sau_x10="popup", **kw):
        super().__init__(the_luc=100000, luot_khu={"cong_xuong": luot}, **kw)
        self.popup_moi = cv2.imread(os.path.join(ANH, "popup_x10.jpg"))
        self.hoi = cv2.imread(os.path.join(ANH, "hoi_x10.jpg"))
        self.xu, self.sau_x10 = xu, sau_x10
        self.cho_n = 0
        self.so_x10 = 0
        self.so_xac_nhan = 0

    def screenshot(self):
        if self.man == "popup_khu":
            img = self.popup_moi.copy()
            img[146:178, 712:910] = (40, 40, 60)  # "Số lần còn lại:NN"
            cv2.putText(img, f"Con lai:{self.luot.get(self.khu, 99)}", (715, 172), cv2.FONT_HERSHEY_SIMPLEX, 0.8,
                        (200, 200, 200), 2)
            return img
        if self.man == "hoi":
            img = self.hoi.copy()
            if self.cho_n == -1:  # bảng hỏi khác: thiếu Xu
                img[285:345, 400:900] = (img[285:345, 400:900] * 0.3).astype(img.dtype)
                cv2.putText(img, "Khong du Xu. Nap them?", (410, 328), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (40, 160, 250), 2)
            return img
        return super().screenshot()

    def tap(self, x, y):
        if self.man == "popup_khu":
            if trong(x, y, HOP_X10):
                self.so_x10 += 1
                if self.luot[self.khu] >= 10:  # game chỉ cho x10 khi còn đủ 10 lượt
                    self.cho_n = 10 if self.xu >= 500 else -1
                    self.man = "hoi"
            elif trong(x, y, HOP_CAN_QUET_MOI):
                if self.quet():
                    self.man = "ket_qua"
            elif trong(x, y, HOP_X_POPUP):
                self.man = "ban_do"
            return
        if self.man == "hoi":
            if trong(x, y, HOP_XAC_DINH) and self.cho_n == 10:
                self.so_xac_nhan += 1
                self.xu -= 500
                for _ in range(10):
                    self.quet()
                self.man = "popup_khu" if self.sau_x10 == "popup" else "ket_qua"
            return
        super().tap(x, y)

    def back(self):
        if self.man == "hoi":
            self.man = "popup_khu"


class TestX10(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            self.cfg = json.load(f)
        for k in ["nghi_giua_vong", "nghi_khi_khong_thay"]:
            self.cfg[k] = 0
        self.tpl = Templates(os.path.join(GOC, "mau"))

    def chay(self, g, kieu):
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["kieu_quet"] = kieu
        q = queue.Queue()
        b = NhanhSweepBot(g, cfg, self.tpl, q.put)
        b.start()
        b.join(120)
        self.assertFalse(b.is_alive())
        logs = [m[2] for m in list(q.queue) if m[0] == "log"]
        print("\n  " + " | ".join(l for l in logs if "x10" in l or "từng lần" in l or "huỷ" in l)[:500])
        return b, logs

    def test_x10_ve_lai_popup(self):
        g = FakeGameX10(luot=25, sau_x10="popup")
        b, logs = self.chay(g, 10)
        self.assertEqual(len(g.lich_su), 25)  # 10 + 10 bằng x10, 5 lượt cuối quét từng lần
        self.assertEqual(g.so_xac_nhan, 2)
        self.assertGreaterEqual(b.stats["can_quet"], 25)  # số đếm trên overlay là ước lượng (đếm theo cú bấm)

    def test_x10_ra_man_ket_qua(self):
        g = FakeGameX10(luot=25, sau_x10="ket_qua")
        b, logs = self.chay(g, 10)
        self.assertEqual(len(g.lich_su), 25)
        self.assertEqual(g.so_xac_nhan, 2)

    def test_thieu_xu_khong_xac_nhan(self):
        g = FakeGameX10(luot=12, xu=0)
        b, logs = self.chay(g, 10)
        self.assertEqual(g.so_xac_nhan, 0)  # bảng hỏi khác → không bấm Xác định
        self.assertEqual(len(g.lich_su), 12)  # chuyển sang quét từng lần
        self.assertTrue(any("huỷ" in l for l in logs))

    def test_che_do_tung_lan_khong_bam_x10(self):
        g = FakeGameX10(luot=12)
        b, logs = self.chay(g, 1)
        self.assertEqual(g.so_x10, 0)
        self.assertEqual(len(g.lich_su), 12)


if __name__ == "__main__":
    unittest.main(verbosity=2)
