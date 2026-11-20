"""Chế độ qua ải: quét hết khu của một ải thì bấm Trở lại, vào ải kế (1-1 → 1-2 → 1-3 → ...).

Danh sách ải nằm trong config.json, mục can_quet.ai. Mỗi ải có:
  ten   tên hiển thị
  bat   có quét ải này không
  mau   ảnh mẫu nhãn ải trên màn chương (ví dụ ai_1_2 = chữ "1-2 Thành Phố Bỏ Hoang")
  khu   danh sách khu của ải; để trống thì lần đầu vào ải tool tự dò rồi lưu lại
Nếu không thấy nhãn ải trên màn chương, tool bấm mũi tên ▶ (rồi ◀) để tìm ở chương khác.
"""
import re
import time

from bot import StopBot
from discover import DiscoverBot
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

    def la_chuong(self, s):
        return self.find(s, "cq_chuong") is not None

    # ---------- vòng lặp ----------
    def loop(self):
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
