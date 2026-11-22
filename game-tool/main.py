"""Overlay điều khiển: luôn nổi trên cùng, chạy/dừng tự động cho từng giả lập."""
import json
import os
import queue
import threading
import time
import tkinter as tk
from tkinter import messagebox, ttk

from adb import Adb, Device, find_adb
from bot import Bot
from capture import CaptureWindow, mo_thu_muc
from matcher import Templates
from chuong import ChuongBot
from discover import DiscoverBot
from sweep import SweepBot

GOC = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(GOC, "config.json")
MAU_DIR = os.path.join(GOC, "mau")

TEN_DEM = {"do": "🔎", "khu": "🏠", "the_luc": "⚡", "can_quet": "🧹", "xuc_xac": "🎲", "boss": "👹", "oan_tu_xi": "✊", "mua": "🛒", "phai_doi": "🚩", "binh_the_luc": "🧪"}


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
        threading.Thread(target=self.kiem_tra_ocr, daemon=True).start()
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
        hang0 = ttk.Frame(f_opt)
        hang0.pack(fill="x")
        ttk.Label(hang0, text="Chế độ:").pack(side="left")
        self.v_che_do = tk.StringVar(value=self.cfg.get("che_do", "can_quet"))
        for gt, nhan in (("can_quet", "Càn quét map"), ("xuc_xac", "Xúc xắc (sự kiện)")):
            ttk.Radiobutton(hang0, text=nhan, value=gt, variable=self.v_che_do,
                            command=self.doi_che_do).pack(side="left", padx=4)
        hang = ttk.Frame(f_opt)
        hang.pack(fill="x", pady=(3, 0))
        ttk.Label(hang, text="Dừng sau").pack(side="left")
        self.e_luot = ttk.Spinbox(hang, from_=0, to=9999, width=6)
        self.e_luot.set(0)
        self.e_luot.pack(side="left", padx=3)
        self.lbl_luot = ttk.Label(hang, text="")
        self.lbl_luot.pack(side="left")

        # --- tuỳ chọn càn quét ---
        self.f_cq = ttk.Frame(f_opt)
        h1 = ttk.Frame(self.f_cq)
        h1.pack(fill="x", pady=(3, 0))
        ttk.Label(h1, text="Mỗi khu quét").pack(side="left")
        self.e_moi_khu = ttk.Spinbox(h1, from_=0, to=999, width=5, command=self.luu_cq)
        self.e_moi_khu.pack(side="left", padx=3)
        ttk.Label(h1, text="lần rồi sang khu khác (0 = tới khi hết 99 lượt)").pack(side="left")
        h2 = ttk.Frame(self.f_cq)
        h2.pack(fill="x", pady=(3, 0))
        ttk.Label(h2, text="Thể lực tối đa").pack(side="left")
        self.e_tl_max = ttk.Spinbox(h2, from_=1, to=9999, width=5, command=self.luu_cq)
        self.e_tl_max.pack(side="left", padx=3)
        ttk.Label(h2, text="  Mỗi lần tốn").pack(side="left")
        self.e_chi_phi = ttk.Spinbox(h2, from_=1, to=99, width=4, command=self.luu_cq)
        self.e_chi_phi.pack(side="left", padx=3)
        ttk.Label(h2, text="thể lực").pack(side="left")
        h4 = ttk.Frame(self.f_cq)
        h4.pack(fill="x", pady=(3, 0))
        ttk.Label(h4, text="Bấm 'lần nữa' mỗi").pack(side="left")
        self.e_nhip = ttk.Spinbox(h4, from_=0.1, to=3.0, increment=0.05, width=5, command=self.luu_cq)
        self.e_nhip.pack(side="left", padx=3)
        ttk.Label(h4, text="giây").pack(side="left")
        self.v_cuon = tk.BooleanVar(value=True)
        ttk.Checkbutton(h4, text="Lướt cả bản đồ", variable=self.v_cuon, command=self.luu_cq).pack(side="left", padx=(12, 0))
        for e in (self.e_moi_khu, self.e_tl_max, self.e_chi_phi, self.e_nhip):
            e.bind("<FocusOut>", lambda _e: self.luu_cq())
        h5 = ttk.Frame(self.f_cq)
        h5.pack(fill="x", pady=(3, 0))
        self.v_qua_ai = tk.BooleanVar(value=True)
        ttk.Checkbutton(h5, text="Hết khu thì Trở lại, sang ải kế (1-1 → 1-2 → …)", variable=self.v_qua_ai,
                        command=self.doi_qua_ai).pack(side="left")
        h8 = ttk.Frame(self.f_cq)
        h8.pack(fill="x", pady=(3, 0))
        self.v_tu_dong = tk.BooleanVar(value=True)
        ttk.Checkbutton(h8, text="Tự động vượt ải: đọc chữ, đi hết 4 ải rồi bấm ▶ sang nước sau",
                        variable=self.v_tu_dong, command=self.doi_qua_ai).pack(side="left")
        h9 = ttk.Frame(self.f_cq)
        h9.pack(fill="x", pady=(3, 0))
        self.v_tham_hiem = tk.BooleanVar(value=True)
        ttk.Checkbutton(h9, text="Tự thám hiểm khu chưa mở (đánh trận, bấm 'Tiến lên')",
                        variable=self.v_tham_hiem, command=self.luu_cq).pack(side="left")
        self.lbl_ocr = ttk.Label(h9, text="", foreground="#888")
        self.lbl_ocr.pack(side="right")
        h7 = ttk.Frame(self.f_cq)
        h7.pack(fill="x", pady=(3, 0))
        ttk.Label(h7, text="Kiểu quét:").pack(side="left")
        self.KIEU = {"Từng lần (bấm 'lần nữa')": 1, "x5 (tốn Xu)": 5, "x10 (tốn Xu)": 10}
        self.cb_kieu = ttk.Combobox(h7, values=list(self.KIEU), state="readonly", width=24)
        self.cb_kieu.pack(side="left", padx=4)
        self.cb_kieu.bind("<<ComboboxSelected>>", lambda _e: self.luu_cq())
        h6 = ttk.Frame(self.f_cq)
        h6.pack(fill="x", pady=(3, 0))
        self.v_bo_tl = tk.BooleanVar(value=False)
        ttk.Checkbutton(h6, text="Không kiểm tra thể lực (đã mua nhiều, chỉ dừng khi hết khu)",
                        variable=self.v_bo_tl, command=self.luu_cq).pack(side="left")
        h3 = ttk.Frame(self.f_cq)
        h3.pack(fill="x", pady=(4, 0))
        self.lbl_ds = ttk.Label(h3, text="", foreground="#555")
        self.lbl_ds.pack(side="left")
        self.btn_do = ttk.Button(h3, text="🔎 Dò khu tự động", command=self.do_khu)
        self.f_khu = ttk.Frame(self.f_cq)
        self.f_khu.pack(fill="x")

        # --- luật xúc xắc ---
        self.f_luat = ttk.Frame(f_opt)
        self.build_rules()
        self.doi_che_do(luu=False)

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
        self.build_cq()

    def doi_che_do(self, luu=True):
        che_do = self.v_che_do.get()
        if che_do == "can_quet":
            self.f_luat.pack_forget()
            self.f_cq.pack(fill="x")
            self.lbl_luot.config(text="lần càn quét (0 = tới khi hết thể lực)")
        else:
            self.f_cq.pack_forget()
            self.f_luat.pack(fill="x", pady=(4, 0))
            self.lbl_luot.config(text="lượt xúc xắc (0 = tới khi hết thể lực)")
        if luu:
            self.cfg["che_do"] = che_do
            self.save_config()

    def build_cq(self):
        cq = self.cfg.setdefault("can_quet", {})
        for e, k, md in ((self.e_moi_khu, "so_lan_moi_khu", 0), (self.e_tl_max, "the_luc_toi_da", 120),
                         (self.e_chi_phi, "chi_phi", 4)):
            e.set(cq.get(k, md))
        self.e_nhip.set(cq.get("nhip_lan_nua", 0.35))
        self.v_cuon.set(cq.get("cuon_map", True))
        self.v_qua_ai.set(cq.get("qua_ai", True))
        self.v_tu_dong.set(cq.get("tu_dong_vuot_ai", True))
        self.v_tham_hiem.set(cq.get("tu_dong_tham_hiem", True))
        self.v_bo_tl.set(cq.get("bo_qua_the_luc", False))
        kieu = int(cq.get("kieu_quet", 1) or 1)
        self.cb_kieu.set(next((t for t, v in self.KIEU.items() if v == kieu), list(self.KIEU)[0]))
        for w in self.f_khu.winfo_children():
            w.destroy()
        if cq.get("qua_ai", True) and cq.get("tu_dong_vuot_ai", True):
            self.btn_do.pack_forget()
            self.lbl_ds.config(text="Các ải đã đi qua (tool tự tìm ải trên màn chương):")
            xong = cq.get("xong_tu_dong") or {}
            xong = set(xong.get("ds", [])) if xong.get("ngay") == time.strftime("%Y-%m-%d") else set()
            ds_ai = cq.get("ai_tu_dong", {})
            if not ds_ai:
                ttk.Label(self.f_khu, text="(chưa có: bấm ▶ Chạy, tool tự vào ải và dò khu)", foreground="#888").pack(anchor="w")
            for key, ai in list(ds_ai.items())[-8:]:
                hang = ttk.Frame(self.f_khu)
                hang.pack(fill="x")
                ttk.Label(hang, text=f"{'✔' if key in xong else '•'} {key}  ({len(ai.get('khu') or [])} khu)").pack(side="left")
                ttk.Button(hang, text="Dò lại", width=6, command=lambda aa=ai: self.do_lai_ai(aa)).pack(side="right")
            if len(ds_ai) > 8:
                ttk.Label(self.f_khu, text=f"… và {len(ds_ai) - 8} ải khác", foreground="#888").pack(anchor="w")
            hang = ttk.Frame(self.f_khu)
            hang.pack(fill="x", pady=(2, 0))
            ttk.Button(hang, text="Quét lại các ải đã xong hôm nay", command=self.lam_lai_hom_nay).pack(side="left")
            return
        if cq.get("qua_ai", True):
            self.btn_do.pack_forget()
            self.lbl_ds.config(text="Các ải (quét theo thứ tự; ải chưa dò sẽ tự dò khu lần đầu):")
            ds_ai = cq.get("ai", [])
            if not ds_ai:
                ttk.Label(self.f_khu, text="(chưa có ải nào: ✂ → khoanh nhãn ải → ➕ Thêm ải)",
                          foreground="#888").pack(anchor="w")
            for i, ai in enumerate(ds_ai):
                hang = ttk.Frame(self.f_khu)
                hang.pack(fill="x")
                v = tk.BooleanVar(value=ai.get("bat", True))
                so = len(ai.get("khu") or [])
                ttk.Checkbutton(hang, text=f"{ai.get('ten', '?')}  ({so} khu)" if so else f"{ai.get('ten', '?')}  (chưa dò)",
                                variable=v, command=lambda aa=ai, vv=v: self.toggle_rule(aa, vv)).pack(side="left")
                ttk.Button(hang, text="✕", width=2, command=lambda aa=ai: self.xoa_khu(aa, "ai")).pack(side="right")
                if i:
                    ttk.Button(hang, text="↑", width=2, command=lambda j=i: self.len_khu(j, "ai")).pack(side="right")
                if so:
                    ttk.Button(hang, text="Dò lại", width=6, command=lambda aa=ai: self.do_lai_ai(aa)).pack(side="right")
            return
        self.btn_do.pack(side="right")
        self.lbl_ds.config(text="Các khu (quét theo thứ tự):")
        ds = cq.get("khu", [])
        if not ds:
            ttk.Label(self.f_khu, text="(chưa có khu nào)", foreground="#888").pack(anchor="w")
        for i, khu in enumerate(ds):
            hang = ttk.Frame(self.f_khu)
            hang.pack(fill="x")
            v = tk.BooleanVar(value=khu.get("bat", True))
            ttk.Checkbutton(hang, text=f"{i + 1}. {khu.get('ten', '?')}", variable=v,
                            command=lambda kk=khu, vv=v: self.toggle_rule(kk, vv)).pack(side="left")
            ttk.Button(hang, text="✕", width=2, command=lambda kk=khu: self.xoa_khu(kk)).pack(side="right")
            if i:
                ttk.Button(hang, text="↑", width=2, command=lambda j=i: self.len_khu(j)).pack(side="right")

    def do_khu(self):
        serial = next((s for s in self.rows if not (self.bots.get(s) and self.bots[s].is_alive())), None)
        if not serial:
            messagebox.showinfo("Dò khu", "Cần một giả lập đang rảnh (bấm 'Tìm giả lập' hoặc dừng bớt).",
                                parent=self.root)
            return
        if not messagebox.askokcancel(
                "Dò khu tự động",
                f"Mở bản đồ khu trên {serial} rồi bấm OK.\n\nTool sẽ lướt và chạm khắp bản đồ (mỗi màn khoảng 4 phút), "
                "chỗ nào mở popup Càn quét thì ghi lại thành một khu. Không bấm gì trong lúc dò.",
                parent=self.root):
            return
        b = DiscoverBot(Device(self.adb, serial), self.cfg, self.templates, self.q.put)
        self.bots[serial] = b
        b.start()

    def nhan_khu_moi(self, ds, moc):
        if not ds:
            messagebox.showinfo("Dò khu", "Không tìm thấy khu nào.", parent=self.root)
            return
        cq = self.cfg.setdefault("can_quet", {})
        cq["khu"] = ds  # vị trí khu gắn với mốc của lần dò này nên thay cả danh sách
        cq["moc"] = moc
        self.save_config()
        self.build_cq()
        messagebox.showinfo("Dò khu", f"Tìm thấy {len(ds)} khu ({len(moc)} mốc bản đồ).", parent=self.root)

    def xoa_khu(self, khu, loai="khu"):
        if messagebox.askyesno("Xoá", f"Xoá '{khu.get('ten')}' khỏi danh sách?", parent=self.root):
            self.cfg["can_quet"][loai].remove(khu)
            self.save_config()
            self.build_cq()

    def do_lai_ai(self, ai):
        if messagebox.askyesno("Dò lại", f"Xoá các khu đã dò của ải '{ai.get('ten')}'? Lần chạy sau tool sẽ dò lại.",
                               parent=self.root):
            ai["khu"] = []
            ai["moc"] = []
            self.save_config()
            self.build_cq()

    def doi_qua_ai(self):
        cq = self.cfg.setdefault("can_quet", {})
        cq["qua_ai"] = bool(self.v_qua_ai.get())
        cq["tu_dong_vuot_ai"] = bool(self.v_tu_dong.get())
        self.save_config()
        self.build_cq()

    def kiem_tra_ocr(self):
        from ocr import co_ocr
        co = co_ocr()
        self.q.put(("ocr", co))

    def lam_lai_hom_nay(self):
        self.cfg.setdefault("can_quet", {})["xong_tu_dong"] = {}
        self.save_config()
        self.build_cq()
        self.log("", "Đã xoá danh sách ải xong hôm nay: lần chạy sau tool đi lại từ ải đầu")

    def them_ai(self, ten, mau):
        self.cfg.setdefault("can_quet", {}).setdefault("ai", []).append({"ten": ten, "bat": True, "mau": mau, "khu": []})
        self.save_config()
        self.build_cq()
        self.log("", f"Đã thêm ải '{ten}'")

    def len_khu(self, i, loai="khu"):
        ds = self.cfg["can_quet"][loai]
        ds[i - 1], ds[i] = ds[i], ds[i - 1]
        self.save_config()
        self.build_cq()

    def luu_cq(self):
        cq = self.cfg.setdefault("can_quet", {})
        for e, k in ((self.e_moi_khu, "so_lan_moi_khu"), (self.e_tl_max, "the_luc_toi_da"), (self.e_chi_phi, "chi_phi")):
            try:
                cq[k] = int(e.get())
            except ValueError:
                pass
        try:
            cq["nhip_lan_nua"] = max(0.1, round(float(self.e_nhip.get()), 2))
        except ValueError:
            pass
        cq["cuon_map"] = bool(self.v_cuon.get())
        cq["bo_qua_the_luc"] = bool(self.v_bo_tl.get())
        cq["kieu_quet"] = self.KIEU.get(self.cb_kieu.get(), 1)
        cq["tu_dong_tham_hiem"] = bool(self.v_tham_hiem.get())
        self.save_config()

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
            CaptureWindow(self.root, Device(self.adb, serial), self.templates, self.cfg, on_khu=self.them_khu,
                          on_ai=self.them_ai)

    def them_khu(self, ten, fx, fy):
        self.cfg.setdefault("can_quet", {}).setdefault("khu", []).append(
            {"ten": ten, "bat": True, "xy": [round(fx, 4), round(fy, 4)]})
        self.save_config()
        self.build_cq()
        self.log("", f"Đã thêm khu '{ten}'")

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
        self.luu_cq()
        if self.cfg.get("che_do", "can_quet") != "can_quet":
            lop = Bot
        elif self.cfg.get("can_quet", {}).get("qua_ai", True) or self.cfg.get("can_quet", {}).get("tu_dong_vuot_ai"):
            lop = ChuongBot
        else:
            lop = SweepBot
        b = lop(Device(self.adb, serial), self.cfg, self.templates, self.q.put, stop_after=luot)
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
        self.v_che_do.set(self.cfg.get("che_do", "can_quet"))
        self.doi_che_do(luu=False)
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
                elif kieu == "ocr":
                    self.lbl_ocr.config(text="Đọc chữ: có ✔" if msg[1] else "Đọc chữ: CHƯA CÀI",
                                        foreground="#1a8f3a" if msg[1] else "#c0392b")
                elif kieu == "luu_cfg":
                    self.save_config()
                    self.build_cq()
                elif kieu == "khu_moi":
                    self.nhan_khu_moi(msg[2], msg[3] if len(msg) > 3 else [])
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
        try:  # ghi thêm ra file nhat_ky.txt để gửi khi cần hỗ trợ
            with open(os.path.join(GOC, "nhat_ky.txt"), "a", encoding="utf-8") as f:
                f.write(time.strftime("%H:%M:%S ") + dong)
        except OSError:
            pass
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
