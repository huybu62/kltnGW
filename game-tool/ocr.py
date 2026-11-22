"""Đọc chữ trên màn hình game (OCR) bằng RapidOCR, nếu đã cài (pip install rapidocr_onnxruntime).

Chữ đọc được đưa về dạng không dấu, chữ thường để so (ví dụ "Số lần còn lại:99" → "so lan con lai:99").
Không có thư viện thì co_ocr() = False và doc() trả về danh sách rỗng.
"""
import re
import threading
import unicodedata
from dataclasses import dataclass

import cv2

_khoa = threading.Lock()
_may = None
_loi = None


@dataclass
class Chu:
    text: str  # chữ gốc đọc được
    chuan: str  # không dấu, chữ thường, bỏ khoảng trắng thừa
    x: int  # tâm (toạ độ màn hình)
    y: int
    x0: int
    y0: int
    x1: int
    y1: int
    diem: float


def chuan_hoa(s):
    s = unicodedata.normalize("NFD", s or "")
    s = "".join(c for c in s if unicodedata.category(c) != "Mn").replace("đ", "d").replace("Đ", "D")
    return re.sub(r"\s+", " ", s.lower()).strip()


def gon(s):
    """Bỏ hết khoảng trắng (OCR hay dính/tách chữ)."""
    return re.sub(r"\s+", "", chuan_hoa(s))


def _lay_may():
    global _may, _loi
    if _may is None and _loi is None:
        try:
            from rapidocr_onnxruntime import RapidOCR
            _may = RapidOCR()
        except Exception as e:  # chưa cài, hoặc máy không chạy được
            _loi = e
    return _may


def co_ocr():
    return _lay_may() is not None


def doc(img, roi=None, rong_toi_da=1280):
    """Đọc chữ trong ảnh (hoặc vùng roi=(x0,y0,x1,y1)). Trả về list[Chu] theo toạ độ màn hình."""
    may = _lay_may()
    if may is None:
        return []
    ox, oy = 0, 0
    if roi is not None:
        ox, oy = max(0, int(roi[0])), max(0, int(roi[1]))
        img = img[oy:max(oy + 1, int(roi[3])), ox:max(ox + 1, int(roi[2]))]
    if img.size == 0:
        return []
    k = 1.0
    if img.shape[1] > rong_toi_da:
        k = rong_toi_da / img.shape[1]
        img = cv2.resize(img, None, fx=k, fy=k, interpolation=cv2.INTER_AREA)
    with _khoa:
        try:
            kq, _ = may(img)
        except Exception:
            return []
    ds = []
    for hop, text, diem in kq or []:
        try:
            diem = float(diem)
        except (TypeError, ValueError):
            continue
        xs = [p[0] / k + ox for p in hop]
        ys = [p[1] / k + oy for p in hop]
        x0, x1, y0, y1 = int(min(xs)), int(max(xs)), int(min(ys)), int(max(ys))
        ds.append(Chu(text, chuan_hoa(text), (x0 + x1) // 2, (y0 + y1) // 2, x0, y0, x1, y1, diem))
    return ds


def tim(ds, *cum):
    """Dòng chữ đầu tiên chứa đủ các cụm (so không dấu, bỏ khoảng trắng)."""
    can = [gon(c) for c in cum]
    for c in ds:
        g = gon(c.text)
        if all(x in g for x in can):
            return c
    return None


def so_trong(text, mau=r"(\d+)"):
    m = re.search(mau, chuan_hoa(text))
    return int(m.group(1)) if m else None
