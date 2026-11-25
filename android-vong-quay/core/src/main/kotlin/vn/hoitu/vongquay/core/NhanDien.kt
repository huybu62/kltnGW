package vn.hoitu.vongquay.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/** 3 món hạn định thật. */
enum class Loai(val ten: String) {
    PHIEU_HUY_DIET("Phiếu Hủy Diệt"),
    DA_VAN_MENH("Đá vận mệnh"),
    TUONG("Tướng hạn định"),
}

/** Mẫu một món: phần thân ô (ảnh xám) + biểu đồ màu. */
class MauMon(anh: Anh) {
    val xam: FloatArray
    val mau: FloatArray

    init {
        val o = anh.doiCo(NhanDien.O_W, NhanDien.O_H)
        xam = o.cat(15, 20, 95, 94).xam()
        mau = o.cat(18, 22, 92, 92).bieuDoMau()
    }
}

/** Vị trí vòng quay trên màn hình: gốc vùng game (gx, gy) và tỉ lệ k so với ảnh gốc rộng 2000. */
data class Neo(val gx: Float, val gy: Float, val k: Float) {
    fun ra(x: Float, y: Float) = Pair(gx + x * k, gy + y * k)
}

/**
 * Nhận diện màn "Vòng quay liên server". Toạ độ tính theo vùng game rộng 2000 × cao 1125
 * (đo trên ảnh chụp thật của người chơi).
 */
object NhanDien {
    const val REF_W = 2000f
    const val O_W = 110
    const val O_H = 114

    // mẫu nút "Khởi động-1 lần" (không bị app khác che) để nhận ra màn vòng quay
    val X1 = Pair(684f, 920f)
    val NUT_X10 = Pair(1163f, 962f)
    val NUT_TAO_MOI = Pair(996f, 582f)
    val CHO_TRONG = Pair(1375f, 1080f) // chỗ trống (giữa nút x10 và Danh sách quà, sát mép dưới): tắt danh sách quà, bỏ hoạt ảnh quay
    val O = linkedMapOf(
        "trên-trái" to Pair(876f, 360f), "trên-phải" to Pair(1022f, 360f),
        "trái-trên" to Pair(762f, 477f), "phải-trên" to Pair(1135f, 477f),
        "trái-dưới" to Pair(762f, 617f), "phải-dưới" to Pair(1135f, 617f),
        "dưới-trái" to Pair(876f, 734f), "dưới-phải" to Pair(1022f, 734f),
    )

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

    /** Có phải màn vòng quay không (thấy nút "Khởi động-1 lần" đúng chỗ, không bị làm tối)? */
    fun timVong(a: Anh, mauX1: Anh): Neo? {
        val v = vungGame(a)
        val k = v[2] / REF_W
        val f = 0.4f / k // làm việc ở cỡ 0.4 ảnh gốc cho nhanh
        val tw = (mauX1.w * 0.4f).roundToInt(); val th = (mauX1.h * 0.4f).roundToInt()
        val t = mauX1.doiCo(tw, th).xam()
        val r = 40f * k // tìm lệch tối đa 40 điểm ảnh gốc
        val ex = v[0] + X1.first * k; val ey = v[1] + X1.second * k
        val x0 = (ex - r).toInt(); val y0 = (ey - r).toInt()
        val vung = a.cat(x0, y0, (ex + mauX1.w * k + r).toInt(), (ey + mauX1.h * k + r).toInt())
        val nw = max(tw + 1, (vung.w * f).roundToInt()); val nh = max(th + 1, (vung.h * f).roundToInt())
        val nho = vung.doiCo(nw, nh)
        val (diem, mx, my) = Anh.timMau(nho.xam(), nw, nh, t, tw, th)
        if (diem < 0.8f) return null
        // nút bị làm tối (có bảng phủ lên) thì không tính
        val o = nho.cat(mx, my, mx + tw, my + th).xam()
        if (Anh.lech(Anh.trungBinh(o), Anh.trungBinh(t)) > 35f) return null
        // sửa lệch nhỏ theo chỗ tìm thấy
        val thayX = x0 + mx / f; val thayY = y0 + my / f
        return Neo(v[0] + (thayX - ex), v[1] + (thayY - ey), k)
    }

    /** Toạ độ màn hình của chỗ trống để tắt danh sách quà (khi không thấy vòng quay). */
    fun choTrong(a: Anh): Pair<Float, Float> {
        val v = vungGame(a)
        val k = v[2] / REF_W
        return Pair(v[0] + CHO_TRONG.first * k, v[1] + CHO_TRONG.second * k)
    }

    data class KetQuaO(val ten: String, val loai: Loai?, val giongMau: Float, val giongHinh: Float)

    /** Món thật (nếu có) ở từng ô trên vòng quay. */
    fun monTrenVong(a: Anh, neo: Neo, mau: Map<Loai, MauMon>): List<KetQuaO> = O.keys.map { ten ->
        val m = MauMon(catO(a, neo, ten))
        var tot: Loai? = null; var dm = 0f; var dh = 0f; var tong = -9f
        for ((loai, mm) in mau) {
            val gm = Anh.giongMau(m.mau, mm.mau)
            val gh = Anh.tuongQuan(m.xam, mm.xam)
            if (gm >= 0.65f && gh >= 0.25f && gm + gh > tong) { tong = gm + gh; tot = loai; dm = gm; dh = gh }
        }
        KetQuaO(ten, tot, dm, dh)
    }

    /** Vùng số "Điểm hiện tại" (chỉ tăng khi quay thật) – dùng để biết lần bấm x10 đã ăn chưa. */
    val VUNG_DIEM = floatArrayOf(450f, 700f, 680f, 760f)

    fun vungDiem(a: Anh, neo: Neo): FloatArray {
        val (x0, y0) = neo.ra(VUNG_DIEM[0], VUNG_DIEM[1])
        val (x1, y1) = neo.ra(VUNG_DIEM[2], VUNG_DIEM[3])
        return a.cat(x0.toInt(), y0.toInt(), x1.toInt(), y1.toInt()).doiCo(90, 20).xam()
    }

    /** Số điểm đã đổi chưa (so số điểm ảnh khác hẳn nhau; 1 chữ số đổi ≈ 20–60 điểm ảnh). */
    fun diemKhac(a: FloatArray, b: FloatArray): Boolean = a.indices.count { kotlin.math.abs(a[it] - b[it]) > 50f } >= 8

    /** Cắt ảnh một ô (cũng dùng để người chơi chọn làm mẫu). */
    fun catO(a: Anh, neo: Neo, ten: String): Anh {
        val (x, y) = O.getValue(ten)
        val (sx, sy) = neo.ra(x, y)
        return a.cat(sx.toInt(), sy.toInt(), (sx + O_W * neo.k).toInt(), (sy + O_H * neo.k).toInt())
    }
}
