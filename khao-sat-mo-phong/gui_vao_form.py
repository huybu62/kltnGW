"""
(Tùy chọn) Gửi vài phiếu mô phỏng vào Google Form để kiểm tra form ghi nhận đúng.

CHỈ gửi vào BẢN SAO của form (Google Drive > chuột phải form > Tạo bản sao),
không gửi vào form đang thu dữ liệu thật — nếu không phiếu giả sẽ lẫn với phiếu thật.

Cách lấy mã entry:
  1. Mở form ở chế độ chỉnh sửa > ⋮ > "Lấy đường liên kết điền sẵn".
  2. Điền đại mỗi câu một đáp án > "Lấy đường liên kết" > dán link vào FILL_LINK dưới đây.
  3. Script tự đọc các entry.xxxx theo đúng thứ tự Câu 1 → Câu 34.
  (Câu 8 chọn nhiều đáp án; các lựa chọn trong sinh_du_lieu.py phải trùng chữ với form.)

Chạy thử (không gửi gì):  python3 gui_vao_form.py
Gửi thật 5 phiếu:          python3 gui_vao_form.py --gui 5
"""

import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import pandas as pd

from sinh_du_lieu import COT_GAN_LOC, COT_LIKERT, COT_NHAN_KHAU

FILL_LINK = "DÁN_LINK_ĐIỀN_SẴN_CỦA_BẢN_SAO_FORM_VÀO_ĐÂY"
CSV = Path(__file__).parent / "output" / "MO_PHONG_350_phieu_tho.csv"
# Số phần (section) của form. Form nhiều phần cần gửi kèm pageHistory, nếu không sẽ bị từ chối.
SO_PHAN = 1
COT = [*COT_GAN_LOC, *COT_NHAN_KHAU, *COT_LIKERT]  # 34 câu


def main():
    so_gui = int(sys.argv[sys.argv.index("--gui") + 1]) if "--gui" in sys.argv else 0
    m = re.search(r"/forms/d/e/([\w-]+)/", FILL_LINK)
    entries = list(dict.fromkeys(re.findall(r"entry\.(\d+)", FILL_LINK)))
    if not m or len(entries) != len(COT):
        sys.exit(f"Chưa có link điền sẵn hợp lệ (tìm thấy {len(entries)}/{len(COT)} entry). Xem hướng dẫn đầu file.")
    url = f"https://docs.google.com/forms/d/e/{m.group(1)}/formResponse"

    df = pd.read_csv(CSV, dtype=str, keep_default_na=False)
    for i, hang in df.head(max(so_gui, 3)).iterrows():
        data = []
        for entry, cot in zip(entries, COT):
            gia_tri = hang[cot]
            if not gia_tri:
                continue
            # Câu 8 (chọn nhiều): mỗi lựa chọn gửi thành một tham số riêng
            # (tách theo ", " — đừng đặt dấu phẩy + cách bên trong một lựa chọn)
            for g in (gia_tri.split(", ") if cot == COT_NHAN_KHAU[3] else [gia_tri]):
                data.append((f"entry.{entry}", g))
        if SO_PHAN > 1:
            data.append(("pageHistory", ",".join(map(str, range(SO_PHAN)))))
        body = urllib.parse.urlencode(data).encode()
        if not so_gui:
            print(f"[chạy thử] phiếu {i + 1}: {len(data)} trường -> {url}")
            continue
        with urllib.request.urlopen(urllib.request.Request(url, data=body)) as r:
            print(f"Phiếu {i + 1}: HTTP {r.status}")
        time.sleep(1.5)


if __name__ == "__main__":
    main()
