"""Kiểm tra lướt bản đồ lớn: dò khu trên cả bản đồ rồi vuốt tới từng khu để càn quét.
Bản đồ giả rộng gấp đôi màn hình, ghép từ ảnh bản đồ thật; vuốt có kéo trớn 15%.
Chạy: python test_ban_do.py
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

from discover import DiscoverBot
from matcher import Templates
from sweep import SweepBot
from test_sweep import ANH, GOC, HOP_CAN_QUET, HOP_DONG, HOP_LAN_NUA, HOP_X_POPUP, trong

W, H = 1280, 720
TREN, DUOI = 110, 590  # phần ảnh bản đồ thật không dính giao diện, dùng để ghép bản đồ lớn
# Các nút giao diện cố định trên màn hình (x1, y1, x2, y2), giống game thật
HUD = [(35, 10, 150, 100), (250, 12, 780, 60), (40, 590, 180, 720), (720, 600, 1100, 720)]

# Khu trên bản đồ lớn (x1, y1, x2, y2), tiêu đề popup
KHU = [
    ((200, 150, 430, 330), "Trai linh"),
    ((1950, 180, 2200, 380), "Ben cang"),
    ((1150, 640, 1400, 820), "Cong vien"),
    ((300, 1120, 560, 1300), "Nha may"),
    ((2150, 1180, 2420, 1380), "Thap nuoc"),
]


def tao_ban_do_lon():
    a = cv2.imread(os.path.join(ANH, "ban_do.jpg"))[TREN:DUOI]  # 480 dòng, không có giao diện
    hang0 = np.hstack([a, a[:, ::-1]])
    hang1 = np.hstack([a[::-1], a[::-1, ::-1]])
    c = cv2.imread(os.path.join(ANH, "chuong.jpg"))[TREN:DUOI]  # hàng dưới: ảnh khác cho đỡ lặp
    hang2 = np.hstack([c, c[:, ::-1]])
    return np.vstack([hang0, hang1, hang2])  # 2560 × 1440


class FakeScrollGame:
    serial = "fake"

    def __init__(self, cam=(700, 400), luot=3, khu=None, lon=None):
        self.khu = khu if khu is not None else KHU
        self.lon = lon if lon is not None else tao_ban_do_lon()
        self.hud = cv2.imread(os.path.join(ANH, "ban_do.jpg"))
        self.anh_popup = cv2.imread(os.path.join(ANH, "popup_khu.jpg"))
        self.anh_kq = cv2.imread(os.path.join(ANH, "ket_qua.jpg"))
        self.cx, self.cy = cam
        self.man = "ban_do"
        self.mo = None
        self.luot = {k[1]: luot for k in self.khu}
        self.lich_su = []
        self.so_vuot = 0

    def _kep(self):
        self.cx = int(max(0, min(self.lon.shape[1] - W, self.cx)))
        self.cy = int(max(0, min(self.lon.shape[0] - H, self.cy)))

    def screenshot(self):
        if self.man == "ban_do":
            img = self.lon[self.cy:self.cy + H, self.cx:self.cx + W].copy()
            for x1, y1, x2, y2 in HUD:
                img[y1:y2, x1:x2] = self.hud[y1:y2, x1:x2]
            img[21:47, 577:765] = (0, 129, 255)  # thể lực đầy
            return img
        if self.man == "popup":
            img = self.anh_popup.copy()
            img[78:120, 395:700] = (20, 40, 70)
            cv2.putText(img, self.mo, (400, 112), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (40, 230, 240), 2)
            return img
        img = self.anh_kq.copy()
        cv2.putText(img, str(len(self.lich_su)), (1080, 435), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 255, 0), 2)
        return img

    def quet(self):
        if self.luot[self.mo] <= 0:
            return False
        self.luot[self.mo] -= 1
        self.lich_su.append(self.mo)
        return True

    def tap(self, x, y):
        if self.man == "ban_do":
            if any(x1 <= x <= x2 and y1 <= y <= y2 for x1, y1, x2, y2 in HUD):
                return
            bx, by = x + self.cx, y + self.cy
            for (x1, y1, x2, y2), ten in self.khu:
                if x1 <= bx <= x2 and y1 <= by <= y2:
                    self.man, self.mo = "popup", ten
                    return
        elif self.man == "popup":
            if trong(x, y, HOP_CAN_QUET) and self.quet():
                self.man = "ket_qua"
            elif trong(x, y, HOP_X_POPUP):
                self.man = "ban_do"
        else:
            if trong(x, y, HOP_LAN_NUA):
                self.quet()
            elif trong(x, y, HOP_DONG):
                self.man = "ban_do"

    def swipe(self, x1, y1, x2, y2, ms=700):
        if self.man != "ban_do":
            return
        self.so_vuot += 1
        self.cx -= (x2 - x1) * 1.15  # nội dung đi theo ngón tay, có kéo trớn
        self.cy -= (y2 - y1) * 1.15
        self._kep()

    def back(self):
        self.man = "ban_do"


class Nhanh:
    def sleep(self, giay):
        super().sleep(min(giay, 0.003))

    def cho_bam(self, ev, giay):
        return ev.wait(min(giay, 0.005))


class NhanhDiscover(Nhanh, DiscoverBot):
    pass


class NhanhSweep(Nhanh, SweepBot):
    pass


class TestBanDo(unittest.TestCase):
    def test_do_va_quet_ca_ban_do(self):
        self._chay(tao_ban_do_lon(), dich=(0, 0))

    def test_ban_do_hinh_thoi_vien_den(self):
        # bản đồ hình thoi (góc đen) và game cho kéo lố ra vùng đen 600 điểm ảnh
        lon = tao_ban_do_lon()
        h, w = lon.shape[:2]
        mat_na = np.zeros((h, w), np.uint8)
        cv2.fillPoly(mat_na, [np.array([[w // 2, -400], [w + 600, h // 2], [w // 2, h + 400], [-600, h // 2]])], 1)
        lon = cv2.copyMakeBorder(lon * mat_na[..., None], 600, 0, 600, 0, cv2.BORDER_CONSTANT, value=(0, 0, 0))
        self._chay(lon, dich=(600, 600))

    def _chay(self, lon, dich):
        khu = [((x1 + dich[0], y1 + dich[1], x2 + dich[0], y2 + dich[1]), ten) for (x1, y1, x2, y2), ten in KHU]
        with open(os.path.join(GOC, "config.json"), encoding="utf-8") as f:
            cfg = json.load(f)
        tmp = tempfile.mkdtemp()
        try:
            for f in os.listdir(os.path.join(GOC, "mau")):
                p = os.path.join(GOC, "mau", f)
                if os.path.isfile(p):
                    shutil.copy(p, tmp)
            tpl = Templates(tmp)

            # 1) Dò khu, bắt đầu ở giữa bản đồ
            g = FakeScrollGame(cam=(700 + dich[0], 400 + dich[1]), khu=khu, lon=lon)
            q = queue.Queue()
            b = NhanhDiscover(g, cfg, tpl, q.put)
            goc = {}
            ve_goc_cu = b.ve_goc

            def ve_goc_ghi():  # ghi lại camera thật lúc tool lấy gốc (0, 0)
                kq = ve_goc_cu()
                goc["xy"] = (g.cx, g.cy)
                return kq

            b.ve_goc = ve_goc_ghi
            b.start()
            b.join(600)
            self.assertFalse(b.is_alive())
            msgs = list(q.queue)
            logs = [m[2] for m in msgs if m[0] == "log"]
            print("\n  " + "\n  ".join(l for l in logs if "Màn" in l or "Khu" in l or "✔" in l or "Mất" in l))
            ds, moc = next((m[2], m[3]) for m in msgs if m[0] == "khu_moi")
            self.assertEqual(len(ds), len(KHU), ds)
            print(f"  dò: {g.so_vuot} lần vuốt; khu = {[k['xy_map'] for k in ds]}")

            # toạ độ bản đồ phải trỏ đúng vào khu (đổi ra điểm ảnh bản đồ lớn)
            ox, oy = goc["xy"]
            for k in ds:
                bx, by = k["xy_map"][0] * W + ox, k["xy_map"][1] * W + oy
                self.assertTrue(any(x1 <= bx <= x2 and y1 <= by <= y2 for (x1, y1, x2, y2), _ in khu), (k, bx, by))

            # 2) Quét: camera đã bị người dùng kéo đi chỗ khác
            cfg2 = copy.deepcopy(cfg)
            cfg2["can_quet"]["khu"] = ds
            cfg2["can_quet"]["moc"] = moc  # như overlay lưu sau khi dò
            g2 = FakeScrollGame(cam=(1100 + dich[0], 150 + dich[1]), luot=3, khu=khu, lon=lon)
            q2 = queue.Queue()
            b2 = NhanhSweep(g2, cfg2, tpl, q2.put)
            b2.start()
            b2.join(600)
            self.assertFalse(b2.is_alive())
            logs2 = [m[2] for m in list(q2.queue) if m[0] == "log"]
            print("  quét: " + " | ".join(logs2[-3:]))
            self.assertEqual(sorted(g2.lich_su), sorted([k[1] for k in KHU] * 3), g2.lich_su)
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
