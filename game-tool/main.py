"""Overlay điều khiển: luôn nổi trên cùng, chạy/dừng tự động cho từng giả lập."""
import json
import os
import queue
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from adb import Adb, Device, find_adb
from bot import Bot
from capture import CaptureWindow, mo_thu_muc
from matcher import Templates

GOC = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(GOC, "config.json")
MAU_DIR = os.path.join(GOC, "mau")

TEN_DEM = {"xuc_xac": "🎲", "boss": "👹", "oan_tu_xi": "✊", "mua": "🛒", "phai_doi": "🚩", "binh_the_luc": "🧪"}


def doc_config():
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return json.load(f)


class App:
    def __init__(self, root):
        self.root = root
        self.cfg = doc_config()
        self.templates = Templates(MAU_DIR)
        self.q = queue.Queue()
        self.bots = {}
        self.rows = {}
        self.rule_vars = []

        p = find_adb(self.cfg.get("adb_path", ""))
        self.adb = Adb(p) if p else None

        root.title("Hội Tụ Auto")
        root.attributes("-topmost", True)
        try:
            root.attributes("-alpha", 0.93)
        except tk.TclError:
            pass
        root.resizable(False, False)
        self.build()
        root.bind("<F12>", lambda _e: self.stop_all())
        self.hotkey_toan_cuc()
        root.after(150, self.poll)
        if self.adb:
            self.log("", f"ADB: {self.adb.path}")
            self.refresh(tim_them=True)
        else:
            self.log("", "Không tìm thấy adb. Ghi đường dẫn adb.exe vào 'adb_path' trong config.json, "
                         "hoặc chép thư mục platform-tools vào cạnh main.py.")

    # ---------- giao diện ----------
    def build(self):
        r = self.root
        top = ttk.Frame(r, padding=(6, 4))
        top.pack(fill="x")
        ttk.Button(top, text="🔄 Tìm giả lập", command=lambda: self.refresh(tim_them=True)).pack(side="left")
        self.e_addr = ttk.Entry(top, width=15)
        self.e_addr.insert(0, "127.0.0.1:5555")
        self.e_addr.pack(side="left", padx=4)
        ttk.Button(top, text="Kết nối", command=self.connect).pack(side="left")
        self.btn_gon = ttk.Button(top, text="▾", width=3, command=self.toggle_gon)
        self.btn_gon.pack(side="right")

        self.f_dev = ttk.LabelFrame(r, text="Giả lập", padding=4)
        self.f_dev.pack(fill="x", padx=6)
        self.lbl_trong = ttk.Label(self.f_dev, text="(chưa thấy giả lập nào)")
        self.lbl_trong.pack()

        self.f_them = ttk.Frame(r)
        self.f_them.pack(fill="both", expand=True)

        f_opt = ttk.LabelFrame(self.f_them, text="Tuỳ chọn", padding=4)
        f_opt.pack(fill="x", padx=6, pady=(4, 0))
        hang = ttk.Frame(f_opt)
        hang.pack(fill="x")
        ttk.Label(hang, text="Dừng sau").pack(side="left")
        self.e_luot = ttk.Spinbox(hang, from_=0, to=9999, width=6)
        self.e_luot.set(0)
        self.e_luot.pack(side="left", padx=3)
        ttk.Label(hang, text="lượt xúc xắc (0 = tới khi hết thể lực)").pack(side="left")

        self.f_luat = ttk.Frame(f_opt)
        self.f_luat.pack(fill="x", pady=(4, 0))
        self.build_rules()

        f_tool = ttk.Frame(self.f_them, padding=(6, 4))
        f_tool.pack(fill="x")
        ttk.Button(f_tool, text="✂ Cắt mẫu", command=self.open_capture).pack(side="left")
        ttk.Button(f_tool, text="📁 Mẫu", command=lambda: mo_thu_muc(MAU_DIR)).pack(side="left", padx=4)
        ttk.Button(f_tool, text="↻ Tải lại cấu hình", command=self.reload).pack(side="left")
        ttk.Button(f_tool, text="⏹ Dừng hết (F12)", command=self.stop_all).pack(side="right")

        self.txt = tk.Text(self.f_them, height=9, width=56, font=("Consolas", 9), state="disabled", wrap="word")
        self.txt.pack(fill="both", expand=True, padx=6, pady=(0, 6))

    def build_rules(self):
        for w in self.f_luat.winfo_children():
            w.destroy()
        self.rule_vars = []
        for i, rule in enumerate(self.cfg.get("luat", [])):
            v = tk.BooleanVar(value=rule.get("bat", True))
            cb = ttk.Checkbutton(self.f_luat, text=rule.get("ten", f"Luật {i + 1}"), variable=v,
                                 command=lambda rr=rule, vv=v: self.toggle_rule(rr, vv))
            cb.grid(row=i // 2, column=i % 2, sticky="w", padx=(0, 10))
            self.rule_vars.append(v)

    def toggle_rule(self, rule, var):
        rule["bat"] = bool(var.get())  # bot dùng chung dict này → có hiệu lực ngay
        self.save_config()

    def save_config(self):
        try:
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(self.cfg, f, ensure_ascii=False, indent=2)
        except OSError as e:
            self.log("", f"Không lưu được config.json: {e}")

    def toggle_gon(self):
        if self.f_them.winfo_ismapped():
            self.f_them.pack_forget()
            self.btn_gon.config(text="▸")
        else:
            self.f_them.pack(fill="both", expand=True)
            self.btn_gon.config(text="▾")

    def device_row(self, serial):
        f = ttk.Frame(self.f_dev)
        f.pack(fill="x", pady=1)
        ttk.Label(f, text=serial, width=18).pack(side="left")
        st = ttk.Label(f, text="nghỉ", width=8, foreground="#888")
        st.pack(side="left")
        dem = ttk.Label(f, text="", width=22)
        dem.pack(side="left")
        btn = ttk.Button(f, text="▶ Chạy", width=8, command=lambda: self.toggle_bot(serial))
        btn.pack(side="right")
        ttk.Button(f, text="✂", width=3, command=lambda: self.open_capture(serial)).pack(side="right", padx=2)
        self.rows[serial] = {"frame": f, "st": st, "dem": dem, "btn": btn}

    # ---------- giả lập ----------
    def refresh(self, tim_them=False):
        if not self.adb:
            return

        def lam():
            try:
                if tim_them:
                    self.adb.connect_common()
                self.q.put(("devices", self.adb.devices()))
            except Exception as e:
                self.q.put(("log", "", f"Lỗi adb: {e}"))

        threading.Thread(target=lam, daemon=True).start()

    def connect(self):
        if not self.adb:
            return
        dc = self.e_addr.get().strip()

        def lam():
            ok = self.adb.connect(dc)
            self.q.put(("log", "", f"Kết nối {dc}: {'được' if ok else 'không được'}"))
            self.q.put(("devices", self.adb.devices()))

        threading.Thread(target=lam, daemon=True).start()

    def set_devices(self, ds):
        for s in list(self.rows):
            if s not in ds and s not in self.bots:
                self.rows.pop(s)["frame"].destroy()
        for s in ds:
            if s not in self.rows:
                self.device_row(s)
        if self.rows:
            self.lbl_trong.pack_forget()
        else:
            self.lbl_trong.pack()

    def chon_serial(self):
        if not self.rows:
            messagebox.showinfo("Chưa có giả lập", "Bấm 'Tìm giả lập' trước.", parent=self.root)
            return None
        return next(iter(self.rows))

    def open_capture(self, serial=None):
        serial = serial or self.chon_serial()
        if serial:
            CaptureWindow(self.root, Device(self.adb, serial), self.templates, self.cfg)

    # ---------- chạy / dừng ----------
    def toggle_bot(self, serial):
        b = self.bots.get(serial)
        if b and b.is_alive():
            b.stop()
            self.rows[serial]["st"].config(text="đang dừng")
            return
        try:
            luot = int(self.e_luot.get() or 0)
        except ValueError:
            luot = 0
        b = Bot(Device(self.adb, serial), self.cfg, self.templates, self.q.put, stop_after=luot)
        self.bots[serial] = b
        self.rows[serial]["dem"].config(text="")
        b.start()

    def stop_all(self):
        for b in self.bots.values():
            b.stop()

    def reload(self):
        try:
            moi = doc_config()
        except (OSError, ValueError) as e:
            messagebox.showerror("config.json lỗi", str(e), parent=self.root)
            return
        self.cfg.clear()
        self.cfg.update(moi)  # giữ nguyên dict để bot đang chạy cũng nhận cấu hình mới
        self.build_rules()
        self.log("", "Đã tải lại config.json")

    def hotkey_toan_cuc(self):
        try:
            import keyboard  # tuỳ chọn: F12 dừng cả khi đang bấm trong giả lập
            keyboard.add_hotkey("f12", lambda: self.q.put(("stop_all",)))
        except Exception:
            pass

    # ---------- nhận tin từ bot ----------
    def poll(self):
        try:
            while True:
                msg = self.q.get_nowait()
                kieu = msg[0]
                if kieu == "log":
                    self.log(msg[1], msg[2])
                elif kieu == "devices":
                    self.set_devices(msg[1])
                elif kieu == "stop_all":
                    self.stop_all()
                elif kieu == "state":
                    row = self.rows.get(msg[1])
                    if row:
                        dang = msg[2]
                        row["st"].config(text="đang chạy" if dang else "nghỉ", foreground="#1a8f3a" if dang else "#888")
                        row["btn"].config(text="⏹ Dừng" if dang else "▶ Chạy")
                elif kieu == "stats":
                    row = self.rows.get(msg[1])
                    if row:
                        row["dem"].config(text="  ".join(f"{TEN_DEM.get(k, k)}{v}" for k, v in msg[2].items()))
        except queue.Empty:
            pass
        self.root.after(150, self.poll)

    def log(self, serial, text):
        dong = f"[{serial}] {text}\n" if serial else f"{text}\n"
        self.txt.config(state="normal")
        self.txt.insert("end", dong)
        so_dong = int(self.txt.index("end-1c").split(".")[0])
        if so_dong > 400:
            self.txt.delete("1.0", f"{so_dong - 400}.0")
        self.txt.see("end")
        self.txt.config(state="disabled")


def main():
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
