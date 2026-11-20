"""Nhận diện nút/màn hình bằng ảnh mẫu (template matching của OpenCV).

Mỗi mẫu là một file PNG trong thư mục `mau/`. Một mẫu có thể có nhiều biến thể:
`nut_xac_nhan.png`, `nut_xac_nhan@2.png`, `nut_xac_nhan@3.png`... chỉ cần một biến
thể khớp là coi như thấy.
"""
import glob
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
        for path in self._files(name):
            tpl = self._load(path)
            if tpl is None:
                continue
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
                tot_nhat = Match(name, x + tw // 2, y + th // 2, x, y, tw, th, float(diem))
        return tot_nhat

    def find(self, screen, name, threshold):
        m = self.best(screen, name)
        return m if m and m.score >= threshold else None
