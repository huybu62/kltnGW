"""Cửa sổ cắt ảnh mẫu từ màn hình giả lập và thử nhận diện."""
import os
import re
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox, simpledialog, ttk

import cv2
from PIL import Image, ImageTk

from matcher import ghi_anh, vung_game

RONG_TOI_DA = 1000
CAO_TOI_DA = 620


class CaptureWindow(tk.Toplevel):
    def __init__(self, master, device, templates, cfg, on_khu=None, on_ai=None):
        super().__init__(master)
        self.on_khu = on_khu
        self.on_ai = on_ai
        self.device = device
        self.templates = templates
        self.cfg = cfg
        self.title(f"Cắt ảnh mẫu – {device.serial}")
        self.attributes("-topmost", True)
        self.img = None
        self.scale = 1.0
        self.sel = None  # (x1, y1, x2, y2) theo toạ độ thật
        self.diem_chon = None
        self._start = None
        self._rect = None

        tb = ttk.Frame(self, padding=4)
        tb.pack(fill="x")
        ttk.Button(tb, text="📷 Chụp lại", command=self.shoot).pack(side="left")
        ttk.Button(tb, text="🔍 Thử nhận diện", command=self.test).pack(side="left", padx=4)
        ttk.Button(tb, text="📁 Thư mục mẫu", command=self.open_folder).pack(side="left")
        self.lbl_xy = ttk.Label(tb, text="Kéo chuột để chọn vùng. Chạm 1 điểm để lấy toạ độ.")
        self.lbl_xy.pack(side="left", padx=8)

        self.canvas = tk.Canvas(self, width=800, height=450, bg="#222", highlightthickness=0, cursor="crosshair")
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<ButtonPress-1>", self.on_press)
        self.canvas.bind("<B1-Motion>", self.on_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_release)

        bot = ttk.Frame(self, padding=4)
        bot.pack(fill="x")
        ttk.Label(bot, text="Tên mẫu:").pack(side="left")
        mo_ta = self.cfg.get("mo_ta_mau", {})
        ten = list(mo_ta) + [n for n in templates.names() if n not in mo_ta]
        self.cb = ttk.Combobox(bot, values=ten, width=22)
        self.cb.pack(side="left", padx=4)
        self.cb.bind("<<ComboboxSelected>>", self.on_name)
        self.cb.bind("<KeyRelease>", self.on_name)
        ttk.Button(bot, text="💾 Lưu mẫu", command=self.save).pack(side="left")
        ttk.Button(bot, text="Sao chép toạ độ", command=self.copy_xy).pack(side="left", padx=4)
        ttk.Button(bot, text="➕ Thêm khu", command=self.them_khu).pack(side="left")
        ttk.Button(bot, text="➕ Thêm ải", command=self.them_ai).pack(side="left", padx=4)
        self.lbl_desc = ttk.Label(bot, text="", foreground="#666")
        self.lbl_desc.pack(side="left", padx=6)

        self.ket_qua = tk.Listbox(self, height=6)
        self.ket_qua.pack(fill="x")

        self.shoot()

    # ---------- chụp & hiển thị ----------
    def shoot(self):
        self.lbl_xy.config(text="Đang chụp màn hình...")

        def lam():
            try:
                img = self.device.screenshot()
                self.after(0, lambda: self.show(img))
            except Exception as e:
                self.after(0, lambda: self.lbl_xy.config(text=f"Lỗi chụp: {e}"))

        threading.Thread(target=lam, daemon=True).start()

    def show(self, img, ve_them=None):
        self.img = img
        h, w = img.shape[:2]
        self.scale = min(1.0, RONG_TOI_DA / w, CAO_TOI_DA / h)
        hien = img.copy()
        for (x, y, rw, rh, nhan) in ve_them or []:
            cv2.rectangle(hien, (x, y), (x + rw, y + rh), (0, 220, 0), 2)
            cv2.putText(hien, nhan, (x, max(12, y - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
        rgb = cv2.cvtColor(hien, cv2.COLOR_BGR2RGB)
        pil = Image.fromarray(rgb).resize((int(w * self.scale), int(h * self.scale)))
        self.photo = ImageTk.PhotoImage(pil)
        self.canvas.config(width=pil.width, height=pil.height)
        self.canvas.delete("all")
        self.canvas.create_image(0, 0, anchor="nw", image=self.photo)
        self._rect = None
        if not ve_them:
            self.sel = None
            self.lbl_xy.config(text=f"Màn hình {w}×{h}. Kéo chuột để chọn vùng. Chạm 1 điểm để lấy toạ độ.")

    # ---------- chọn vùng ----------
    def _that(self, cx, cy):
        h, w = self.img.shape[:2]
        x = int(min(max(cx / self.scale, 0), w - 1))
        y = int(min(max(cy / self.scale, 0), h - 1))
        return x, y

    def on_press(self, e):
        if self.img is None:
            return
        self._start = (e.x, e.y)
        if self._rect:
            self.canvas.delete(self._rect)
        self._rect = self.canvas.create_rectangle(e.x, e.y, e.x, e.y, outline="#ff3b3b", width=2)

    def on_drag(self, e):
        if self._start and self._rect:
            self.canvas.coords(self._rect, self._start[0], self._start[1], e.x, e.y)

    def on_release(self, e):
        if not self._start:
            return
        x1, y1 = self._that(*self._start)
        x2, y2 = self._that(e.x, e.y)
        self._start = None
        x1, x2 = sorted((x1, x2))
        y1, y2 = sorted((y1, y2))
        if x2 - x1 < 6 or y2 - y1 < 6:
            self.sel = None
            self.diem_chon = (x1, y1)
            self.lbl_xy.config(text=f"Toạ độ: [{x1}, {y1}]")
            return
        self.sel = (x1, y1, x2, y2)
        self.diem_chon = ((x1 + x2) // 2, (y1 + y2) // 2)
        self.lbl_xy.config(text=f"Vùng: x={x1} y={y1} {x2 - x1}×{y2 - y1}  ·  tâm [{self.diem_chon[0]}, {self.diem_chon[1]}]")

    def on_name(self, _e=None):
        self.lbl_desc.config(text=self.cfg.get("mo_ta_mau", {}).get(self.cb.get().strip(), ""))

    def copy_xy(self):
        if self.diem_chon:
            self.clipboard_clear()
            self.clipboard_append(f"[{self.diem_chon[0]}, {self.diem_chon[1]}]")

    def them_khu(self):
        """Thêm điểm vừa chạm làm một khu càn quét (lưu theo tỉ lệ vùng game)."""
        if self.img is None or not self.diem_chon:
            messagebox.showinfo("Chưa chọn điểm", "Chạm vào toà nhà (khu) trên ảnh trước.", parent=self)
            return
        ten = simpledialog.askstring("Thêm khu", "Tên khu (ví dụ Công xưởng):", parent=self)
        if not ten:
            return
        gx, gy, gw, gh = self.templates.vung(self.img)
        x, y = self.diem_chon
        if self.on_khu:
            self.on_khu(ten.strip(), (x - gx) / gw, (y - gy) / gh)
        self.lbl_xy.config(text=f"Đã thêm khu '{ten.strip()}'")

    def them_ai(self):
        """Khoanh chữ nhãn ải trên màn chương (ví dụ "2-1 ...") → lưu mẫu và thêm vào danh sách ải."""
        if self.img is None or not self.sel:
            messagebox.showinfo("Chưa chọn vùng", "Ở màn chương, kéo chuột khoanh phần CHỮ của nhãn ải "
                                "(ví dụ '2-1 Tên ải') rồi bấm lại.", parent=self)
            return
        ten = simpledialog.askstring("Thêm ải", "Tên ải (ví dụ 2-1 Sa Mạc):", parent=self)
        if not ten:
            return
        ma = "ai_" + (re.sub(r"[^0-9a-z]+", "_", ten.strip().lower().split(" ")[0]).strip("_") or "moi")
        while self.templates.exists(ma):
            ma += "_"
        x1, y1, x2, y2 = self.sel
        path = os.path.join(self.templates.folder, f"{ma}.png")
        ghi_anh(path, self.img[y1:y2, x1:x2])
        self.templates.ghi_ti_le(path, self.templates.vung(self.img)[2])
        if self.on_ai:
            self.on_ai(ten.strip(), ma)
        self.lbl_xy.config(text=f"Đã thêm ải '{ten.strip()}' (mẫu {ma}.png)")

    # ---------- lưu ----------
    def save(self):
        if self.img is None or not self.sel:
            messagebox.showinfo("Chưa chọn vùng", "Hãy kéo chuột để khoanh vùng nút trên ảnh.", parent=self)
            return
        ten = self.cb.get().strip()
        if not re.fullmatch(r"[a-z0-9_]+", ten):
            messagebox.showwarning("Tên không hợp lệ", "Tên mẫu chỉ gồm chữ thường không dấu, số và dấu _ (ví dụ nut_xuc_xac).", parent=self)
            return
        x1, y1, x2, y2 = self.sel
        cat = self.img[y1:y2, x1:x2]
        path = os.path.join(self.templates.folder, f"{ten}.png")
        if self.templates.exists(ten):
            tl = messagebox.askyesnocancel(
                "Mẫu đã có",
                f"Đã có mẫu '{ten}'.\n\nCó = thay thế mẫu cũ\nKhông = thêm biến thể (giữ cả hai)\nHuỷ = không lưu",
                parent=self,
            )
            if tl is None:
                return
            if tl is False:
                path = self.templates.next_variant_path(ten)
        ghi_anh(path, cat)
        self.templates.ghi_ti_le(path, self.templates.vung(self.img)[2])
        self.lbl_xy.config(text=f"Đã lưu {os.path.basename(path)} ({x2 - x1}×{y2 - y1})")
        if ten not in self.cb["values"]:
            self.cb["values"] = list(self.cb["values"]) + [ten]

    # ---------- thử nhận diện ----------
    def test(self):
        if self.img is None:
            return
        nguong = self.cfg.get("nguong_khop", 0.85)
        rieng = self.cfg.get("nguong_rieng", {})
        ve, dong = [], []
        for ten in self.templates.names():
            m = self.templates.best(self.img, ten)
            if not m:
                continue
            ng = rieng.get(ten, nguong)
            ok = m.score >= ng
            dong.append((m.score, f"{'✔' if ok else '✘'} {ten}: {m.score:.2f} (ngưỡng {ng:.2f}) tại [{m.x}, {m.y}]"))
            if ok:
                ve.append((m.left, m.top, m.w, m.h, ten))
        self.show(self.img, ve_them=ve)
        self.ket_qua.delete(0, "end")
        for _, d in sorted(dong, reverse=True):
            self.ket_qua.insert("end", d)
        if not dong:
            self.ket_qua.insert("end", "Chưa có ảnh mẫu nào trong thư mục mau/")

    def open_folder(self):
        mo_thu_muc(self.templates.folder)


def mo_thu_muc(path):
    if sys.platform == "win32":
        os.startfile(path)
    elif sys.platform == "darwin":
        subprocess.Popen(["open", path])
    else:
        subprocess.Popen(["xdg-open", path])
