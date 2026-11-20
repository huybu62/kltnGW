"""Bản đồ lớn hơn màn hình: vuốt để di chuyển và biết mình đang ở đâu trên bản đồ.

- Mỗi lần vuốt, tool so ảnh trước/sau (ở những chỗ có nhiều chi tiết) để đo bản đồ đã dịch
  bao nhiêu, kể cả khi game kéo trớn.
- Lúc dò, mỗi màn tool lưu một "mốc" (mảnh ảnh bản đồ nhiều chi tiết, kèm toạ độ). Lúc quét,
  tool tìm các mốc trên màn hình để biết chính xác vị trí, nên không phụ thuộc kéo về góc và
  tự sửa sai lệch sau mỗi lần vuốt.
- Không kéo vào vùng đen ngoài mép bản đồ: phần sắp hiện ra mà gần như đen thì coi là mép.
Toạ độ trên bản đồ (xy_map) tính theo chiều rộng vùng game.
"""
import os

import cv2
import numpy as np

# Tiêu đề popup khu so với tâm nút X, theo điểm ảnh của mẫu gốc (rộng 2000)
_TIEU_DE = (-761, 31, -276, 106)

_K = 0.5  # thu nhỏ ảnh khi so để nhanh hơn
_CO_MIENG = (0.18, 0.2)  # cỡ miếng ảnh dùng đo/làm mốc, theo tỉ lệ vùng game
_TOI = 30  # điểm ảnh có mọi kênh màu < 30 coi là "đen"

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


def xam_nho(img):
    return cv2.resize(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), None, fx=_K, fy=_K, interpolation=cv2.INTER_AREA)


def _cat_game(s, vung):
    gx, gy, gw, gh = vung
    return s[gy:gy + gh, gx:gx + gw]


def chon_mieng(g, so=6, vung_x=(0.12, 0.88), vung_y=(0.18, 0.82)):
    """Những miếng có nhiều chi tiết nhất (độ lệch chuẩn cao, ít vùng đen) trên ảnh xám g."""
    h, w = g.shape
    pw, ph = int(w * _CO_MIENG[0]), int(h * _CO_MIENG[1])
    ung_vien = []
    for cx in np.linspace(vung_x[0] + _CO_MIENG[0] / 2, vung_x[1] - _CO_MIENG[0] / 2, 5):
        for cy in np.linspace(vung_y[0] + _CO_MIENG[1] / 2, vung_y[1] - _CO_MIENG[1] / 2, 4):
            x0, y0 = int(cx * w - pw / 2), int(cy * h - ph / 2)
            m = g[y0:y0 + ph, x0:x0 + pw]
            if (m < _TOI).mean() > 0.25:
                continue
            ung_vien.append((float(m.std()), x0, y0))
    ung_vien.sort(reverse=True)
    return [(x0, y0, pw, ph) for sd, x0, y0 in ung_vien[:so] if sd >= 10]


def do_lech(a, b, vung):
    """Nội dung bản đồ dịch (dx, dy) điểm ảnh từ ảnh a sang ảnh b. None nếu không đo chắc."""
    ga, gb = xam_nho(_cat_game(a, vung)), xam_nho(_cat_game(b, vung))
    if ga.shape != gb.shape:
        return None
    kq = []
    for x0, y0, pw, ph in chon_mieng(ga):
        res = cv2.matchTemplate(gb, ga[y0:y0 + ph, x0:x0 + pw], cv2.TM_CCOEFF_NORMED)
        _, diem, _, (mx, my) = cv2.minMaxLoc(res)
        if diem > 0.75:
            kq.append(((mx - x0) / _K, (my - y0) / _K, diem))
    if not kq:
        return None

    # chọn độ dịch được nhiều miếng đồng ý nhất (miếng dính nhân vật đang động sẽ lệch)
    def dong_y(t):
        return sum(1 for u in kq if abs(u[0] - t[0]) <= 8 and abs(u[1] - t[1]) <= 8)

    tot = max(kq, key=lambda t: (dong_y(t), t[2]))
    if dong_y(tot) == 1 and len(kq) >= 3 and tot[2] < 0.9:
        return None
    return tot[0], tot[1]


def ti_le_den(s, vung, phia=None, be_rong=0.25):
    """Tỉ lệ điểm ảnh đen trong vùng game, hoặc trong dải sát một phía (trai/phai/tren/duoi)."""
    g = _cat_game(s, vung)[::2, ::2]
    h, w = g.shape[:2]
    if phia == "trai":
        g = g[:, :int(w * be_rong)]
    elif phia == "phai":
        g = g[:, w - int(w * be_rong):]
    elif phia == "tren":
        g = g[:int(h * be_rong)]
    elif phia == "duoi":
        g = g[h - int(h * be_rong):]
    return float((g.max(axis=2) < _TOI).mean())


class BanDoMixin:
    """Dùng chung cho SweepBot và DiscoverBot (cần self.device, self.templates, self.shot, self.sleep...)."""

    def _init_ban_do(self):
        self.cam = [0.0, 0.0]
        self.cam_ok = False  # đã biết vị trí trên bản đồ chưa
        self.map_cuon = False  # bản đồ có kéo được không
        if not hasattr(self, "_anh_moc"):
            self._anh_moc = {}  # tên file mốc → ảnh xám thu nhỏ

    def ds_moc(self):
        return []

    def thu_muc_moc(self):
        return os.path.join(self.templates.folder, "moc")

    def la_ban_do(self, s):
        return self.find(s, "cq_the_luc") is not None

    def mep(self, s, phia):
        """Phía này đã là mép bản đồ (dải sát mép gần như toàn đen)?"""
        return ti_le_den(s, self.templates.vung(s), phia) > 0.75

    # ---------- mốc ----------
    def _anh_cua_moc(self, moc):
        ten = moc["anh"]
        if ten not in self._anh_moc:
            p = os.path.join(self.thu_muc_moc(), ten)
            img = cv2.imdecode(np.fromfile(p, dtype=np.uint8), cv2.IMREAD_COLOR) if os.path.isfile(p) else None
            self._anh_moc[ten] = xam_nho(img) if img is not None else None
        return self._anh_moc[ten]

    def dinh_vi_nhanh(self, s):
        """Tìm các mốc đang hiện trên màn hình để biết vị trí camera. True nếu tìm được."""
        ds = self.ds_moc()
        if not ds:
            return False
        vung = self.templates.vung(s)
        gx, gy, gw, gh = vung
        g = xam_nho(_cat_game(s, vung))
        uoc = []
        for moc in ds:
            m = self._anh_cua_moc(moc)
            if m is None or m.shape[0] > g.shape[0] or m.shape[1] > g.shape[1]:
                continue
            _, diem, _, (mx, my) = cv2.minMaxLoc(cv2.matchTemplate(g, m, cv2.TM_CCOEFF_NORMED))
            if diem > 0.88:
                sx, sy = (mx + m.shape[1] / 2) / _K, (my + m.shape[0] / 2) / _K  # tâm mốc trên màn (trong vùng game)
                uoc.append((moc["xy"][0] * gw - sx, moc["xy"][1] * gw - sy, diem))
        if not uoc:
            return False
        if self.cam_ok:  # ưu tiên ước lượng gần vị trí đang theo dõi (tránh khớp nhầm chỗ giống nhau)
            gan = [u for u in uoc if abs(u[0] - self.cam[0]) < 0.6 * gw and abs(u[1] - self.cam[1]) < 0.6 * gh]
            uoc = gan or uoc

        def dong_y(t):
            return sum(1 for u in uoc if abs(u[0] - t[0]) <= 0.02 * gw and abs(u[1] - t[1]) <= 0.02 * gw)

        tot = max(uoc, key=lambda t: (dong_y(t), t[2]))
        self.cam = [tot[0], tot[1]]
        self.cam_ok = True
        return True

    def tao_moc(self, s, ten_anh):
        """Cắt một mốc ở giữa màn hình hiện tại. Trả về (dict mốc, ảnh màu) hoặc None."""
        vung = self.templates.vung(s)
        gx, gy, gw, gh = vung
        g = xam_nho(_cat_game(s, vung))
        ds = chon_mieng(g, so=1, vung_x=(0.25, 0.75), vung_y=(0.25, 0.75)) or chon_mieng(g, so=1)
        if not ds:
            return None
        x0, y0, pw, ph = ds[0]
        X0, Y0, PW, PH = int(x0 / _K), int(y0 / _K), int(pw / _K), int(ph / _K)
        mau = _cat_game(s, vung)[Y0:Y0 + PH, X0:X0 + PW].copy()
        ax, ay = self.sang_map(s, gx + X0 + PW / 2, gy + Y0 + PH / 2)
        self._anh_moc[ten_anh] = xam_nho(mau)
        return {"anh": ten_anh, "xy": [round(ax, 4), round(ay, 4)]}, mau

    # ---------- vuốt ----------
    def vuot_camera(self, dx, dy, s_truoc=None):
        """Dời camera (dx, dy) điểm ảnh (dương = sang phải / xuống). Trả về (độ dời thật, ảnh mới)."""
        s_truoc = s_truoc if s_truoc is not None else self.shot()
        vung = self.templates.vung(s_truoc)
        gx, gy, gw, gh = vung
        cam_truoc = list(self.cam)
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
            d = do_lech(s, s2, vung)
            s = s2
            if d is None or (abs(d[0]) < 2 and abs(d[1]) < 2):
                break
        if not self.la_ban_do(s):
            # lỡ chạm mở popup → đóng, vị trí camera không còn chắc
            self.thoat_ve_ban_do(s)
            self.sleep(1.0)
            self.cam_ok = False
            return None, self.shot()
        d = do_lech(s_truoc, s, vung)
        if d is None and ti_le_den(s, vung) < 0.6 and float(
                np.abs(s_truoc[::4, ::4].astype(np.int16) - s[::4, ::4].astype(np.int16)).mean()) < 2.5:
            d = (0.0, 0.0)  # ảnh gần như không đổi → bản đồ không dịch
        if d is not None:
            self.cam[0] -= d[0]
            self.cam[1] -= d[1]
        da_dinh_vi = self.dinh_vi_nhanh(s)  # có mốc thì sửa luôn sai số
        if d is None and not da_dinh_vi:
            self.cam_ok = False
            return None, s
        dich = (self.cam[0] - cam_truoc[0], self.cam[1] - cam_truoc[1])
        if abs(dich[0]) > 3 or abs(dich[1]) > 3:
            self.map_cuon = True
        return dich, s

    def ve_goc(self):
        """Vuốt về phía trên-trái tới mép bản đồ (không đi vào vùng đen) và lấy làm gốc (0, 0)."""
        s = self.shot()
        if not self.la_ban_do(s):
            self.luu_anh_loi(s, "lấy mốc nhưng không thấy thanh Thể lực")
        for truc, phia, ten in ((0, "trai", "trái"), (1, "tren", "trên")):
            khong_do_duoc = 0
            for lan in range(1, 13):
                if self.mep(s, phia):
                    self.log(f"  đã tới mép {ten} (vùng đen) sau {lan - 1} lần vuốt")
                    break
                gx, gy, gw, gh = self.templates.vung(s)
                dich, s = self.vuot_camera(-gw if truc == 0 else 0, -gh if truc == 1 else 0, s)
                if dich is None:
                    khong_do_duoc += 1
                    self.log(f"  vuốt {ten} lần {lan}: không đo được bản đồ dịch bao nhiêu")
                    if khong_do_duoc >= 2:
                        self.luu_anh_loi(s, "không đo được độ dịch bản đồ")
                        break
                    continue
                khong_do_duoc = 0
                if abs(dich[truc]) < 4:
                    self.log(f"  đã tới mép {ten} sau {lan} lần vuốt")
                    break
            else:
                self.log(f"  ⚠ vuốt {ten} 12 lần vẫn chưa tới mép")
        self.cam = [0.0, 0.0]
        self.cam_ok = True
        return s

    def dinh_vi(self, s):
        """Biết chắc vị trí trên bản đồ: tìm mốc; không thấy mốc nào thì lướt bản đồ để tìm."""
        if not self.ds_moc():  # khu dò bằng bản cũ (chưa có mốc): lấy góc trên-trái làm gốc
            return s if self.cam_ok else self.ve_goc()
        if self.dinh_vi_nhanh(s):
            return s
        self.log("  Không thấy mốc bản đồ trên màn hình → lướt tìm")
        s = self.ve_goc()
        self.cam_ok = False
        huong = 1
        for _ in range(30):
            if self.dinh_vi_nhanh(s):
                return s
            gx, gy, gw, gh = self.templates.vung(s)
            if not self.mep(s, "phai" if huong > 0 else "trai"):
                dich, s = self.vuot_camera(huong * 0.3 * gw, 0, s)
                if dich is not None and abs(dich[0]) > 0.05 * gw:
                    continue
            if self.mep(s, "duoi"):
                break
            dich, s = self.vuot_camera(0, 0.25 * gh, s)
            if dich is None or abs(dich[1]) < 0.05 * gh:
                break
            huong = -huong
        if not self.dinh_vi_nhanh(s):
            self.luu_anh_loi(s, "không tìm thấy mốc bản đồ nào")
        return s

    # ---------- đổi toạ độ ----------
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
        for _ in range(12):
            x, y = self.ra_man_hinh(s, ax, ay)
            if self.trong_vung_an_toan(s, x, y) or not self.cam_ok:
                return x, y, s
            gx, gy, gw, gh = self.templates.vung(s)
            dich, s = self.vuot_camera(x - (gx + 0.5 * gw), y - (gy + 0.48 * gh), s)
            if dich is None:
                s = self.dinh_vi(s)
                if not self.cam_ok:
                    return None
                continue
            if abs(dich[0]) < 3 and abs(dich[1]) < 3:
                x, y = self.ra_man_hinh(s, ax, ay)
                return x, y, s  # đã tới mép bản đồ, chạm luôn
        x, y = self.ra_man_hinh(s, ax, ay)
        return x, y, s
