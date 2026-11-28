package vn.hoitu.banco.core

import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.VanBan
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Màn của sự kiện Bàn Cờ Lửa. */
enum class LoaiBC { BANG, MUA, HOI_TAO_MOI, HOI_TAKE_AWAY, HOI_KHAC, KHAC }

/** [vung]: vùng game trên ảnh (x, y, rộng, cao). [takeAway]: nút Take-away (toạ độ chuẩn) khi đang mở bảng Mua. */
class ManBC(val loai: LoaiBC, val vung: IntArray, val takeAway: Pair<Float, Float>? = null, val chuHoi: String = "", val giaHoi: Int? = null) {
    val k get() = vung[2] / DocBC.REF_W
    fun ra(p: Pair<Float, Float>) = Pair(vung[0] + p.first * k, vung[1] + p.second * k)
    override fun toString() = "$loai" + (if (chuHoi.isNotEmpty()) "(\"$chuHoi\")" else "")
}

/** Một ô trong 5 ô đầu hàng trên cùng. */
enum class O(val ten: String) { TUONG("Tướng"), SOAI("Soái"), CO("cờ"), UP("úp"), KHAC("khác") }

data class HangDau(val o: List<O>) {
    /** điểm giống mẫu Tướng/Soái của các ô cờ (để ghi nhật ký) */
    var diem: List<Float> = emptyList()
    /** độ sáng/độ lệch 5 ô (để chẩn đoán) */
    var chiTiet: String = ""
    val soCo get() = o.count { it == O.TUONG || it == O.SOAI || it == O.CO }
    val up get() = o.count { it == O.UP } >= 3
    val coTuongSoai get() = o.any { it == O.TUONG || it == O.SOAI }
    override fun toString() = o.joinToString(" ") { it.ten }
}

object DocBC {
    const val REF_W = 2000f
    const val REF_H = 1125f

    // toạ độ chuẩn (vùng game 2000×1125)
    val O_X = FloatArray(5) { 375f + 88f * it }
    const val O_Y = 293f
    val TAY = Pair(650f, 987f)
    val TAO_MOI = Pair(872f, 987f)
    val MUA = Pair(1097f, 987f)
    val TAKE_AWAY = Pair(1385f, 967f)
    val OK = Pair(1188f, 718f)
    val HUY = Pair(835f, 718f)
    /** Chỗ trống bên phải (hình ngọn lửa) – chạm để tắt bảng Mua. */
    val CHO_TRONG = Pair(1530f, 560f)

    fun vungGame(a: Anh) = DocMan.vungGame(a)

    // ---------- đọc chữ ----------
    fun doc(chu: List<Chu>, vung: IntArray): ManBC {
        val k = vung[2] / REF_W
        data class C(val n: String, val x: Float, val y: Float, val t: String)
        val ds = chu.map { C(VanBan.chuan(it.text), ((it.x0 + it.x1) / 2 - vung[0]) / k, ((it.y0 + it.y1) / 2 - vung[1]) / k, it.text) }
        val ok = ds.any { it.n == "OK" && it.x in 1030f..1350f && it.y in 640f..800f }
        val huy = ds.any { (it.n == "HUY" || it.n == "HUYS") && it.x in 680f..990f && it.y in 640f..800f }
        if (ok || huy) {
            // bỏ nhãn số lượng của ô bên dưới lớp tối (vd "x500", "888)")
            val hoi = ds.filter { it.x in 560f..1200f && it.y in 440f..640f && it.n != "OK" && it.n != "HUY" && it.n.count { c -> c.isLetter() } >= 3 && !Regex("X?\\d+").matches(it.n) }
            val n = hoi.joinToString("") { it.n }
            val t = hoi.joinToString(" ") { it.t }
            val mienPhi = n.contains("MIENPHI") || VanBan.khoangCachDoan("MIENPHI", n) <= 1
            val gia = Regex("TON(\\d+)").find(n)?.groupValues?.get(1)?.toIntOrNull() ?: if (mienPhi) 0 else null
            val loai = when {
                mienPhi || n.contains("TAOMOI") || VanBan.khoangCachDoan("TAOMOI", n) <= 1 -> LoaiBC.HOI_TAO_MOI
                n.contains("TAKEAWAY") || n.contains("XACNHAN") || VanBan.khoangCachDoan("TAKEAWAY", n) <= 2 -> LoaiBC.HOI_TAKE_AWAY
                else -> LoaiBC.HOI_KHAC
            }
            return ManBC(loai, vung, chuHoi = t, giaHoi = gia)
        }
        ds.firstOrNull { it.x > 1200f && it.y in 880f..1060f && (it.n.contains("TAKEAWAY") || VanBan.khoangCachDoan("TAKEAWAY", it.n) <= 1) }
            ?.let { return ManBC(LoaiBC.MUA, vung, takeAway = Pair(it.x, it.y)) }
        val nut = ds.filter { it.y in 930f..1050f }
        val soNut = listOf("TAY" to 650f, "TAOMOI" to 872f, "MUA" to 1097f).count { (ten, x) -> nut.any { it.n == ten && kotlin.math.abs(it.x - x) < 120f } }
        if (soNut >= 2) return ManBC(LoaiBC.BANG, vung)
        return ManBC(LoaiBC.KHAC, vung)
    }

    // ---------- đọc ảnh: 5 ô đầu ----------
    private fun hsv(p: Int): FloatArray {
        val r = ((p shr 16) and 0xFF) / 255f; val g = ((p shr 8) and 0xFF) / 255f; val b = (p and 0xFF) / 255f
        val mx = max(r, max(g, b)); val mn = min(r, min(g, b)); val d = mx - mn
        var h = when {
            d == 0f -> 0f
            mx == r -> 60f * (((g - b) / d) % 6f)
            mx == g -> 60f * ((b - r) / d + 2f)
            else -> 60f * ((r - g) / d + 4f)
        }
        if (h < 0) h += 360f
        return floatArrayOf(h, if (mx == 0f) 0f else d / mx, mx)
    }

    /** Tỉ lệ điểm ảnh đỏ / vàng cam / màu lạnh / sáng nhạt trong ô. */
    fun mauO(a: Anh, vung: IntArray, i: Int): FloatArray {
        val k = vung[2] / REF_W
        val cx = vung[0] + O_X[i] * k; val cy = vung[1] + O_Y * k; val r = 34f * k
        var n = 0; var red = 0; var warm = 0; var cool = 0; var light = 0
        var y = (cy - r).toInt()
        while (y < (cy + r).toInt()) {
            var x = (cx - r).toInt()
            while (x < (cx + r).toInt()) {
                if (x in 0 until a.w && y in 0 until a.h) {
                    val (h, s, v) = hsv(a.px[y * a.w + x]).let { Triple(it[0], it[1], it[2]) }
                    n++
                    if (s > 0.5f && v > 0.35f && (h < 22f || h > 340f)) red++
                    else if (s > 0.4f && v > 0.35f && h >= 22f && h < 60f) warm++
                    else if (s > 0.3f && v > 0.25f && h >= 60f && h < 330f) cool++
                    if (s < 0.35f && v > 0.7f) light++
                }
                x++
            }
            y++
        }
        if (n == 0) return floatArrayOf(0f, 0f, 0f, 0f)
        return floatArrayOf(red / n.toFloat(), warm / n.toFloat(), cool / n.toFloat(), light / n.toFloat())
    }

    private fun laChu(p: Int): Boolean {
        val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
        return r > 60 && g > 0.66f * r && b > 0.42f * r && r - b > 15
    }

    const val S = 20

    /** Hình chữ (màu be) trong vùng, cắt sát rồi đổi cỡ S×S (0..1). */
    fun hinhChu(a: Anh): FloatArray? {
        val xs = ArrayList<Int>(); val ys = ArrayList<Int>()
        for (y in 0 until a.h) for (x in 0 until a.w) if (laChu(a.px[y * a.w + x])) { xs += x; ys += y }
        val n = xs.size
        if (n < 15) return null
        xs.sort(); ys.sort()
        val x0 = xs[n / 50]; val x1 = xs[n - 1 - n / 50]; val y0 = ys[n / 50]; val y1 = ys[n - 1 - n / 50]
        if (x1 - x0 < 4 || y1 - y0 < 4) return null
        val w = x1 - x0 + 1; val h = y1 - y0 + 1
        val px = IntArray(w * h) { i -> if (laChu(a.px[(y0 + i / w) * a.w + x0 + i % w])) -0x1 else -0x1000000 }
        val m = Anh(w, h, px).doiCo(S, S)
        return FloatArray(S * S) { m.r(it) / 255f }
    }

    /** Vùng chữ trên ô i (toạ độ ảnh). */
    fun vungChu(a: Anh, vung: IntArray, i: Int): Anh {
        val k = vung[2] / REF_W
        val cx = vung[0] + O_X[i] * k; val cy = vung[1] + O_Y * k
        return a.cat((cx - 28 * k).toInt(), (cy - 30 * k).toInt(), (cx + 28 * k).toInt(), (cy + 16 * k).toInt())
    }

    fun ncc(a: FloatArray, b: FloatArray): Float {
        val ma = a.average().toFloat(); val mb = b.average().toFloat()
        var s = 0f; var da = 0f; var db = 0f
        for (i in a.indices) { val x = a[i] - ma; val y = b[i] - mb; s += x * y; da += x * x; db += y * y }
        return s / (sqrt(da * db) + 1e-6f)
    }

    private fun mau(hex: String) = FloatArray(S * S) { Character.digit(hex[it], 16) / 15f }

    // mẫu chữ 将 (Tướng) và 帅 (Soái), lấy từ ảnh người dùng gửi (xem BanCoTest.taoMau)
    val MAU_TUONG = mau(
        "0000ffa0005ffc0000000005ffa000cfff7777070000ffa002ffffffffffc800ffa00cfffffdffffff72ffa0ffff00005ffc" +
        "fffffffaffffa2007ff7fffffffcff7ffc42fff22ffffff27507ffffffa00afffff00000affffb00007cfff00027fffff000" +
        "0005ffa047fffffcf7500007ffa0cfffd700ffc0000cffc07fff7005fff2007ffff5ffffffffffff02fffffcffffffffffff" +
        "2dffffa255dc5557dff7ffffff7000ab0000afa0ff70ff5000ff50007fa0fc00ff5000afc0005fa05200cf50002cf0005fa0"
    )
    val MAU_SOAI = mau(
        "0000fff500000cfa00000000bff000000afa0000ff707ff000000cfa0000ffa07ff005557fff7553ffa07ff04fffffffffff" +
        "ffa0bff07fffffffffffffa0fff37ff75ffd53ffffa0fff57ff00ffa00ffffa0fff57ff00fff00ffffa0fff27ff00fff00ff" +
        "ffa0fff07ff00fff00ffffa0fff07ff00ffc00ffff70ffc07ff00ffa00ffff50ffa02ff00cfa00ffff50ffa00fc00afa00cf" +
        "ff55ffa00fa00afa00cfff58ff300fa008fd58ff472cfc000fa005fffff7005ff5000fa005f5777000afc200083005f50000"
    )
    const val NGUONG_CHU = 0.55f

    /** Độ sáng trung bình và độ lệch chuẩn trong ô i (ô úp: màu trơn, lệch rất nhỏ). */
    fun sangO(a: Anh, vung: IntArray, i: Int): Pair<Float, Float> {
        val k = vung[2] / REF_W
        val cx = vung[0] + O_X[i] * k; val cy = vung[1] + O_Y * k; val r = 30f * k
        var n = 0; var s = 0.0; var s2 = 0.0
        for (y in (cy - r).toInt() until (cy + r).toInt()) for (x in (cx - r).toInt() until (cx + r).toInt()) {
            if (x !in 0 until a.w || y !in 0 until a.h) continue
            val p = a.px[y * a.w + x]
            val l = ((p shr 16) and 0xFF) * 0.299 + ((p shr 8) and 0xFF) * 0.587 + (p and 0xFF) * 0.114
            n++; s += l; s2 += l * l
        }
        if (n == 0) return Pair(0f, 999f)
        val m = s / n
        return Pair(m.toFloat(), sqrt(max(0.0, s2 / n - m * m)).toFloat())
    }

    /** Bàn đã úp: 5 ô đầu đều trơn màu, sáng – tối xen kẽ (ô chẵn sáng hơn ô lẻ). */
    fun banUp(a: Anh, vung: IntArray = vungGame(a)): Boolean {
        val o = (0 until 5).map { sangO(a, vung, it) }
        if (o.any { it.second > 14f }) return false
        val chan = listOf(0, 2, 4).map { o[it].first }; val le = listOf(1, 3).map { o[it].first }
        return chan.min() > le.max() * 1.4f
    }

    /** Đọc 5 ô đầu hàng trên cùng (chỉ dùng khi không có bảng/hộp thoại che). */
    fun docHang(a: Anh, vung: IntArray = vungGame(a)): HangDau {
        val ct = (0 until 5).joinToString(" ") { sangO(a, vung, it).let { (m, d) -> "${m.toInt()}/${d.toInt()}" } } + " vùng ${vung.toList()}"
        if (banUp(a, vung)) return HangDau(List(5) { O.UP }).also { it.chiTiet = ct }
        val o = ArrayList<O>(); val diem = ArrayList<Float>()
        for (i in 0 until 5) {
            val (red, warm, cool, light) = mauO(a, vung, i).let { listOf(it[0], it[1], it[2], it[3]) }
            val loai = when {
                (warm >= 0.7f && red < 0.1f) || (red >= 0.85f && warm < 0.12f && light < 0.05f) -> O.UP
                red in 0.5f..0.9f && warm >= 0.08f && cool < 0.08f && light < 0.1f -> {
                    val h = hinhChu(vungChu(a, vung, i))
                    val t = h?.let { ncc(it, MAU_TUONG) } ?: 0f
                    val s = h?.let { ncc(it, MAU_SOAI) } ?: 0f
                    diem += max(t, s)
                    when {
                        t >= NGUONG_CHU && t >= s -> O.TUONG
                        s >= NGUONG_CHU -> O.SOAI
                        else -> O.CO
                    }
                }
                else -> O.KHAC
            }
            o += loai
        }
        return HangDau(o).also { it.diem = diem; it.chiTiet = ct }
    }
}
