"""Kiểm tra chế độ qua ải: màn chương thật (ảnh chụp), 4 ải mỗi ải một bản đồ riêng.
Chạy: python test_chuong.py
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
from test_ban_do import FakeScrollGame, tao_ban_do_lon
from test_sweep import ANH, GOC

# tâm nhãn ải trên màn chương 1280×720 (ảnh thật)
NHAN = {"1-1": (612, 262), "1-2": (552, 512), "1-3": (856, 607), "1-4": (896, 397)}
TRO_LAI = (35, 10, 150, 100)


class FakeChuongGame:
    serial = "fake"

    def __init__(self):
        self.anh_chuong = cv2.imread(os.path.join(ANH, "chuong.jpg"))
        lon = tao_ban_do_lon()
        nho = lon[:720, :1280].copy()  # bản đồ vừa một màn hình
        self.ai = {
            "1-1": FakeScrollGame(cam=(0, 0), luot=2, lon=nho,
                                  khu=[((200, 150, 430, 330), "A1"), ((800, 300, 1050, 480), "A2")]),
            "1-2": FakeScrollGame(cam=(600, 300), luot=2,  # bản đồ lớn, phải kéo
                                  khu=[((200, 150, 430, 330), "B1"), ((1950, 180, 2200, 380), "B2"),
                                       ((2150, 1180, 2420, 1380), "B3")]),
            "1-3": FakeScrollGame(cam=(0, 0), luot=2, lon=nho, khu=[((500, 400, 760, 560), "C1")]),
            "1-4": FakeScrollGame(cam=(0, 0), luot=0, lon=nho, khu=[((500, 400, 760, 560), "D1")]),  # hết lượt
        }
        self.o = "1-3"  # người dùng đang đứng trong ải 1-3 lúc bấm Chạy
        self.vao = []

    def screenshot(self):
        return self.anh_chuong.copy() if self.o is None else self.ai[self.o].screenshot()

    def tap(self, x, y):
        if self.o is None:
            for ten, (cx, cy) in NHAN.items():
                if abs(x - cx) < 90 and abs(y - cy) < 16:
                    self.o = ten
                    self.vao.append(ten)
                    self.ai[ten].man = "ban_do"
            return
        g = self.ai[self.o]
        if g.man == "ban_do" and TRO_LAI[0] <= x <= TRO_LAI[2] and TRO_LAI[1] <= y <= TRO_LAI[3]:
            self.o = None
            return
        g.tap(x, y)

    def swipe(self, *a):
        if self.o is not None:
            self.ai[self.o].swipe(*a)

    def back(self):
        pass


class NhanhChuong(ChuongBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.003))

    def cho_bam(self, ev, giay):
        return ev.wait(min(giay, 0.005))


class TestChuong(unittest.TestCase):
    def test_qua_ai(self):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = json.load(f)
        cfg = copy.deepcopy(cfg)
        cfg["can_quet"]["qua_ai"] = True
        cfg["can_quet"]["tu_dong_vuot_ai"] = False  # kiểm tra chế độ danh sách ải
        cfg["can_quet"]["tu_dong_tham_hiem"] = False
        cfg["can_quet"]["kieu_quet"] = 1
        for ai in cfg["can_quet"]["ai"]:
            ai["khu"] = []
        tmp = tempfile.mkdtemp()
        try:
            for f in os.listdir(os.path.join(GOC, "mau")):
                p = os.path.join(GOC, "mau", f)
                if os.path.isfile(p):
                    shutil.copy(p, tmp)
            g = FakeChuongGame()
            q = queue.Queue()
            b = NhanhChuong(g, cfg, Templates(tmp), q.put)
            b.start()
            b.join(900)
            self.assertFalse(b.is_alive())
            logs = [m[2] for m in list(q.queue) if m[0] == "log"]
            print("\n  " + "\n  ".join(l for l in logs if "══" in l or "Dò xong" in l or "✔" in l or "Trở lại" in l))
            self.assertEqual(g.vao, ["1-1", "1-2", "1-3", "1-4"])
            lich_su = sorted(sum((x.lich_su for x in g.ai.values()), []))
            self.assertEqual(lich_su, sorted(["A1", "A2", "B1", "B2", "B3", "C1"] * 2))
            self.assertEqual([len(a["khu"]) for a in cfg["can_quet"]["ai"]], [2, 3, 1, 1])
            self.assertTrue(any("Đã quét xong mọi ải" in l for l in logs))
            self.assertTrue(os.path.isfile(os.path.join(tmp, "tieu_de_khu", "ai_1_2_khu_3.png")))
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
