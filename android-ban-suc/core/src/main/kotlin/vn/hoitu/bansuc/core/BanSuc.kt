package vn.hoitu.bansuc.core

import kotlin.math.abs

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
    /** Bậc theo màu của 8 ô thẻ ở bảng chọn đá đang hiện (chỉ chụp ảnh, không đọc chữ – nhanh). null: không xem được. */
    fun bacCacO(): List<Int?>? = null
    /** Ảnh màn hình (chỉ chụp, không đọc chữ). */
    fun anh(): Anh? = null
    /** Ô đá của bảng Điểm Hóa / Thác Ấn đang mở có đá chưa (chỉ xem hình – nhanh). null: không rõ. */
    fun oCoDa(diemHoa: Boolean): Boolean? = null
    /** Vuốt nhanh (lật trang bảng chọn đá). */
    fun vuotNhanh(x0: Float, y0: Float, x1: Float, y1: Float) = vuot(x0, y0, x1, y1)
    /** Trang đang xem của bảng chọn đá (trang, số trang) đọc từ chấm trang; null nếu không biết. */
    fun trang(): Pair<Int, Int>? = null
    /** Nút Quay lại của máy (dự phòng khi nút quay lại trong game bị che). */
    fun quayLai() {}
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
        var chonDaLan = 0
        repeat(12) {
            val m = nhin()
            when (m.loai) {
                LoaiMan.CHINH -> return m
                LoaiMan.DIEM_HOA, LoaiMan.THAC_AN -> cham(m, DocMan.DONG_BANG)
                LoaiMan.CHON_DA -> if (++chonDaLan % 2 == 1) cham(m, DocMan.QUAY_LAI) else tb.quayLai() // nút quay lại của game, không ăn thì Quay lại của máy
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
        var khongDoi = 0
        repeat(25) {
            val truoc = m.hang.map { it.da }
            vuotXuong(m); ngu(500)
            m = veManChinh()
            if (m.hang.isNotEmpty() && m.hang.map { it.da } == truoc) { if (++khongDoi >= 2) return m } else khongDoi = 0
        }
        return m
    }

    private fun vuotNguocNgan(m: ManHinh) { // kéo nội dung xuống một đoạn ngắn (~1 hàng)
        val (x0, y0) = m.ra(DocMan.VUOT_DS_TREN.first, DocMan.VUOT_DS_TREN.second)
        val (x1, y1) = m.ra(DocMan.VUOT_DS_TREN.first, DocMan.VUOT_DS_TREN.second + 200f)
        tb.vuot(x0, y0, x1, y1)
    }

    /** Gộp trang mới vào cuối danh sách (bỏ phần trùng). Trả về số hàng trùng. */
    private fun gop(tatCa: MutableList<Hang>, trang: List<Hang>): Int {
        val a = tatCa.map { it.da }; val b = trang.map { it.da }
        var trung = 0
        for (t in minOf(a.size, b.size) downTo 1) if (a.takeLast(t) == b.take(t)) { trung = t; break }
        tatCa += trang.drop(trung)
        return trung
    }

    /**
     * Duyệt danh sách đá từ đầu tới cuối, gọi [xem] với từng trang (dừng khi [xem] trả true).
     * Vuốt trôi quá xa (trang mới không nối được với phần đã xem) thì kéo ngược từng chút để không sót hàng.
     */
    private fun duyetDanhSach(xem: (ManHinh) -> Boolean): Boolean {
        var m = lenDau()
        if (xem(m)) return true
        val daXem = ArrayList<Da>(m.hang.map { it.da })
        var khongDoi = 0
        repeat(60) {
            vuotLen(m); ngu(500)
            var moi = veManChinh()
            if (moi.hang.map { it.da } == m.hang.map { it.da }) {
                if (++khongDoi >= 2) return false // 2 lần vuốt mà trang không đổi: hết danh sách
                return@repeat
            }
            khongDoi = 0
            fun noi(b: List<Da>) = (1..minOf(daXem.size, b.size)).any { t -> daXem.takeLast(t) == b.take(t) }
            if (!noi(moi.hang.map { it.da })) {
                for (lan in 0 until 6) {
                    vuotNguocNgan(moi); ngu(500)
                    moi = veManChinh()
                    if (noi(moi.hang.map { it.da })) break
                }
            }
            if (xem(moi)) return true
            val b = moi.hang.map { it.da }
            var trung = 0
            for (t in minOf(daXem.size, b.size) downTo 1) if (daXem.takeLast(t) == b.take(t)) { trung = t; break }
            daXem += b.drop(trung)
            m = moi
        }
        return false
    }

    /** Đọc cả danh sách đá (gộp các trang, bỏ phần trùng do vuốt chồng lên nhau). */
    private fun quetDanhSach(): List<Hang> {
        val tatCa = ArrayList<Hang>()
        duyetDanhSach { m -> gop(tatCa, m.hang); false }
        return tatCa
    }

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
        return duyetDanhSach { thu(it) }
    }

    private fun moBang(loai: LoaiMan, daThay: ManHinh? = null): ManHinh {
        val m = if (daThay?.loai == LoaiMan.CHINH) daThay else veManChinh()
        cham(m, if (loai == LoaiMan.DIEM_HOA) DocMan.NUT_DIEM_HOA else DocMan.NUT_THAC_AN)
        return cho(5000) { it.loai == loai && it.hien != null } ?: throw DungLai("Không mở được bảng ${if (loai == LoaiMan.DIEM_HOA) "Điểm Hóa" else "Thác Ấn"}")
    }

    private fun tenDa(bac: Int, daIn: Boolean) =
        if (daIn) "Đá In " + "S".repeat(bac) else when (bac) { 1 -> "B-S"; 2 -> "B-SS"; else -> "A-SSS" } + " ${he.ten}"

    // nhớ tồn kho (đọc từ số "xN" trên thẻ, trừ mỗi lần dùng, cộng khi Thác Ấn ra) và vị trí thẻ (trang, ô)
    private val tonKho = HashMap<String, Int>()
    private val chacHet = HashSet<String>() // đã biết chắc là hết (không tìm thấy thẻ, hoặc dùng hết từ số nhỏ đọc được)
    private val viTri = hashMapOf("IN1" to Pair(0, 1), "IN2" to Pair(0, 4), "IN3" to Pair(0, 5)) // Đá In: vị trí cố định, kiểm màu trước khi bấm

    private val hinhMau = HashMap<String, FloatArray>() // hình thẻ đá điểm hóa đã chọn đúng (để lần sau so hình, khỏi đọc chữ)

    private fun khoa(bac: Int, daIn: Boolean) = if (daIn) "IN$bac" else "DH$bac${he.name}"

    private fun daDung(key: String) {
        val c = tonKho[key] ?: return
        tonKho[key] = maxOf(0, c - 1)
        if (c - 1 <= 0) {
            if (c <= 9) chacHet += key // số nhỏ đọc được: tin là hết, khỏi mở bảng chọn
            if (key.startsWith("DH")) run { viTri.keys.removeAll { it.startsWith("DH") }; hinhMau.clear() } // thẻ biến mất → vị trí các thẻ khác dịch đi
        }
    }

    private fun duocThem(key: String) {
        if (key in chacHet || tonKho[key] == 0) run { viTri.keys.removeAll { it.startsWith("DH") }; hinhMau.clear() } // thẻ mới hiện ra
        chacHet -= key
        tonKho[key]?.let { tonKho[key] = it + 1 }
    }

    /** "Dấu vân" vùng thẻ của bảng chọn đá (để biết trang đã đổi chưa) – chỉ chụp ảnh. */
    private fun vanTrang(): FloatArray? = tb.anh()?.let { a ->
        val v = DocMan.vungGame(a); val k = v[2] / DocMan.REF_W
        a.cat((v[0] + 260 * k).toInt(), (v[1] + 230 * k).toInt(), (v[0] + 1800 * k).toInt(), (v[1] + 1050 * k).toInt()).doiCo(64, 32).xam()
    }

    private fun khacTrang(a: FloatArray?, b: FloatArray?): Boolean {
        if (a == null || b == null || a.size != b.size) return true
        var d = 0f; for (i in a.indices) d += abs(a[i] - b[i])
        return d / a.size > 6f
    }

    /**
     * Sang trang sau / trước của bảng chọn đá: vuốt ngang trên vùng thẻ; trang không đổi thì chạm mũi tên,
     * rồi chạm chấm trang. false nếu trang không đổi (đã hết trang theo hướng đó).
     */
    private fun latTrang(m: ManHinh, sau: Boolean): Boolean {
        val tr = tb.trang()
        if (tr != null && ((sau && tr.first >= tr.second - 1) || (!sau && tr.first == 0))) return false // đã ở trang cuối / đầu
        val truoc = vanTrang()
        fun doi(): Boolean {
            if (tr != null) tb.trang()?.let { return it.first != tr.first }
            return khacTrang(truoc, vanTrang())
        }
        val cach = listOf<() -> Unit>(
            {
                // trang sau: kéo từ phải sang trái; trang trước: từ trái sang phải
                val (x0, y0) = m.ra(if (sau) 1500f else 500f, 600f); val (x1, y1) = m.ra(if (sau) 500f else 1500f, 600f)
                tb.vuotNhanh(x0, y0, x1, y1)
            },
            { cham(m, if (sau) DocMan.TRANG_SAU else DocMan.TRANG_TRUOC) },
        )
        for (c in cach) {
            c()
            repeat(5) {
                ngu(150)
                if (doi()) {
                    // chờ trang trượt xong (2 ảnh liền nhau giống nhau)
                    var cu = vanTrang()
                    repeat(5) { ngu(120); val moi = vanTrang(); if (!khacTrang(cu, moi)) return true; cu = moi }
                    return true
                }
            }
        }
        return false
    }

    /** Lật tới trang [dich] (đọc chấm trang); không đọc được chấm thì thôi (coi như đang đúng trang). */
    private fun toiTrang(m: ManHinh, dich: Int): Boolean {
        repeat(6) {
            val tr = tb.trang() ?: return dich == 0
            if (tr.first == dich) return true
            if (!latTrang(m, sau = tr.first < dich)) return false
        }
        return false
    }

    private enum class Them { DUOC, HET, LOI }

    /**
     * Bấm ô "+ Thêm Đá ..." rồi chọn thẻ đúng loại. false: chắc chắn không có thẻ đó (đã xem hết các trang).
     * Không mở được bảng chọn / chọn hỏng thì thử lại (không coi là hết đá).
     */
    private fun themDa(loai: LoaiMan, bac: Int, daIn: Boolean): Boolean {
        repeat(3) { lan ->
            when (themDaMotLan(loai, bac, daIn)) {
                Them.DUOC -> return true
                Them.HET -> return false
                Them.LOI -> {
                    if (cho(1500) { it.loai == loai } != null && oDungDa(khoa(bac, daIn), daIn)) return true // thật ra đã vào ô
                    tb.log("  Chọn ${tenDa(bac, daIn)} chưa được (lần ${lan + 1}) → thử lại")
                    // về đúng bảng Điểm Hóa / Thác Ấn rồi thử lại
                    val m = nhin()
                    if (m.loai == LoaiMan.CHON_DA) { cham(m, DocMan.QUAY_LAI); ngu(600) }
                    if (cho(2500) { it.loai == loai } == null) {
                        val c = veManChinh()
                        cham(c, if (loai == LoaiMan.DIEM_HOA) DocMan.NUT_DIEM_HOA else DocMan.NUT_THAC_AN)
                        cho(5000) { it.loai == loai }
                    }
                }
            }
        }
        throw DungLai("Chọn ${tenDa(bac, daIn)} không được sau 3 lần → dừng (xem màn hình)")
    }

    // hình viên đá trong ô sau khi chọn đúng (game giữ đá trong ô giữa các lần: có đúng viên rồi thì khỏi chọn lại,
    // chọn lại đúng thẻ đang nằm trong ô có thể gỡ nó ra)
    private val hinhOMau = HashMap<String, FloatArray>()

    private fun oDungDa(key: String, daIn: Boolean): Boolean {
        if (tb.oCoDa(!daIn) != true) return false
        val mau = hinhOMau[key] ?: return false
        val a = tb.anh() ?: return false
        return Anh.tuongQuan(DocMan.hinhO(a, DocMan.vungGame(a), !daIn), mau) >= 0.97f
    }

    private fun luuHinhO(key: String, daIn: Boolean) {
        ngu(150)
        if (tb.oCoDa(!daIn) != true) return
        val a = tb.anh() ?: return
        hinhOMau[key] = DocMan.hinhO(a, DocMan.vungGame(a), !daIn)
    }

    private fun themDaMotLan(loai: LoaiMan, bac: Int, daIn: Boolean): Them {
        val key = khoa(bac, daIn)
        if (key in chacHet) return Them.HET
        val bang = cho(3000) { it.loai == loai } ?: return Them.LOI
        if (oDungDa(key, daIn)) return Them.DUOC // ô đã có đúng viên đá này
        fun ve(b: ManHinh?) = b != null && (daIn || b.sau?.he == null || b.sau.he == he)
        fun ra(vi: Int) = bang.ra(DocMan.COT[vi % 4], DocMan.HANG_CHAM[vi / 4])
        /** Bấm ô thêm đá và chờ bảng chọn hiện (xem màu thẻ – nhanh; không rõ thì đọc chữ). */
        fun moChon(): Boolean {
            cham(bang, DocMan.NUT_O)
            for (lan in 0 until 8) {
                ngu(200)
                val mau = tb.bacCacO() ?: break
                if (mau.count { it != null } >= 2) return true
            }
            return cho(2500) { it.loai == LoaiMan.CHON_DA } != null
        }
        fun dongChon() {
            val m = nhin()
            if (m.loai == LoaiMan.CHON_DA) { cham(m, DocMan.QUAY_LAI); cho(3000) { it.loai == loai } }
        }
        /** Chạm thẻ ở ô vi; true nếu đá đã vào ô (và đúng hệ với đá điểm hóa). */
        fun chonO(vi: Int, x: Float, y: Float, daKiemHinh: Boolean): Boolean {
            ngu(200) // bảng chọn vừa hiện / vừa lật trang: chờ đứng yên rồi mới chạm
            tb.cham(x, y)
            if (daIn || daKiemHinh) {
                for (lan in 0 until 15) {
                    if (tb.oCoDa(!daIn) == true) { luuHinhO(key, daIn); return true }
                    ngu(150)
                }
            }
            val b = cho(4000) { it.loai == loai && it.daThem != false }
            if (ve(b)) { luuHinhO(key, daIn); return true }
            val m = nhin()
            tb.log("  (chạm thẻ ô ${vi + 1} xong thấy: ${m.loai}" + (if (m.loai == loai) ", ô đá ${m.daThem}, sau ${m.sau}" else "") + ")")
            return false
        }

        if (!moChon()) return Them.LOI
        // 1) vị trí đã nhớ: kiểm màu (và hình với đá điểm hóa) rồi bấm thẳng
        viTri[key]?.let { (trang, vi) ->
            val dungTrang = if (tb.trang() != null) toiTrang(bang, trang) else (0 until trang).all { latTrang(bang, sau = true) }
            var dungMau = false
            if (dungTrang) for (lan in 0 until 6) {
                if (tb.bacCacO()?.getOrNull(vi) == bac) { dungMau = true; break }
                ngu(150)
            }
            val mauHinh = hinhMau[key]
            val dungHinh = dungMau && !daIn && mauHinh != null && (0 until 4).any { lan ->
                if (lan > 0) ngu(150)
                tb.anh()?.let { DocMan.giongThe(it, vi, mauHinh) >= 0.97f } ?: false
            }
            if (dungMau && (daIn || dungHinh)) {
                val (x, y) = ra(vi)
                if (chonO(vi, x, y, true)) return Them.DUOC
            }
            // chỗ nhớ không còn đúng: dò lại từ đầu
            viTri.remove(key); hinhMau.remove(key)
            dongChon()
            if (!moChon()) return Them.LOI
        }
        // 2) xem lần lượt từng trang từ trang 1 (kéo phải → trái để sang trang sau).
        //    Lượt nhanh: trang mà màu thẻ (đã đứng yên) không có màu cần tìm thì lật qua không đọc chữ.
        //    Không thấy thì lượt chắc: về trang 1, đọc chữ mọi trang. Chỉ cả 2 lượt không thấy mới là hết.
        var thayThe = false
        fun mauYen(): List<Int?>? {
            var cu = tb.bacCacO() ?: return null
            repeat(4) { ngu(150); val moi = tb.bacCacO() ?: return null; if (moi == cu) return moi; cu = moi }
            return null // trang chưa đứng yên: đừng tin màu
        }
        fun veTrangDau() {
            if (tb.trang() != null) { toiTrang(bang, 0); return }
            repeat(5) { if (!latTrang(bang, sau = false)) return }
        }
        for (luot in 0..1) {
            if (luot == 0) toiTrang(bang, 0) else veTrangDau()
            for (trang in 0 until 5) {
                val mau = if (luot == 0) mauYen() else null
                if (mau != null && mau.any { it != null }) thayThe = true
                if (mau == null || mau.all { it == null } || bac in mau) {
                    val m = cho(3000) { it.loai == LoaiMan.CHON_DA } ?: return Them.LOI
                    if (m.the.isNotEmpty()) thayThe = true
                    val t = m.the.firstOrNull { it.bac == bac && it.daIn == daIn && (daIn || it.he == he) && (it.soLuong ?: 1) > 0 }
                    if (t != null) {
                        val hinh = if (!daIn && t.vi >= 0) tb.anh()?.let { DocMan.hinhThe(it, DocMan.vungGame(it), t.vi) } else null
                        if (chonO(t.vi, t.x, t.y, false)) {
                            val trangThat = tb.trang()?.first ?: trang
                            if (t.vi >= 0) viTri[key] = Pair(trangThat, t.vi)
                            if (hinh != null) hinhMau[key] = hinh
                            t.soLuong?.let { tonKho[key] = it }
                            chacHet -= key
                            return Them.DUOC
                        }
                        return Them.LOI // chạm thẻ mà không vào ô / sai hệ: thử lại từ đầu
                    }
                }
                if (trang == 4 || !latTrang(bang, sau = true)) break // hết trang
            }
            if (luot == 0) tb.log("  Lượt nhanh chưa thấy ${tenDa(bac, daIn)} → xem lại kỹ từng trang")
        }
        if (!thayThe) { dongChon(); return Them.LOI } // không thấy thẻ nào: bảng chọn chưa hiện đúng
        tb.log("  Đã xem kỹ hết các trang, không có thẻ ${tenDa(bac, daIn)} → hết")
        tonKho[key] = 0; chacHet += key
        dongChon()
        return Them.HET
    }

    private sealed class KetQua {
        data class Dat(val hq: HieuQua) : KetQua()
        /** Hết đá điểm hóa; [hq] là hiệu quả hiện tại của đá (có thể đã đổi trong lúc điểm hóa). */
        data class HetDa(val hq: HieuQua?) : KetQua()
    }

    /** Mở bảng Điểm Hóa của đá đang chọn, thêm đá điểm hóa bậc [bac] hệ đã chọn, bấm tới khi [xong]. */
    private fun diemHoaToiKhi(bac: Int, xong: (HieuQua) -> Boolean): KetQua {
        if (khoa(bac, false) in chacHet) return KetQua.HetDa(null) // biết là hết: khỏi mở bảng
        var m = moBang(LoaiMan.DIEM_HOA)
        m.hien?.let { if (xong(it)) return KetQua.Dat(it) }
        if (!themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(m.hien)
        m = cho(3000) { it.loai == LoaiMan.DIEM_HOA } ?: throw DungLai("Mất bảng Điểm Hóa")
        val sau = m.sau
        if (sau?.he != null && sau.he != he) throw DungLai("Đá điểm hóa đã thêm không phải hệ ${he.ten} (thấy ${sau.he.ten}) → dừng cho an toàn")
        var lan = 0
        while (true) {
            if (khoa(bac, false) in chacHet && m.daThem != true) return KetQua.HetDa(m.hien)
            if (m.daThem == false && !themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(m.hien)
            val truoc = m.hien
            cham(m, DocMan.NUT_LAM)
            lan++; soLanDiemHoa++
            daDung(khoa(bac, false))
            ngu(cd.nghiMs.toLong())
            // game có thể giữ bảng Điểm Hóa, hoặc tự đóng bảng và về màn chính sau mỗi lần bấm
            val kq = cho(5000) { (it.loai == LoaiMan.DIEM_HOA && it.hien != null) || (it.loai == LoaiMan.CHINH && it.daChon != null) }
                ?: throw DungLai("Không thấy kết quả sau khi bấm Điểm Hóa")
            val hq = if (kq.loai == LoaiMan.CHINH) HieuQua(kq.daChon!!.pham, kq.daChon.he) else kq.hien!!
            if (kq.loai == LoaiMan.DIEM_HOA) m = kq
            if (hq != truoc) tb.log("  Điểm hóa ${tenDa(bac, false)} lần $lan: ${chu(truoc)} → ${chu(hq)}")
            else if (lan % 10 == 0) tb.log("  Điểm hóa ${tenDa(bac, false)} lần $lan: vẫn ${chu(hq)}")
            if (xong(hq)) return KetQua.Dat(hq)
            if (khoa(bac, false) in chacHet) { veManChinh(); return KetQua.HetDa(hq) } // vừa dùng viên cuối: đi nhà máy luôn
            if (kq.loai == LoaiMan.CHINH) {
                m = moBang(LoaiMan.DIEM_HOA, kq) // mở lại bảng để bấm tiếp (đá điểm hóa thường vẫn còn trong ô)
                if (m.daThem == true && m.sau?.he != null && m.sau.he != he) {
                    if (!themDa(LoaiMan.DIEM_HOA, bac, false)) return KetQua.HetDa(hq)
                    m = cho(3000) { it.loai == LoaiMan.DIEM_HOA } ?: throw DungLai("Mất bảng Điểm Hóa")
                }
            }
        }
    }

    private fun tomTat(ds: List<Hang>) = "${ds.size} hàng: " +
        ds.groupBy { it.da.lv }.entries.sortedByDescending { it.key }.joinToString { "LV${it.key}: ${it.value.size}" }

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
        daDung(khoa(bacIn, true))
        ngu(cd.nghiMs.toLong())
        cho(5000) { (it.loai == LoaiMan.THAC_AN && it.hien?.pham == null) || (it.loai == LoaiMan.CHINH && it.daChon != null && it.daChon.pham == null) }
            ?: throw DungLai("Thác Ấn không ăn (đá vẫn còn ${chu(truoc)})")
        if (truoc.he == he) duocThem(khoa(bacIn, false))
        tb.log("  Thác Ấn ${chu(truoc)} bằng ${tenDa(bacIn, true)} → +1 ${when (bacIn) { 2 -> "B-SS"; 3 -> "A-SSS"; else -> "B-S" }} ${he.ten}")
        veManChinh()
    }

    // ---------- nhà máy ----------
    /** Làm 1 viên B-SS bằng đá LV5 nhà máy. */
    private fun lamBSS(): Boolean {
        var f: Da? = nhaMayLv5
        if (f == null || !chonDa(f)) {
            var tatCa = quetDanhSach()
            if (tatCa.none { it.da.lv == 5 }) {
                tb.log("  Chưa thấy đá LV5 (đọc được ${tomTat(tatCa)}) → quét lại")
                tatCa = quetDanhSach()
            }
            val ds = tatCa.map { it.da }.filter { it.lv == 5 }
            f = ds.sortedBy {
                when {
                    it.he == he && it.pham == 'B' -> 0
                    it.he == he -> 1
                    it.pham == null -> 2
                    else -> 3
                }
            }.firstOrNull() ?: throw DungLai("Không có đá LV5 làm nhà máy (danh sách đọc được ${tomTat(tatCa)})")
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
                tb.log("  Đọc hết danh sách: ${tomTat(ds)}")
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
