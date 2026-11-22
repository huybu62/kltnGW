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
import threading
import time

import cv2
import numpy as np

from ban_do import BanDoMixin, cat_tieu_de, giong_nhau
from bot import Bot, StopBot
from matcher import _doc_anh
from ocr import co_ocr, doc, gon, so_trong

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
    hsv = cv2.cvtColor(screen[y0:y1, x0:x1], cv2.COLOR_BGR2HSV)
    h, s_, v = hsv[..., 0].astype(np.int16), hsv[..., 1].astype(np.int16), hsv[..., 2].astype(np.int16)
    cam = (h >= 5) & (h <= 25) & (s_ > 150) & (v > 180)  # phần đầy: cam sáng
    nen = ((h <= 8) | (h >= 170)) & (s_ > 100) & (v >= 25) & (v <= 120)  # phần trống: đỏ sẫm
    can = max(1, int(2 * k))
    cot_cam = cam.sum(axis=0) >= can
    cot_nen = nen.sum(axis=0) >= can
    if (cot_cam | cot_nen).mean() < 0.7:
        return None  # màn đang tối/mờ (popup vừa đóng, chuyển cảnh): không đọc được, KHÔNG coi là 0
    cot = np.where(cot_cam)[0]
    if len(cot) == 0:
        return 0.0
    return min(1.0, (cot[-1] + 1) / (x1 - x0))


class MayBam(threading.Thread):
    """Luồng chỉ lo bấm một điểm đều nhịp; luồng chính vẫn chụp/kiểm tra song song."""

    def __init__(self, bot, x, y, nhip):
        super().__init__(daemon=True)
        self.bot, self.x, self.y, self.nhip = bot, x, y, nhip
        self.dung = threading.Event()
        self.da_bam = 0
        self.toi_da = None  # tổng số cú được bấm (None = không giới hạn)

    def run(self):
        while not self.dung.is_set() and not self.bot.stop_event.is_set():
            if self.toi_da is not None and self.da_bam >= self.toi_da:
                if self.bot.cho_bam(self.dung, 0.05):
                    break
                continue
            try:
                self.bot.tap_nhanh(self.x, self.y)
            except Exception:
                break
            self.da_bam += 1
            if self.bot.cho_bam(self.dung, self.nhip):
                break


class XongKhu(StopBot):
    """Mọi khu của bản đồ hiện tại đã quét xong (chế độ qua ải sẽ sang ải kế)."""


class SweepBot(BanDoMixin, Bot):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.the_luc = None  # ước tính thể lực còn lại
        self.reset_khu()

    def reset_khu(self):
        """Trạng thái riêng của một bản đồ (gọi lại khi sang ải khác)."""
        self._init_ban_do()
        self.kq_anh = None  # ảnh vùng "Số lần" lần cuối thấy đổi
        self.kq_doi = 0.0
        self.kq_da_cham = False
        self.mo_nham = {}  # khu → số lần mở nhầm khu khác
        self.khu_i = 0
        self.da_quet = {}  # tên khu → số lần đã quét trong vòng này
        self.het_luot = set()  # khu không quét được nữa
        self.cham_khu_lien = 0
        self.dinh_vi_hong = 0
        self.bo_vong = set()  # khu tạm bỏ qua trong vòng này (thử lại ở vòng sau)
        self.boi_hong = set()  # khu không dùng được x5/x10 nữa (còn ít lượt / hết Xu) → quét từng lần
        self.cho_boi = None  # (khu, n, ảnh "Số lần còn lại") vừa bấm x5/x10, chờ bảng hỏi
        self.boi_xac_nhan = None  # (khu, n, ảnh "Số lần còn lại") vừa bấm Xác định
        self.dang_danh = None  # khu đang thám hiểm (đánh trận)
        self.danh_tu = 0.0
        self.con_lai = {}  # khu → "Số lần còn lại" đọc được gần nhất
        self.so_lan_tam_bo = {}
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

    def ds_moc(self):
        return self.cq.get("moc", [])

    def khu_hien_tai(self):
        ds = self.ds_khu()
        return ds[self.khu_i % len(ds)] if ds else None

    def du_chi_tieu(self, khu):
        n = self.cq.get("so_lan_moi_khu", 0)
        return khu["ten"] in self.het_luot or khu["ten"] in self.bo_vong or khu["ten"] == self.nghi_het or (n > 0 and self.da_quet.get(khu["ten"], 0) >= n)

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
                self.dung_bam()
                if self.thoat_ve_ban_do(s):
                    self.sleep(1.2)
                    continue
                self.log(f"Đã quét đủ {self.stop_after} lần → dừng")
                return

            la_kq = self.man_khong_du(s) or self.man_hoi(s) or self.man_quet_lai(s) or self.man_ket_qua(s)
            if not la_kq and self.bam_xuyen_hieu_ung(s):
                lan_thay_cuoi = time.time()
                continue
            if not la_kq:
                self.dung_bam()  # rời hẳn màn kết quả: ngừng bấm
            xu_ly = la_kq or self.man_popup(s) or self.man_ban_do(s) or self.man_tran(s) or self.man_khac(s)
            now = time.time()
            if xu_ly:
                lan_thay_cuoi = now
                self.go_la_lan = 0
                continue
            ranh = now - lan_thay_cuoi
            if ranh > 2.5:
                self.go_man_la(s)
            if ranh > self.cq.get("dung_khi_khong_nhan_ra_giay", 90):
                self.log(f"Không nhận ra màn hình nào trong {int(ranh)} giây → dừng")
                return
            if ranh > 20 and int(ranh) % 20 == 0:
                self.log(f"⚠ {int(ranh)} giây không nhận ra màn hình (đang chuyển cảnh, hay có popup lạ?)")
            self.sleep(1.0)

    def man_khac(self, s):
        """Chỗ cho lớp con xử lý thêm màn (vd. màn chương)."""
        return False

    def go_man_la(self, s):
        """Màn lạ (lên cấp, nhận thưởng, thông báo...): chạm mép trên màn hình, không được thì bấm
        Quay lại. Không chạm giữa màn để tránh bấm nhầm nút mua."""
        lan = getattr(self, "go_la_lan", 0)
        self.go_la_lan = lan + 1
        if lan == 0:
            self.luu_anh_loi(s, "gặp màn lạ (lên cấp / thông báo?)")
        for ten in ("cq_dong", "cq_x_popup", "nut_dong", "nut_tiep_tuc", "cham_de_tiep_tuc", "nut_xac_nhan"):
            if self.templates.exists(ten):
                m = self.find(s, ten)
                if m:
                    self.log(f"  Màn lạ → bấm {ten}")
                    self.tap_match(m)
                    self.sleep(1.2)
                    return
        gx, gy, gw, gh = self.templates.vung(s)
        if lan % 2 == 0:
            self.log("  Màn lạ (lên cấp?) → chạm mép trên màn hình")
            self.tap(gx + 0.5 * gw, gy + 0.03 * gh)
        else:
            self.log("  Màn lạ → bấm Quay lại")
            self.device.back()
        self.sleep(1.5)

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

    def cho_bam(self, ev, giay):
        """Luồng bấm chờ giữa hai cú (lớp kiểm thử có thể rút ngắn)."""
        return ev.wait(giay)

    def dung_bam(self):
        mb = getattr(self, "may_bam", None)
        if mb is not None:
            mb.dung.set()
            self.may_bam = None

    def bam_xuyen_hieu_ung(self, s):
        """Sau mỗi lần quét game chạy hiệu ứng ~1 giây, nút "lần nữa" tạm biến mất. Như auto click:
        cứ bấm tiếp, chỉ dừng khi thấy rõ đã về bản đồ / mở popup khu, hoặc màn lạ quá lâu."""
        if getattr(self, "may_bam", None) is None:
            return False
        if time.time() - getattr(self, "kq_thay_cuoi", 0) > self.cq.get("bam_qua_hieu_ung_giay", 3):
            return False
        if self.la_ban_do(s) or self.find(s, "cq_x_popup") or self.find(s, "cq_nut_can_quet"):
            return False
        self.sleep(0.2)
        return True

    def man_ket_qua(self, s):
        roi = getattr(self, "kq_roi", None)
        m_lan_nua = (self.find(s, "cq_lan_nua", roi) if roi else None) or self.find(s, "cq_lan_nua")
        if not m_lan_nua:
            return False
        self.kq_roi = (m_lan_nua.left - 60, m_lan_nua.top - 60, m_lan_nua.left + m_lan_nua.w + 60,
                       m_lan_nua.top + m_lan_nua.h + 60)
        self.kq_thay_cuoi = time.time()
        khu = self.dang_mo_khu or self.khu_hien_tai()
        self.cho_popup = None
        self.popup_hong = 0
        k = m_lan_nua.scale
        # vùng chữ "Số lần: 98/99" ngay dưới chữ "Càn quét lần nữa"
        y0, y1 = m_lan_nua.top + int(75 * k), m_lan_nua.top + int(135 * k)
        x0, x1 = m_lan_nua.left - int(45 * k), m_lan_nua.left + int(285 * k)
        so_lan = s[max(0, y0):y1, max(0, x0):x1].astype(np.int16)
        mb = getattr(self, "may_bam", None)
        da_bam = mb.da_bam if mb else 0

        now = time.time()
        if self.kq_anh is None or self.kq_anh.shape != so_lan.shape:
            self.kq_anh, self.kq_doi = so_lan, now
            self.kq_moc = da_bam
            self.kq_con = self.doc_so_lan(s, (x0, y0, x1, y1))
            if self.kq_con == 0:  # lượt vừa quét là lượt cuối
                self.log(f"  {khu['ten']}: hết lượt (Số lần 0)")
                self.het_luot.add(khu["ten"])
        elif (np.abs(self.kq_anh - so_lan).sum(axis=2) > 90).mean() >= 0.003:
            # "Số lần" vừa đổi: có đọc chữ thì lấy đúng số còn lại, không thì ước lượng theo số cú bấm
            self.kq_anh, self.kq_doi = so_lan, now
            con = self.doc_so_lan(s, (x0, y0, x1, y1))
            truoc = getattr(self, "kq_con", None)
            if con is not None and truoc is not None and 0 <= truoc - con <= 50:
                if self.kq_da_cham:
                    self.dem(khu, truoc - con)
                self.kq_moc += truoc - con  # chỉ tính những cú bấm đã thấy kết quả
            else:
                if self.kq_da_cham:
                    self.dem(khu, max(1, da_bam - self.kq_moc))
                self.kq_moc = da_bam
            if con is not None:
                self.kq_con = con
                self.con_lai[khu["ten"]] = con
                if con == 0:
                    self.dung_bam()
                    self.log(f"  {khu['ten']}: hết lượt (Số lần 0)")
                    self.het_luot.add(khu["ten"])
        elif self.kq_da_cham and now - self.kq_doi > self.cq.get("cho_khong_doi_giay", 8):
            # bấm liên tục mà "Số lần" không đổi → khu hết lượt hoặc hết thể lực
            self.log("  'Càn quét lần nữa' không còn tác dụng")
            self.nghi_het = khu["ten"]
            self.the_luc = None  # đọc lại trên bản đồ

        if self.boi_xac_nhan is not None and self.boi_xac_nhan[0] is khu:
            self.boi_xac_nhan = None  # có màn kết quả → xN đã quét được
        if mb is not None and mb.toi_da is not None and mb.da_bam >= mb.toi_da and now - self.kq_doi > 1.5:
            self.kq_moc = mb.da_bam  # các cú bấm còn treo bị game bỏ qua (lúc hiệu ứng) → cân lại
        du_tong = self.stop_after and self.stats["can_quet"] >= self.stop_after
        if khu and self.boi_so(khu) > 1:
            du_tong = True  # đang dùng xN: đóng kết quả rồi bấm xN lại ở popup
        if khu and not du_tong and not self.du_chi_tieu(khu) and self.du_the_luc(khu) and khu["ten"] not in self.het_luot:
            # không bấm lố: tính cả các cú đã bấm mà chưa thấy "Số lần" đổi
            gioi_han = []
            if self.stop_after:
                gioi_han.append(self.stop_after - self.stats["can_quet"])
            if self.cq.get("so_lan_moi_khu", 0) > 0:
                gioi_han.append(self.cq["so_lan_moi_khu"] - self.da_quet.get(khu["ten"], 0))
            x, y = m_lan_nua.x, m_lan_nua.y - int(118 * k)  # biểu tượng đầu lâu phía trên chữ
            if mb is None:
                if getattr(self, "kq_log_khu", None) != khu["ten"]:
                    self.log(f"• Càn quét lần nữa liên tục – {khu['ten']}")
                    self.kq_log_khu = khu["ten"]
                mb = MayBam(self, x, y, max(0.05, float(self.cq.get("nhip_lan_nua", 0.15))))
                self.may_bam = mb
                self.kq_moc = 0
                mb.toi_da = min(gioi_han) if gioi_han else None
                mb.start()
            else:
                mb.x, mb.y = x, y
                mb.nhip = max(0.05, float(self.cq.get("nhip_lan_nua", 0.15)))
                mb.toi_da = self.kq_moc + min(gioi_han) if gioi_han else None
            self.kq_da_cham = True
            self.sleep(self.cq.get("kiem_tra_moi_giay", 0.5))  # luồng bấm vẫn chạy trong lúc chờ
            return True

        self.dung_bam()
        m = self.find(s, "cq_dong")
        self.kq_log_khu = None
        self.log(f"• Đóng kết quả – {khu['ten']} đã quét {self.da_quet.get(khu['ten'], 0)} lần")
        if m:
            self.tap_match(m)
        else:
            self.tap(m_lan_nua.x, m_lan_nua.y + int(266 * k))
        self.dang_mo_khu = None
        self.reset_kq()
        self.sleep(1.2)
        return True

    def doc_so_lan(self, s, roi):
        """Số lần còn lại trên màn kết quả ("Số lần: 98/99" → 98); None nếu không đọc được."""
        if not co_ocr():
            return None
        x0, y0, x1, y1 = roi
        h = y1 - y0
        for c in doc(s, (x0 - 10, y0 - h // 3, x1 + 10, y1 + h // 3)):
            n = so_trong(c.text, r"(\d+)\s*/\s*\d+")
            if n is not None:
                return n
        return None

    def reset_kq(self):
        self.dung_bam()
        self.kq_con = None
        self.kq_moc = 0
        self.kq_roi = None
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
        self.vua_boi = None
        if self.dang_danh is not None:
            self.log(f"  Thám hiểm xong {self.dang_danh['ten']}")
            self.stats["tham_hiem"] += 1
            self.dang_danh = None
        ten_ocr, con = self.doc_popup(s, m_x) if m_x else (None, None)
        if con is not None:
            self.con_lai[khu["ten"]] = con
        if self.dang_mo_khu is not None and self.cho_popup is None and m_x and not self.dung_khu(s, m_x, khu, ten_ocr):
            # bản đồ lệch so với lúc dò → mở nhầm khu khác: đóng lại, lấy mốc lại
            self.mo_nham[khu["ten"]] = self.mo_nham.get(khu["ten"], 0) + 1
            if self.mo_nham[khu["ten"]] >= 3:
                self.mo_nham[khu["ten"]] = 0
                self.tam_bo_khu(khu, "mở nhầm khu khác 3 lần", s)
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
        if m_x and self.kiem_tra_boi(s, m_x, khu):
            return True
        if con == 0 and m_cq:
            self.log(f"  {khu['ten']}: đã hết lượt (còn 0) → sang khu khác")
            self.het_luot.add(khu["ten"])
        elif not m_cq and self.cq.get("tu_dong_tham_hiem") and self.templates.exists("cq_nut_tham_hiem") \
                and self.find(s, "cq_nut_tham_hiem") and self.so_lan_tam_bo.get("tham_hiem:" + khu["ten"], 0) < 2:
            m_th = self.find(s, "cq_nut_tham_hiem")
            self.so_lan_tam_bo["tham_hiem:" + khu["ten"]] = self.so_lan_tam_bo.get("tham_hiem:" + khu["ten"], 0) + 1
            self.log(f"• Thám hiểm {khu['ten']} (khu chưa mở càn quét)")
            self.dang_mo_khu = khu
            self.dang_danh, self.danh_tu = khu, time.time()
            self.da_log_tien_len = False
            self.tap_match(m_th)
            self.sleep(2.0)
            return True
        elif not m_cq:
            self.log(f"  {khu['ten']}: không có nút Càn quét (chưa mở hoặc hết lượt) → sang khu khác")
            self.het_luot.add(khu["ten"])
        elif self.du_chi_tieu(khu) or not self.du_the_luc(khu):
            pass
        elif m_x and self.bam_boi(s, m_x, khu):
            return True
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

    # ---------- đọc chữ popup ----------
    def doc_popup(self, s, m_x):
        """(tên khu, số lần còn lại) đọc bằng OCR; (None, None) nếu không có OCR."""
        if not co_ocr():
            return None, None
        k = m_x.scale
        roi = (m_x.x - int(800 * k), m_x.y + int(20 * k), m_x.x + int(60 * k), m_x.y + int(215 * k))
        ten = con = None
        for c in doc(s, roi):
            g = gon(c.text)
            if "solan" in g or "conlai" in g:
                con = so_trong(c.text, r"(\d+)\D*$")
            elif ten is None and c.y < m_x.y + int(120 * k) and c.x < m_x.x - int(250 * k) and len(g) >= 3:
                ten = c.text.strip()
        return ten, con

    # ---------- thám hiểm (đánh trận) ----------
    def man_tran(self, s):
        """Đang đánh trận thám hiểm: bấm "Tiến lên", hết trận thì bấm nút an toàn (Tiếp tục, Đóng...)."""
        if self.dang_danh is None or not co_ocr():
            return False
        if time.time() - self.danh_tu > self.cq.get("toi_da_tran_giay", 600):
            self.log(f"  Đánh {self.dang_danh['ten']} quá lâu → bỏ")
            self.luu_anh_loi(s, "đánh trận quá lâu")
            self.dang_danh = None
            return False
        ds = doc(s)
        nguy_hiem = any(x in gon(c.text) for c in ds for x in ("mua", "nap", "kimcuong", "naptien"))
        for chu in ("tienlen", "tieptuc", "boqua", "dong", "nhanthuong", "nhan", "hoanthanh", "xacnhan"):
            if nguy_hiem and chu in ("xacnhan", "nhan"):
                continue
            c = next((c for c in ds if gon(c.text) == chu or (chu == "tienlen" and "tienlen" in gon(c.text))), None)
            if c:
                if chu != "tienlen" or not getattr(self, "da_log_tien_len", False):
                    self.log(f"  Trận: bấm '{c.text.strip()}'")
                    self.da_log_tien_len = chu == "tienlen"
                self.tap(c.x, c.y)
                self.sleep(1.0)
                return True
        if any("hiep" in gon(c.text) for c in ds):
            self.sleep(1.0)  # đang đánh, chờ
            return True
        return False

    # ---------- càn quét x5 / x10 ----------
    def boi_so(self, khu):
        """Số lần mỗi lượt bấm cho khu này: 5/10 nếu chọn và còn dùng được, ngược lại 1."""
        n = int(self.cq.get("kieu_quet", 1) or 1)
        if n <= 1 or khu["ten"] in self.boi_hong or not self.templates.exists(f"cq_nut_x{n}"):
            return 1
        con = []
        if self.con_lai.get(khu["ten"]) is not None:
            con.append(self.con_lai[khu["ten"]])
        if self.stop_after:
            con.append(self.stop_after - self.stats["can_quet"])
        if self.cq.get("so_lan_moi_khu", 0) > 0:
            con.append(self.cq["so_lan_moi_khu"] - self.da_quet.get(khu["ten"], 0))
        return n if not con or min(con) >= n else 1

    def anh_con_lai(self, s, m_x):
        """Ảnh vùng chữ "Số lần còn lại:NN" trong popup (so trước/sau để biết đã quét được chưa)."""
        k = m_x.scale
        x0, x1 = m_x.x - int(266 * k), m_x.x + int(44 * k)
        y0, y1 = m_x.y + int(141 * k), m_x.y + int(191 * k)
        return s[max(0, y0):y1, max(0, x0):x1].astype(np.int16)

    def kiem_tra_boi(self, s, m_x, khu):
        """Quay lại popup sau khi bấm xN: số lần còn lại có đổi không? Không đổi → khu này thôi dùng xN."""
        for ten_bien in ("cho_boi", "boi_xac_nhan"):
            cho = getattr(self, ten_bien)
            if cho is None or cho[0] is not khu:
                continue
            setattr(self, ten_bien, None)
            truoc = cho[2]
            if truoc is None:
                return False  # xN bấm từ màn "Quét lại": không có ảnh để so
            sau = self.anh_con_lai(s, m_x)
            doi = truoc.shape == sau.shape and (np.abs(truoc - sau).max(axis=2) > 60).mean() > 0.003
            if ten_bien == "boi_xac_nhan" and doi:
                return False  # đã quét xN thành công, popup vẫn mở → bấm tiếp
            if ten_bien == "boi_xac_nhan":
                self.dem(khu, -cho[1])
            self.log(f"  x{cho[1]} không quét được ({'còn ít lượt / thiếu Xu?'}) → {khu['ten']} quét từng lần")
            self.boi_hong.add(khu["ten"])
        return False

    def bam_boi(self, s, m_x, khu):
        n = self.boi_so(khu)
        if n <= 1:
            return False
        m = self.find(s, f"cq_nut_x{n}")
        if not m:
            self.boi_hong.add(khu["ten"])
            return False
        self.dang_mo_khu = khu
        self.cho_boi = (khu, n, self.anh_con_lai(s, m_x))
        self.log(f"• Càn quét x{n} – {khu['ten']}")
        self.tap_match(m)
        self.sleep(1.5)
        return True

    def man_quet_lai(self, s):
        """Màn kết quả sau khi quét xN có nút "Quét lại": bấm luôn (rồi Xác định ở bảng hỏi) thay vì
        đóng ra mở lại popup. Còn ít hơn N lượt thì đóng để quét lẻ phần còn lại."""
        khu = getattr(self, "vua_boi", None)
        if khu is None or not co_ocr():
            return False
        ds = doc(s)
        nut = next((c for c in ds if "quetlai" in gon(c.text)), None)
        if nut is None:
            return False
        # "Số lần: N/99" (không lấy nhầm thanh EXP "6265/9840" ở trên cùng): ưu tiên dòng có chữ "số lần",
        # không thì con số dạng N/M gần ngay dưới nút "Quét lại"
        ung_vien = [c for c in ds if so_trong(c.text, r"(\d+)\s*/\s*\d+") is not None]
        dong_so_lan = next((c for c in ung_vien if "solan" in gon(c.text)), None) or min(
            (c for c in ung_vien if 0 < c.y - nut.y < 250 and abs(c.x - nut.x) < 250),
            key=lambda c: c.y - nut.y, default=None)
        if dong_so_lan is not None:
            self.con_lai[khu["ten"]] = so_trong(dong_so_lan.text, r"(\d+)\s*/\s*\d+")
        self.boi_xac_nhan = None  # có màn này → lần xN trước đã quét được
        n = self.boi_so(khu)
        if n > 1 and khu["ten"] not in self.boi_hong and not self.du_chi_tieu(khu):
            if getattr(self, "quet_lai_cho", None) is khu and time.time() - self.quet_lai_tu < 4:
                self.sleep(0.4)  # vừa bấm, chờ bảng hỏi
                return True
            if getattr(self, "quet_lai_cho", None) is khu:
                # bấm "Quét lại" mà không ra bảng hỏi → không quét xN được nữa
                self.log(f"  'Quét lại' không ra bảng hỏi → {khu['ten']} quét từng lần")
                self.boi_hong.add(khu["ten"])
                self.quet_lai_cho = None
            else:
                self.log(f"• Quét lại x{n} – {khu['ten']}")
                self.cho_boi = (khu, n, None)
                self.quet_lai_cho, self.quet_lai_tu = khu, time.time()
                self.tap(nut.x, nut.y)
                self.sleep(1.0)
                return True
        # không quét xN tiếp: đóng màn này để về popup
        self.vua_boi = None
        self.quet_lai_cho = None
        dong = next((c for c in ds if gon(c.text) in ("dong", "thoat", "quaylai")), None)
        m = self.find(s, "cq_dong") or self.find(s, "cq_x_popup")
        self.log(f"• Đóng kết quả x{self.cq.get('kieu_quet', 5)} – {khu['ten']}")
        if m:
            self.tap_match(m)
        elif dong:
            self.tap(dong.x, dong.y)
        else:
            self.device.back()
        self.sleep(1.2)
        return True

    def man_hoi(self, s):
        """Bảng hỏi "Càn quét N lần: tốn ... Xác nhận?" → chỉ bấm Xác định khi đúng là câu hỏi càn quét
        và do tool vừa bấm xN. Bảng hỏi khác (mua Xu, mua thể lực...) → bấm Quay lại để huỷ."""
        if not self.templates.exists("cq_xac_dinh"):
            return False
        m = self.find(s, "cq_xac_dinh")
        if not m:
            return False
        k = m.scale
        roi = (m.x - int(520 * k), m.y - int(330 * k), m.x + int(520 * k), m.y - int(110 * k))
        chu = self.templates.khop_chu_cam(s, "cq_hoi_can_quet", roi) if self.templates.exists("cq_hoi_can_quet") else None
        cho = self.cho_boi
        if chu is None or chu.score < 0.7 or cho is None:
            ly_do = "bảng hỏi không phải càn quét" if chu is None or chu.score < 0.7 else "bảng hỏi càn quét tool không bấm"
            self.luu_anh_loi(s, ly_do)
            self.log(f"  {ly_do} → huỷ (Quay lại), không xác nhận")
            if cho is not None:
                self.boi_hong.add(cho[0]["ten"])  # vd. thiếu Xu → quét từng lần
                self.cho_boi = None
            self.device.back()
            self.sleep(1.5)
            return True
        khu, n, anh = cho
        self.cho_boi = None
        self.quet_lai_cho = None
        self.log(f"  Xác nhận càn quét x{n} – {khu['ten']}")
        self.tap_match(m)
        self.dem(khu, n)
        self.boi_xac_nhan = (khu, n, anh)
        self.vua_boi = khu
        if self.con_lai.get(khu["ten"]) is not None:
            self.con_lai[khu["ten"]] = max(0, self.con_lai[khu["ten"]] - n)
        self.sleep(1.5)
        return True

    def dung_khu(self, s, m_x, khu, ten_ocr=None):
        """Popup đang mở có đúng khu không: so tên đọc được (nếu có), không thì so ảnh tiêu đề lúc dò."""
        if ten_ocr and khu.get("ten_ocr"):
            from difflib import SequenceMatcher
            return SequenceMatcher(None, gon(ten_ocr), gon(khu["ten_ocr"])).ratio() >= 0.75
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
        self.boi_xac_nhan = None  # về bản đồ sau khi xác nhận xN: coi như đã quét
        self.cho_boi = None
        self.vua_boi = None
        if self.dang_danh is not None:
            self.log(f"  Đánh xong {self.dang_danh['ten']}, về bản đồ → mở lại khu để càn quét")
            self.stats["tham_hiem"] += 1
            self.dang_danh = None
        ti_le = None if self.cq.get("bo_qua_the_luc") else doc_thanh_the_luc(s, m)
        if self.cq.get("bo_qua_the_luc"):
            self.the_luc = None
        elif ti_le is not None and ti_le >= 0.985:
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
            self.tl_thap = getattr(self, "tl_thap", 0) + 1
            if self.tl_thap < 2:  # đọc lại cho chắc (tránh đọc nhầm lúc màn đang chuyển)
                self.log(f"  Thể lực đọc được ~{self.the_luc}, kiểm tra lại...")
                self.sleep(1.5)
                return True
            self.luu_anh_loi(s, f"hết thể lực (đọc được ~{self.the_luc})")
            self.log(f"⛔ Hết thể lực (còn khoảng {self.the_luc}) → dừng")
            raise StopBot
        self.tl_thap = 0
        if self.nghi_het:
            # thể lực vẫn đủ → khu đó thật sự đã hết lượt
            self.log(f"  {self.nghi_het}: hết lượt → sang khu kế")
            self.het_luot.add(self.nghi_het)
            self.nghi_het = None

        khu = self.chon_khu()
        if khu is None:
            return True
        if not self.du_the_luc(khu):
            self.luu_anh_loi(s, "hết thể lực")
            self.log(f"⛔ Hết thể lực (còn khoảng {self.the_luc}, cần {self.chi_phi(khu)}) → dừng")
            raise StopBot

        vt = self.vi_tri_khu(s, khu)
        if vt is None:  # chưa định vị được bản đồ: chưa chạm, không tính là chạm hỏng
            self.dinh_vi_hong += 1
            if self.dinh_vi_hong >= 4:
                self.dinh_vi_hong = 0
                self.tam_bo_khu(khu, "không định vị được bản đồ", s)
            return True
        self.dinh_vi_hong = 0

        self.cham_khu_lien += 1
        if self.cham_khu_lien > 3:
            self.cham_khu_lien = 0
            self.tam_bo_khu(khu, "chạm 3 lần không mở được", s)
            return True
        self.dang_mo_khu = khu
        self.log(f"• Mở khu {khu['ten']} (thể lực ~{self.the_luc if self.the_luc is not None else 'đầy'})")
        self.tap(*vt)
        # chờ popup mở (game có thể cho nhân vật đi bộ tới toà nhà trước) – không chạm lại vội
        for _ in range(int(self.cq.get("cho_mo_khu_giay", 6) / 0.5)):
            self.sleep(0.5)
            if not self.la_ban_do(self.shot()):
                break
        return True

    def tam_bo_khu(self, khu, ly_do, s=None):
        """Bỏ qua khu trong vòng này, thử lại ở vòng sau; 3 lần như vậy mới bỏ hẳn."""
        ten = khu["ten"]
        self.so_lan_tam_bo[ten] = self.so_lan_tam_bo.get(ten, 0) + 1
        if s is not None:
            self.luu_anh_loi(s, f"{ten}: {ly_do}")
        if self.so_lan_tam_bo[ten] >= 3:
            self.log(f"  {ten}: {ly_do} (lần thứ 3) → bỏ hẳn khu này")
            self.het_luot.add(ten)
        else:
            self.log(f"  {ten}: {ly_do} → tạm bỏ qua, sẽ thử lại ở vòng sau")
            self.bo_vong.add(ten)
        self.khu_i += 1

    def chon_khu(self):
        ds = self.ds_khu()
        for _ in range(len(ds)):
            khu = self.khu_hien_tai()
            if not self.du_chi_tieu(khu):
                return khu
            self.khu_i += 1
        # mọi khu đều xong
        if self.cq.get("lap_vong", True) and any(k["ten"] not in self.het_luot for k in ds):
            self.log("↻ Xong một vòng các khu, quay lại thử các khu còn lượt")
            self.da_quet.clear()
            self.bo_vong.clear()
            self.khu_i = 0
            return self.chon_khu()
        self.log("✔ Đã quét xong mọi khu")
        raise XongKhu

    def vi_tri_khu(self, s, khu):
        if "xy_map" in khu:
            if not self.cq.get("cuon_map", True):
                self.cam, self.cam_ok = [0.0, 0.0], True  # không lướt: dùng đúng màn đang thấy
            elif self.ds_moc():
                s = self.dinh_vi(s)  # tìm mốc trên màn hình: biết chính xác đang ở đâu
                if not self.cam_ok:
                    return None
            elif not self.cam_ok:
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
