@echo off
chcp 65001 >nul
cd /d "%~dp0"
where python >NUL 2>NUL || (echo Chua cai Python. Tai tai https://www.python.org/downloads/ va tick "Add python.exe to PATH". & pause & exit /b 1)
if not exist .venv (
  echo Lan dau chay: dang cai thu vien, cho mot chut...
  python -m venv .venv
)
call .venv\Scripts\activate.bat
python -m pip install -q -r requirements.txt
python -c "import rapidocr_onnxruntime" 2>NUL || python -m pip install -q "rapidocr_onnxruntime==1.2.3"
python main.py
if errorlevel 1 pause
