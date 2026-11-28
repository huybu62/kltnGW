package vn.hoitu.bansuc.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Một viên đá vận mệnh: cấp, phẩm (null = chưa có hiệu quả), hệ, chỉ số. */
data class Da(val lv: Int, val pham: Char?, val he: He?, val chiSo: ChiSo?) {
    override fun toString() = "LV$lv${pham ?: ""}${he?.let { "·" + it.ten } ?: " (trống)"}-${chiSo?.ten ?: "?"}"
}

/** Hiệu quả ban sức đang có (pham = null: "Không có hiệu quả Ban Sức"). */
data class HieuQua(val pham: Char?, val he: He?)

/** Một hàng ở danh sách đá bên trái (x, y: chỗ chạm trên màn hình). */
data class Hang(val da: Da, val x: Float, val y: Float, val daChon: Boolean, val soLuong: Int = 1)

/**
 * Một thẻ trong bảng chọn đá. [bac]: 1 = xanh lam (B-S / Đá In S), 2 = tím (B-SS / Đá In SS), 3 = vàng (A-SSS / Đá In SSS).
 * [daIn]: thẻ Đá In (bảng Thác Ấn) hay Đá Điểm Hóa.
 */
data class The(val bac: Int, val daIn: Boolean, val he: He?, val soLuong: Int?, val x: Float, val y: Float, val chu: String, val vi: Int = -1)

enum class LoaiMan { CHINH, DIEM_HOA, THAC_AN, CHON_DA, KHAC }

/** Màn nhận nhanh bằng ảnh (không đọc chữ): bảng chọn đá, bảng Điểm Hóa / Thác Ấn, màn chính, khác. */
enum class ManNhanh { CHON, BANG, CHINH, KHAC }

/** Những gì đọc được trên một màn hình. Toạ độ chạm đã đổi ra màn hình thật. */
data class ManHinh(
    val loai: LoaiMan,
    val gx: Float, val gy: Float, val k: Float,
    val daChon: Da? = null, // màn chính: tên đá đang chọn (bảng phải)
    val hang: List<Hang> = emptyList(), // màn chính: danh sách bên trái
    val hien: HieuQua? = null, // bảng Điểm Hóa / Thác Ấn: hiệu quả hiện tại của đá
    val sau: HieuQua? = null, // bảng Điểm Hóa / Thác Ấn: hiệu quả sau khi làm
    val daThem: Boolean? = null, // bảng Điểm Hóa / Thác Ấn: đã thêm đá vào ô chưa
    val the: List<The> = emptyList(), // bảng chọn đá
    val tenDaChonTho: String = "", // chữ đọc được ở dòng tên đá bảng phải (để báo lỗi)
) {
    fun ra(x: Float, y: Float) = Pair(gx + x * k, gy + y * k)
}

/**
 * Đọc màn Ban Sức Đá Quý Vận Mệnh từ chữ (OCR) + màu. Toạ độ chuẩn: vùng game rộng 2000 × cao 1125
 * (đo trên ảnh chụp thật của người chơi).
 */
object DocMan {
    const val REF_W = 2000f

    // màn chính
    val TIEU_DE_CHINH = floatArrayOf(1040f, 175f, 1600f, 245f)
    val TEN_DA_CHON = floatArrayOf(1080f, 280f, 1530f, 350f)
    val VUNG_DS = floatArrayOf(395f, 235f, 830f, 1010f) // tên đá ở danh sách trái
    val NUT_DIEM_HOA = Pair(1304f, 954f)
    val NUT_THAC_AN = Pair(1588f, 954f)
    // vuốt ngắn (~2,3 hàng) để mỗi trang chồng lên trang trước, không sót hàng
    val VUOT_DS_TREN = Pair(560f, 420f)
    val VUOT_DS_DUOI = Pair(560f, 830f)

    // bảng Điểm Hóa / Thác Ấn
    val TIEU_DE_BANG = floatArrayOf(820f, 150f, 1260f, 222f)
    val HIEN = floatArrayOf(745f, 296f, 1535f, 362f)
    val SAU = floatArrayOf(745f, 606f, 1535f, 672f)
    val NHAN_O = floatArrayOf(1320f, 558f, 1570f, 612f) // "Thêm Đá Điểm Hóa" / "Thêm Đá In" / "Đã Thêm"
    val NUT_O = Pair(1470f, 505f)
    val NUT_LAM = Pair(1043f, 842f)
    val DONG_BANG = Pair(1510f, 210f)

    // bảng chọn đá
    val COT = floatArrayOf(450f, 840f, 1230f, 1625f)
    val HANG_NHAN = arrayOf(floatArrayOf(440f, 565f), floatArrayOf(920f, 1048f))
    val HANG_CHAM = floatArrayOf(300f, 770f)
    val TRANG_SAU = Pair(1853f, 598f)
    val TRANG_TRUOC = Pair(222f, 598f)
    val QUAY_LAI = Pair(155f, 45f)

    /** Vùng game 16:9 (bỏ viền đen nếu có): (x, y, rộng, cao). */
    fun vungGame(a: Anh): IntArray {
        val hang = a.sangTheoHang(); val cot = a.sangTheoCot()
        val hs = hang.indices.filter { hang[it] > 0.05f }
        val cs = cot.indices.filter { cot[it] > 0.05f }
        var x0 = 0; var y0 = 0; var w = a.w; var h = a.h
        if (hs.isNotEmpty() && cs.isNotEmpty()) {
            y0 = hs.first() * 4; h = minOf(a.h, hs.last() * 4 + 4) - y0
            x0 = cs.first() * 4; w = minOf(a.w, cs.last() * 4 + 4) - x0
            if (w < a.w / 2 || h < a.h / 2) { x0 = 0; y0 = 0; w = a.w; h = a.h }
        }
        val tile = w.toFloat() / h
        if (abs(tile - 16f / 9f) > 0.03f) {
            if (tile > 16f / 9f) { val nw = (h * 16f / 9f).roundToInt(); x0 += (w - nw) / 2; w = nw }
            else { val nh = (w * 9f / 16f).roundToInt(); y0 += (h - nh) / 2; h = nh }
        }
        return intArrayOf(x0, y0, w, h)
    }

    /** Chữ đổi sang toạ độ chuẩn. */
    private class ChuRef(val c: Chu, val x0: Float, val y0: Float, val x1: Float, val y1: Float) {
        val cx get() = (x0 + x1) / 2
        val cy get() = (y0 + y1) / 2
        val n by lazy { VanBan.chuan(c.text) }
    }

    private fun trong(c: ChuRef, v: FloatArray) = c.cx >= v[0] && c.cx <= v[2] && c.cy >= v[1] && c.cy <= v[3]

    private fun noi(ds: List<ChuRef>) = ds.sortedWith(compareBy({ (it.cy / 25).toInt() }, { it.cx })).joinToString(" ") { it.c.text }

    /** Tên đá, vd "LV6A·Lãnh Chúa-Phòng", "LV5Đá Vận Mệnh-HP". */
    fun docTenDa(tho: String): Da? {
        val n = VanBan.chuan(tho)
        val m = Regex("LV(\\d)(.*)").find(n) ?: return null
        val lv = m.groupValues[1].toInt()
        val sau = m.groupValues[2]
        val cs = VanBan.timChiSo(tho)
        // đá chưa ban sức: "LV5Đá Vận Mệnh-HP" (chữ Đ có thể bị đọc sai/mất, nên chỉ cần thấy "VANMENH")
        if (sau.length >= 5 && VanBan.khoangCachDoan("VANMENH", sau.take(12)) <= 2) return Da(lv, null, null, cs)
        if (sau.isEmpty()) return null
        val p = sau[0]
        if (p !in Pham.THU_TU) return null
        val he = VanBan.timHe(sau.drop(1)) ?: return null
        return Da(lv, p, he, cs)
    }

    /** Hiệu quả trong bảng, vd "C·Lãnh Chúa" hoặc "Không có hiệu quả Ban Sức". */
    fun docHieuQua(tho: String): HieuQua? {
        val n = VanBan.chuan(tho)
        if (n.isEmpty()) return null
        if (VanBan.coGanDung("KHONGCOHIEU", n, 3)) return HieuQua(null, null)
        val p = n[0]
        if (p !in Pham.THU_TU) return null
        val he = VanBan.timHe(n.drop(1).take(14)) ?: return null
        return HieuQua(p, he)
    }

    /**
     * Ô đá của bảng có đá chưa, xem bằng hình: ô trống là dấu "+" vàng (chéo góc tối),
     * ô có đá thì chéo góc sáng. null nếu không có ảnh / không rõ.
     */
    fun oCoDa(a: Anh?, vung: IntArray, diemHoa: Boolean): Boolean? {
        if (a == null) return null
        val k = vung[2] / REF_W
        val cx = if (diemHoa) 1480f else 1456f; val cy = 505f
        fun sang(x: Float, y: Float): Int {
            val px = (vung[0] + x * k).toInt(); val py = (vung[1] + y * k).toInt()
            if (px !in 0 until a.w || py !in 0 until a.h) return 0
            val v = a.px[py * a.w + px]
            return maxOf((v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF)
        }
        var tay = 0; var nTay = 0
        for (d in -30..30 step 6) { tay += sang(cx + d, cy) + sang(cx, cy + d); nTay += 2 }
        var cheo = 0; var nCheo = 0
        for (d in listOf(18f, 26f, 34f)) for (sx in listOf(-1, 1)) for (sy in listOf(-1, 1)) { cheo += sang(cx + d * sx, cy + d * sy); nCheo++ }
        val tb = tay / nTay; val tc = cheo / nCheo
        return when {
            tc > 90 -> true
            tb > 150 && tc < 75 -> false
            else -> null
        }
    }

    /** Ảnh xám phần viên đá (có biểu tượng hệ) ở giữa thẻ ô [vi], lệch (dx, dy) theo toạ độ chuẩn. */
    fun hinhThe(a: Anh, vung: IntArray, vi: Int, dx: Float = 0f, dy: Float = 0f): FloatArray {
        val k = vung[2] / REF_W
        val c = COT[vi % 4] + dx; val r = HANG_CHAM[vi / 4] + dy
        val x0 = (vung[0] + (c - 45f) * k).toInt(); val y0 = (vung[1] + (r - 60f) * k).toInt()
        val x1 = (vung[0] + (c + 45f) * k).toInt(); val y1 = (vung[1] + (r + 30f) * k).toInt()
        return a.cat(x0, y0, x1, y1).doiCo(48, 48).xam()
    }

    /** Độ giống (lớn nhất khi xê dịch vài điểm) giữa thẻ ô [vi] trên ảnh [a] và mẫu đã lưu. */
    fun giongThe(a: Anh, vi: Int, mau: FloatArray): Float {
        val v = vungGame(a)
        var tot = -1f
        for (dy in -4..4 step 2) for (dx in -4..4 step 2) tot = maxOf(tot, Anh.tuongQuan(hinhThe(a, v, vi, dx.toFloat(), dy.toFloat()), mau))
        return tot
    }

    /**
     * Trang đang xem của bảng chọn đá, đọc từ các chấm trang dưới cùng (chấm đang chọn sáng hơn hẳn).
     * Trả về (trang, số trang), trang tính từ 0; null nếu không thấy chấm.
     */
    fun trangChon(a: Anh): Pair<Int, Int>? {
        val v = vungGame(a); val k = v[2] / REF_W
        val sang = ArrayList<Pair<Float, Float>>() // (x chuẩn, độ sáng cam lớn nhất của cột)
        var x = 820f
        while (x < 1260f) {
            var tot = 0
            var y = 1080f
            while (y < 1125f) {
                val px = (v[0] + x * k).toInt(); val py = (v[1] + y * k).toInt()
                if (px in 0 until a.w && py in 0 until a.h) {
                    val c = a.px[py * a.w + px]
                    val hsv = Anh.hsv((c shr 16) and 0xFF, (c shr 8) and 0xFF, c and 0xFF)
                    if (hsv[0] in 9..27 && hsv[1] > 120) tot = maxOf(tot, hsv[2])
                }
                y += 3f
            }
            if (tot > 75) sang += Pair(x, tot.toFloat())
            x += 4f
        }
        if (sang.isEmpty()) return null
        // gom thành từng chấm (cách nhau > 8)
        val cham = ArrayList<MutableList<Pair<Float, Float>>>()
        for (p in sang) if (cham.isEmpty() || p.first - cham.last().last().first > 8f) cham += mutableListOf(p) else cham.last() += p
        if (cham.size < 2) return null
        val do_ = cham.map { c -> c.maxOf { it.second } }
        val i = do_.indices.maxBy { do_[it] }
        val nhi = do_.filterIndexed { j, _ -> j != i }.max()
        return if (do_[i] > nhi * 1.25f) Pair(i, cham.size) else null
    }

    /** Tỉ lệ điểm ảnh thỏa [dk] (h 0..360, s, v 0..255) trong vùng chuẩn. */
    private fun tiLe(a: Anh, v: IntArray, x0: Float, y0: Float, x1: Float, y1: Float, dk: (Int, Int, Int) -> Boolean): Float {
        val k = v[2] / REF_W
        var n = 0; var c = 0
        var y = y0
        while (y < y1) {
            var x = x0
            while (x < x1) {
                val px = (v[0] + x * k).toInt(); val py = (v[1] + y * k).toInt()
                if (px in 0 until a.w && py in 0 until a.h) {
                    val p = a.px[py * a.w + px]
                    val hsv = Anh.hsv((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
                    n++; if (dk(hsv[0] * 2, hsv[1], hsv[2])) c++
                }
                x += 4f
            }
            y += 4f
        }
        return if (n == 0) 0f else c.toFloat() / n
    }

    /**
     * Nhận màn bằng ảnh, gần như tức thì: bảng chọn đá có nút quay lại xanh lá góc trái trên; bảng Điểm Hóa /
     * Thác Ấn có nút X đỏ ở giữa trên; màn chính chỉ có nút X đỏ góc phải.
     */
    fun manNhanh(a: Anh): ManNhanh {
        val v = vungGame(a)
        val xanh = tiLe(a, v, 90f, 15f, 250f, 95f) { h, s, b -> h in 86..159 && s > 115 && b > 100 }
        if (xanh > 0.25f) return ManNhanh.CHON
        val doDo = { h: Int, s: Int, b: Int -> (h < 15 || h > 345) && s > 150 && b > 140 }
        val xBang = tiLe(a, v, 1460f, 165f, 1570f, 255f, doDo)
        if (xBang > 0.35f) return ManNhanh.BANG
        val xChinh = tiLe(a, v, 1680f, 170f, 1800f, 265f, doDo)
        if (xChinh > 0.35f) return ManNhanh.CHINH
        return ManNhanh.KHAC
    }

    /** Ảnh xám viên đá đang nằm trong ô của bảng Điểm Hóa / Thác Ấn (để biết ô đã có đúng viên đá cần chưa). */
    fun hinhO(a: Anh, vung: IntArray, diemHoa: Boolean): FloatArray {
        val k = vung[2] / REF_W
        val cx = if (diemHoa) 1480f else 1456f; val cy = 505f
        return a.cat((vung[0] + (cx - 48f) * k).toInt(), (vung[1] + (cy - 48f) * k).toInt(),
            (vung[0] + (cx + 48f) * k).toInt(), (vung[1] + (cy + 48f) * k).toInt()).doiCo(32, 32).xam()
    }

    /** Bậc theo màu của 8 ô thẻ trên bảng chọn đá (xem nhanh bằng ảnh, không đọc chữ). */
    fun bacCacO(a: Anh): List<Int?> {
        val v = vungGame(a)
        return (0 until 8).map { bacTheoMau(a, v, COT[it % 4], it / 4) }
    }

    /** Màu nhãn thẻ → bậc (1 xanh lam, 2 tím, 3 vàng), null nếu thẻ trống/khóa. */
    fun bacTheoMau(a: Anh?, vung: IntArray, cot: Float, hang: Int): Int? {
        if (a == null) return null
        val k = vung[2] / REF_W
        val (y0, y1) = if (hang == 0) Pair(455f, 545f) else Pair(935f, 1025f)
        var xanh = 0; var tim = 0; var vang = 0
        var yy = y0
        while (yy < y1) {
            var xx = cot - 130f
            while (xx < cot + 130f) {
                val px = (vung[0] + xx * k).toInt(); val py = (vung[1] + yy * k).toInt()
                if (px in 0 until a.w && py in 0 until a.h) {
                    val v = a.px[py * a.w + px]
                    val hsv = Anh.hsv((v shr 16) and 0xFF, (v shr 8) and 0xFF, v and 0xFF) // h 0..180, s,v 0..255
                    if (hsv[1] > 100 && hsv[2] > 90) {
                        val h = hsv[0] * 2
                        when {
                            h in 180..222 -> xanh++
                            h in 223..300 -> tim++
                            h in 15..65 -> vang++
                        }
                    }
                }
                xx += 4f
            }
            yy += 4f
        }
        val tong = xanh + tim + vang
        if (tong < 150) return null
        return when (max(xanh, max(tim, vang))) { xanh -> 1; tim -> 2; else -> 3 }
    }

    private fun docThe(cs: List<ChuRef>, a: Anh?, vung: IntArray, k: Float): List<The> {
        val ds = ArrayList<The>()
        for ((h, yr) in HANG_NHAN.withIndex()) for ((ci, cot) in COT.withIndex()) {
            // chữ nằm trong ô thẻ; dòng bị đọc dính qua nhiều thẻ thì cắt theo tỉ lệ bề ngang
            val phan = ArrayList<Pair<Float, String>>()
            for (c in cs) {
                if (c.cy < yr[0] || c.cy > yr[1]) continue
                val l = cot - 195f; val r = cot + 195f
                val chung = min(r, c.x1) - max(l, c.x0)
                if (chung <= 0) continue
                val rong = c.x1 - c.x0
                if (chung / rong >= 0.85f) { phan += Pair(c.cy, c.c.text); continue }
                if (chung < 60f) continue
                val t = c.c.text
                val i0 = ((max(l, c.x0) - c.x0) / rong * t.length).roundToInt().coerceIn(0, t.length)
                val i1 = ((min(r, c.x1) - c.x0) / rong * t.length).roundToInt().coerceIn(i0, t.length)
                phan += Pair(c.cy, t.substring(i0, i1))
            }
            if (phan.isEmpty()) continue
            val chu = phan.sortedBy { it.first }.joinToString(" ") { it.second }
            val n = VanBan.chuan(chu)
            if (n.contains("BOTRONG") || n.length < 4) continue
            if (!n.contains("DIEM") && !n.contains("DAIN") && !n.contains("HOA")) continue
            val daIn = Regex("DAIN").containsMatchIn(n) && !n.contains("DIEM")
            val soLuong = Regex("X(\\d+)").findAll(n).lastOrNull()?.groupValues?.get(1)?.toIntOrNull()
            var bac = bacTheoMau(a, vung, cot, h)
            if (bac == null) {
                // không có màu (vd chạy thử không có ảnh): đọc bậc từ chữ
                bac = if (daIn) Regex("DAIN(S{1,3})").find(n)?.groupValues?.get(1)?.length
                else when (Regex("(ASSS|BSS|BS)DA").find(n)?.groupValues?.get(1)) { "BS" -> 1; "BSS" -> 2; "ASSS" -> 3; else -> null }
            }
            if (bac == null) continue
            val he = if (daIn) null else VanBan.timHe(n.substringAfter("DIEMHOA", n.substringAfter("DIEM", n)))
            val (tx, ty) = Pair(vung[0] + cot * k, vung[1] + HANG_CHAM[h] * k)
            ds += The(bac, daIn, he, soLuong, tx, ty, chu, h * 4 + ci)
        }
        return ds
    }

    /** Đọc màn hình từ các dòng chữ (toạ độ ảnh chụp) và ảnh (để xem màu thẻ; có thể null). */
    fun doc(chu: List<Chu>, a: Anh?, vung: IntArray): ManHinh {
        val k = vung[2] / REF_W
        val gx = vung[0].toFloat(); val gy = vung[1].toFloat()
        val cs = chu.map { ChuRef(it, (it.x0 - gx) / k, (it.y0 - gy) / k, (it.x1 - gx) / k, (it.y1 - gy) / k) }
        fun o(v: FloatArray) = cs.filter { trong(it, v) }

        val tieuDeBang = VanBan.chuan(noi(o(TIEU_DE_BANG)))
        val laDiemHoa = VanBan.coGanDung("DIEMHOAVAN", tieuDeBang, 2)
        val laThacAn = VanBan.coGanDung("THACANVAN", tieuDeBang, 2)
        if (laDiemHoa || laThacAn) {
            // ô đá: xem hình trước (chữ "Đã Thêm" hay bị dòng chữ xanh "Sau In thì..." đè lên), không rõ mới đọc chữ
            val nhan = VanBan.chuan(noi(o(NHAN_O)))
            val daThem = oCoDa(a, vung, laDiemHoa) ?: when {
                nhan.contains("THEMDAIN") || nhan.contains("THEMDADIEM") -> false
                VanBan.coGanDung("DATHEM", nhan, 1) -> true
                else -> null
            }
            return ManHinh(
                if (laDiemHoa) LoaiMan.DIEM_HOA else LoaiMan.THAC_AN, gx, gy, k,
                hien = docHieuQua(noi(o(HIEN))), sau = docHieuQua(noi(o(SAU))), daThem = daThem,
            )
        }

        val tieuDe = VanBan.chuan(noi(o(TIEU_DE_CHINH)))
        if (VanBan.coGanDung("QUYVANMENH", tieuDe, 3)) {
            val tenTho = noi(o(TEN_DA_CHON))
            val daChon = docTenDa(tenTho)
            val hang = ArrayList<Hang>()
            val ten = cs.filter { trong(it, VUNG_DS) && Regex("^LV\\d").containsMatchIn(it.n) }
            val chon = cs.filter { VanBan.coGanDung("DACHON", it.n, 1) && it.cx < VUNG_DS[0] + 60 }
            for (t in ten) {
                val da = docTenDa(t.c.text) ?: continue
                val daChon2 = chon.any { abs(it.cy - (t.cy + 60f)) < 110f }
                // số lượng chồng (vd "x4" ở góc biểu tượng), không đọc được thì coi là 1
                val sl = cs.firstOrNull { it.cx in 300f..560f && it.cy in (t.cy + 50f)..(t.cy + 170f) && Regex("^X?\\d{1,2}$").matches(it.n) }
                    ?.n?.trimStart('X')?.toIntOrNull() ?: 1
                hang += Hang(da, gx + (t.cx) * k, gy + (t.cy + 30f) * k, daChon2, sl)
            }
            // hàng đang chọn bị làm mờ nên hay đọc sót: chỗ có nhãn "Đã chọn" mà không có hàng nào → dùng tên ở bảng phải
            if (daChon != null) for (c in chon) {
                if (hang.none { abs((it.y - gy) / k - (c.cy - 30f)) < 110f }) hang += Hang(daChon, gx + 600f * k, gy + (c.cy - 30f) * k, true)
            }
            return ManHinh(LoaiMan.CHINH, gx, gy, k, daChon = daChon, hang = hang.sortedBy { it.y }, tenDaChonTho = tenTho)
        }
        val the = docThe(cs, a, vung, k)
        if (the.isNotEmpty() || cs.any { it.n.contains("BOTRONG") }) return ManHinh(LoaiMan.CHON_DA, gx, gy, k, the = the)
        return ManHinh(LoaiMan.KHAC, gx, gy, k)
    }
}
