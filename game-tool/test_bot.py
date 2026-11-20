"""Kiểm tra bộ máy luật bằng màn hình tổng hợp, không cần giả lập thật.
Chạy: python test_bot.py
"""
import copy
import json
import os
import queue
import tempfile
import unittest

import numpy as np

from bot import Bot
from matcher import Templates, ghi_anh

GOC = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)


def nen():
    img = np.full((720, 1280, 3), 60, np.uint8)
    img += rng.integers(0, 25, img.shape, dtype=np.uint8)
    return img


def tao_mau(w=80, h=40):
    # Khối màu ngẫu nhiên, đủ đặc trưng để khớp duy nhất
    o = rng.integers(0, 255, (h // 8, w // 8, 3), dtype=np.uint8)
    return np.kron(o, np.ones((8, 8, 1), np.uint8))


def dan(img, tpl, x, y):
    img = img.copy()
    h, w = tpl.shape[:2]
    img[y:y + h, x:x + w] = tpl
    return img


class FakeDevice:
    """Mỗi lần chạm đúng chỗ mong đợi thì chuyển sang màn kế tiếp."""

    serial = "fake"

    def __init__(self, man, cuoi):
        self.man = man  # [(ảnh, vùng_đúng (x1,y1,x2,y2) hoặc None)]
        self.cuoi = cuoi
        self.i = 0
        self.cham = []

    def screenshot(self):
        return self.man[self.i][0] if self.i < len(self.man) else self.cuoi

    def tap(self, x, y):
        self.cham.append((x, y))
        if self.i < len(self.man):
            vung = self.man[self.i][1]
            if vung and vung[0] <= x <= vung[2] and vung[1] <= y <= vung[3]:
                self.i += 1

    def back(self):
        pass


class TestBot(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tpl = Templates(self.tmp.name)
        self.m = {}
        for ten in ["nut_xuc_xac", "het_the_luc", "man_oan_tu_xi", "keo", "bua", "bao",
                    "man_chon_team", "team_chon", "nut_xuat_chien", "nut_danh_boss", "nut_xac_nhan"]:
            self.m[ten] = tao_mau()
            ghi_anh(os.path.join(self.tmp.name, f"{ten}.png"), self.m[ten])
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            self.cfg = json.load(f)
        for k in ["nghi_giua_vong", "nghi_khi_khong_thay"]:
            self.cfg[k] = 0
        for r in self.cfg["luat"]:
            r["nghi_sau"] = 0
            for b in r.get("buoc", []):
                b["nghi_sau"] = 0

    def tearDown(self):
        self.tmp.cleanup()

    def chay(self, dev, cfg=None, stop_after=0):
        q = queue.Queue()
        b = Bot(dev, cfg or self.cfg, self.tpl, q.put, stop_after=stop_after)
        b.start()
        b.join(20)
        self.assertFalse(b.is_alive(), "bot không tự dừng")
        logs = []
        while not q.empty():
            msg = q.get()
            if msg[0] == "log":
                logs.append(msg[2])
        return b, logs

    def test_ca_vong(self):
        m = self.m
        ban_do = dan(nen(), m["nut_xuc_xac"], 1100, 600)
        rps = dan(dan(dan(dan(nen(), m["man_oan_tu_xi"], 600, 50), m["keo"], 300, 500), m["bua"], 600, 500), m["bao"], 900, 500)
        boss = dan(nen(), m["nut_danh_boss"], 600, 400)
        team = dan(dan(dan(nen(), m["man_chon_team"], 600, 40), m["team_chon"], 200, 300), m["nut_xuat_chien"], 1000, 620)
        popup = dan(ban_do, m["nut_xac_nhan"], 600, 450)
        het = dan(nen(), m["het_the_luc"], 600, 300)
        man = [
            (ban_do, (1100, 600, 1180, 640)),
            (rps, (300, 500, 980, 540)),  # chạm vào bất kỳ lựa chọn nào
            (ban_do, (1100, 600, 1180, 640)),
            (boss, (600, 400, 680, 440)),
            (team, (1000, 620, 1080, 660)),  # chạm team_chon (không chuyển màn) rồi xuất chiến
            (popup, (600, 450, 680, 490)),  # popup phải được xử lý trước nút xúc xắc phía sau
            (ban_do, (1100, 600, 1180, 640)),
        ]
        dev = FakeDevice(man, het)
        b, logs = self.chay(dev)
        self.assertEqual(dev.i, len(man), logs)
        self.assertEqual(b.stats["xuc_xac"], 3)
        self.assertEqual(b.stats["oan_tu_xi"], 1)
        self.assertEqual(b.stats["boss"], 1)
        self.assertIn((240, 320), dev.cham)  # đã chọn team
        self.assertTrue(any("Hết thể lực" in l for l in logs))

    def test_dung_sau_n_luot(self):
        ban_do = dan(nen(), self.m["nut_xuc_xac"], 1100, 600)
        dev = FakeDevice([], ban_do)
        b, _ = self.chay(dev, stop_after=4)
        self.assertEqual(b.stats["xuc_xac"], 4)

    def test_nut_bi_lam_toi_khong_khop(self):
        toi = (self.m["nut_xuc_xac"].astype(np.float32) * 0.4).astype(np.uint8)
        man = dan(nen(), toi, 1100, 600)
        self.assertIsNone(self.tpl.find(man, "nut_xuc_xac", 0.85))
        self.assertIsNotNone(self.tpl.find(dan(nen(), self.m["nut_xuc_xac"], 1100, 600), "nut_xuc_xac", 0.85))

    def test_bien_the(self):
        khac = tao_mau()
        ghi_anh(self.tpl.next_variant_path("nut_xuc_xac"), khac)
        self.assertEqual(self.tpl.names().count("nut_xuc_xac"), 1)
        self.assertIsNotNone(self.tpl.find(dan(nen(), khac, 100, 100), "nut_xuc_xac", 0.85))

    def test_khong_nhan_ra_thi_dung(self):
        cfg = copy.deepcopy(self.cfg)
        cfg["dung_khi_khong_nhan_ra_giay"] = 0.5
        b, logs = self.chay(FakeDevice([], nen()), cfg)
        self.assertTrue(any("Không nhận ra" in l for l in logs))


if __name__ == "__main__":
    unittest.main(verbosity=2)
