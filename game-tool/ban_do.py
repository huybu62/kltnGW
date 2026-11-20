"""Bản đồ lớn hơn màn hình: vuốt để di chuyển và theo dõi vị trí "camera".

Mỗi lần vuốt, tool so ảnh trước và sau để đo bản đồ đã dịch bao nhiêu điểm ảnh, kể cả khi
game kéo trớn. Vị trí khu được lưu theo toạ độ trên cả bản đồ, tính từ góc trên-trái và
đổi theo chiều rộng màn hình (xy_map). Mỗi lần chạy, tool vuốt về góc trên-trái để lấy mốc.
"""
import cv2
import numpy as np

# Tiêu đề popup khu so với tâm nút X, theo điểm ảnh của mẫu gốc (rộng 2000)
_TIEU_DE = (-761, 31, -276, 106)

# Các miếng ảnh dùng để đo độ dịch (tâm, theo tỉ lệ vùng game) và cỡ miếng
_MIENG = [(0.5, 0.5), (0.32, 0.4), (0.68, 0.6), (0.38, 0.66), (0.62, 0.34)]
_CO_MIENG = (0.2, 0.22)

# Vùng an toàn để chạm khu (tránh nút giao diện), theo tỉ lệ vùng game
AN_TOAN = (0.15, 0.18, 0.85, 0.78)


def cat_tieu_de(s, m_x):
    k = m_x.scale
    x0, y0 = m_x.x + int(_TIEU_DE[0] * k), m_x.y + int(_TIEU_DE[1] * k)
    x1, y1 = m_x.x + int(_TIEU_DE[2] * k), m_x.y + int(_TIEU_DE[3] * k)
    return s[max(0, y0):y1, max(0, x0):x1].copy()


def giong_nhau(a, b):
    if a is None or b is None or a.shape != b.shape or a.size == 0:
        return False
    # cùng một tiêu đề thì gần như trùng từng điểm ảnh; khác một chữ thôi cũng đủ phân biệt
    khac = (np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2) > 60).mean()
    return khac < 0.004


def do_lech(a, b, vung):
    """Nội dung bản đồ dịch (dx, dy) điểm ảnh từ ảnh a sang ảnh b. None nếu không đo chắc."""
    gx, gy, gw, gh = vung
    k = 0.5
    ga = cv2.resize(cv2.cvtColor(a[gy:gy + gh, gx:gx + gw], cv2.COLOR_BGR2GRAY), None, fx=k, fy=k,
                    interpolation=cv2.INTER_AREA)
    gb = cv2.resize(cv2.cvtColor(b[gy:gy + gh, gx:gx + gw], cv2.COLOR_BGR2GRAY), None, fx=k, fy=k,
                    interpolation=cv2.INTER_AREA)
    if ga.shape != gb.shape:
        return None
    h, w = ga.shape
    pw, ph = int(w * _CO_MIENG[0]), int(h * _CO_MIENG[1])
    kq = []
    for cx, cy in _MIENG:
        x0, y0 = int(cx * w - pw / 2), int(cy * h - ph / 2)
        mieng = ga[y0:y0 + ph, x0:x0 + pw]
        if mieng.std() < 8:  # vùng phẳng (nước, đường) không đo được
            continue
        res = cv2.matchTemplate(gb, mieng, cv2.TM_CCOEFF_NORMED)
        _, diem, _, (mx, my) = cv2.minMaxLoc(res)
        if diem > 0.75:
            kq.append(((mx - x0) / k, (my - y0) / k, diem))
    if not kq:
        return None
    # chọn độ dịch được nhiều miếng đồng ý nhất (miếng dính nhân vật đang động sẽ lệch)
    def dong_y(t):
        return sum(1 for u in kq if abs(u[0] - t[0]) <= 8 and abs(u[1] - t[1]) <= 8)

    tot = max(kq, key=lambda t: (dong_y(t), t[2]))
    if dong_y(tot) == 1 and len(kq) >= 3 and tot[2] < 0.9:
        return None
    return tot[0], tot[1]


class BanDoMixin:
    """Dùng chung cho SweepBot và DiscoverBot (cần self.device, self.templates, self.shot, self.sleep...)."""

    def _init_ban_do(self):
        self.cam = [0.0, 0.0]
        self.cam_ok = False  # đã lấy mốc góc trên-trái chưa
        self.map_cuon = False  # bản đồ có kéo được không

    def la_ban_do(self, s):
        return self.find(s, "cq_the_luc") is not None

    def vuot_camera(self, dx, dy, s_truoc=None):
        """Dời camera (dx, dy) điểm ảnh (dương = sang phải / xuống). Trả về (độ dời thật, ảnh mới)."""
        s_truoc = s_truoc if s_truoc is not None else self.shot()
        gx, gy, gw, gh = self.templates.vung(s_truoc)
        vx = -max(-0.3 * gw, min(0.3 * gw, dx))  # ngón tay đi ngược hướng camera
        vy = -max(-0.25 * gh, min(0.25 * gh, dy))
        cx, cy = gx + 0.5 * gw, gy + 0.5 * gh
        self.device.swipe(cx - vx / 2, cy - vy / 2, cx + vx / 2, cy + vy / 2, self.cq.get("toc_do_vuot_ms", 700))
        self.sleep(self.cq.get("toc_do_vuot_ms", 700) / 1000 + 0.5)
        # chờ bản đồ đứng yên (game có thể kéo trớn)
        s = self.shot()
        for _ in range(6):
            self.sleep(0.25)
            s2 = self.shot()
            d = do_lech(s, s2, self.templates.vung(s2))
            s = s2
            if d is None or (abs(d[0]) < 2 and abs(d[1]) < 2):
                break
        if not self.la_ban_do(s):
            # lỡ chạm mở popup → đóng, vị trí camera không còn chắc
            self.thoat_ve_ban_do(s)
            self.sleep(1.0)
            self.cam_ok = False
            return None, self.shot()
        d = do_lech(s_truoc, s, self.templates.vung(s))
        if d is None:
            self.cam_ok = False
            return None, s
        self.cam[0] -= d[0]
        self.cam[1] -= d[1]
        if abs(d[0]) > 3 or abs(d[1]) > 3:
            self.map_cuon = True
        return (-d[0], -d[1]), s

    def ve_goc(self):
        """Vuốt về góc trên-trái bản đồ và lấy làm mốc (0, 0)."""
        s = self.shot()
        for truc in (0, 1):
            for _ in range(15):
                gx, gy, gw, gh = self.templates.vung(s)
                dich, s = self.vuot_camera(-gw if truc == 0 else 0, -gh if truc == 1 else 0, s)
                if dich is not None and abs(dich[truc]) < 4:
                    break
        self.cam = [0.0, 0.0]
        self.cam_ok = True
        return s

    def sang_map(self, s, sx, sy):
        """Toạ độ màn hình → toạ độ trên cả bản đồ (theo chiều rộng vùng game)."""
        gx, gy, gw, gh = self.templates.vung(s)
        return (self.cam[0] + sx - gx) / gw, (self.cam[1] + sy - gy) / gw

    def ra_man_hinh(self, s, ax, ay):
        gx, gy, gw, gh = self.templates.vung(s)
        return gx + ax * gw - self.cam[0], gy + ay * gw - self.cam[1]

    def trong_vung_an_toan(self, s, x, y):
        gx, gy, gw, gh = self.templates.vung(s)
        fx, fy = (x - gx) / gw, (y - gy) / gh
        return AN_TOAN[0] <= fx <= AN_TOAN[2] and AN_TOAN[1] <= fy <= AN_TOAN[3]

    def toi_diem(self, s, ax, ay):
        """Vuốt cho điểm (ax, ay) trên bản đồ vào vùng an toàn. Trả về (x, y, ảnh) trên màn hình."""
        for _ in range(10):
            x, y = self.ra_man_hinh(s, ax, ay)
            if self.trong_vung_an_toan(s, x, y) or not self.cam_ok:
                return x, y, s
            gx, gy, gw, gh = self.templates.vung(s)
            dich, s = self.vuot_camera(x - (gx + 0.5 * gw), y - (gy + 0.48 * gh), s)
            if dich is None:
                return None
            if abs(dich[0]) < 3 and abs(dich[1]) < 3:
                return x, y, s  # đã tới mép bản đồ, chạm luôn
        x, y = self.ra_man_hinh(s, ax, ay)
        return x, y, s
