"""Chế độ Càn quét map: quét lần lượt từng khu (toà nhà) trên bản đồ tới khi hết thể lực.

Các màn hình:
  Bản đồ   : thấy chữ "Thể lực" (cq_the_luc) → đọc thanh thể lực, chạm vào khu cần quét
  Popup khu: thấy nút "Càn quét" (cq_nut_can_quet) → chạm Càn quét, hoặc X (cq_x_popup) để rời
  Kết quả  : thấy "Càn quét lần nữa" (cq_lan_nua) → chạm lần nữa, hoặc Đóng (cq_dong)

Cấu hình trong config.json, mục "can_quet":
  chi_phi         thể lực mỗi lần quét (mặc định 4)
  the_luc_toi_da  thể lực tối đa của nhân vật (để quy đổi thanh thể lực ra số)
  so_lan_moi_khu  quét bao nhiêu lần ở một khu rồi sang khu kế (0 = quét tới khi khu hết lượt)
  lap_vong        hết danh sách khu thì quay lại khu đầu
  khu             danh sách khu: {"ten", "bat", "mau" (ảnh toà nhà, tuỳ chọn), "xy": [tỉ lệ x, tỉ lệ y]}
"""
import os
import time

import numpy as np

from ban_do import BanDoMixin, cat_tieu_de, giong_nhau
from bot import Bot, StopBot
from matcher import _doc_anh

# Vị trí thanh thể lực so với góc trên-trái chữ "Thể lực", tính theo điểm ảnh của mẫu gốc
_THANH_X = (111, 406)
_THANH_Y = (5, 40)


def doc_thanh_the_luc(screen, m):
    """Tỉ lệ đầy (0..1) của thanh thể lực cam bên phải chữ "Thể lực"; None nếu không đọc được."""
    k = m.scale
    x0, x1 = m.left + int(_THANH_X[0] * k), m.left + int(_THANH_X[1] * k)
    y0, y1 = m.top + int(_THANH_Y[0] * k), m.top + int(_THANH_Y[1] * k)
    h, w = screen.shape[:2]
    if x1 > w or y1 > h or x1 - x0 < 20:
        return None
    vung = screen[y0:y1, x0:x1].astype(np.int16)
    b, g, r = vung[..., 0], vung[..., 1], vung[..., 2]
    cam = (r > 150) & (g > 60) & (g < 210) & (b < 100) & (r - b > 120)
    cot = np.where(cam.sum(axis=0) >= max(1, int(2 * k)))[0]
    if len(cot) == 0:
        return 0.0
    return min(1.0, (cot[-1] + 1) / (x1 - x0))


class SweepBot(BanDoMixin, Bot):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._init_ban_do()
        self.kq_anh = None  # ảnh vùng "Số lần" lần cuối thấy đổi
        self.kq_doi = 0.0
        self.kq_da_cham = False
        self.mo_nham = {}  # khu → số lần mở nhầm khu khác
        self.khu_i = 0
        self.da_quet = {}  # tên khu → số lần đã quét trong vòng này
        self.het_luot = set()  # khu không quét được nữa
        self.the_luc = None  # ước tính thể lực còn lại
        self.cham_khu_lien = 0
        self.dang_mo_khu = None
        self.cho_popup = None  # khu vừa chạm "Càn quét" trong popup, chờ màn kết quả
        self.popup_hong = 0
        self.nghi_het = None  # khu nghi đã hết lượt (hoặc do hết thể lực), xác nhận khi về bản đồ

    # ---------- cấu hình ----------
    @property
    def cq(self):
        return self.cfg.setdefault("can_quet", {})

    def chi_phi(self, khu=None):
        return (khu or {}).get("chi_phi", self.cq.get("chi_phi", 4))

    def ds_khu(self):
        return [k for k in self.cq.get("khu", []) if k.get("bat", True)]

    def khu_hien_tai(self):
        ds = self.ds_khu()
        return ds[self.khu_i % len(ds)] if ds else None

    def du_chi_tieu(self, khu):
        n = self.cq.get("so_lan_moi_khu", 0)
        return khu["ten"] in self.het_luot or khu["ten"] == self.nghi_het or (n > 0 and self.da_quet.get(khu["ten"], 0) >= n)

    def du_the_luc(self, khu):
        return self.the_luc is None or self.the_luc >= self.chi_phi(khu)

    def dem(self, khu, d=1):
        self.da_quet[khu["ten"]] = self.da_quet.get(khu["ten"], 0) + d
        self.stats["can_quet"] += d
        if self.the_luc is not None:
            self.the_luc -= self.chi_phi(khu) * d
        self.emit(("stats", self.device.serial, dict(self.stats)))

    # ---------- vòng lặp ----------
    def kiem_tra_mau(self):
        can = ["cq_the_luc", "cq_nut_can_quet", "cq_x_popup", "cq_lan_nua", "cq_dong"]
        thieu = [n for n in can if not self.templates.exists(n)]
        if thieu:
            self.log("Thiếu mẫu càn quét: " + ", ".join(thieu))
        if not self.ds_khu():
            self.log("Chưa có khu nào để quét: thêm khu bằng nút ✂ → chạm vào toà nhà → '➕ Thêm khu'")
            raise StopBot

    def loop(self):
        lan_thay_cuoi = time.time()
        while not self.stop_event.is_set():
            s = self.shot()
            if self.stop_after and self.stats["can_quet"] >= self.stop_after:
                if self.thoat_ve_ban_do(s):
                    self.sleep(1.2)
                    continue
                self.log(f"Đã quét đủ {self.stop_after} lần → dừng")
                return

            xu_ly = (self.man_khong_du(s) or self.man_ket_qua(s) or self.man_popup(s) or self.man_ban_do(s))
            now = time.time()
            if xu_ly:
                lan_thay_cuoi = now
                continue
            ranh = now - lan_thay_cuoi
            if ranh > self.cq.get("dung_khi_khong_nhan_ra_giay", 90):
                self.log(f"Không nhận ra màn hình nào trong {int(ranh)} giây → dừng")
                return
            if ranh > 20 and int(ranh) % 20 == 0:
                self.log(f"⚠ {int(ranh)} giây không nhận ra màn hình (đang chuyển cảnh, hay có popup lạ?)")
            self.sleep(1.0)

    def thoat_ve_ban_do(self, s):
        """Đóng màn kết quả / popup nếu đang mở. Trả về True nếu vừa chạm."""
        for ten in ("cq_dong", "cq_x_popup"):
            m = self.find(s, ten)
            if m:
                self.tap_match(m)
                return True
        return False

    # ---------- từng màn ----------
    def man_khong_du(self, s):
        """Popup báo không đủ thể lực (nếu bạn đã cắt mẫu cq_khong_du): đóng rồi dừng, không bấm mua."""
        if not self.templates.exists("cq_khong_du") or not self.find(s, "cq_khong_du"):
            return False
        self.log("⛔ Game báo không đủ thể lực → dừng")
        m = self.find(s, "cq_x_popup")
        if m:
            self.tap_match(m)
        raise StopBot

    def man_ket_qua(self, s):
        m_lan_nua = self.find(s, "cq_lan_nua")
        if not m_lan_nua:
            return False
        khu = self.dang_mo_khu or self.khu_hien_tai()
        self.cho_popup = None
        self.popup_hong = 0
        k = m_lan_nua.scale
        # vùng chữ "Số lần: 98/99" ngay dưới chữ "Càn quét lần nữa"
        y0, y1 = m_lan_nua.top + int(75 * k), m_lan_nua.top + int(135 * k)
        x0, x1 = m_lan_nua.left - int(45 * k), m_lan_nua.left + int(285 * k)
        so_lan = s[max(0, y0):y1, max(0, x0):x1].astype(np.int16)

        now = time.time()
        if self.kq_anh is None or self.kq_anh.shape != so_lan.shape:
            self.kq_anh, self.kq_doi = so_lan, now
        elif (np.abs(self.kq_anh - so_lan).sum(axis=2) > 90).mean() >= 0.003:
            # "Số lần" vừa đổi → thêm một lần càn quét thành công
            self.kq_anh, self.kq_doi = so_lan, now
            if self.kq_da_cham:
                self.dem(khu)
        elif self.kq_da_cham and now - self.kq_doi > self.cq.get("cho_khong_doi_giay", 4):
            # bấm liên tục mà "Số lần" không đổi → khu hết lượt hoặc hết thể lực
            self.log("  'Càn quét lần nữa' không còn tác dụng")
            self.nghi_het = khu["ten"]
            self.the_luc = None  # đọc lại trên bản đồ

        du_tong = self.stop_after and self.stats["can_quet"] >= self.stop_after
        if khu and not du_tong and not self.du_chi_tieu(khu) and self.du_the_luc(khu) and khu["ten"] not in self.het_luot:
            # chạm vào biểu tượng đầu lâu phía trên chữ, liên tục theo nhịp
            self.tap(m_lan_nua.x, m_lan_nua.y - int(118 * k))
            if not self.kq_da_cham:
                self.log(f"• Càn quét lần nữa liên tục – {khu['ten']}")
            self.kq_da_cham = True
            self.sleep(self.cq.get("nhip_lan_nua", 0.35))
            return True

        m = self.find(s, "cq_dong")
        self.log(f"• Đóng kết quả – {khu['ten']} đã quét {self.da_quet.get(khu['ten'], 0)} lần")
        if m:
            self.tap_match(m)
        else:
            self.tap(m_lan_nua.x, m_lan_nua.y + int(266 * k))
        self.dang_mo_khu = None
        self.reset_kq()
        self.sleep(1.2)
        return True

    def reset_kq(self):
        self.kq_anh = None
        self.kq_da_cham = False

    def man_popup(self, s):
        m_x = self.find(s, "cq_x_popup")
        m_cq = self.find(s, "cq_nut_can_quet")
        if not m_cq and not (m_x and self.find(s, "cq_nut_tham_hiem")):
            return False
        khu = self.dang_mo_khu or self.khu_hien_tai()
        self.cham_khu_lien = 0
        self.reset_kq()
        if self.dang_mo_khu is not None and self.cho_popup is None and m_x and not self.dung_khu(s, m_x, khu):
            # bản đồ lệch so với lúc dò → mở nhầm khu khác: đóng lại, lấy mốc lại
            self.mo_nham[khu["ten"]] = self.mo_nham.get(khu["ten"], 0) + 1
            if self.mo_nham[khu["ten"]] >= 3:
                self.log(f"  Không mở đúng được {khu['ten']} → bỏ qua khu này")
                self.het_luot.add(khu["ten"])
            else:
                self.log(f"  Mở nhầm khu khác (bản đồ lệch) → lấy mốc lại rồi thử lại {khu['ten']}")
            self.cam_ok = False
            self.tap_match(m_x)
            self.dang_mo_khu = None
            self.sleep(1.2)
            return True
        if self.cho_popup is khu:
            # đã chạm "Càn quét" mà vẫn ở popup → không quét được (hết lượt / thiếu thể lực)
            self.cho_popup = None
            self.dem(khu, -1)
            self.popup_hong += 1
            self.log("  Chạm 'Càn quét' nhưng không có kết quả")
            if self.popup_hong >= 2:
                self.nghi_het = khu["ten"]
                self.the_luc = None
        if not m_cq:
            self.log(f"  {khu['ten']}: không có nút Càn quét (chưa mở hoặc hết lượt) → sang khu khác")
            self.het_luot.add(khu["ten"])
        elif self.du_chi_tieu(khu) or not self.du_the_luc(khu):
            pass
        else:
            self.dang_mo_khu = khu
            self.cho_popup = khu
            self.tap_match(m_cq)
            self.dem(khu)
            self.log(f"• Càn quét – {khu['ten']} ({self.da_quet.get(khu['ten'], 0)})")
            self.sleep(2.0)
            return True
        if m_x:
            self.tap_match(m_x)
        self.dang_mo_khu = None
        self.cho_popup = None
        self.sleep(1.2)
        return True

    def dung_khu(self, s, m_x, khu):
        """Popup đang mở có đúng tiêu đề khu (ảnh lưu lúc dò) không. Khu không có ảnh thì coi là đúng."""
        ten_anh = khu.get("tieu_de")
        if not ten_anh:
            return True
        p = os.path.join(self.templates.folder, "tieu_de_khu", ten_anh)
        if not os.path.isfile(p):
            return True
        return giong_nhau(_doc_anh(p), cat_tieu_de(s, m_x))

    def man_ban_do(self, s):
        m = self.find(s, "cq_the_luc")
        if not m:
            return False
        self.reset_kq()
        ti_le = doc_thanh_the_luc(s, m)
        if ti_le is not None and ti_le >= 0.985:
            # thanh đầy: có thể đang vượt mức tối đa (đã mua thêm) → không giới hạn theo ước tính,
            # khi hết thật thì "Càn quét lần nữa" hết tác dụng và lần về bản đồ sau sẽ đọc lại.
            self.the_luc = None
            self.emit(("stats", self.device.serial, {**self.stats, "the_luc": "đầy"}))
        elif ti_le is not None:
            toi_da = self.cq.get("the_luc_toi_da", 120)
            self.the_luc = int(ti_le * toi_da + 0.3)
            self.emit(("stats", self.device.serial, {**self.stats, "the_luc": self.the_luc}))

        ds = self.ds_khu()
        if self.the_luc is not None and ds and self.the_luc < min(self.chi_phi(k) for k in ds):
            self.log(f"⛔ Hết thể lực (còn khoảng {self.the_luc}) → dừng")
            raise StopBot
        if self.nghi_het:
            # thể lực vẫn đủ → khu đó thật sự đã hết lượt
            self.log(f"  {self.nghi_het}: hết lượt → sang khu kế")
            self.het_luot.add(self.nghi_het)
            self.nghi_het = None

        khu = self.chon_khu()
        if khu is None:
            return True
        if not self.du_the_luc(khu):
            self.log(f"⛔ Hết thể lực (còn khoảng {self.the_luc}, cần {self.chi_phi(khu)}) → dừng")
            raise StopBot

        self.cham_khu_lien += 1
        if self.cham_khu_lien > 3:
            self.log(f"  Chạm '{khu['ten']}' 3 lần không mở được → bỏ qua khu này")
            self.het_luot.add(khu["ten"])
            self.cham_khu_lien = 0
            return True

        vt = self.vi_tri_khu(s, khu)
        if vt is None:
            return True  # vừa vuốt bản đồ mà không đo được vị trí: vòng sau lấy mốc lại
        self.dang_mo_khu = khu
        self.log(f"• Mở khu {khu['ten']} (thể lực ~{self.the_luc if self.the_luc is not None else 'đầy'})")
        self.tap(*vt)
        self.sleep(1.5)
        return True

    def chon_khu(self):
        ds = self.ds_khu()
        for _ in range(len(ds)):
            khu = self.khu_hien_tai()
            if not self.du_chi_tieu(khu):
                return khu
            self.khu_i += 1
        # mọi khu đều xong
        if self.cq.get("lap_vong", True) and len(self.het_luot) < len(ds):
            self.log("↻ Xong một vòng các khu, quay lại khu đầu")
            self.da_quet.clear()
            self.khu_i = 0
            return self.chon_khu()
        self.log("✔ Đã quét xong mọi khu → dừng")
        raise StopBot

    def vi_tri_khu(self, s, khu):
        if "xy_map" in khu:
            if not self.cam_ok:
                self.log("  Vuốt về góc bản đồ để lấy mốc...")
                s = self.ve_goc()
            kq = self.toi_diem(s, *khu["xy_map"])
            return None if kq is None else kq[:2]
        if khu.get("mau") and self.templates.exists(khu["mau"]):
            m = self.find(s, khu["mau"])
            if m:
                return m.x, m.y
        gx, gy, gw, gh = self.templates.vung(s)
        fx, fy = khu["xy"]
        return gx + fx * gw, gy + fy * gh
