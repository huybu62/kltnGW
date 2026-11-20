"""Tự dò các khu càn quét trên bản đồ: chạm lần lượt theo lưới, chỗ nào mở popup có nút
Thám hiểm / Càn quét thì ghi lại. Các điểm mở cùng một khu (cùng tiêu đề popup) được gộp,
lấy điểm giữa làm chỗ chạm.
"""
import os

import cv2
import numpy as np

from bot import StopBot
from matcher import ghi_anh
from sweep import SweepBot

# Vùng có nút giao diện, không chạm khi dò (tỉ lệ vùng game: x1, y1, x2, y2)
VUNG_BO = [
    (0.00, 0.00, 0.14, 0.17),  # Trở lại
    (0.17, 0.00, 0.64, 0.09),  # thanh EXP / thể lực
    (0.00, 0.78, 0.16, 1.00),  # Điểm thu hồi
    (0.55, 0.82, 0.87, 1.00),  # Trang bị / Đồng đội / Trận hình
]
BUOC_X, BUOC_Y = 0.075, 0.09

# Tiêu đề popup so với tâm nút X, theo điểm ảnh của mẫu gốc (rộng 2000)
_TIEU_DE = (-761, 31, -276, 106)


def luoi_diem():
    ds = []
    fy = 0.06
    while fy < 0.97:
        fx = 0.04
        while fx < 0.98:
            if not any(x1 <= fx <= x2 and y1 <= fy <= y2 for x1, y1, x2, y2 in VUNG_BO):
                ds.append((round(fx, 4), round(fy, 4)))
            fx += BUOC_X
        fy += BUOC_Y
    return ds


def cat_tieu_de(s, m_x):
    k = m_x.scale
    x0, y0 = m_x.x + int(_TIEU_DE[0] * k), m_x.y + int(_TIEU_DE[1] * k)
    x1, y1 = m_x.x + int(_TIEU_DE[2] * k), m_x.y + int(_TIEU_DE[3] * k)
    return s[max(0, y0):y1, max(0, x0):x1].copy()


def giong_nhau(a, b):
    if a.shape != b.shape or a.size == 0:
        return False
    diem = cv2.matchTemplate(a, b, cv2.TM_CCOEFF_NORMED)[0][0]
    return diem > 0.9 or np.abs(a.astype(np.int16) - b.astype(np.int16)).mean() < 6


class DiscoverBot(SweepBot):
    def kiem_tra_mau(self):
        thieu = [n for n in ("cq_the_luc", "cq_x_popup", "cq_nut_tham_hiem") if not self.templates.exists(n)]
        if thieu:
            self.log("Thiếu mẫu để dò khu: " + ", ".join(thieu))
            raise StopBot

    def ve_ban_do(self):
        for _ in range(4):
            s = self.shot()
            if self.find(s, "cq_the_luc"):
                return s
            if not self.thoat_ve_ban_do(s):
                self.sleep(1.0)
            else:
                self.sleep(1.2)
        self.log("Không thấy bản đồ (thanh Thể lực). Hãy mở bản đồ khu rồi dò lại.")
        raise StopBot

    def sau_khi_cham(self):
        """Trả về ('popup', ảnh, nút X, có_càn_quét) / ('ban_do', ...) / ('la', ...)."""
        self.sleep(0.9)
        for lan in range(4):
            s = self.shot()
            m_x = self.find(s, "cq_x_popup")
            if m_x and self.find(s, "cq_nut_tham_hiem"):
                return "popup", s, m_x, bool(self.find(s, "cq_nut_can_quet"))
            if self.find(s, "cq_the_luc"):
                if lan >= 1:
                    return "ban_do", s, None, False
            self.sleep(0.5)
        return "la", s, None, False

    def loop(self):
        s = self.ve_ban_do()
        gx, gy, gw, gh = self.templates.vung(s)
        diem = luoi_diem()
        self.log(f"🔎 Dò {len(diem)} điểm trên bản đồ (khoảng {len(diem) * 2 // 60 + 1} phút)...")
        tim = []  # {"tieu_de": ảnh, "diem": [(fx, fy)], "can_quet": bool}
        for i, (fx, fy) in enumerate(diem, 1):
            self.tap(gx + fx * gw, gy + fy * gh)
            kieu, s, m_x, co_cq = self.sau_khi_cham()
            if kieu == "popup":
                td = cat_tieu_de(s, m_x)
                cu = next((t for t in tim if giong_nhau(t["tieu_de"], td)), None)
                if cu is None:
                    cu = {"tieu_de": td, "diem": [], "can_quet": co_cq}
                    tim.append(cu)
                    self.log(f"  + Khu {len(tim)} tại [{fx}, {fy}]" + ("" if co_cq else " (chưa có nút Càn quét)"))
                cu["diem"].append((fx, fy))
                self.tap_match(m_x)
                self.sleep(0.8)
                self.ve_ban_do()
            elif kieu == "la":
                self.log(f"  Điểm [{fx}, {fy}] mở màn lạ → thử quay lại")
                if not self.thoat_ve_ban_do(s):
                    self.device.back()
                self.sleep(1.5)
                self.ve_ban_do()
            self.emit(("stats", self.device.serial, {"do": f"{i}/{len(diem)}", "khu": len(tim)}))

        ket_qua = []
        thu_muc = os.path.join(self.templates.folder, "tieu_de_khu")
        os.makedirs(thu_muc, exist_ok=True)
        for j, t in enumerate(tim, 1):
            fx, fy = self.diem_giua(t, gx, gy, gw, gh)
            ghi_anh(os.path.join(thu_muc, f"khu_{j}.png"), t["tieu_de"])
            ten = f"Khu {j}" + ("" if t["can_quet"] else " (chưa quét được)")
            ket_qua.append({"ten": ten, "bat": t["can_quet"], "xy": [fx, fy]})
        self.log(f"✔ Dò xong: {len(ket_qua)} khu. Ảnh tiêu đề từng khu ở mau/tieu_de_khu/")
        self.emit(("khu_moi", self.device.serial, ket_qua))

    def diem_giua(self, t, gx, gy, gw, gh):
        """Điểm giữa các điểm đã mở khu; kiểm tra lại, sai thì dùng điểm đầu tiên."""
        ds = t["diem"]
        if len(ds) == 1:
            return ds[0]
        cx = round(sum(p[0] for p in ds) / len(ds), 4)
        cy = round(sum(p[1] for p in ds) / len(ds), 4)
        self.tap(gx + cx * gw, gy + cy * gh)
        kieu, s, m_x, _ = self.sau_khi_cham()
        dung = kieu == "popup" and giong_nhau(t["tieu_de"], cat_tieu_de(s, m_x))
        if kieu == "popup":
            self.tap_match(m_x)
            self.sleep(0.8)
        self.ve_ban_do()
        if dung:
            return cx, cy
        # chọn điểm gần điểm giữa nhất
        return min(ds, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
