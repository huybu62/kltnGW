"""Đọc màn chương bằng OCR: tên nước (dải tiêu đề giữa trên) và các nhãn ải "N-M Tên ải".

Nhãn ải hay bị đọc thiếu chữ số đầu (dính viền khung) hoặc bị nhân vật che, nên:
- lấy số ải M từ "N-M", "-M" hoặc chữ số đứng đầu nhãn;
- nhãn đọc được chữ mà không có số (bị che) thì gán số còn thiếu trong 1..4.
"""
import re
from difflib import SequenceMatcher

from ocr import chuan_hoa, doc, gon

# chữ giao diện cố định trên màn chương, không phải nhãn ải
_GIAO_DIEN = ["trolai", "diemthuhoi", "chuong", "aithuong", "aitinhanh", "duonganhhung", "tudongchiendau",
              "hoantoan", "thuhoi", "%"]


def doc_man_chuong(s, vung):
    """Trả về (tên nước, [(số ải, chữ nhãn, x, y)]) sắp theo số ải."""
    gx, gy, gw, gh = vung
    ds = doc(s)
    nuoc = ""
    nhan = []
    for c in ds:
        fx, fy = (c.x - gx) / gw, (c.y - gy) / gh
        g = gon(c.text)
        if fy < 0.16 and 0.4 < fx < 0.75 and len(g) >= 3:
            nuoc = c.text.strip()  # dải tiêu đề tên nước
            continue
        if fx < 0.27 or fy < 0.16 or c.diem < 0.5:  # cột thẻ Ải bên trái, thanh trên
            continue
        if any(k in g for k in _GIAO_DIEN) or len(re.sub(r"[^a-z]", "", g)) < 3:
            continue
        # dòng vàng "Hoàn toàn thu hồi" phía trên nhãn hay bị đọc sai ("Hon tonuhai", "Hoantoantnuhot")
        if SequenceMatcher(None, re.sub(r"[^a-z]", "", g), "hoantoanthuhoi").ratio() >= 0.6:
            continue
        t = chuan_hoa(c.text)
        m = re.match(r"^\s*(?:\d\s*)?[-–—]\s*(\d)", t) or re.match(r"^\s*(\d)\s*[-–—]?\s*[a-z]", t) \
            or re.match(r"^\s*\d\s*[-–—]\s*(\d)", t)
        nhan.append([int(m.group(1)) if m else None, c.text.strip(), c.x, c.y])
    co_so = {n[0] for n in nhan if n[0]}
    thieu = [i for i in range(1, 5) if i not in co_so]
    for n in nhan:
        if n[0] is None and thieu:
            n[0] = thieu.pop(0)  # nhãn bị che mất số → số còn thiếu
    nhan = [tuple(n) for n in nhan if n[0]]
    # mỗi số chỉ giữ một nhãn
    gap = {}
    for n in sorted(nhan):
        gap.setdefault(n[0], n)
    return nuoc, [gap[k] for k in sorted(gap)]
