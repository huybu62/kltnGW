"""Kết nối giả lập Android qua ADB: tìm adb, liệt kê máy, chụp màn hình, chạm."""
import os
import shutil
import struct
import subprocess
import sys
import threading
import time

import cv2
import numpy as np

# Không bật cửa sổ đen mỗi lần gọi adb trên Windows
_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0

# Nơi các giả lập phổ biến để sẵn adb
_ADB_THUONG_GAP = [
    r"C:\LDPlayer\LDPlayer9\adb.exe",
    r"C:\LDPlayer\LDPlayer4.0\adb.exe",
    r"D:\LDPlayer\LDPlayer9\adb.exe",
    r"C:\Program Files\Netease\MuMuPlayer-12.0\shell\adb.exe",
    r"C:\Program Files\Netease\MuMu Player 12\shell\adb.exe",
    r"D:\Program Files\Netease\MuMuPlayer-12.0\shell\adb.exe",
    r"C:\Program Files\BlueStacks_nxt\HD-Adb.exe",
    r"C:\Program Files\BlueStacks\HD-Adb.exe",
    r"C:\Program Files\Nox\bin\nox_adb.exe",
    r"D:\Program Files\Nox\bin\nox_adb.exe",
    r"C:\Program Files (x86)\Nox\bin\nox_adb.exe",
    # macOS
    "/opt/homebrew/bin/adb",
    "/usr/local/bin/adb",
    "/Applications/BlueStacks.app/Contents/MacOS/hd-adb",
    os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"),
]

# Cổng ADB mặc định của các giả lập (LDPlayer, BlueStacks, MuMu, Nox...)
CONG_THUONG_GAP = [5555, 5557, 5559, 5561, 7555, 16384, 16416, 16448, 62001, 62025, 62026]


def find_adb(cau_hinh=""):
    """Trả về đường dẫn adb: ưu tiên cấu hình, rồi thư mục tool, PATH, rồi các giả lập."""
    ung_vien = []
    if cau_hinh:
        ung_vien.append(cau_hinh)
    goc = os.path.dirname(os.path.abspath(__file__))
    ung_vien += [os.path.join(goc, "platform-tools", "adb.exe"), os.path.join(goc, "platform-tools", "adb")]
    tren_path = shutil.which("adb")
    if tren_path:
        ung_vien.append(tren_path)
    ung_vien += _ADB_THUONG_GAP
    for p in ung_vien:
        if p and os.path.isfile(p):
            return p
    return None


class AdbError(RuntimeError):
    pass


class Adb:
    def __init__(self, path):
        self.path = path

    def run(self, *args, timeout=15):
        try:
            return subprocess.run(
                [self.path, *args],
                capture_output=True,
                timeout=timeout,
                creationflags=_NO_WINDOW,
            )
        except subprocess.TimeoutExpired as e:
            raise AdbError(f"adb {' '.join(args[:3])} quá thời gian") from e

    def devices(self):
        out = self.run("devices", timeout=10).stdout.decode("utf-8", "ignore")
        ds = []
        for dong in out.splitlines()[1:]:
            phan = dong.split()
            if len(phan) >= 2 and phan[1] == "device":
                ds.append(phan[0])
        # Một giả lập có thể hiện 2 lần (emulator-5554 và 127.0.0.1:5555): giữ cả,
        # người dùng chỉ cần chạy một trong hai.
        return ds

    def connect(self, dia_chi):
        out = self.run("connect", dia_chi, timeout=5).stdout.decode("utf-8", "ignore")
        return "connected" in out

    def connect_common(self):
        for cong in CONG_THUONG_GAP:
            try:
                self.connect(f"127.0.0.1:{cong}")
            except AdbError:
                pass


class Device:
    def __init__(self, adb, serial):
        self.adb = adb
        self.serial = serial
        self._raw_ok = True  # thử chụp ảnh thô (nhanh hơn PNG), lỗi thì quay về PNG
        self._sh = None  # adb shell giữ sẵn để chạm/vuốt không phải mở adb mỗi lần
        self._sh_lock = threading.Lock()
        self._da_gui = 0  # số lệnh đã gửi / đã chạy xong (để không dồn lệnh khi bấm quá nhanh)
        self._da_xong = 0

    def _shell(self, *args, timeout=10):
        r = self.adb.run("-s", self.serial, "shell", *args, timeout=timeout)
        if r.returncode != 0:
            raise AdbError(r.stderr.decode("utf-8", "ignore").strip() or "adb shell lỗi")
        return r.stdout

    def _doc_xac_nhan(self, sh):
        for dong in iter(sh.stdout.readline, b""):
            if b"@@xong" in dong:
                self._da_xong += 1

    def _gui_lenh(self, lenh, toi_da_cho=2):
        """Gửi lệnh vào adb shell đang mở sẵn. Nếu đã có `toi_da_cho` lệnh chưa chạy xong thì chờ
        (bấm nhanh hơn giả lập xử lý sẽ làm lệnh dồn lại và chạm lung tung sau đó)."""
        han = time.time() + 3
        while self._sh is not None and self._da_gui - self._da_xong >= toi_da_cho and time.time() < han:
            time.sleep(0.01)
        with self._sh_lock:
            for _ in range(2):
                try:
                    if self._sh is None or self._sh.poll() is not None:
                        self._sh = subprocess.Popen(
                            [self.adb.path, "-s", self.serial, "shell"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            creationflags=_NO_WINDOW)
                        self._da_gui = self._da_xong = 0
                        threading.Thread(target=self._doc_xac_nhan, args=(self._sh,), daemon=True).start()
                    noi = " " if lenh.rstrip().endswith("&") else "; "  # "lệnh &; echo" là lỗi cú pháp
                    self._sh.stdin.write(f"{lenh}{noi}echo @@xong\n".encode())
                    self._sh.stdin.flush()
                    self._da_gui += 1
                    return
                except (OSError, ValueError):
                    self._sh = None
        self._shell(*lenh.split())

    def close(self):
        with self._sh_lock:
            if self._sh and self._sh.poll() is None:
                try:
                    self._sh.stdin.close()
                    self._sh.terminate()
                except OSError:
                    pass
            self._sh = None

    def screenshot(self):
        if self._raw_ok:
            r = self.adb.run("-s", self.serial, "exec-out", "screencap", timeout=15)
            img = _doc_anh_tho(r.stdout)
            if img is not None:
                return img
            self._raw_ok = False
        r = self.adb.run("-s", self.serial, "exec-out", "screencap", "-p", timeout=15)
        img = None
        if r.stdout:
            img = cv2.imdecode(np.frombuffer(r.stdout, np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            loi = r.stderr.decode("utf-8", "ignore").strip()
            raise AdbError(f"không chụp được màn hình {self.serial} {loi}".strip())
        return img

    def tap(self, x, y):
        self._gui_lenh(f"input tap {int(x)} {int(y)}")

    def tap_nhanh(self, x, y):
        """Chạm chạy nền trên máy ảo: không phải chờ cú trước xong (mỗi lệnh input mất ~0,2 giây)."""
        self._gui_lenh(f"input tap {int(x)} {int(y)} &", toi_da_cho=3)

    def swipe(self, x1, y1, x2, y2, ms=700):
        self._gui_lenh(f"input swipe {int(x1)} {int(y1)} {int(x2)} {int(y2)} {int(ms)}")

    def back(self):
        self._gui_lenh("input keyevent 4")


def _doc_anh_tho(data):
    """Ảnh thô của `screencap` (không -p): đầu 12 hoặc 16 byte (rộng, cao, định dạng[, màu]) + RGBA."""
    if not data or len(data) < 16:
        return None
    w, h, dinh_dang = struct.unpack_from("<III", data, 0)
    if not (0 < w < 10000 and 0 < h < 10000) or dinh_dang != 1:  # 1 = RGBA_8888
        return None
    dau = len(data) - w * h * 4
    if dau not in (12, 16):
        return None
    rgba = np.frombuffer(data, np.uint8, count=w * h * 4, offset=dau).reshape(h, w, 4)
    return cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGR)
