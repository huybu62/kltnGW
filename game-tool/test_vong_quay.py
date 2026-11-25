"""Kiểm tra chế độ VÒNG QUAY trên ảnh thật màn Vòng quay liên server (2 vòng khác nhau).
Chạy: python test_vong_quay.py
"""
import copy
import json
import os
import queue
import unittest

import cv2
import numpy as np

from matcher import Templates
from ocr import co_ocr
from test_sweep import ANH, GOC
from vong_quay import _O, VongQuayBot


def doi(X, Y):  # ảnh gốc rộng 2000 (vùng game bắt đầu y=108) → màn 1280×720
    return X * 0.64, (Y - 108) * 0.64


def o_anh(img, ten):
    x, y = doi(*_O[ten])
    return img[int(y):int(y + 114 * 0.64), int(x):int(x + 110 * 0.64)].copy()


class FakeVongQuay:
    serial = "fake"

    def __init__(self, xu=100000, vong="C", tao_moi=("C", "A"), ket_qua=()):
        self.a = cv2.imread(os.path.join(ANH, "vong_quay_a.jpg"))  # tướng hạn định ở ô trái-dưới
        self.b = cv2.imread(os.path.join(ANH, "vong_quay_b.jpg"))  # tướng hạn định trên-trái + rương trái-dưới
        self.c = self.a.copy()  # không có ô hạn định: lấy ô thường đè lên ô tướng hạn định
        x, y = doi(*_O["trai_duoi"])
        self.c[int(y):int(y) + o_anh(self.a, "phai_tren").shape[0], int(x):int(x) + o_anh(self.a, "phai_tren").shape[1]] = \
            o_anh(self.a, "phai_tren")
        self.xu, self.vong = xu, vong
        self.tao_moi = list(tao_moi)  # các vòng lần lượt hiện ra khi bấm Tạo mới
        self.ket_qua = list(ket_qua)  # kết quả từng lần bấm x10: ("vong", "ô") hoặc None
        self.popup = None
        self.popup_con = 0
        self.so_x10 = 0
        self.so_tao_moi = 0

    def anh_vong(self):
        return {"A": self.a, "B": self.b, "C": self.c}[self.vong]

    def screenshot(self):
        img = self.anh_vong().copy()
        img[548:600, 269:442] = (30, 20, 40)
        cv2.putText(img, str(self.xu), (290, 584), cv2.FONT_HERSHEY_SIMPLEX, 0.95, (60, 230, 60), 3)
        if self.popup_con > 0:  # món trúng hiện to giữa màn hình, nền tối
            self.popup_con -= 1
            img = (img * 0.35).astype(np.uint8)
            if self.popup is not None:
                p = cv2.resize(self.popup, None, fx=2.2, fy=2.2)
                y0, x0 = 360 - p.shape[0] // 2, 640 - p.shape[1] // 2
                img[y0:y0 + p.shape[0], x0:x0 + p.shape[1]] = p
        return img

    def tap(self, x, y):
        if self.popup_con > 0:
            return
        bx, by = doi(1163, 1070)
        if abs(x - bx) < 70 and abs(y - by) < 25:  # Khởi động 10 lần
            self.so_x10 += 1
            self.xu -= 480
            kq = self.ket_qua.pop(0) if self.ket_qua else None
            self.popup = o_anh({"A": self.a, "B": self.b, "C": self.c}[kq[0]], kq[1]) if kq else o_anh(self.a, "duoi_trai")
            self.popup_con = 3
            return
        tx, ty = doi(996, 690)
        if abs(x - tx) < 50 and abs(y - ty) < 40:  # Tạo mới
            self.so_tao_moi += 1
            self.xu -= 1
            if self.tao_moi:
                self.vong = self.tao_moi.pop(0)

    def swipe(self, *a):
        pass

    def back(self):
        pass


class NhanhVQ(VongQuayBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.003))


@unittest.skipUnless(co_ocr(), "cần bộ đọc chữ rapidocr_onnxruntime")
class TestVongQuay(unittest.TestCase):
    def chay(self, g, dem, toi_da):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = copy.deepcopy(json.load(f))
        cfg["vong_quay"] = {"dem": dem, "moc": 73, "xu_toi_thieu": 0, "tao_moi_toi_da": 10, "dung_khi_trung": False,
                            "toi_da_bam": toi_da, "cho_ket_qua": 1.0, "cho_tao_moi": 0.05}
        q = queue.Queue()
        b = NhanhVQ(g, cfg, Templates(os.path.join(GOC, "mau")), q.put)
        b.start()
        b.join(300)
        self.assertFalse(b.is_alive())
        logs = [m[2] for m in list(q.queue) if m[0] == "log"]
        print("\n  " + "\n  ".join(logs))
        return cfg["vong_quay"], logs

    def test_toi_moc_73_tao_moi_ra_tuong(self):
        g = FakeVongQuay(vong="C", tao_moi=["C", "A"])
        vq, logs = self.chay(g, dem=70, toi_da=4)
        self.assertEqual(g.so_x10, 4)
        self.assertEqual(g.so_tao_moi, 2)  # C → C → A (có tướng hạn định) mới quay lần 73
        self.assertEqual(vq["dem"], 1)  # 71, 72, 73→0, 1

    def test_trung_tuong_han_dinh_ve_0(self):
        g = FakeVongQuay(vong="A", ket_qua=[None, ("A", "trai_duoi"), None])
        vq, logs = self.chay(g, dem=10, toi_da=3)
        self.assertEqual(vq["dem"], 1)  # 11, trúng → 0, 1
        self.assertTrue(any("trúng hạn định" in l for l in logs))
        self.assertEqual(g.so_tao_moi, 0)

    def test_trung_tuong_thuong_khong_ve_0(self):
        g = FakeVongQuay(vong="B", ket_qua=[("B", "phai_tren"), ("B", "tren_phai"), ("B", "duoi_trai")])
        vq, logs = self.chay(g, dem=20, toi_da=3)
        self.assertEqual(vq["dem"], 23)
        self.assertFalse(any("trúng hạn định" in l for l in logs))

    def test_dung_khi_xu_duoi_muc(self):
        g = FakeVongQuay(vong="A", xu=1500)
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = copy.deepcopy(json.load(f))
        cfg["vong_quay"] = {"dem": 0, "moc": 73, "xu_toi_thieu": 1000, "cho_ket_qua": 1.0}
        q = queue.Queue()
        b = NhanhVQ(g, cfg, Templates(os.path.join(GOC, "mau")), q.put)
        b.start()
        b.join(120)
        self.assertEqual(g.so_x10, 2)  # 1500 → 1020 → 540 < 1000 thì dừng


if __name__ == "__main__":
    unittest.main(verbosity=2)
