#!/bin/bash
# Chạy Hội Tụ Auto trên macOS: nháy đúp file này (lần đầu: chuột phải → Mở).
cd "$(dirname "$0")" || exit 1

dung_lai() { echo; read -r -p "Nhấn Enter để đóng cửa sổ này..." _; exit 1; }

# Tìm Python 3.10+ có tkinter (bản cài từ python.org)
PY=""
for p in /usr/local/bin/python3 python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys, tkinter; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$p"; break
  fi
done
if [ -z "$PY" ]; then
  echo "Chưa có Python 3.10 trở lên. Tải bản macOS tại https://www.python.org/downloads/macos/ rồi chạy lại."
  dung_lai
fi
echo "Dùng $("$PY" --version) ($PY)"

if [ ! -x .venv/bin/python ]; then
  echo "Lần đầu chạy: đang cài thư viện (1-2 phút)..."
  "$PY" -m venv .venv || { echo "Không tạo được môi trường Python."; dung_lai; }
fi
.venv/bin/python -m pip install -q --disable-pip-version-check -r requirements.txt || { echo "Cài thư viện bị lỗi (kiểm tra mạng)."; dung_lai; }
# Bộ đọc chữ (cho chế độ tự động vượt ải). Lỗi thì tool vẫn chạy, chỉ không đọc chữ được.
if ! .venv/bin/python -c "import rapidocr_onnxruntime" 2>/dev/null; then
  echo "Đang cài bộ đọc chữ (lần đầu, khoảng 1 phút)..."
  .venv/bin/python -m pip install -q --disable-pip-version-check "rapidocr_onnxruntime==1.2.3" \
    || echo "⚠ Không cài được bộ đọc chữ: tool vẫn chạy nhưng không tự vượt ải được."
fi

# adb: dùng bản có sẵn, nếu không có thì tải platform-tools chính thức của Google
if ! command -v adb >/dev/null 2>&1 && [ ! -x platform-tools/adb ]; then
  echo "Đang tải adb (Android platform-tools của Google)..."
  TMPZIP="$(mktemp -t platformtools).zip"
  curl -fL --progress-bar -o "$TMPZIP" https://dl.google.com/android/repository/platform-tools-latest-darwin.zip \
    && unzip -qo "$TMPZIP" -d . && rm -f "$TMPZIP" \
    || { echo "Không tải được adb. Có thể cài bằng: brew install --cask android-platform-tools"; dung_lai; }
fi

echo "Đang mở Hội Tụ Auto... (giữ cửa sổ Terminal này, đóng nó là tắt tool)"
.venv/bin/python main.py || { echo "Tool báo lỗi ở trên."; dung_lai; }
