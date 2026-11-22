"""Kiểm tra tự dò khu trên ảnh bản đồ thật, với 3 khu giả có tiêu đề popup khác nhau.
Chạy: python test_discover.py
"""
import json
import os
import queue
import tempfile
import unittest

import cv2

from discover import DiscoverBot
from matcher import Templates
from test_sweep import ANH, GOC, HOP_CONG_XUONG, HOP_X_POPUP, trong

# (hộp trên ảnh gốc 2000 px, tiêu đề popup, có nút Càn quét không)
KHU = [
    (HOP_CONG_XUONG, "Cong xuong", True),
    ((260, 240, 760, 560), "Nha tho", True),       # nhà thờ mái cam
    ((840, 920, 1220, 1090), "Bai xe", False),     # bãi xe: chưa mở càn quét
]


class FakeMap:
    serial = "fake"

    def __init__(self):
        self.anh = {n: cv2.imread(os.path.join(ANH, f"{n}.jpg")) for n in ("ban_do", "popup_khu")}
        self.man = "ban_do"
        self.mo = None
        self.so_cham = 0

    def screenshot(self):
        if self.man == "ban_do":
            return self.anh["ban_do"]
        img = self.anh["popup_khu"].copy()
        hop, ten, co_cq = self.mo
        img[78:120, 395:700] = (20, 40, 70)  # xoá tiêu đề cũ
        cv2.putText(img, ten, (400, 112), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (40, 230, 240), 2)
        if not co_cq:
            img[590:655, 710:860] = (25, 45, 75)  # che nút Càn quét
        return img

    def tap(self, x, y):
        self.so_cham += 1
        if self.man == "ban_do":
            for k in KHU:
                if trong(x, y, k[0]):
                    self.man, self.mo = "popup", k
                    return
        elif trong(x, y, HOP_X_POPUP):
            self.man = "ban_do"

    def back(self):
        self.man = "ban_do"

    def swipe(self, *a):
        pass  # bản đồ này không kéo được


class NhanhDiscover(DiscoverBot):
    def sleep(self, giay):
        super().sleep(min(giay, 0.01))


class TestDiscover(unittest.TestCase):
    def test_do_khu(self):
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = json.load(f)
        cfg["can_quet"]["tu_dong_tham_hiem"] = False  # khu chưa thám hiểm thì để tắt
        with tempfile.TemporaryDirectory() as tmp:
            # chép mẫu sang thư mục tạm để ảnh tiêu đề khu không ghi vào mau/
            for f in os.listdir(os.path.join(GOC, "mau")):
                p = os.path.join(GOC, "mau", f)
                if os.path.isfile(p):
                    with open(p, "rb") as a, open(os.path.join(tmp, f), "wb") as b:
                        b.write(a.read())
            q = queue.Queue()
            g = FakeMap()
            b = NhanhDiscover(g, cfg, Templates(tmp), q.put)
            b.start()
            b.join(120)
            self.assertFalse(b.is_alive())
            msgs = list(q.queue)
            print("\n  " + " | ".join(m[2] for m in msgs if m[0] == "log")[-400:])
            ds = next(m[2] for m in msgs if m[0] == "khu_moi")
            self.assertEqual(len(ds), 3, ds)
            self.assertEqual([k["bat"] for k in ds], [True, True, False])
            self.assertEqual(len(os.listdir(os.path.join(tmp, "tieu_de_khu"))), 3)
            # điểm chạm của mỗi khu phải nằm trong đúng khu đó
            for khu in ds:  # bản đồ không kéo: toạ độ bản đồ = toạ độ màn hình / chiều rộng
                x, y = khu["xy_map"][0] * 1280, khu["xy_map"][1] * 1280
                self.assertTrue(any(trong(x, y, k[0]) for k in KHU), khu)
            print(f"  {g.so_cham} lần chạm, khu: {ds}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
