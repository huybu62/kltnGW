"""Chế độ qua ải: quét hết khu của một ải thì bấm Trở lại, vào ải kế (1-1 → 1-2 → 1-3 → ...).

Danh sách ải nằm trong config.json, mục can_quet.ai. Mỗi ải có:
  ten   tên hiển thị
  bat   có quét ải này không
  mau   ảnh mẫu nhãn ải trên màn chương (ví dụ ai_1_2 = chữ "1-2 Thành Phố Bỏ Hoang")
  khu   danh sách khu của ải; để trống thì lần đầu vào ải tool tự dò rồi lưu lại
Nếu không thấy nhãn ải trên màn chương, tool bấm mũi tên ▶ (rồi ◀) để tìm ở chương khác.

Chế độ TỰ ĐỘNG VƯỢT ẢI (can_quet.tu_dong_vuot_ai, cần OCR): không cần danh sách ải. Tool đọc chữ màn
chương (tên nước + số ải), vào lần lượt ải 1 → 4, dò khu (lần đầu), thám hiểm khu chưa mở, càn quét hết,
Trở lại; xong 4 ải thì bấm mũi tên xanh ▶ sang nước sau. Khu/mốc của từng ải lưu ở can_quet.ai_tu_dong,
ải đã xong trong ngày lưu ở can_quet.xong_tu_dong.
"""
import re
import time

from bot import StopBot
from chuong_ocr import doc_man_chuong
from discover import DiscoverBot
from ocr import co_ocr, gon
from sweep import SweepBot, XongKhu


class ChuongBot(DiscoverBot):
    ai_dang = None

    def kiem_tra_mau(self):
        can = ["cq_the_luc", "cq_x_popup", "cq_nut_tham_hiem", "cq_nut_can_quet", "cq_lan_nua", "cq_dong",
               "cq_tro_lai", "cq_chuong"]
        thieu = [n for n in can if not self.templates.exists(n)]
        if thieu:
            self.log("Thiếu mẫu: " + ", ".join(thieu))
            raise StopBot
        if self.cq.get("tu_dong_vuot_ai") and co_ocr():
            return
        if not self.ds_ai():
            self.log("Chưa có ải nào để quét (bật ải trong danh sách, hoặc thêm ải bằng ✂ → ➕ Thêm ải)")
            raise StopBot

    def ds_ai(self):
        return [a for a in self.cq.get("ai", []) if a.get("bat", True)]

    def ds_khu(self):
        if self.ai_dang is None:
            return super().ds_khu()
        return [k for k in self.ai_dang.get("khu", []) if k.get("bat", True)]

    def ds_moc(self):
        if getattr(self, "dang_do", False):
            return self.moc_moi
        return (self.ai_dang or {}).get("moc", [])

    def man_khac(self, s):
        """Đang quét mà lỡ về màn chương (vd. bấm Quay lại ở màn lạ) → vào lại ải đang quét."""
        if self.ai_dang is None or not self.la_chuong(s):
            return False
        if self.ai_dang.get("mau"):
            m = self.find(s, self.ai_dang["mau"])
            if not m:
                return False
            self.log(f"  Đang ở màn chương → vào lại ải {self.ai_dang['ten']}")
            self.tap_match(m)
        elif getattr(self, "ai_vi_tri", None):
            self.log(f"  Đang ở màn chương → vào lại ải {self.ai_dang['ten']}")
            self.tap(*self.ai_vi_tri)
        else:
            return False
        self.cam_ok = False
        self.sleep(3.0)
        return True

    def la_chuong(self, s):
        return self.find(s, "cq_chuong") is not None

    # ---------- vòng lặp ----------
    def loop(self):
        if self.cq.get("tu_dong_vuot_ai"):
            if co_ocr():
                return self.loop_tu_dong()
            self.log("⚠ Chưa cài bộ đọc chữ (OCR) nên không tự vượt ải được → dùng danh sách ải như cũ")
        for ai in self.ds_ai():
            if not self.templates.exists(ai.get("mau", "")):
                self.log(f"Ải {ai['ten']}: chưa có ảnh mẫu nhãn ải → bỏ qua")
                continue
            self.log(f"══ Ải {ai['ten']} ══")
            if not self.vao_ai(ai):
                self.log(f"  Không tìm thấy ải {ai['ten']} trên màn chương → bỏ qua")
                continue
            self.ai_dang = ai
            self.reset_khu()
            if not ai.get("khu") or (self.cq.get("cuon_map", True) and not ai.get("moc")):
                self.log("  Ải này chưa dò khu (hoặc dò bằng bản cũ chưa có mốc) → dò trước, sau đó nhớ luôn")
                ai["khu"] = self.do_ca_ban_do(tien_to=re.sub(r"[^a-z0-9_]", "", ai["mau"]) + "_")
                ai["moc"] = self.moc_ket_qua
                self.emit(("luu_cfg",))
                self.reset_khu()
            if self.ds_khu():
                try:
                    SweepBot.loop(self)
                except XongKhu:
                    pass
                else:
                    return  # dừng vì đủ số lần đặt, hoặc gặp màn lạ quá lâu
            else:
                self.log("  Ải này không có khu nào càn quét được")
            self.ai_dang = None
            self.ra_chuong()
        self.log("✔ Đã quét xong mọi ải")

    def vao_ai(self, ai):
        """Từ đâu cũng về màn chương, tìm nhãn ải (đổi chương bằng mũi tên nếu cần) rồi vào ải."""
        phai, trai = 0, 0
        het_han = time.time() + 150
        while time.time() < het_han:
            s = self.shot()
            if self.la_ban_do(s):
                m = self.find(s, "cq_tro_lai")
                if m:
                    self.tap_match(m)
                    self.sleep(2.0)
                    continue
            if self.la_chuong(s):
                m = self.find(s, ai["mau"])
                if m:
                    self.tap_match(m)
                    for _ in range(15):
                        self.sleep(1.0)
                        if self.la_ban_do(self.shot()):
                            self.sleep(0.5)
                            return True
                    return False
                if phai < 8 and self.templates.exists("cq_mui_ten_phai"):
                    m = self.find(s, "cq_mui_ten_phai")
                    if m:
                        self.log("  Không thấy ải ở chương này → sang chương sau ▶")
                        self.tap_match(m)
                        phai += 1
                        self.sleep(2.0)
                        continue
                    phai = 8
                if trai < 16 and self.templates.exists("cq_mui_ten_trai"):
                    m = self.find(s, "cq_mui_ten_trai")
                    if m:
                        self.log("  → về chương trước ◀")
                        self.tap_match(m)
                        trai += 1
                        self.sleep(2.0)
                        continue
                return False
            # popup / màn kết quả còn mở
            if not self.thoat_ve_ban_do(s):
                self.sleep(1.0)
            else:
                self.sleep(1.2)
        return False

    def ra_chuong(self):
        for _ in range(10):
            s = self.shot()
            if self.la_chuong(s):
                return
            if self.la_ban_do(s):
                m = self.find(s, "cq_tro_lai")
                if m:
                    self.log("• Trở lại màn chương")
                    self.tap_match(m)
            else:
                self.thoat_ve_ban_do(s)
            self.sleep(1.5)

    # ---------- tự động vượt ải (đọc chữ) ----------
    def ds_xong(self):
        d = self.cq.get("xong_tu_dong") or {}
        return set(d.get("ds", [])) if d.get("ngay") == time.strftime("%Y-%m-%d") else set()

    def danh_dau_xong(self, key):
        hom_nay = time.strftime("%Y-%m-%d")
        d = self.cq.get("xong_tu_dong") or {}
        if d.get("ngay") != hom_nay:
            d = {"ngay": hom_nay, "ds": []}
        if key not in d["ds"]:
            d["ds"].append(key)
        self.cq["xong_tu_dong"] = d
        self.emit(("luu_cfg",))

    def ve_man_chuong(self):
        for _ in range(25):
            s = self.shot()
            if self.la_chuong(s):
                return s
            if self.la_ban_do(s):
                m = self.find(s, "cq_tro_lai")
                if m:
                    self.tap_match(m)
                    self.sleep(2.0)
                    continue
            if self.man_tran(s):
                continue
            if not self.thoat_ve_ban_do(s):
                self.go_man_la(s)
            self.sleep(1.0)
        self.luu_anh_loi(self.shot(), "không về được màn chương")
        self.log("⛔ Không về được màn chương (có nút 'Chương' góc phải trên) → dừng")
        raise StopBot

    def vao_ai_xy(self, x, y):
        self.tap(x, y)
        for _ in range(15):
            self.sleep(1.0)
            if self.la_ban_do(self.shot()):
                self.sleep(0.5)
                return True
        return False

    def sang_nuoc_sau(self, s, nuoc):
        m = self.find(s, "cq_mui_ten_phai") if self.templates.exists("cq_mui_ten_phai") else None
        if not m:
            return False
        self.log(f"▶ Xong các ải của {nuoc} → bấm mũi tên xanh sang nước sau")
        self.tap_match(m)
        self.sleep(2.5)
        s2 = self.shot()
        nuoc2, _ = doc_man_chuong(s2, self.templates.vung(s2))
        if not nuoc2 or gon(nuoc2) == gon(nuoc):
            self.log("  Không sang được nước sau (đã là nước cuối hoặc chưa mở)")
            return False
        return True

    def loop_tu_dong(self):
        xong = self.ds_xong()
        da_thu = set()
        doc_hong = 0
        while True:
            s = self.ve_man_chuong()
            nuoc, ds = doc_man_chuong(s, self.templates.vung(s))
            if not ds:
                doc_hong += 1
                self.luu_anh_loi(s, "không đọc được nhãn ải trên màn chương")
                if doc_hong >= 3:
                    self.log("⛔ Không đọc được nhãn ải nào → dừng (tắt app auto click nếu nó che màn hình)")
                    return
                self.sleep(2.0)
                continue
            doc_hong = 0
            nuoc = nuoc or "?"
            con = [a for a in ds if f"{nuoc} {a[0]}" not in xong and f"{nuoc} {a[0]}" not in da_thu]
            if not con:
                if not self.sang_nuoc_sau(s, nuoc):
                    self.log("✔ Đã đi hết các ải các nước mở được")
                    return
                continue
            so, nhan, x, y = con[0]
            key = f"{nuoc} {so}"
            da_thu.add(key)
            self.log(f"══ {nuoc} – ải {so}: {nhan} ══")
            self.ai_vi_tri = (x, y)
            if not self.vao_ai_xy(x, y):
                self.luu_anh_loi(self.shot(), f"không vào được ải {key}")
                self.log(f"  Không vào được ải {key} (chưa mở?) → bỏ qua")
                continue
            data = self.cq.setdefault("ai_tu_dong", {}).setdefault(key, {"ten": key})
            self.ai_dang = data
            self.reset_khu()
            if not data.get("khu") or (self.cq.get("cuon_map", True) and not data.get("moc")):
                self.log("  Ải này chưa dò khu → dò trước (chỉ một lần, sau đó nhớ luôn)")
                data["khu"] = self.do_ca_ban_do(tien_to=re.sub(r"[^a-z0-9]+", "_", gon(key)) + "_")
                data["moc"] = self.moc_ket_qua
                self.emit(("luu_cfg",))
                self.reset_khu()
            if self.ds_khu():
                try:
                    SweepBot.loop(self)
                except XongKhu:
                    pass
                else:
                    return  # dừng vì đủ số lần đặt, hoặc gặp màn lạ quá lâu
            else:
                self.log("  Ải này không có khu nào")
            self.danh_dau_xong(key)
            xong.add(key)
            self.ai_dang = None
            self.ra_chuong()
