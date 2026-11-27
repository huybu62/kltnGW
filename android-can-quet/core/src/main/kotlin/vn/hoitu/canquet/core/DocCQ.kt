package vn.hoitu.canquet.core

import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.VanBan
import kotlin.math.abs

/** Các màn của Càn quét. */
enum class LoaiCQ { BAN_DO, POPUP, KET_QUA, QUET_LAI, HOI, CHUONG, TRAN, KHAC }

/** Một ải trên màn chương: số ải (1..4), chữ nhãn, chỗ chạm nhãn (màn hình). */
data class AiChuong(val so: Int, val chu: String, val x: Float, val y: Float)

/**
 * Những gì đọc được trên một màn. Toạ độ nút đã đổi ra màn hình thật.
 * [nut]: "CAN_QUET", "X5", "X10", "THAM_HIEM", "DONG" (nút X / Đóng), "LAN_NUA", "QUET_LAI", "XAC_DINH", "TIEN_LEN", "TIEP".
 */
data class ManCQ(
    val loai: LoaiCQ,
    val gx: Float, val gy: Float, val k: Float,
    val theLuc: Int? = null, val theLucMax: Int? = null,
    val ten: String? = null, // tên khu (bảng khu)
    val conLai: Int? = null, // "Số lần còn lại" (bảng khu) hoặc "Số lần: N/M" (màn kết quả)
    val nut: Map<String, Pair<Float, Float>> = emptyMap(),
    val hoiCanQuet: Boolean = false, val hoiSo: Int? = null, // bảng hỏi "Càn quét N lần ... Xác nhận?"
    val nuoc: String? = null, val ai: List<AiChuong> = emptyList(), // màn chương
) {
    fun ra(x: Float, y: Float) = Pair(gx + x * k, gy + y * k)
}

/**
 * Đọc màn Càn quét từ chữ (OCR). Toạ độ chuẩn: vùng game 2000 × 1125 (đo trên ảnh chụp thật).
 */
object DocCQ {
    const val REF_W = 2000f
    const val REF_H = 1125f

    val DONG_POPUP = Pair(1384f, 84f) // nút X đỏ của bảng khu
    val TRO_LAI = Pair(150f, 110f)
    val MUI_TEN_PHAI = Pair(1820f, 560f)
    val MUI_TEN_TRAI = Pair(566f, 560f)
    val MEP_TREN = Pair(1000f, 22f) // chạm để tắt màn lạ (lên cấp...)

    /** Vùng có nút giao diện trên bản đồ, KHÔNG chạm khi tìm toà nhà (x0, y0, x1, y1). */
    val VUNG_CAM = listOf(
        floatArrayOf(0f, 0f, 300f, 210f), // Trở lại
        floatArrayOf(360f, 0f, 1200f, 125f), // thanh EXP / Thể lực
        floatArrayOf(0f, 790f, 500f, 1125f), // Điểm thu hồi (icon + chữ + thanh %)
        floatArrayOf(1030f, 850f, 2000f, 1125f), // Trang bị / Đồng đội / Trận hình
    )

    fun trongVungCam(x: Float, y: Float) = VUNG_CAM.any { x >= it[0] && x <= it[2] && y >= it[1] && y <= it[3] }

    private class C(val c: Chu, val x0: Float, val y0: Float, val x1: Float, val y1: Float) {
        val cx get() = (x0 + x1) / 2
        val cy get() = (y0 + y1) / 2
        val n = VanBan.chuan(c.text)
    }

    /** Số đầu của "N/M" (thể lực có thể bị đọc dính ký hiệu phía sau: "17611/120" → 176). */
    fun soPhanSo(t: String, toiDaHopLy: Int = 9999): Pair<Int, Int>? {
        val m = Regex("(\\d+)\\s*/\\s*(\\d+)").find(t) ?: return null
        val tu = m.groupValues[1]; val mau = m.groupValues[2].toIntOrNull() ?: return null
        var n = tu.toIntOrNull() ?: return null
        if (n > toiDaHopLy) {
            // lấy tiền tố dài nhất còn hợp lý
            n = (tu.length - 1 downTo 1).map { tu.take(it).toInt() }.firstOrNull { it <= toiDaHopLy } ?: return null
        }
        return Pair(n, mau)
    }

    private val CHU_AN_TOAN = listOf("TIEPTUC", "BOQUA", "DONG", "NHANTHUONG", "HOANTHANH", "THOAT")
    private val CHU_NGUY_HIEM = listOf("MUA", "NAP", "KIMCUONG")
    private val GIAO_DIEN_CHUONG = listOf("TROLAI", "DIEMTHUHOI", "CHUONG", "AITHUONG", "AITINHANH", "DUONGANHHUNG", "TUDONGCHIENDAU")

    fun doc(chu: List<Chu>, vung: IntArray): ManCQ {
        val k = vung[2] / REF_W
        val gx = vung[0].toFloat(); val gy = vung[1].toFloat()
        val cs = chu.map { C(it, (it.x0 - gx) / k, (it.y0 - gy) / k, (it.x1 - gx) / k, (it.y1 - gy) / k) }
        fun ra(x: Float, y: Float) = Pair(gx + x * k, gy + y * k)
        fun tim(mau: String, sai: Int = 1, dk: (C) -> Boolean = { true }) =
            cs.firstOrNull { dk(it) && it.n.length >= mau.length - sai && VanBan.khoangCachDoan(mau, it.n) <= sai }
        fun nut(c: C, dy: Float = 0f) = ra(c.cx, c.cy + dy)

        // 1) bảng hỏi xác nhận (đè lên bản đồ)
        val xacDinh = tim("XACDINH", 1)
        val xacNhan = tim("XACNHAN", 2)
        if (xacDinh != null && xacNhan != null) {
            val cau = cs.filter { it.cy < xacDinh.cy && it.cy > xacDinh.cy - 300f }.sortedBy { it.cy }.joinToString("") { it.n }
            val so = Regex("CANQUET(\\d+)LAN").find(cau)?.groupValues?.get(1)?.toIntOrNull()
            val laCQ = VanBan.coGanDung("CANQUET", cau, 2) && so != null && CHU_NGUY_HIEM.none { cau.contains(it) && !cau.contains("XU") }
            return ManCQ(LoaiCQ.HOI, gx, gy, k, nut = mapOf("XAC_DINH" to nut(xacDinh)), hoiCanQuet = laCQ, hoiSo = so)
        }

        fun soLanKetQua(): Int? = cs.filter { it.n.contains("SOLAN") && !it.n.contains("CONLAI") }
            .firstNotNullOfOrNull { soPhanSo(it.c.text)?.first }

        // 2) màn kết quả sau xN: nút "Quét lại"
        val quetLai = tim("QUETLAI", 1) { it.n.length <= 9 }
        if (quetLai != null) {
            val dong = tim("DONG", 0) { it.cx > 1300f } ?: tim("THOAT", 1)
            val nut = mutableMapOf("QUET_LAI" to nut(quetLai))
            dong?.let { nut["DONG"] = nut(it) }
            return ManCQ(LoaiCQ.QUET_LAI, gx, gy, k, conLai = soLanKetQua(), nut = nut)
        }

        // 3) màn kết quả càn quét lẻ: "Càn quét lần nữa" + "Số lần: N/M" + "Đóng"
        val lanNua = tim("CANQUETLANNUA", 3) { it.cx > 1350f }
        if (lanNua != null) {
            val nut = mutableMapOf("LAN_NUA" to ra(lanNua.cx, lanNua.cy - 110f)) // biểu tượng đầu lâu phía trên chữ
            val dong = tim("DONG", 0) { it.cx > 1350f && it.cy > lanNua.cy }
            nut["DONG"] = if (dong != null) ra(dong.cx, dong.cy - 115f) else ra(1745f, 840f) // dấu X đỏ trên chữ "Đóng"
            return ManCQ(LoaiCQ.KET_QUA, gx, gy, k, conLai = soLanKetQua(), nut = nut)
        }

        // 4) bảng khu: "Số lần còn lại:N"
        val conLaiC = cs.firstOrNull { VanBan.coGanDung("SOLANCONLAI", it.n, 3) && it.n.length >= 8 }
        if (conLaiC != null) {
            val con = Regex("(\\d+)\\D*$").find(conLaiC.c.text)?.groupValues?.get(1)?.toIntOrNull()
            val ten = cs.filter { it.cy in 90f..215f && it.cx in 560f..1150f && it.n.length >= 3 && !it.n.contains("SOLAN") }
                .minByOrNull { it.cy }?.c?.text?.trim()
            val nut = mutableMapOf("DONG" to ra(DONG_POPUP.first, DONG_POPUP.second))
            val hangNut = cs.filter { it.cy > 880f && it.cy < 1080f }
            hangNut.firstOrNull { VanBan.khoangCachDoan("CANQUET", it.n) <= 1 && it.n.length <= 9 }?.let { nut["CAN_QUET"] = nut(it) }
            hangNut.firstOrNull { VanBan.khoangCachDoan("THAMHIEM", it.n) <= 2 && it.n.length <= 10 }?.let { nut["THAM_HIEM"] = nut(it) }
            hangNut.firstOrNull { it.n == "X10" || it.n == "10" }?.let { nut["X10"] = nut(it) }
            hangNut.firstOrNull { it.n == "X5" || it.n == "5" || it.n == "XS" }?.let { nut["X5"] = nut(it) }
            return ManCQ(LoaiCQ.POPUP, gx, gy, k, ten = ten, conLai = con, nut = nut)
        }

        // 5) đang đánh (thám hiểm)
        val tienLen = tim("TIENLEN", 1)
        val hiep = cs.firstOrNull { it.n == "HIEP" && it.cy < 200f }
        if (tienLen != null || hiep != null) {
            val nut = mutableMapOf<String, Pair<Float, Float>>()
            tienLen?.let { nut["TIEN_LEN"] = nut(it) }
            return ManCQ(LoaiCQ.TRAN, gx, gy, k, nut = nut)
        }

        // 6) màn chương: nút "Chương" góc phải trên + nhãn ải
        val chuong = cs.firstOrNull { it.n == "CHUONG" && it.cx > 1600f && it.cy < 260f }
        if (chuong != null) {
            val nuoc = cs.firstOrNull { it.cy < 0.16f * REF_H && it.cx in 0.4f * REF_W..0.75f * REF_W && it.n.length >= 3 }?.c?.text?.trim()
            return ManCQ(LoaiCQ.CHUONG, gx, gy, k, nuoc = nuoc, ai = docAi(cs.map { Triple(it.c.text, it.cx, it.cy) }).map { (so, t, x, y) ->
                val (sx, sy) = ra(x, y); AiChuong(so, t, sx, sy)
            })
        }

        // 7) bản đồ: "Thể lực N/M" ở thanh trên
        val theLuc = tim("THELUC", 1) { it.cy < 150f && it.n.length <= 7 }
        if (theLuc != null) {
            val so = cs.filter { it.cy < 150f && it.x0 >= theLuc.x1 - 10f && it.x0 < theLuc.x1 + 400f }
                .firstNotNullOfOrNull { soPhanSo(it.c.text, 999) }
            val tl = so?.let { (n, m) -> if (n > m * 3) null else n }
            return ManCQ(LoaiCQ.BAN_DO, gx, gy, k, theLuc = tl, theLucMax = so?.second)
        }

        // 8) màn lạ: tìm nút an toàn (không bấm khi có chữ mua / nạp)
        val nguyHiem = cs.any { c -> CHU_NGUY_HIEM.any { c.n.contains(it) } }
        val an = if (nguyHiem) null else cs.firstOrNull { c -> CHU_AN_TOAN.any { c.n == it } }
        return ManCQ(LoaiCQ.KHAC, gx, gy, k, nut = an?.let { mapOf("TIEP" to nut(it)) } ?: emptyMap())
    }

    /** Nhãn ải "N-M Tên ải" trên màn chương (chữ thô + tâm theo toạ độ chuẩn) → (số ải, chữ, x, y) sắp theo số. */
    fun docAi(ds: List<Triple<String, Float, Float>>): List<AiChuong> {
        val nhan = ArrayList<Array<Any?>>()
        for ((t, x, y) in ds) {
            val fx = x / REF_W; val fy = y / REF_H
            val n = VanBan.chuan(t)
            if (fx < 0.27f || fy < 0.16f) continue
            if (GIAO_DIEN_CHUONG.any { n.contains(it) } || n.contains("%") || n.count { it in 'A'..'Z' } < 3) continue
            // dòng vàng "Hoàn toàn thu hồi" hay bị đọc sai ("Hoan ton huhoi", "Hoantoanthuhot")
            if (VanBan.khoangCachDoan("HOANTOANTHUHOI", n.filter { it in 'A'..'Z' }) <= 4 && n.length <= 16) continue
            if (VanBan.coGanDung("THUHOI", n, 1) && n.length <= 16) continue
            val tho = t.lowercase()
            val m = Regex("^\\s*(?:\\d\\s*)?[-–—]\\s*(\\d)").find(tho) ?: Regex("^\\s*(\\d)\\s*[-–—]?\\s*[a-zà-ỹđ]").find(tho)
            nhan += arrayOf(m?.groupValues?.get(1)?.toIntOrNull(), t.trim(), x, y)
        }
        val coSo = nhan.mapNotNull { it[0] as Int? }.toSet()
        val thieu = (1..4).filter { it !in coSo }.toMutableList()
        for (n in nhan) if (n[0] == null && thieu.isNotEmpty()) n[0] = thieu.removeAt(0) // nhãn bị che mất số
        val gap = LinkedHashMap<Int, AiChuong>()
        for (n in nhan.filter { it[0] != null }.sortedBy { it[0] as Int }) {
            val so = n[0] as Int
            if (so in 1..9) gap.getOrPut(so) { AiChuong(so, n[1] as String, n[2] as Float, n[3] as Float) }
        }
        return gap.values.toList()
    }

    /**
     * Vùng game: khung 16:9 ở giữa ảnh chụp (theo tỉ lệ màn hình, không dò viền đen – ở mép bản đồ có
     * vùng đen nên dò viền sẽ sai).
     */
    fun vungGame(w: Int, h: Int): IntArray {
        val tl = w.toFloat() / h
        return if (tl > 16f / 9f) { val gw = (h * 16f / 9f).toInt(); intArrayOf((w - gw) / 2, 0, gw, h) }
        else { val gh = (w * 9f / 16f).toInt(); intArrayOf(0, (h - gh) / 2, w, gh) }
    }

    // ---------- ảnh (không đọc chữ – nhanh) ----------
    /** Ảnh xám thu nhỏ của vùng game (để đo bản đồ dịch, đo độ sáng). [buoc]: điểm ảnh chuẩn mỗi ô. */
    fun xamNho(a: Anh, buoc: Float = 8f): Triple<FloatArray, Int, Int> {
        val v = vungGame(a.w, a.h)
        val w = (REF_W / buoc).toInt(); val h = (REF_H / buoc).toInt()
        return Triple(a.cat(v[0], v[1], v[0] + v[2], v[1] + v[3]).doiCo(w, h).xam(), w, h)
    }

    /** Độ sáng trung bình phần giữa vùng game (bảng / màn tối đi thì giảm mạnh). */
    fun doSang(g: Triple<FloatArray, Int, Int>): Float {
        val (px, w, h) = g
        var s = 0.0; var n = 0
        for (y in h / 5 until h * 4 / 5) for (x in w / 5 until w * 4 / 5) { s += px[y * w + x]; n++ }
        return (s / maxOf(1, n)).toFloat()
    }

    /** Độ chi tiết (độ lệch chuẩn) quanh điểm (x, y) chuẩn – toà nhà nhiều chi tiết hơn đường / cỏ. */
    fun doChiTiet(g: Triple<FloatArray, Int, Int>, x: Float, y: Float, buoc: Float = 8f, ban: Int = 7): Float {
        val (px, w, h) = g
        val cx = (x / buoc).toInt(); val cy = (y / buoc).toInt()
        var s = 0.0; var s2 = 0.0; var n = 0
        for (yy in (cy - ban).coerceAtLeast(0)..(cy + ban).coerceAtMost(h - 1)) for (xx in (cx - ban).coerceAtLeast(0)..(cx + ban).coerceAtMost(w - 1)) {
            val v = px[yy * w + xx].toDouble(); s += v; s2 += v * v; n++
        }
        if (n == 0) return 0f
        val tb = s / n
        return kotlin.math.sqrt(maxOf(0.0, s2 / n - tb * tb)).toFloat()
    }

    /** NCC của miếng t (tw×th) đặt tại (x, y) trên ảnh a (aw rộng). */
    private fun ncc(a: FloatArray, aw: Int, x: Int, y: Int, t: FloatArray, tw: Int, th: Int, tTb: Float, tDo: Double): Float {
        var s = 0.0
        for (yy in 0 until th) { val o = (y + yy) * aw + x; for (xx in 0 until tw) s += a[o + xx] }
        val tb = s / (tw * th)
        var sab = 0.0; var saa = 0.0; var k = 0
        for (yy in 0 until th) {
            val o = (y + yy) * aw + x
            for (xx in 0 until tw) { val d = a[o + xx] - tb; sab += d * (t[k] - tTb); saa += d * d; k++ }
        }
        val m = kotlin.math.sqrt(saa * tDo)
        return if (m < 1e-6) 0f else (sab / m).toFloat()
    }

    /**
     * Bản đồ dịch bao nhiêu (theo toạ độ chuẩn) từ ảnh a sang b: so vài miếng nhiều chi tiết, lấy độ dịch
     * nhiều miếng đồng ý nhất. [goiY]: độ dịch dự đoán (chuẩn) – chỉ dò trong khoảng từ 0 tới gợi ý (± lề),
     * nhanh hơn nhiều. null nếu không đo chắc.
     */
    fun doLech(a: Triple<FloatArray, Int, Int>, b: Triple<FloatArray, Int, Int>, buoc: Float = 8f, goiY: Pair<Float, Float>? = null, chiQuanh: Boolean = false): Pair<Float, Float>? {
        val (pa, w, h) = a; val pb = b.first
        if (b.second != w || b.third != h) return null
        val pw = (w * 0.16f).toInt(); val ph = (h * 0.18f).toInt()
        val le = 14
        val gx = ((goiY?.first ?: 0f) / buoc).toInt(); val gy = ((goiY?.second ?: 0f) / buoc).toInt()
        // chiQuanh: chỉ dò quanh gợi ý (± lề); không thì dò từ 0 tới gợi ý (± lề)
        val dx0 = if (goiY == null) -w else if (chiQuanh) gx - le else minOf(0, gx) - le
        val dx1 = if (goiY == null) w else if (chiQuanh) gx + le else maxOf(0, gx) + le
        val dy0 = if (goiY == null) -h else if (chiQuanh) gy - le else minOf(0, gy) - le
        val dy1 = if (goiY == null) h else if (chiQuanh) gy + le else maxOf(0, gy) + le
        val ung = ArrayList<Triple<Float, Int, Int>>()
        for (iy in 0 until 5) for (ix in 0 until 8) {
            val x0 = (w * (0.06f + ix * 0.11f)).toInt(); val y0 = (h * (0.14f + iy * 0.12f)).toInt()
            if (x0 + pw >= w || y0 + ph >= h) continue
            // miếng phải còn nằm trọn trong ảnh với mọi độ dịch đang dò (không thì khớp nhầm)
            if (goiY != null && (x0 + dx0 < 0 || x0 + dx1 + pw > w || y0 + dy0 < 0 || y0 + dy1 + ph > h)) continue
            var s = 0.0; var s2 = 0.0
            for (y in y0 until y0 + ph) for (x in x0 until x0 + pw) { val v = pa[y * w + x].toDouble(); s += v; s2 += v * v }
            val n = pw * ph; val sd = kotlin.math.sqrt(maxOf(0.0, s2 / n - (s / n) * (s / n)))
            if (sd >= 10) ung += Triple(sd.toFloat(), x0, y0)
        }
        val kq = ArrayList<Triple<Float, Float, Float>>()
        for ((_, x0, y0) in ung.sortedByDescending { it.first }.take(7)) {
            val t = FloatArray(pw * ph) { pa[(y0 + it / pw) * w + x0 + it % pw] }
            var tb = 0.0; for (v in t) tb += v; tb /= t.size
            var tDo = 0.0; for (v in t) tDo += (v - tb) * (v - tb)
            var tot = -2f; var bx = 0; var by = 0
            for (dy in dy0..dy1) {
                val y = y0 + dy; if (y < 0 || y + ph > h) continue
                for (dx in dx0..dx1) {
                    val x = x0 + dx; if (x < 0 || x + pw > w) continue
                    val d = ncc(pb, w, x, y, t, pw, ph, tb.toFloat(), tDo)
                    if (d > tot) { tot = d; bx = dx; by = dy }
                }
            }
            if (tot > 0.8f) kq += Triple(bx.toFloat(), by.toFloat(), tot)
        }
        if (kq.isEmpty()) return null
        // kiểm lại từng độ dịch ứng viên trên CẢ phần ảnh trùng nhau (đường dài khớp được nhiều chỗ, cả ảnh thì không)
        val tot = kq.map { Pair(it.first.toInt(), it.second.toInt()) }.distinct()
            .map { Triple(it, saiLech(pa, pb, w, h, it.first, it.second), kq.count { k -> abs(k.first - it.first) <= 1.5f && abs(k.second - it.second) <= 1.5f }) }
            .minWith(compareBy({ it.second }, { -it.third }))
        if (tot.second > 14f) return null
        return Pair(tot.first.first * buoc, tot.first.second * buoc)
    }

    /** Độ khác trung bình giữa a và b dịch (dx, dy) trên phần trùng nhau (bỏ thanh trên / dưới). */
    private fun saiLech(pa: FloatArray, pb: FloatArray, w: Int, h: Int, dx: Int, dy: Int): Float {
        var s = 0.0; var n = 0
        val y0 = maxOf(h / 8, h / 8 - dy); val y1 = minOf(h * 7 / 8, h * 7 / 8 - dy)
        val x0 = maxOf(w / 12, -dx); val x1 = minOf(w * 11 / 12, w - dx)
        var y = y0
        while (y < y1) {
            var x = x0
            while (x < x1) { s += abs(pa[y * w + x] - pb[(y + dy) * w + x + dx]); n++; x += 2 }
            y += 2
        }
        return if (n < 200) 999f else (s / n).toFloat()
    }

    /** Ảnh thu nhỏ một nửa (để đo thô trên cả ảnh cho nhanh). */
    fun nuaCo(a: Triple<FloatArray, Int, Int>): Triple<FloatArray, Int, Int> {
        val (p, w, h) = a
        val w2 = w / 2; val h2 = h / 2
        return Triple(FloatArray(w2 * h2) { i -> val x = (i % w2) * 2; val y = (i / w2) * 2
            (p[y * w + x] + p[y * w + x + 1] + p[(y + 1) * w + x] + p[(y + 1) * w + x + 1]) / 4f }, w2, h2)
    }

    /** Đo dịch thô trên cả ảnh (khi đo nhanh quanh độ dịch dự đoán không ra – vd game kéo bản đồ nhanh/chậm hơn ngón tay). */
    fun doLechTho(a: Triple<FloatArray, Int, Int>, b: Triple<FloatArray, Int, Int>, buoc: Float = 8f): Pair<Float, Float>? {
        val tho = doLech(nuaCo(a), nuaCo(b), buoc * 2, null) ?: return null
        // tinh chỉnh lại quanh kết quả thô
        return doLech(a, b, buoc, tho) ?: tho
    }

    /** Hai ảnh gần như giống hệt (bản đồ không dịch). */
    fun giongHet(a: Triple<FloatArray, Int, Int>, b: Triple<FloatArray, Int, Int>): Boolean {
        val (pa, w, h) = a; val pb = b.first
        var d = 0.0; var n = 0
        for (y in h / 6 until h * 5 / 6 step 2) for (x in w / 8 until w * 7 / 8 step 2) { d += abs(pa[y * w + x] - pb[y * w + x]); n++ }
        return d / maxOf(1, n) < 3.0
    }
}
