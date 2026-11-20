"""Kết nối giả lập Android qua ADB: tìm adb, liệt kê máy, chụp màn hình, chạm."""
import os
import shutil
import subprocess
import sys

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

    def _shell(self, *args, timeout=10):
        r = self.adb.run("-s", self.serial, "shell", *args, timeout=timeout)
        if r.returncode != 0:
            raise AdbError(r.stderr.decode("utf-8", "ignore").strip() or "adb shell lỗi")
        return r.stdout

    def screenshot(self):
        r = self.adb.run("-s", self.serial, "exec-out", "screencap", "-p", timeout=15)
        img = None
        if r.stdout:
            img = cv2.imdecode(np.frombuffer(r.stdout, np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            loi = r.stderr.decode("utf-8", "ignore").strip()
            raise AdbError(f"không chụp được màn hình {self.serial} {loi}".strip())
        return img

    def tap(self, x, y):
        self._shell("input", "tap", str(int(x)), str(int(y)))

    def back(self):
        self._shell("input", "keyevent", "4")
