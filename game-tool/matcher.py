"""Nhận diện nút/màn hình bằng ảnh mẫu (template matching của OpenCV).

Mỗi mẫu là một file PNG trong thư mục `mau/`. Một mẫu có thể có nhiều biến thể:
`nut_xac_nhan.png`, `nut_xac_nhan@2.png`, `nut_xac_nhan@3.png`... chỉ cần một biến
thể khớp là coi như thấy.

Mẫu tự co giãn theo kích thước màn hình: file `mau/_ti_le.json` ghi chiều rộng vùng
game lúc cắt mẫu; khi màn hình thật rộng khác, mẫu được phóng/thu cho khớp.
"""
import glob
import json
import os
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass
class Match:
    name: str
    x: int  # tâm
    y: int
    left: int
    top: int
    w: int
    h: int
    score: float
    scale: float = 1.0


def vung_game(screen):
    """(x, y, w, h) của phần hình game, bỏ viền đen trên/dưới/hai bên nếu có."""
    g = screen[::4, ::4].max(axis=2) > 25
    hang = np.where(g.mean(axis=1) > 0.05)[0]
    cot = np.where(g.mean(axis=0) > 0.05)[0]
    sh, sw = screen.shape[:2]
    if len(hang) == 0 or len(cot) == 0:
        return 0, 0, sw, sh
    y0, y1 = hang[0] * 4, min(sh, hang[-1] * 4 + 4)
    x0, x1 = cot[0] * 4, min(sw, cot[-1] * 4 + 4)
    if (x1 - x0) < sw * 0.5 or (y1 - y0) < sh * 0.5:  # màn gần như tối hết: dùng cả màn
        return 0, 0, sw, sh
    return int(x0), int(y0), int(x1 - x0), int(y1 - y0)


def _doc_anh(path):
    # np.fromfile để đọc được đường dẫn có dấu tiếng Việt trên Windows
    data = np.fromfile(path, dtype=np.uint8)
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def ghi_anh(path, img):
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise RuntimeError("không mã hoá được ảnh")
    buf.tofile(path)


class Templates:
    # Chênh lệch độ sáng trung bình tối đa (0-255) giữa mẫu và vùng khớp.
    # Dùng để loại nút bị làm tối phía sau popup hoặc nút bị xám (không bấm được).
    CHENH_SANG_TOI_DA = 35

    def __init__(self, folder):
        self.folder = folder
        os.makedirs(folder, exist_ok=True)
        self._cache = {}  # path -> (mtime, img)
        self._co_gian = {}  # (path, scale) -> img
        self._vung = (None, None)  # (màn hình, vùng game)
        self._vung_theo_co = {}  # (rộng, cao) màn hình → vùng game
        self._ti_le_path = os.path.join(folder, "_ti_le.json")
        self._ti_le = (None, {})

    def ti_le(self):
        """{tên file: chiều rộng vùng game lúc cắt}."""
        try:
            mtime = os.path.getmtime(self._ti_le_path)
        except OSError:
            return {}
        if self._ti_le[0] != mtime:
            try:
                with open(self._ti_le_path, encoding="utf-8") as f:
                    self._ti_le = (mtime, json.load(f))
            except (OSError, ValueError):
                self._ti_le = (mtime, {})
        return self._ti_le[1]

    def ghi_ti_le(self, path, rong_game):
        d = dict(self.ti_le())
        d[os.path.basename(path)] = int(rong_game)
        with open(self._ti_le_path, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=1, sort_keys=True)

    def vung(self, screen):
        """Vùng game, cố định theo độ phân giải: không đo lại mỗi ảnh, vì mép bản đồ đen
        (hoặc màn tối khi có popup) sẽ làm đo sai."""
        if self._vung[0] is screen:
            return self._vung[1]
        sh, sw = screen.shape[:2]
        v = self._vung_theo_co.get((sw, sh))
        if v is None:
            if abs(sw / sh - 16 / 9) < 0.03:
                v = (0, 0, sw, sh)  # màn 16:9 → cả màn là game
                self._vung_theo_co[(sw, sh)] = v
            else:
                d = vung_game(screen)
                if abs(d[2] / d[3] - 16 / 9) < 0.03:
                    v = d  # có viền đen đúng kiểu khung 16:9 → nhớ luôn
                    self._vung_theo_co[(sw, sh)] = v
                else:  # chưa chắc: tạm lấy khung 16:9 ở giữa, không nhớ
                    w = min(sw, round(sh * 16 / 9))
                    h = round(w * 9 / 16)
                    v = ((sw - w) // 2, (sh - h) // 2, w, h)
        self._vung = (screen, v)
        return v

    def _files(self, name):
        chinh = os.path.join(self.folder, f"{name}.png")
        bien_the = sorted(glob.glob(os.path.join(self.folder, f"{glob.escape(name)}@*.png")))
        return ([chinh] if os.path.isfile(chinh) else []) + bien_the

    def _load(self, path):
        mtime = os.path.getmtime(path)
        cu = self._cache.get(path)
        if cu and cu[0] == mtime:
            return cu[1]
        img = _doc_anh(path)
        self._cache[path] = (mtime, img)
        return img

    def exists(self, name):
        return bool(self._files(name))

    def names(self):
        ten = set()
        for p in glob.glob(os.path.join(self.folder, "*.png")):
            ten.add(os.path.splitext(os.path.basename(p))[0].split("@")[0])
        return sorted(ten)

    def next_variant_path(self, name):
        i = 2
        while os.path.exists(os.path.join(self.folder, f"{name}@{i}.png")):
            i += 1
        return os.path.join(self.folder, f"{name}@{i}.png")

    def best(self, screen, name):
        """Vị trí khớp tốt nhất của mẫu (mọi biến thể), không xét ngưỡng."""
        tot_nhat = None
        rong = self.vung(screen)[2]
        ti_le = self.ti_le()
        for path in self._files(name):
            tpl = self._load(path)
            if tpl is None:
                continue
            k = 1.0
            goc = ti_le.get(os.path.basename(path))
            if goc:
                k = rong / goc
                if abs(k - 1) > 0.01:
                    khoa = (path, round(k, 3))
                    if khoa not in self._co_gian:
                        tw0, th0 = tpl.shape[1], tpl.shape[0]
                        self._co_gian[khoa] = cv2.resize(
                            tpl, (max(4, round(tw0 * k)), max(4, round(th0 * k))),
                            interpolation=cv2.INTER_AREA if k < 1 else cv2.INTER_CUBIC)
                    tpl = self._co_gian[khoa]
            th, tw = tpl.shape[:2]
            sh, sw = screen.shape[:2]
            if th > sh or tw > sw:
                continue
            res = cv2.matchTemplate(screen, tpl, cv2.TM_CCOEFF_NORMED)
            _, diem, _, (x, y) = cv2.minMaxLoc(res)
            vung = screen[y:y + th, x:x + tw]
            if abs(float(vung.mean()) - float(tpl.mean())) > self.CHENH_SANG_TOI_DA:
                diem = min(diem, 0.5)  # đúng hình nhưng tối/xám hơn hẳn: không tính
            if tot_nhat is None or diem > tot_nhat.score:
                tot_nhat = Match(name, x + tw // 2, y + th // 2, x, y, tw, th, float(diem), k)
        return tot_nhat

    def find(self, screen, name, threshold):
        m = self.best(screen, name)
        return m if m and m.score >= threshold else None
