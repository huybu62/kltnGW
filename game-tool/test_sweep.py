"""Kiểm tra chế độ Càn quét bằng ảnh màn hình thật của game (thu về 1280×720).
Chạy: python test_sweep.py
"""
import copy
import json
import os
import queue
import time
import unittest

import cv2
import numpy as np

from matcher import Templates
from sweep import SweepBot, doc_thanh_the_luc

GOC = os.path.dirname(os.path.abspath(__file__))
ANH = os.path.join(GOC, "anh_test")
K = 1280 / 2000  # ảnh gốc rộng 2000, vùng game bắt đầu ở y=108


def doi(x, y):
    return x * K, (y - 108) * K


def trong(x, y, hop):
    (x1, y1), (x2, y2) = doi(*hop[:2]), doi(*hop[2:])
    return x1 <= x <= x2 and y1 <= y <= y2


HOP_CONG_XUONG = (1100, 640, 1670, 1010)
HOP_TRAN_HINH = (1540, 1050, 1700, 1190)  # dùng làm "khu thứ 2" giả
HOP_CAN_QUET = (1112, 1030, 1340, 1128)
HOP_X_POPUP = (1300, 150, 1452, 238)
HOP_LAN_NUA = (1650, 475, 1855, 662)
HOP_DONG = (1680, 870, 1835, 1035)


class FakeGame:
    """Mô phỏng: bản đồ → popup khu → kết quả, có tính thể lực và số lần còn lại."""

    serial = "fake"

    def __init__(self, the_luc=43, luot_khu=None):
        self.anh = {n: cv2.imread(os.path.join(ANH, f"{n}.jpg")) for n in ("ban_do", "popup_khu", "ket_qua")}
        self.man = "ban_do"
        self.the_luc = the_luc
        self.luot = dict(luot_khu or {})  # khu -> số lần còn lại
        self.khu = None
        self.lich_su = []  # (khu) mỗi lần quét thành công

    def screenshot(self):
        img = self.anh[self.man].copy()
        if self.man == "ban_do":
            x0, x1 = 577, 765
            dai = int((x1 - x0) * min(1, self.the_luc / 120))
            img[21:47, x0:x1] = (17, 13, 57)  # nền thanh (đỏ sẫm)
            img[21:47, x0:x0 + dai] = (0, 129, 255)  # phần cam
        if self.man == "ket_qua":
            # số lần còn lại thay đổi sau mỗi lần quét
            cv2.putText(img, str(len(self.lich_su)), (1080, 435), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
        return img

    def quet(self):
        if self.the_luc < 4 or self.luot.get(self.khu, 99) <= 0:
            return False
        self.the_luc -= 4
        self.luot[self.khu] = self.luot.get(self.khu, 99) - 1
        self.lich_su.append(self.khu)
        return True

    def tap(self, x, y):
        if self.man == "ban_do":
            if trong(x, y, HOP_CONG_XUONG):
                self.khu, self.man = "cong_xuong", "popup_khu"
            elif trong(x, y, HOP_TRAN_HINH):
                self.khu, self.man = "khu_2", "popup_khu"
        elif self.man == "popup_khu":
            if trong(x, y, HOP_CAN_QUET) and self.quet():
                self.man = "ket_qua"
            elif trong(x, y, HOP_X_POPUP):
                self.man = "ban_do"
        elif self.man == "ket_qua":
            if trong(x, y, HOP_LAN_NUA):
                self.quet()
            elif trong(x, y, HOP_DONG):
                self.man = "ban_do"

    def back(self):
        pass


class NhanhSweepBot(SweepBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.02))

    def cho_bam(self, ev, giay):
        return ev.wait(min(giay, 0.005))


class TestSweep(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            self.cfg = json.load(f)
        self.tpl = Templates(os.path.join(GOC, "mau"))

    def chay(self, game, cfg, stop_after=0):
        q = queue.Queue()
        b = NhanhSweepBot(game, cfg, self.tpl, q.put, stop_after=stop_after)
        t = time.time()
        b.start()
        b.join(60)
        self.assertFalse(b.is_alive(), "bot không tự dừng")
        logs = [m[2] for m in list(q.queue) if m[0] == "log"]
        print(f"\n  ({time.time() - t:.1f}s) " + " | ".join(logs[-4:]))
        return b, logs

    def test_doc_the_luc(self):
        for tl in (0, 4, 43, 80, 120):
            g = FakeGame(the_luc=tl)
            s = g.screenshot()
            m = self.tpl.find(s, "cq_the_luc", 0.8)
            self.assertIsNotNone(m)
            self.assertAlmostEqual(doc_thanh_the_luc(s, m) * 120, tl, delta=1.5)
        # ảnh gốc chưa vẽ lại: 43/120
        s = cv2.imread(os.path.join(ANH, "ban_do.jpg"))
        m = self.tpl.find(s, "cq_the_luc", 0.8)
        self.assertAlmostEqual(doc_thanh_the_luc(s, m) * 120, 43, delta=1.5)

    def test_quet_het_the_luc_mot_khu(self):
        g = FakeGame(the_luc=43)
        b, logs = self.chay(g, self.cfg)
        self.assertEqual(len(g.lich_su), 10)  # 43 thể lực / 4 = 10 lần
        self.assertEqual(g.man, "ban_do")
        self.assertTrue(any("Hết thể lực" in l for l in logs))

    def test_xoay_vong_hai_khu(self):
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["so_lan_moi_khu"] = 3
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        g = FakeGame(the_luc=43)
        self.chay(g, cfg)
        self.assertEqual(g.lich_su, ["cong_xuong"] * 3 + ["khu_2"] * 3 + ["cong_xuong"] * 3 + ["khu_2"])

    def test_khu_het_luot_thi_sang_khu_khac(self):
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        g = FakeGame(the_luc=43, luot_khu={"cong_xuong": 2})
        b, logs = self.chay(g, cfg)
        self.assertEqual(g.lich_su, ["cong_xuong"] * 2 + ["khu_2"] * 8)

    def test_the_luc_mua_vuot_muc(self):
        # mua thêm: 200/120, thanh đầy → không dừng ở 30 lần mà quét tới khi hết thật
        g = FakeGame(the_luc=200)
        b, logs = self.chay(g, self.cfg)
        self.assertEqual(len(g.lich_su), 50)
        self.assertTrue(any("Hết thể lực" in l for l in logs))

    def test_het_99_luot_sang_khu_ke(self):
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        g = FakeGame(the_luc=1000, luot_khu={"cong_xuong": 99, "khu_2": 99})
        self.chay(g, cfg)
        self.assertEqual(g.lich_su, ["cong_xuong"] * 99 + ["khu_2"] * 99)

    def test_man_mo_khi_dong_ket_qua_khong_bao_het_the_luc(self):
        # vừa đóng màn kết quả, bản đồ còn tối mờ 2 khung hình (hiệu ứng) → không được đọc thành 0
        class GameMo(FakeGame):
            mo = 0

            def tap(self, x, y):
                truoc = self.man
                super().tap(x, y)
                if truoc != "ban_do" and self.man == "ban_do":
                    self.mo = 2

            def screenshot(self):
                img = super().screenshot()
                if self.man == "ban_do" and self.mo > 0:
                    self.mo -= 1
                    return (img * 0.5).astype(img.dtype)
                return img

        g = GameMo(the_luc=200, luot_khu={"cong_xuong": 3, "khu_2": 3})
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        b, logs = self.chay(g, cfg)
        self.assertEqual(g.lich_su, ["cong_xuong"] * 3 + ["khu_2"] * 3)
        self.assertFalse(any("Hết thể lực" in l for l in logs), logs)

    def test_khong_kiem_tra_the_luc(self):
        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["bo_qua_the_luc"] = True
        g = FakeGame(the_luc=43, luot_khu={"cong_xuong": 5})
        b, logs = self.chay(g, cfg)
        self.assertEqual(len(g.lich_su), 5)  # không dừng vì thể lực, chỉ dừng khi hết khu
        self.assertFalse(any("Hết thể lực" in l for l in logs))

    def test_nhan_vat_di_bo_moi_mo_popup(self):
        # chạm khu thì nhân vật đi bộ tới, 5 khung hình sau popup mới mở; chạm lại giữa chừng là đi lại từ đầu
        class GameDiBo(FakeGame):
            cho = None

            def tap(self, x, y):
                if self.man == "ban_do":
                    super().tap(x, y)
                    if self.man == "popup_khu":
                        self.man, self.cho = "ban_do", 5
                    else:
                        self.cho = None
                    return
                super().tap(x, y)

            def screenshot(self):
                if self.cho is not None:
                    self.cho -= 1
                    if self.cho <= 0:
                        self.man, self.cho = "popup_khu", None
                return super().screenshot()

        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        g = GameDiBo(the_luc=1000, luot_khu={"cong_xuong": 4, "khu_2": 4})
        b, logs = self.chay(g, cfg)
        self.assertEqual(g.lich_su, ["cong_xuong"] * 4 + ["khu_2"] * 4)

    def test_khu_tam_bo_duoc_thu_lai(self):
        # khu 2 mấy lần đầu chạm không ăn → tạm bỏ qua, vòng sau quay lại quét được hết
        class GameKhoMo(FakeGame):
            bo = 5

            def tap(self, x, y):
                if self.man == "ban_do" and trong(x, y, HOP_TRAN_HINH) and self.bo > 0:
                    self.bo -= 1
                    return
                super().tap(x, y)

        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["khu"].append({"ten": "Khu 2", "bat": True, "xy": [0.81, 0.92]})
        g = GameKhoMo(the_luc=1000, luot_khu={"cong_xuong": 3, "khu_2": 3})
        b, logs = self.chay(g, cfg)
        self.assertEqual(sorted(g.lich_su), sorted(["cong_xuong"] * 3 + ["khu_2"] * 3), logs)
        self.assertTrue(any("tạm bỏ qua" in l for l in logs))

    def test_len_cap_giua_chung(self):
        # sau lần quét thứ 4 và thứ 9 hiện màn "lên cấp" (tool không biết), chạm mép trên / Quay lại mới tắt
        class GameLenCap(FakeGame):
            len_cap = False
            so_tap = 0

            def quet(self):
                ok = super().quet()
                if ok and len(self.lich_su) in (4, 9):
                    self.len_cap = True
                return ok

            def tap(self, x, y):
                self.so_tap += 1
                if self.len_cap:
                    if y < 0.08 * 720:
                        self.len_cap = False
                    return
                super().tap(x, y)

            def back(self):
                self.len_cap = False

            def screenshot(self):
                if self.len_cap:
                    img = np.full((720, 1280, 3), (60, 20, 90), np.uint8)
                    cv2.putText(img, "LEVEL UP!", (420, 360), cv2.FONT_HERSHEY_SIMPLEX, 3, (0, 220, 255), 6)
                    return img
                return super().screenshot()

        g = GameLenCap(the_luc=1000, luot_khu={"cong_xuong": 12})
        b, logs = self.chay(g, self.cfg)
        self.assertEqual(len(g.lich_su), 12, logs[-8:])
        self.assertTrue(any("Màn lạ" in l for l in logs))
        self.assertFalse(any("Không nhận ra màn hình" in l for l in logs))

    def test_bam_theo_loat(self):
        # đang bấm "lần nữa" thì mỗi lần chụp màn hình phải bấm được nhiều cú
        class GameDem(FakeGame):
            so_chup = 0

            def screenshot(self):
                if self.man == "ket_qua" and len(self.lich_su) < 40:  # chỉ đếm lúc khu còn lượt
                    self.so_chup += 1
                return super().screenshot()

        cfg = copy.deepcopy(self.cfg)
        cfg["can_quet"]["nhip_lan_nua"] = 0.2
        g = GameDem(the_luc=1000, luot_khu={"cong_xuong": 40})
        b, logs = self.chay(g, cfg)
        self.assertEqual(len(g.lich_su), 40)
        self.assertLess(g.so_chup, 25, f"chụp {g.so_chup} lần cho 40 lần quét")
        self.assertGreaterEqual(b.stats["can_quet"], 40)

    def test_dung_sau_n_lan(self):
        g = FakeGame(the_luc=120)
        self.chay(g, self.cfg, stop_after=5)
        self.assertEqual(len(g.lich_su), 5)
        self.assertEqual(g.man, "ban_do")  # đóng hết popup trước khi dừng


if __name__ == "__main__":
    unittest.main(verbosity=2)
