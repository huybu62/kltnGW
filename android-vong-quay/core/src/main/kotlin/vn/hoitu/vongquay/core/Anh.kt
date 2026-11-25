package vn.hoitu.vongquay.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Ảnh màu ARGB (không phụ thuộc Android để chạy thử được trên máy tính). */
class Anh(val w: Int, val h: Int, val px: IntArray) {
    init {
        require(px.size == w * h) { "kích thước ảnh sai" }
    }

    fun r(i: Int) = (px[i] shr 16) and 0xFF
    fun g(i: Int) = (px[i] shr 8) and 0xFF
    fun b(i: Int) = px[i] and 0xFF

    /** Cắt vùng [x0, x1) × [y0, y1), tự kẹp trong ảnh. */
    fun cat(x0: Int, y0: Int, x1: Int, y1: Int): Anh {
        val a = x0.coerceIn(0, w); val c = x1.coerceIn(a, w)
        val b = y0.coerceIn(0, h); val d = y1.coerceIn(b, h)
        val nw = max(1, c - a); val nh = max(1, d - b)
        val out = IntArray(nw * nh)
        for (y in 0 until nh) {
            val sy = min(h - 1, b + y)
            for (x in 0 until nw) out[y * nw + x] = px[sy * w + min(w - 1, a + x)]
        }
        return Anh(nw, nh, out)
    }

    /** Đổi cỡ: thu nhỏ thì lấy trung bình vùng (giống INTER_AREA), phóng to thì nội suy song tuyến. */
    fun doiCo(nw: Int, nh: Int): Anh {
        if (nw == w && nh == h) return this
        val out = IntArray(nw * nh)
        val fx = w.toDouble() / nw; val fy = h.toDouble() / nh
        if (fx >= 1.0 && fy >= 1.0) {
            for (y in 0 until nh) {
                val y0 = (y * fy).toInt(); val y1 = max(y0 + 1, min(h, ((y + 1) * fy).toInt()))
                for (x in 0 until nw) {
                    val x0 = (x * fx).toInt(); val x1 = max(x0 + 1, min(w, ((x + 1) * fx).toInt()))
                    var sr = 0; var sg = 0; var sb = 0; var n = 0
                    for (yy in y0 until y1) for (xx in x0 until x1) {
                        val p = px[yy * w + xx]
                        sr += (p shr 16) and 0xFF; sg += (p shr 8) and 0xFF; sb += p and 0xFF; n++
                    }
                    out[y * nw + x] = (0xFF shl 24) or ((sr / n) shl 16) or ((sg / n) shl 8) or (sb / n)
                }
            }
        } else {
            for (y in 0 until nh) {
                val sy = ((y + 0.5) * fy - 0.5).coerceIn(0.0, (h - 1).toDouble())
                val y0 = sy.toInt(); val y1 = min(h - 1, y0 + 1); val ty = sy - y0
                for (x in 0 until nw) {
                    val sx = ((x + 0.5) * fx - 0.5).coerceIn(0.0, (w - 1).toDouble())
                    val x0 = sx.toInt(); val x1 = min(w - 1, x0 + 1); val tx = sx - x0
                    var p = 0xFF shl 24
                    for (sh in intArrayOf(16, 8, 0)) {
                        fun k(i: Int) = ((px[i] shr sh) and 0xFF).toDouble()
                        val v = (k(y0 * w + x0) * (1 - tx) + k(y0 * w + x1) * tx) * (1 - ty) +
                            (k(y1 * w + x0) * (1 - tx) + k(y1 * w + x1) * tx) * ty
                        p = p or (v.toInt().coerceIn(0, 255) shl sh)
                    }
                    out[y * nw + x] = p
                }
            }
        }
        return Anh(nw, nh, out)
    }

    /** Ảnh xám (0..255) theo công thức độ sáng chuẩn. */
    fun xam(): FloatArray = FloatArray(w * h) { i -> (r(i) * 0.299f + g(i) * 0.587f + b(i) * 0.114f) }

    /** Tỉ lệ điểm ảnh không tối (có kênh > 25) theo hàng – dùng tìm viền đen. */
    fun sangTheoHang(buoc: Int = 4): FloatArray = FloatArray((h + buoc - 1) / buoc) { yy ->
        val y = yy * buoc; var sang = 0; var n = 0
        var x = 0
        while (x < w) { val i = y * w + x; if (max(r(i), max(g(i), b(i))) > 25) sang++; n++; x += buoc }
        sang.toFloat() / n
    }

    fun sangTheoCot(buoc: Int = 4): FloatArray = FloatArray((w + buoc - 1) / buoc) { xx ->
        val x = xx * buoc; var sang = 0; var n = 0
        var y = 0
        while (y < h) { val i = y * w + x; if (max(r(i), max(g(i), b(i))) > 25) sang++; n++; y += buoc }
        sang.toFloat() / n
    }

    /** Biểu đồ màu (Hue × Saturation) chuẩn hoá tổng = 1, bỏ điểm ảnh nhạt màu (S ≤ 60). */
    fun bieuDoMau(binH: Int = 30, binS: Int = 4): FloatArray {
        val hist = FloatArray(binH * binS)
        var tong = 0f
        for (i in 0 until w * h) {
            val hsv = hsv(r(i), g(i), b(i))
            if (hsv[1] <= 60) continue
            val bh = min(binH - 1, hsv[0] * binH / 180)
            val bs = min(binS - 1, (hsv[1] - 60) * binS / 196)
            hist[bh * binS + bs] += 1f; tong += 1f
        }
        if (tong > 0) for (k in hist.indices) hist[k] /= tong
        return hist
    }

    companion object {
        /** HSV kiểu OpenCV: H 0..179, S và V 0..255. */
        fun hsv(r: Int, g: Int, b: Int): IntArray {
            val mx = max(r, max(g, b)); val mn = min(r, min(g, b)); val d = mx - mn
            val s = if (mx == 0) 0 else 255 * d / mx
            var hh = when {
                d == 0 -> 0.0
                mx == r -> 60.0 * (g - b) / d
                mx == g -> 120.0 + 60.0 * (b - r) / d
                else -> 240.0 + 60.0 * (r - g) / d
            }
            if (hh < 0) hh += 360.0
            return intArrayOf((hh / 2).toInt().coerceIn(0, 179), s, mx)
        }

        /** Độ giống Bhattacharyya của 2 biểu đồ (1 = giống hệt), cùng cách tính như OpenCV. */
        fun giongMau(a: FloatArray, b: FloatArray): Float {
            var bc = 0.0
            for (i in a.indices) bc += sqrt((a[i] * b[i]).toDouble())
            return (1.0 - sqrt(max(0.0, 1.0 - bc))).toFloat()
        }

        /** Hệ số tương quan (NCC) giữa 2 mảng cùng cỡ. */
        fun tuongQuan(a: FloatArray, b: FloatArray): Float {
            val n = a.size
            var ma = 0.0; var mb = 0.0
            for (i in 0 until n) { ma += a[i]; mb += b[i] }
            ma /= n; mb /= n
            var sab = 0.0; var saa = 0.0; var sbb = 0.0
            for (i in 0 until n) {
                val da = a[i] - ma; val db = b[i] - mb
                sab += da * db; saa += da * da; sbb += db * db
            }
            val m = sqrt(saa * sbb)
            return if (m < 1e-6) 0f else (sab / m).toFloat()
        }

        /** Tìm mẫu t (tw×th) trong ảnh a (aw×ah), cả hai là ảnh xám. Trả về (điểm NCC cao nhất, x, y). */
        fun timMau(a: FloatArray, aw: Int, ah: Int, t: FloatArray, tw: Int, th: Int): Triple<Float, Int, Int> {
            if (tw > aw || th > ah) return Triple(-1f, 0, 0)
            val n = tw * th
            var mt = 0.0
            for (v in t) mt += v
            mt /= n
            val dt = DoubleArray(n) { t[it] - mt }
            var stt = 0.0
            for (v in dt) stt += v * v
            var tot = -2f; var bx = 0; var by = 0
            for (y in 0..(ah - th)) for (x in 0..(aw - tw)) {
                var ma = 0.0
                for (yy in 0 until th) { val o = (y + yy) * aw + x; for (xx in 0 until tw) ma += a[o + xx] }
                ma /= n
                var sab = 0.0; var saa = 0.0; var k = 0
                for (yy in 0 until th) {
                    val o = (y + yy) * aw + x
                    for (xx in 0 until tw) { val da = a[o + xx] - ma; sab += da * dt[k]; saa += da * da; k++ }
                }
                val m = sqrt(saa * stt)
                val d = if (m < 1e-6) 0f else (sab / m).toFloat()
                if (d > tot) { tot = d; bx = x; by = y }
            }
            return Triple(tot, bx, by)
        }

        fun trungBinh(a: FloatArray): Float { var s = 0.0; for (v in a) s += v; return (s / a.size).toFloat() }

        fun lech(a: Float, b: Float) = abs(a - b)
    }
}
