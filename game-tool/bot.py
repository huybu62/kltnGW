"""Vòng lặp tự động: chụp màn hình → tìm luật đầu tiên khớp → làm hành động.

Luật nằm trong config.json, mục "luat", xét theo thứ tự từ trên xuống. Mỗi luật:
  ten           tên hiển thị
  bat           true/false: bật hay tắt luật
  thay          tên mẫu (hoặc danh sách mẫu, phải thấy đủ) để luật được chọn
  khong_thay    (tuỳ chọn) mẫu mà nếu thấy thì bỏ qua luật
  lam           cham | cham_xy | cham_ngau_nhien | chuoi | cho | back | dung
  muc_tieu      cham: mẫu cần chạm (mặc định là mẫu đầu tiên trong "thay")
                cham_ngau_nhien: danh sách mẫu, chọn ngẫu nhiên một cái đang hiện
  xy            cham_xy: [x, y]
  lech          (tuỳ chọn) [dx, dy] chạm lệch khỏi tâm mẫu
  buoc          chuoi: danh sách bước, xem run_steps()
  dem           (tuỳ chọn) tên bộ đếm tăng lên mỗi lần luật chạy
  nghi_sau      số giây nghỉ sau khi làm (mặc định "nghi_giua_vong")
"""
import random
import threading
import time
import traceback
from collections import Counter


class StopBot(Exception):
    pass


def _ds(v):
    if not v:
        return []
    return [v] if isinstance(v, str) else list(v)


class Bot(threading.Thread):
    def __init__(self, device, cfg, templates, emit, stop_after=0):
        super().__init__(daemon=True)
        self.device = device
        self.cfg = cfg  # dùng chung với overlay: bật/tắt luật có hiệu lực ngay
        self.templates = templates
        self.emit = emit
        self.stop_after = stop_after
        self.stop_event = threading.Event()
        self.stats = Counter()

    # ---------- tiện ích ----------
    def stop(self):
        self.stop_event.set()

    def log(self, msg):
        self.emit(("log", self.device.serial, msg))

    def sleep(self, giay):
        if self.stop_event.wait(max(0.0, float(giay))):
            raise StopBot

    def nguong(self, name):
        return self.cfg.get("nguong_rieng", {}).get(name, self.cfg.get("nguong_khop", 0.85))

    def find(self, screen, name):
        return self.templates.find(screen, name, self.nguong(name))

    def shot(self):
        loi = 0
        while True:
            if self.stop_event.is_set():
                raise StopBot
            try:
                return self.device.screenshot()
            except Exception as e:  # adb rớt kết nối, giả lập đang tải...
                loi += 1
                if loi >= 5:
                    self.log(f"Không chụp được màn hình 5 lần liền: {e}")
                    raise StopBot
                self.sleep(2)

    def tap(self, x, y):
        self.device.tap(x, y)

    def tap_match(self, m, lech=None):
        dx, dy = lech or (0, 0)
        self.tap(m.x + dx, m.y + dy)

    # ---------- vòng lặp ----------
    def run(self):
        self.emit(("state", self.device.serial, True))
        self.log("▶ Bắt đầu")
        try:
            self.kiem_tra_mau()
            self.loop()
        except StopBot:
            pass
        except Exception as e:
            self.log(f"Lỗi: {e}")
            traceback.print_exc()
        finally:
            if hasattr(self.device, "close"):
                self.device.close()
            self.emit(("state", self.device.serial, False))
            self.log("■ Đã dừng")

    def kiem_tra_mau(self):
        thieu = set()
        for rule in self.cfg.get("luat", []):
            if rule.get("bat", True):
                for n in _ds(rule.get("thay")):
                    if not self.templates.exists(n):
                        thieu.add(n)
        if thieu:
            self.log("Chưa có mẫu (luật liên quan sẽ bỏ qua): " + ", ".join(sorted(thieu)))

    def loop(self):
        cfg = self.cfg
        lan_thay_cuoi = time.time()
        lan_ket_cuoi = 0.0
        luat_truoc = None
        so_lap = 0
        while not self.stop_event.is_set():
            screen = self.shot()
            rule, match = self.pick_rule(screen)
            now = time.time()

            if rule is None:
                ranh = now - lan_thay_cuoi
                if ranh > cfg.get("dung_khi_khong_nhan_ra_giay", 300):
                    self.log(f"Không nhận ra màn hình nào trong {int(ranh)} giây → dừng")
                    return
                if ranh > cfg.get("ket_sau_giay", 45) and now - lan_ket_cuoi > cfg.get("ket_sau_giay", 45):
                    lan_ket_cuoi = now
                    self.on_stuck(f"không nhận ra màn hình {int(ranh)} giây")
                self.sleep(cfg.get("nghi_khi_khong_thay", 1.0))
                continue

            lan_thay_cuoi = now
            so_lap = so_lap + 1 if rule is luat_truoc else 1
            lap_lai = rule is luat_truoc
            luat_truoc = rule
            if rule.get("lam") != "cho" and so_lap > cfg.get("lap_toi_da", 15):
                self.on_stuck(f"luật '{rule.get('ten')}' lặp {so_lap} lần liền")
                so_lap = 0

            self.execute(rule, match, screen, im_lang=lap_lai and rule.get("lam") == "cho")

            if self.stop_after and self.stats["xuc_xac"] >= self.stop_after:
                self.log(f"Đã đổ đủ {self.stop_after} lượt xúc xắc → dừng")
                return
            self.sleep(rule.get("nghi_sau", cfg.get("nghi_giua_vong", 0.8)))

    def on_stuck(self, ly_do):
        kieu = self.cfg.get("khi_ket", "bao")
        if kieu == "back":
            self.log(f"⚠ Có vẻ bị kẹt ({ly_do}) → bấm Quay lại")
            self.device.back()
        elif kieu == "cham_xy" and self.cfg.get("xy_khi_ket"):
            self.log(f"⚠ Có vẻ bị kẹt ({ly_do}) → chạm {self.cfg['xy_khi_ket']}")
            self.tap(*self.cfg["xy_khi_ket"])
        else:
            self.log(f"⚠ Có vẻ bị kẹt ({ly_do})")

    def pick_rule(self, screen):
        for rule in self.cfg.get("luat", []):
            if not rule.get("bat", True):
                continue
            can = _ds(rule.get("thay"))
            if not can:
                continue
            dau_tien = None
            du = True
            for n in can:
                m = self.find(screen, n) if self.templates.exists(n) else None
                if m is None:
                    du = False
                    break
                dau_tien = dau_tien or m
            if not du:
                continue
            if any(self.templates.exists(n) and self.find(screen, n) for n in _ds(rule.get("khong_thay"))):
                continue
            return rule, dau_tien
        return None, None

    # ---------- hành động ----------
    def execute(self, rule, match, screen, im_lang=False):
        ten = rule.get("ten", "?")
        kieu = rule.get("lam", "cham")
        if not im_lang:
            self.log(f"• {ten}")

        if kieu == "dung":
            self.log(f"⛔ {ten} → dừng")
            raise StopBot
        elif kieu == "cham":
            muc_tieu = rule.get("muc_tieu")
            m = self.find(screen, muc_tieu) if muc_tieu else match
            if not m:
                self.log(f"  không thấy '{muc_tieu}'")
                return
            self.tap_match(m, rule.get("lech"))
        elif kieu == "cham_xy":
            self.tap(*rule["xy"])
        elif kieu == "cham_ngau_nhien":
            dang_hien = [m for m in (self.find(screen, n) for n in _ds(rule.get("muc_tieu"))) if m]
            if dang_hien:
                m = random.choice(dang_hien)
                self.log(f"  chọn {m.name}")
                self.tap_match(m, rule.get("lech"))
            elif rule.get("xy_list"):
                self.tap(*random.choice(rule["xy_list"]))
            else:
                self.log("  không thấy lựa chọn nào")
                return
        elif kieu == "chuoi":
            if not self.run_steps(rule.get("buoc", []), ten):
                return
        elif kieu == "back":
            self.device.back()
        elif kieu == "cho":
            pass
        else:
            self.log(f"  kiểu hành động lạ: {kieu}")
            return

        if rule.get("dem"):
            self.stats[rule["dem"]] += 1
            self.emit(("stats", self.device.serial, dict(self.stats)))

    def run_steps(self, buoc, ten):
        """Mỗi bước là một trong:
        {"cham": "mau", "cho_toi_da": 4, "bo_qua_neu_khong_thay": false, "lech": [dx,dy], "nghi_sau": 0.6}
        {"cham_xy": [x, y], "nghi_sau": 0.6}
        {"nghi": 1.0}
        {"back": true}
        """
        for i, b in enumerate(buoc, 1):
            if "nghi" in b:
                self.sleep(b["nghi"])
            elif "cham_xy" in b:
                self.tap(*b["cham_xy"])
                self.sleep(b.get("nghi_sau", 0.6))
            elif "back" in b:
                self.device.back()
                self.sleep(b.get("nghi_sau", 0.6))
            elif "cham" in b:
                mau = b["cham"]
                han = time.time() + b.get("cho_toi_da", 4)
                m = None
                if self.templates.exists(mau):
                    while True:
                        m = self.find(self.shot(), mau)
                        if m or time.time() >= han:
                            break
                        self.sleep(0.5)
                if not m:
                    if b.get("bo_qua_neu_khong_thay"):
                        continue
                    self.log(f"  {ten}: bước {i} không thấy '{mau}', bỏ chuỗi")
                    return False
                self.tap_match(m, b.get("lech"))
                self.sleep(b.get("nghi_sau", 0.6))
        return True
