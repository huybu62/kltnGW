package vn.hoitu.bansuc.core

/** Cài đặt người chơi. */
data class CaiDat(
    var he: He = He.LANHCHUA,
    var mucTieu: Char = 'A', // 'A' hoặc 'S'
    var soLuong: MutableMap<ChiSo, Int> = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1), // số viên LV6 cần cho mỗi chỉ số
    var nhaMayLv6: Boolean = false, // hết đá A-SSS thì tự làm bằng 1 viên LV6 (lên A rồi Thác Ấn bằng Đá In SSS)
    var nghiMs: Int = 600, // chờ sau mỗi lần bấm Điểm Hóa / Thác Ấn
)

/** Những gì bộ điều khiển cần từ điện thoại (nhìn màn hình đã đọc chữ, chạm, vuốt...). */
interface ThietBi {
    fun nhin(): ManHinh?
    fun cham(x: Float, y: Float)
    fun vuot(x0: Float, y0: Float, x1: Float, y1: Float)
    fun ngu(ms: Long)
    fun log(s: String)
}

private class DungLai(msg: String) : Exception(msg)

/**
 * Ban sức đá vận mệnh tự động:
 * - Đá LV6 (đá trong bộ): Điểm Hóa bằng B-SS (mục tiêu A) hoặc A-SSS (mục tiêu S) tới khi đạt phẩm;
 *   rơi đúng phẩm B thì Thác Ấn bằng Đá In SS lấy 1 viên B-SS rồi làm tiếp.
 * - Hết B-SS: dùng đá LV5 "nhà máy": Điểm Hóa bằng B-S tới phẩm B, Thác Ấn bằng Đá In SS → 1 viên B-SS (từng viên một).
 * - Hết A-SSS (mục tiêu S, nếu bật nhà máy LV6): đưa 1 viên LV6 lên A rồi Thác Ấn bằng Đá In SSS → 1 viên A-SSS.
 * Chỉ đụng tới đá chưa ban sức hoặc đá đúng hệ đã chọn; đá hệ khác để yên. Dừng khi đủ số lượng.
 */
class BanSuc(private val tb: ThietBi, private val cd: CaiDat) {
    @Volatile var dung = false
    var soLanDiemHoa = 0; private set
    var soLanThacAn = 0; private set

    private val he get() = cd.he
    private var nhaMayLv5: Da? = null

    // ---------- tiện ích ----------
    private fun ngu(ms: Long) { if (dung) throw DungLai("đã dừng"); tb.ngu(ms) }

    private fun nhin(): ManHinh {
        repeat(20) {
            if (dung) throw DungLai("đã dừng")
            tb.nhin()?.let { return it }
            ngu(200)
        }
        throw DungLai("Không chụp được màn hình")
    }

    private fun cham(m: ManHinh, p: Pair<Float, Float>) { val (x, y) = m.ra(p.first, p.second); tb.cham(x, y) }

    private fun cho(han: Long = 6000, dk: (ManHinh) -> Boolean): ManHinh? {
        var t = 0L
        while (t <= han) {
            val m = nhin()
            if (dk(m)) return m
            ngu(250); t += 250
        }
        return null
    }

    private fun veManChinh(): ManHinh {
        var khac = 0
        repeat(12) {
            val m = nhin()
            when (m.loai) {
                LoaiMan.CHINH -> return m
                LoaiMan.DIEM_HOA, LoaiMan.THAC_AN -> cham(m, DocMan.DONG_BANG)
                LoaiMan.CHON_DA -> cham(m, DocMan.QUAY_LAI)
                LoaiMan.KHAC -> if (++khac >= 6) throw DungLai("Không thấy màn Ban Sức Đá Quý Vận Mệnh – hãy mở màn đó rồi bấm ▶")
            }
            ngu(500)
        }
        throw DungLai("Không về được màn Ban Sức Đá Quý Vận Mệnh")
    }

    private fun vuotLen(m: ManHinh) { // kéo nội dung lên (xem đá phía dưới)
        val (x0, y0) = m.ra(DocMan.VUOT_DS_DUOI.first, DocMan.VUOT_DS_DUOI.second)
        val (x1, y1) = m.ra(DocMan.VUOT_DS_TREN.first, DocMan.VUOT_DS_TREN.second)
        tb.vuot(x0, y0, x1, y1)
    }

    private fun vuotXuong(m: ManHinh) { // kéo nội dung xuống (về đầu danh sách)
        val (x0, y0) = m.ra(DocMan.VUOT_DS_TREN.first, DocMan.VUOT_DS_TREN.second)
        val (x1, y1) = m.ra(DocMan.VUOT_DS_DUOI.first, DocMan.VUOT_DS_DUOI.second)
        tb.vuot(x0, y0, x1, y1)
    }

    private fun lenDau(): ManHinh {
        var m = veManChinh()
        repeat(20) {
            val truoc = m.hang.map { it.da }
            vuotXuong(m); ngu(500)
            m = veManChinh()
            if (m.hang.map { it.da } == truoc) return m
        }
        return m
    }

    /** Đọc cả danh sách đá (gộp các trang, bỏ phần trùng do vuốt chồng lên nhau). */
    private fun quetDanhSach(): List<Hang> {
        var m = lenDau()
        val tatCa = ArrayList<Hang>(m.hang)
        repeat(40) {
            vuotLen(m); ngu(500)
            val moi = veManChinh()
            if (moi.hang.map { it.da } == m.hang.map { it.da }) return tatCa
            // độ trùng lớn nhất giữa đuôi danh sách đã có và đầu trang mới
            val a = tatCa.map { it.da }; val b = moi.hang.map { it.da }
            var trung = 0
            for (t in minOf(a.size, b.size) downTo 1) if (a.takeLast(t) == b.take(t)) { trung = t; break }
            tatCa += moi.hang.drop(trung)
            m = moi
        }
        return tatCa
    }

    /** Chọn (chạm) một viên giống [da] ở danh sách: tìm ở trang đang xem trước, không thấy thì dò từ đầu. */
    /** Hai viên giống nhau (chỉ số có thể không đọc được ở một bên). */
    private fun giong(a: Da?, b: Da) = a != null && a.lv == b.lv && a.pham == b.pham && a.he == b.he &&
        (a.chiSo == null || b.chiSo == null || a.chiSo == b.chiSo)

    private var docDuocLanCuoi = ""

    private fun chonDa(da: Da): Boolean {
        fun daChonDung(m: ManHinh) = m.loai == LoaiMan.CHINH &&
            (giong(m.daChon, da) || m.hang.any { it.daChon && giong(it.da, da) })
        fun thu(m: ManHinh): Boolean {
            if (giong(m.daChon, da)) return true
            val h = m.hang.firstOrNull { giong(it.da, da) } ?: return false
            tb.cham(h.x, h.y)
            val ok = cho(3000) { daChonDung(it) }
            if (ok == null) docDuocLanCuoi = nhin().let { "bảng phải đọc được \"${it.tenDaChonTho}\"" }
            return ok != null
        }
        if (thu(veManChinh())) return true
        var m = lenDau()
        repeat(40) {
            if (thu(m)) return true
            val truoc = m.hang.map { it.da }
            vuotLen(m); ngu(500)
            m = veManChinh()
            if (m.hang.map { it.da } == truoc) return false
        }
        return false
    }

    private fun moBang(loai: LoaiMan): ManHinh {
        val m = veManChinh()
        cham(m, if (loai == LoaiMan.DIEM_HOA) DocMan.NUT_DIEM_HOA else DocMan.NUT_THAC_AN)
        return cho(5000) { it.loai == loai && it.hien != null } ?: throw DungLai("Không mở được bảng ${if (loai == LoaiMan.DIEM_HOA) "Điểm Hóa" else "Thác Ấn"}")
    }

    private fun tenDa(bac: Int, daIn: Boolean) =
        if (daIn) "Đá In " + "S".repeat(bac) else when (bac) { 1 -> "B-S"; 2 -> "B-SS"; else -> "A-SSS" } + " ${he.ten}"

    /** Bấm ô "+ Thêm Đá ..." rồi chọn thẻ đúng loại (dò các trang). false: không có thẻ đó (hết đá). */
    private fun themDa(loai: LoaiMan, bac: Int, daIn: Boolean): Boolean {
        val bang = cho(3000) { it.loai == loai } ?: return false
        cham(bang, DocMan.NUT_O)
        var m = cho(4000) { it.loai == LoaiMan.CHON_DA } ?: return false
        fun timThe(m: ManHinh) = m.the.firstOrNull { it.bac == bac && it.daIn == daIn && (daIn || it.he == he) && (it.soLuong ?: 1) > 0 }
        for (huong in listOf(DocMan.TRANG_SAU, DocMan.TRANG_TRUOC)) {
            repeat(4) {
                val t = timThe(m)
                if (t != null) {
                    tb.cham(t.x, t.y)
                    val b = cho(4000) { it.loai == loai && it.daThem != false } // đã chọn thẻ và về lại bảng
                    if (b != null) return true
                    m = cho(2000) { it.loai == LoaiMan.CHON_DA } ?: return false
                    return@repeat
                }
                val truoc = m.the.map { it.chu }
                cham(m, huong); ngu(600)
                m = cho(3000) { it.loai == LoaiMan.CHON_DA } ?: return false
                if (m.the.map { it.chu } == truoc) return@repeat
            }
        }
        cham(m, DocMan.QUAY_LAI)
        cho(3000) { it.loai == loai }
        return false
    }

    private sealed class KetQua {
        data class Dat(val hq: HieuQua) : KetQua()
        /** Hết đá điểm hóa; [hq] là hiệu quả hiện tại của đá (có thể đã đổi trong lúc điểm hóa). */
        data class HetDa(val hq: HieuQua?) : KetQua()
    }

    /** Mở bảng Điểm Hóa của đá đang chọn, thêm đá điểm hóa bậc [bac] hệ đã chọn, bấm tới khi [xong]. */
    private fun diemHoaToiKhi(bac: Int, xong: (HieuQua) -> Boolean): KetQua {
        var m = moBang(LoaiMan.DIEM_HOA)
        m.hien?.let { if (xong(it)) return KetQua.Dat(it) }
        if (!themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(m.hien)
        m = cho(3000) { it.loai == LoaiMan.DIEM_HOA } ?: throw DungLai("Mất bảng Điểm Hóa")
        val sau = m.sau
        if (sau?.he != null && sau.he != he) throw DungLai("Đá điểm hóa đã thêm không phải hệ ${he.ten} (thấy ${sau.he.ten}) → dừng cho an toàn")
        var lan = 0
        while (true) {
            if (m.daThem == false && !themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(m.hien)
            val truoc = m.hien
            cham(m, DocMan.NUT_LAM)
            lan++; soLanDiemHoa++
            ngu(cd.nghiMs.toLong())
            // game có thể giữ bảng Điểm Hóa, hoặc tự đóng bảng và về màn chính sau mỗi lần bấm
            val kq = cho(5000) { (it.loai == LoaiMan.DIEM_HOA && it.hien != null) || (it.loai == LoaiMan.CHINH && it.daChon != null) }
                ?: throw DungLai("Không thấy kết quả sau khi bấm Điểm Hóa")
            val hq = if (kq.loai == LoaiMan.CHINH) HieuQua(kq.daChon!!.pham, kq.daChon.he) else kq.hien!!
            if (kq.loai == LoaiMan.DIEM_HOA) m = kq
            if (hq != truoc) tb.log("  Điểm hóa ${tenDa(bac, false)} lần $lan: ${chu(truoc)} → ${chu(hq)}")
            else if (lan % 10 == 0) tb.log("  Điểm hóa ${tenDa(bac, false)} lần $lan: vẫn ${chu(hq)}")
            if (xong(hq)) return KetQua.Dat(hq)
            if (kq.loai == LoaiMan.CHINH) {
                m = moBang(LoaiMan.DIEM_HOA) // mở lại bảng để bấm tiếp (đá điểm hóa thường vẫn còn trong ô)
                if (m.daThem == true && m.sau?.he != null && m.sau.he != he) {
                    if (!themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(hq)
                    m = cho(3000) { it.loai == LoaiMan.DIEM_HOA } ?: throw DungLai("Mất bảng Điểm Hóa")
                }
            }
        }
    }

    private fun capNhat(d: Da, hq: HieuQua?) = if (hq == null) d else d.copy(pham = hq.pham, he = hq.he)

    private fun chu(h: HieuQua?) = if (h?.pham == null) "trống" else "${h.pham}·${h.he?.ten}"

    /** Thác Ấn đá đang chọn bằng Đá In bậc [bacIn]. */
    private fun thacAn(bacIn: Int) {
        val m = moBang(LoaiMan.THAC_AN)
        val truoc = m.hien
        if (truoc?.pham == null) { veManChinh(); return }
        if (!themDa(LoaiMan.THAC_AN, bacIn, true)) throw DungLai("Hết ${tenDa(bacIn, true)} → dừng")
        val b = cho(3000) { it.loai == LoaiMan.THAC_AN } ?: throw DungLai("Mất bảng Thác Ấn")
        cham(b, DocMan.NUT_LAM)
        soLanThacAn++
        ngu(cd.nghiMs.toLong())
        cho(5000) { (it.loai == LoaiMan.THAC_AN && it.hien?.pham == null) || (it.loai == LoaiMan.CHINH && it.daChon != null && it.daChon.pham == null) }
            ?: throw DungLai("Thác Ấn không ăn (đá vẫn còn ${chu(truoc)})")
        tb.log("  Thác Ấn ${chu(truoc)} bằng ${tenDa(bacIn, true)} → +1 ${when (bacIn) { 2 -> "B-SS"; 3 -> "A-SSS"; else -> "B-S" }} ${he.ten}")
        veManChinh()
    }

    // ---------- nhà máy ----------
    /** Làm 1 viên B-SS bằng đá LV5 nhà máy. */
    private fun lamBSS(): Boolean {
        var f: Da? = nhaMayLv5
        if (f == null || !chonDa(f)) {
            val ds = quetDanhSach().map { it.da }.filter { it.lv == 5 }
            f = ds.sortedBy {
                when {
                    it.he == he && it.pham == 'B' -> 0
                    it.he == he -> 1
                    it.pham == null -> 2
                    else -> 3
                }
            }.firstOrNull() ?: throw DungLai("Không có đá LV5 làm nhà máy")
            if (!chonDa(f)) throw DungLai("Không chọn được đá LV5 nhà máy $f ($docDuocLanCuoi)")
        }
        f!!
        tb.log("🏭 Nhà máy LV5 ($f): làm 1 viên B-SS ${he.ten}")
        var hien: Da = f
        while (true) {
            if (hien.he == he && hien.pham == 'B') {
                thacAn(2)
                nhaMayLv5 = hien.copy(pham = null, he = null)
                return true
            }
            when (val kq = diemHoaToiKhi(1) { it.he == he && it.pham == 'B' }) {
                is KetQua.HetDa -> { tb.log("⛔ Hết đá điểm hóa B-S ${he.ten}"); nhaMayLv5 = capNhat(hien, kq.hq); return false }
                is KetQua.Dat -> { hien = hien.copy(pham = kq.hq.pham, he = kq.hq.he); veManChinh() }
            }
        }
    }

    /** Làm 1 viên A-SSS bằng 1 viên LV6 (lên A bằng B-SS rồi Thác Ấn bằng Đá In SSS). */
    private fun lamASSS(tranh: Da?): Boolean {
        if (!cd.nhaMayLv6) { tb.log("⛔ Hết đá điểm hóa A-SSS ${he.ten} (bật \"Nhà máy LV6\" để app tự làm)"); return false }
        val ds = quetDanhSach().map { it.da }.filter { it.lv == 6 && it.pham != 'S' && (it.pham == null || it.he == he) }
        // tránh viên đang làm dở (nếu có viên khác để dùng)
        val ds2 = ds.toMutableList().also { l -> tranh?.let { l.remove(it) } }
        var hien = ds2.sortedBy { if (it.pham == 'A') 0 else if (it.he == he) 1 else 2 }.firstOrNull()
            ?: throw DungLai("Không có đá LV6 làm nhà máy A-SSS")
        if (!chonDa(hien)) throw DungLai("Không chọn được đá LV6 nhà máy $hien ($docDuocLanCuoi)")
        tb.log("🏭 Nhà máy LV6 ($hien): làm 1 viên A-SSS ${he.ten}")
        while (true) {
            if (hien.he == he && hien.pham == 'A') { thacAn(3); return true }
            if (hien.he == he && hien.pham == 'B') { thacAn(2); hien = hien.copy(pham = null, he = null); continue }
            when (val kq = diemHoaToiKhi(2) { it.he == he && (it.pham == 'A' || it.pham == 'B') }) {
                is KetQua.HetDa -> {
                    hien = capNhat(hien, kq.hq)
                    veManChinh()
                    if (!lamBSS()) return false
                    if (!chonDa(hien)) throw DungLai("Không tìm lại được đá LV6 nhà máy $hien")
                }
                is KetQua.Dat -> { hien = hien.copy(pham = kq.hq.pham, he = kq.hq.he); veManChinh() }
            }
        }
    }

    // ---------- đá trong bộ ----------
    private fun daXong(d: Da) = d.lv == 6 && d.he == he && Pham.datToi(d.pham, cd.mucTieu)

    private fun thieu(ds: List<Hang>): ChiSo? = cd.soLuong.entries.firstOrNull { (cs, can) ->
        can > 0 && ds.filter { it.da.chiSo == cs && daXong(it.da) }.sumOf { it.soLuong } < can
    }?.key

    private fun lamDaLv6(batDau: Da): Boolean {
        var hien = batDau
        if (!chonDa(hien)) throw DungLai("Không chọn được đá $hien ($docDuocLanCuoi)")
        tb.log("💎 Làm đá $hien → ${cd.mucTieu}·${he.ten}")
        val bac = if (cd.mucTieu == 'A') 2 else 3
        while (true) {
            if (daXong(hien)) { tb.log("✔ Xong 1 viên: $hien"); return true }
            if (hien.he == he && hien.pham == 'B') { thacAn(2); hien = hien.copy(pham = null, he = null); continue }
            when (val kq = diemHoaToiKhi(bac) { it.he == he && (Pham.datToi(it.pham, cd.mucTieu) || it.pham == 'B') }) {
                is KetQua.HetDa -> {
                    hien = capNhat(hien, kq.hq)
                    veManChinh()
                    val ok = if (bac == 2) lamBSS() else lamASSS(hien)
                    if (!ok) return false
                    if (!chonDa(hien)) { tb.log("  Không thấy lại đá $hien → đọc lại danh sách"); return true }
                }
                is KetQua.Dat -> { hien = hien.copy(pham = kq.hq.pham, he = kq.hq.he); veManChinh() }
            }
        }
    }

    fun chay() {
        try {
            tb.log("▶ Bắt đầu: hệ ${he.ten}, mục tiêu ${cd.mucTieu}, " + cd.soLuong.filter { it.value > 0 }.entries.joinToString { "${it.key.ten} ${it.value}" })
            while (!dung) {
                val ds = quetDanhSach()
                tb.log("  Đọc hết danh sách: ${ds.size} hàng đá (" + ds.groupBy { it.da.lv }.entries.sortedByDescending { it.key }.joinToString { "LV${it.key}: ${it.value.size}" } + ")")
                val cs = thieu(ds)
                if (cs == null) { tb.log("🎉 Đã đủ số đá ${cd.mucTieu}·${he.ten} → dừng"); return }
                val ung = ds.map { it.da }.filter { it.lv == 6 && it.chiSo == cs && !daXong(it) && (it.pham == null || it.he == he) }
                val da = ung.sortedBy { if (it.he == he) 0 else 1 }.firstOrNull()
                    ?: run { tb.log("⛔ Thiếu đá LV6-${cs.ten} chưa ban sức (hoặc đúng hệ) để làm → dừng"); return }
                if (!lamDaLv6(da)) return
            }
        } catch (e: DungLai) {
            tb.log(if (dung) "■ Đã dừng" else "⛔ ${e.message}")
        }
    }
}
