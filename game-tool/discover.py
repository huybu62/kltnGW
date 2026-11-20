"""Tự dò các khu càn quét trên CẢ bản đồ.

Tool vuốt về góc trên-trái, rồi lướt bản đồ theo hình chữ chi: hết một màn thì vuốt sang
màn bên cạnh, hết hàng thì xuống hàng dưới và đi ngược lại. Ở mỗi màn, tool chạm theo lưới,
bỏ qua những điểm đã chạm ở màn trước. Chỗ nào mở popup có nút Thám hiểm / Càn quét thì ghi
lại. Các điểm mở cùng một khu (cùng tiêu đề popup) được gộp, lấy điểm gần giữa nhất. Vị trí
khu lưu theo toạ độ trên cả bản đồ (xy_map), nên lúc quét tool tự vuốt tới đúng khu.
"""
import os

from ban_do import cat_tieu_de, giong_nhau
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
BUOC_X, BUOC_Y = 0.09, 0.11
TOI_DA_MAN = 40


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


class DiscoverBot(SweepBot):
    def kiem_tra_mau(self):
        thieu = [n for n in ("cq_the_luc", "cq_x_popup", "cq_nut_tham_hiem") if not self.templates.exists(n)]
        if thieu:
            self.log("Thiếu mẫu để dò khu: " + ", ".join(thieu))
            raise StopBot

    def ve_ban_do(self):
        for _ in range(4):
            s = self.shot()
            if self.la_ban_do(s):
                return s
            if not self.thoat_ve_ban_do(s):
                self.sleep(1.0)
            else:
                self.sleep(1.2)
        self.log("Không thấy bản đồ (thanh Thể lực). Hãy mở bản đồ khu rồi dò lại.")
        raise StopBot

    def sau_khi_cham(self):
        """Trả về ('popup', ảnh, nút X, có_càn_quét) / ('ban_do', ...) / ('la', ...)."""
        self.sleep(0.7)
        for lan in range(4):
            s = self.shot()
            m_x = self.find(s, "cq_x_popup")
            if m_x and self.find(s, "cq_nut_tham_hiem"):
                return "popup", s, m_x, bool(self.find(s, "cq_nut_can_quet"))
            if self.la_ban_do(s) and lan >= 1:
                return "ban_do", s, None, False
            self.sleep(0.4)
        return "la", s, None, False

    def loop(self):
        self.emit(("khu_moi", self.device.serial, self.do_ca_ban_do()))

    def do_ca_ban_do(self, tien_to=""):
        """Dò hết bản đồ hiện tại, trả về danh sách khu (ảnh tiêu đề lưu với tên tien_to + khu_j.png)."""
        s = self.ve_ban_do()
        cuon = self.cq.get("cuon_map", True)
        if cuon:
            self.log("🔎 Vuốt về góc trên-trái bản đồ...")
            s = self.ve_goc()
        else:
            self.cam, self.cam_ok = [0.0, 0.0], True
        self.tim = []  # {"tieu_de": ảnh, "diem": [(ax, ay)], "can_quet": bool}
        self.da_cham = []  # các điểm (ax, ay) đã chạm, theo toạ độ bản đồ
        luoi = luoi_diem()
        huong, so_man = 1, 0
        while so_man < TOI_DA_MAN:
            so_man += 1
            s = self.do_mot_man(s, luoi, so_man)
            if not cuon:
                break
            if not self.cam_ok:
                self.log("  Mất vị trí bản đồ → dừng dò, giữ các khu đã tìm được")
                break
            gx, gy, gw, gh = self.templates.vung(s)
            # sang màn bên cạnh trong cùng hàng
            dich, s = self.vuot_camera(huong * 0.6 * gw, 0, s)
            if dich is not None and abs(dich[0]) > 0.1 * gw:
                continue
            # hết hàng → xuống hàng dưới, đổi chiều
            dich, s = self.vuot_camera(0, 0.6 * gh, s)
            if dich is None or abs(dich[1]) < 0.1 * gh:
                break
            huong = -huong
        if not self.map_cuon and cuon:
            self.log("  (Bản đồ không kéo được, chỉ có 1 màn)")
        return self.xong(tien_to)

    def do_mot_man(self, s, luoi, so_man):
        gx, gy, gw, gh = self.templates.vung(s)
        can_cham = []
        for fx, fy in luoi:
            ax, ay = self.sang_map(s, gx + fx * gw, gy + fy * gh)
            gan = any(abs(ax - bx) < BUOC_X * 0.5 and abs(ay - by) < BUOC_Y * 0.5 * gh / gw
                      for bx, by in self.da_cham)
            if not gan:
                can_cham.append((fx, fy, ax, ay))
        self.log(f"🔎 Màn {so_man}: chạm {len(can_cham)} điểm (đã có {len(self.tim)} khu)")
        for i, (fx, fy, ax, ay) in enumerate(can_cham, 1):
            self.da_cham.append((ax, ay))
            self.tap(gx + fx * gw, gy + fy * gh)
            kieu, s2, m_x, co_cq = self.sau_khi_cham()
            if kieu == "popup":
                td = cat_tieu_de(s2, m_x)
                cu = next((t for t in self.tim if giong_nhau(t["tieu_de"], td)), None)
                if cu is None:
                    cu = {"tieu_de": td, "diem": [], "can_quet": co_cq}
                    self.tim.append(cu)
                    self.log(f"  + Khu {len(self.tim)}" + ("" if co_cq else " (chưa có nút Càn quét)"))
                cu["diem"].append((round(ax, 4), round(ay, 4)))
                self.tap_match(m_x)
                self.sleep(0.8)
                self.ve_ban_do()
            elif kieu == "la":
                self.log(f"  Điểm [{fx}, {fy}] mở màn lạ → thử quay lại")
                if not self.thoat_ve_ban_do(s2):
                    self.device.back()
                self.sleep(1.5)
                self.ve_ban_do()
            self.emit(("stats", self.device.serial,
                       {"do": f"màn {so_man} {i}/{len(can_cham)}", "khu": len(self.tim)}))
        return self.ve_ban_do()

    def xong(self, tien_to=""):
        ket_qua = []
        thu_muc = os.path.join(self.templates.folder, "tieu_de_khu")
        os.makedirs(thu_muc, exist_ok=True)
        for j, t in enumerate(self.tim, 1):
            ds = t["diem"]
            cx = sum(p[0] for p in ds) / len(ds)
            cy = sum(p[1] for p in ds) / len(ds)
            ax, ay = min(ds, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)  # điểm thật gần giữa nhất
            ten_anh = f"{tien_to}khu_{j}.png"
            ghi_anh(os.path.join(thu_muc, ten_anh), t["tieu_de"])
            ten = f"Khu {j}" + ("" if t["can_quet"] else " (chưa quét được)")
            ket_qua.append({"ten": ten, "bat": t["can_quet"], "xy_map": [ax, ay], "tieu_de": ten_anh})
        self.log(f"✔ Dò xong: {len(ket_qua)} khu. Ảnh tiêu đề từng khu ở mau/tieu_de_khu/")
        return ket_qua
