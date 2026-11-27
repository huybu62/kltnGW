package vn.hoitu.canquet.core

import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.VanBan
import kotlin.math.abs
import kotlin.math.roundToInt

/** Cài đặt Càn quét. */
data class CaiDatCQ(
    var kieu: Int = 10, // 1, 5 hoặc 10: dùng nút x5 / x10 khi có (không có thì quét lẻ)
    var quaAi: Boolean = true, // quét xong bản đồ thì tự sang ải kế (1 → 4) rồi sang nước sau
    var nguoc: Boolean = false, // đi ngược: ải 4 → 1, nước sau → nước trước
    var thamHiem: Boolean = false, // khu chưa mở càn quét: tự Thám hiểm (đánh) rồi quét
    var dungSau: Int = 0, // dừng sau N lần càn quét (0 = không giới hạn)
    var chiPhi: Int = 4, // thể lực mỗi lần quét
    var nhipMs: Int = 150, // nhịp bấm "Càn quét lần nữa"
    var ngay: String = "", // ngày của danh sách ải đã xong
    var xong: MutableSet<String> = mutableSetOf(), // ải đã quét xong hôm nay ("Nước N")
    var khuAi: MutableMap<String, MutableSet<String>> = mutableMapOf(), // dữ liệu ải: "Nước N" → tên các khu đã dò được
)

/** Những gì Càn quét cần từ điện thoại. */
interface ThietBiCQ {
    fun nhin(): ManCQ? // chụp + đọc chữ (chậm)
    fun anh(): Anh? // chỉ chụp (nhanh)
    fun cham(x: Float, y: Float)
    fun vuot(x0: Float, y0: Float, x1: Float, y1: Float, ms: Long)
    fun quayLai()
    fun ngu(ms: Long)
    fun log(s: String)
    fun luu(cd: CaiDatCQ) {}
    fun homNay(): String = ""
}

private class DungCQ(msg: String) : Exception(msg)

/**
 * Càn quét bản đồ:
 * - Tìm toà nhà ngay trên màn đang thấy: chạm những chỗ nhiều chi tiết (không chạm vùng nút giao diện),
 *   chỉ coi là trúng khi bảng khu mở ra (đọc được "Số lần còn lại"). Không lưu toạ độ, không dùng mốc.
 * - Xem hết bản đồ bằng cách vuốt từng nửa màn; đo bản đồ dịch bao nhiêu (so ảnh) để không chạm lại chỗ cũ,
 *   tới mép thì thôi đi hướng đó. Không kéo về góc bản đồ.
 * - Mỗi khu: quét x10 / x5 (Quét lại liên tục) hoặc quét lẻ bấm "lần nữa" liên tục, tới khi hết lượt.
 * - Qua ải: xong bản đồ thì Trở lại → ải kế → nước sau.
 */
class CanQuet(private val tb: ThietBiCQ, private val cd: CaiDatCQ) {
    @Volatile var dung = false
    var soLan = 0; private set // tổng số lần đã càn quét
    var soKhu = 0; private set

    // trạng thái bản đồ đang quét
    private var camX = 0f; private var camY = 0f // vị trí camera so với lúc vào bản đồ (toạ độ chuẩn)
    private val daCham = ArrayList<Pair<Float, Float>>() // các điểm đã chạm (toạ độ bản đồ)
    private val khuViTri = HashMap<String, Pair<Float, Float>>()
    private val daXong = HashSet<String>()
    private val boiHong = HashSet<String>()
    private val thamHiemLan = HashMap<String, Int>()
    private var theLuc: Int? = null
    private var gioiHan = floatArrayOf(-1e9f, -1e9f, 1e9f, 1e9f) // camX min, camY min, camX max, camY max
    private var daBaoUocLuong = false

    companion object {
        const val BUOC_X = 1000f // vuốt nửa màn
        const val BUOC_Y = 560f
        // lưới chạm: toà nhà nhỏ nhất vẫn rộng hơn khoảng cách 2 điểm nên không sót
        val LUOI_X = (0 until 9).map { 200f + it * 190f }
        val LUOI_Y = (0 until 5).map { 230f + it * 150f }
        const val CHI_TIET_TOI_THIEU = 8f // chỉ bỏ chỗ phẳng hẳn (vùng đen ngoài bản đồ, nước)
        const val BK_X = 120f; const val BK_Y = 90f // quanh khu đã mở: không chạm lại
    }

    private fun ngu(ms: Long) { if (dung) throw DungCQ("đã dừng"); tb.ngu(ms) }

    private fun nhin(): ManCQ {
        repeat(20) {
            if (dung) throw DungCQ("đã dừng")
            tb.nhin()?.let { return it }
            ngu(200)
        }
        throw DungCQ("Không chụp được màn hình")
    }

    private fun cho(han: Long, buoc: Long = 300, dk: (ManCQ) -> Boolean): ManCQ? {
        var t = 0L
        while (t <= han) {
            val m = nhin()
            if (dk(m)) return m
            ngu(buoc); t += buoc
        }
        return null
    }

    private fun cham(m: ManCQ, ten: String): Boolean {
        val p = m.nut[ten] ?: return false
        tb.cham(p.first, p.second); return true
    }

    private fun chamRef(m: ManCQ, p: Pair<Float, Float>) { val (x, y) = m.ra(p.first, p.second); tb.cham(x, y) }

    private fun khoa(ten: String?) = VanBan.chuan(ten ?: "?")

    private fun duSoLan() = cd.dungSau > 0 && soLan >= cd.dungSau

    private fun conDuocQuet() = if (cd.dungSau > 0) cd.dungSau - soLan else Int.MAX_VALUE

    // ================= chung =================
    /** Đóng mọi bảng / màn kết quả / màn lạ để về bản đồ (hoặc màn chương). */
    private fun veBanDo(): ManCQ {
        var la = 0
        repeat(25) {
            val m = nhin()
            when (m.loai) {
                LoaiCQ.BAN_DO, LoaiCQ.CHUONG -> return m
                LoaiCQ.POPUP, LoaiCQ.KET_QUA, LoaiCQ.QUET_LAI -> if (!cham(m, "DONG")) tb.quayLai()
                LoaiCQ.HOI -> tb.quayLai() // không xác nhận gì tool không bấm
                LoaiCQ.TRAN -> danhTran()
                LoaiCQ.KHAC -> goManLa(m, la++)
            }
            ngu(700)
        }
        throw DungCQ("Không về được bản đồ")
    }

    /**
     * Màn lạ (lên cấp, thông báo...): bấm nút an toàn nếu có, không thì chạm mép trên.
     * KHÔNG bấm Quay lại của máy (bấm nhầm ở bản đồ / màn chương là thoát ra sảnh game).
     */
    private fun goManLa(m: ManCQ, lan: Int) {
        if (cham(m, "TIEP")) { tb.log("  Màn lạ → bấm nút an toàn"); return }
        chamRef(m, DocCQ.MEP_TREN)
        if (lan == 0) tb.log("  Màn lạ (lên cấp / thông báo?) → chạm mép trên")
        if (lan >= 10) throw DungCQ("Gặp màn lạ không thoát được (đang ở đâu? mở lại bản đồ / màn chương rồi chạy lại)")
    }

    /** Đánh trận thám hiểm: bấm Tiến lên, hết trận bấm nút an toàn, về bản đồ / bảng khu thì thôi. */
    private fun danhTran() {
        var t = 0L
        var la = 0
        while (t < 600_000) {
            val m = nhin()
            when (m.loai) {
                LoaiCQ.TRAN -> if (!cham(m, "TIEN_LEN")) Unit
                LoaiCQ.BAN_DO, LoaiCQ.POPUP, LoaiCQ.CHUONG -> return
                LoaiCQ.KHAC -> goManLa(m, la++)
                else -> return
            }
            ngu(1000); t += 1000
        }
        tb.log("  Đánh quá lâu → bỏ")
    }

    // ================= ảnh =================
    private class Khung(val g: Triple<FloatArray, Int, Int>, val gx: Float, val gy: Float, val k: Float) {
        fun ra(x: Float, y: Float) = Pair(gx + x * k, gy + y * k)
    }

    private fun khung(): Khung? {
        val a = tb.anh() ?: return null
        val v = DocCQ.vungGame(a.w, a.h)
        return Khung(DocCQ.xamNho(a), v[0].toFloat(), v[1].toFloat(), v[2] / DocCQ.REF_W)
    }

    private fun khacNhieu(a: Khung, b: Khung): Boolean {
        val sa = DocCQ.doSang(a.g); val sb = DocCQ.doSang(b.g)
        if (sb < sa * 0.82f) return true // màn tối đi: bảng mở
        var d = 0.0; var n = 0
        val (pa, w, h) = a.g; val pb = b.g.first
        for (y in h / 5 until h * 4 / 5 step 2) for (x in w / 6 until w * 5 / 6 step 2) { d += abs(pa[y * w + x] - pb[y * w + x]); n++ }
        return d / maxOf(1, n) > 22.0
    }

    /** Sau khi đổi màn (đóng bảng...), đo camera có bị dời không (game có thể kéo theo nhân vật). */
    private fun doLaiCamera(truoc: Khung?) {
        val sau = khung() ?: return
        if (truoc == null) return
        val d = DocCQ.doLech(truoc.g, sau.g, goiY = Pair(0f, 0f)) ?: return
        if (abs(d.first) > 12f || abs(d.second) > 12f) { camX -= d.first; camY -= d.second }
    }

    // tỉ lệ bản đồ dịch / ngón tay (game có thể kéo nhanh hay chậm hơn ngón tay): tự học từ các lần vuốt
    private val mauTiLe = ArrayList<Float>()
    // vuốt bị mép chặn chỉ làm tỉ lệ đo được nhỏ đi → lấy giá trị lớn (lớn thứ 2 khi đủ mẫu, phòng đo sai)
    private fun tiLeKeo(): Float? = when {
        mauTiLe.isEmpty() -> null
        mauTiLe.size < 3 -> mauTiLe.max()
        else -> mauTiLe.sortedDescending()[1]
    }

    /** Vuốt để camera dời (dx, dy) toạ độ chuẩn (dương = sang phải / xuống). Trả về độ dời thật, null nếu không chụp được. */
    private fun dichCamera(dx: Float, dy: Float): Pair<Float, Float>? {
        val truoc = khung() ?: return null
        val tl = tiLeKeo()
        // ngón tay đi ngược hướng camera; đã biết tỉ lệ kéo thì vuốt đúng khoảng cần đi
        // bản đồ chỉ nên chạy tối đa nửa màn mỗi lần (còn đủ phần trùng để đo); chưa biết tỉ lệ thì vuốt ngắn
        val fx = if (tl == null) dx.coerceIn(-600f, 600f) else (dx.coerceIn(-BUOC_X, BUOC_X) / tl).coerceIn(-1200f, 1200f)
        val fy = if (tl == null) dy.coerceIn(-340f, 340f) else (dy.coerceIn(-BUOC_Y, BUOC_Y) / tl).coerceIn(-680f, 680f)
        val (x0, y0) = truoc.ra(1000f + fx / 2, 500f + fy / 2)
        val (x1, y1) = truoc.ra(1000f - fx / 2, 500f - fy / 2)
        tb.vuot(x0, y0, x1, y1, 700)
        // chờ bản đồ đứng yên (có thể trôi)
        var cu = khung() ?: return null
        for (lan in 0 until 6) {
            ngu(200)
            val moi = khung() ?: return null
            val d = DocCQ.doLech(cu.g, moi.g, goiY = Pair(0f, 0f))
            cu = moi
            if (d == null || (abs(d.first) < 9f && abs(d.second) < 9f)) break
        }
        // đo: chưa biết tỉ lệ kéo thì đo thô cả ảnh; biết rồi thì dò quanh độ dịch dự đoán (kết quả sát rìa khoảng dò là đáng ngờ → đo thô)
        val goiY = tl?.let { Pair(-fx * it, -fy * it) }
        val goiY0 = goiY ?: Pair(-fx, -fy)
        var d = goiY?.let { g -> DocCQ.doLech(truoc.g, cu.g, goiY = g, chiQuanh = true) } // đi đủ như dự đoán
            ?: DocCQ.doLech(truoc.g, cu.g, goiY = goiY0) // từ 0 tới dự đoán: bị mép chặn một phần
            ?: DocCQ.doLechTho(truoc.g, cu.g) // đo thô cả ảnh (tỉ lệ kéo khác hẳn...)
            ?: DocCQ.doLech(truoc.g, cu.g, goiY = Pair(0f, 0f), chiQuanh = true) // bị mép chặn hẳn
        if (d == null) {
            d = if (DocCQ.giongHet(truoc.g, cu.g)) Pair(0f, 0f)
            else {
                if (!daBaoUocLuong) { tb.log("  · Không đo chính xác được bản đồ dịch → ước lượng theo cú vuốt"); daBaoUocLuong = true }
                Pair(-fx * (tl ?: 1f), -fy * (tl ?: 1f))
            }
        } else {
            // học tỉ lệ kéo từ những lần vuốt đủ dài và không bị mép chặn
            if (abs(fx) > 300f) (-d.first / fx).takeIf { it in 0.3f..3f }?.let { mauTiLe += it }
            if (abs(fy) > 200f) (-d.second / fy).takeIf { it in 0.3f..3f }?.let { mauTiLe += it }
            if (mauTiLe.size > 15) mauTiLe.removeAt(0)
        }
        camX -= d.first; camY -= d.second
        return Pair(-d.first, -d.second)
    }

    // ================= bản đồ =================
    private fun datLaiBanDo() {
        camX = 0f; camY = 0f
        daCham.clear(); khuViTri.clear(); daXong.clear(); boiHong.clear(); thamHiemLan.clear()
        gioiHan = floatArrayOf(-1e9f, -1e9f, 1e9f, 1e9f)
    }

    private fun capNhatTheLuc(m: ManCQ) {
        if (m.loai != LoaiCQ.BAN_DO) return
        m.theLuc?.let { theLuc = it }
        val tl = theLuc
        if (tl != null && tl < cd.chiPhi) {
            // đọc lại cho chắc (lúc màn đang chuyển có thể đọc sai)
            ngu(1200)
            val m2 = nhin()
            if (m2.loai == LoaiCQ.BAN_DO && (m2.theLuc ?: tl) < cd.chiPhi) throw DungCQ("Hết thể lực (còn ${m2.theLuc ?: tl}) → dừng")
            theLuc = m2.theLuc
        }
    }

    /** Quét hết bản đồ đang mở. [key]: "Nước N" (đi qua ải) để dùng / lưu dữ liệu khu của ải. */
    private fun quetBanDo(key: String? = null) {
        datLaiBanDo()
        val biet = key?.let { cd.khuAi[it] }?.takeIf { it.isNotEmpty() }
        fun duKhuBiet() = biet != null && biet.all { it in daXong }
        var m = veBanDo()
        if (m.loai != LoaiCQ.BAN_DO) return
        capNhatTheLuc(m)
        tb.log("🗺 Quét bản đồ (thể lực ${theLuc ?: "?"})" + if (biet != null) " – ải đã có dữ liệu: ${biet.size} khu" else if (key != null) " – ải chưa có dữ liệu: dò cả bản đồ" else "")
        // các vị trí camera đã xem; ô kế bên → đích (đặt ngay mép nếu đã biết mép), chỉ bỏ khi chỗ đó đã xem rồi
        val daXem = ArrayList<Pair<Float, Float>>()
        val khongToi = ArrayList<Pair<Float, Float>>()
        fun dich(i: Int, j: Int) = Pair((i * BUOC_X).coerceIn(gioiHan[0], gioiHan[2]), (j * BUOC_Y).coerceIn(gioiHan[1], gioiHan[3]))
        fun gan(a: Pair<Float, Float>, b: Pair<Float, Float>) = abs(a.first - b.first) < BUOC_X * 0.2f && abs(a.second - b.second) < BUOC_Y * 0.2f
        daXem += Pair(camX, camY)
        lamManHinh()
        var lan = 0
        var hetBanDo = false
        while (!dung && lan++ < 40) {
            if (duSoLan()) return
            if (duKhuBiet()) { tb.log("  Đã quét đủ ${biet!!.size} khu đã biết của ải"); break }
            val o = daXem.map { Pair((it.first / BUOC_X).roundToInt(), (it.second / BUOC_Y).roundToInt()) }.toSet()
            val dichDen = o.flatMap { (i, j) -> listOf(Pair(i + 1, j), Pair(i - 1, j), Pair(i, j + 1), Pair(i, j - 1)) }
                .map { dich(it.first, it.second) }.distinct()
                .filter { t -> daXem.none { gan(it, t) } && khongToi.none { gan(it, t) } }
                .minByOrNull { abs(it.first - camX) / BUOC_X + abs(it.second - camY) / BUOC_Y } ?: run { hetBanDo = true; null } ?: break
            if (!toiO(dichDen.first, dichDen.second)) { khongToi += dichDen; continue }
            if (daXem.any { gan(it, Pair(camX, camY)) }) { khongToi += dichDen; continue } // bị chặn, vẫn ở chỗ đã xem
            daXem += Pair(camX, camY)
            tb.log("  · Xem vùng camera ${camX.toInt()}, ${camY.toInt()}")
            lamManHinh()
        }
        if (key != null && hetBanDo && khuViTri.isNotEmpty()) {
            // dò hết bản đồ: lưu tên các khu (lần sau quét xong các khu này là sang ải kế, khỏi dò lại)
            cd.khuAi[key] = khuViTri.keys.toMutableSet()
            tb.luu(cd)
            tb.log("  Lưu dữ liệu ải $key: ${khuViTri.size} khu")
        }
        tb.log("✔ Xong bản đồ: ${daXong.size} khu, đã quét $soLan lần")
    }

    /** Ghi mép bản đồ; mâu thuẫn với mép đối diện (do đo sai trước đó) thì bỏ mép kia. */
    private fun datMep(i: Int, v: Float) {
        gioiHan[i] = v
        if (gioiHan[0] > gioiHan[2]) { if (i == 0) gioiHan[2] = 1e9f else gioiHan[0] = -1e9f }
        if (gioiHan[1] > gioiHan[3]) { if (i == 1) gioiHan[3] = 1e9f else gioiHan[1] = -1e9f }
    }

    /** Vuốt tới vị trí camera (tx, ty). false nếu bị chặn (mép bản đồ) trước khi tới. */
    private fun toiO(tx0: Float, ty0: Float): Boolean {
        val x0 = camX; val y0 = camY
        repeat(8) {
            // đã biết mép thì đích nằm ngay mép (để xem được cả dải sát mép bản đồ)
            val tx = tx0.coerceIn(gioiHan[0], gioiHan[2]); val ty = ty0.coerceIn(gioiHan[1], gioiHan[3])
            val dx = tx - camX; val dy = ty - camY
            if (abs(dx) < BUOC_X * 0.12f && abs(dy) < BUOC_Y * 0.12f) return true
            val dxx = if (abs(dx) >= BUOC_X * 0.12f) dx else 0f
            val dyy = if (abs(dy) >= BUOC_Y * 0.12f) dy else 0f
            val d = dichCamera(dxx, dyy)
            if (d == null) {
                // không đo được: về bản đồ cho chắc, coi như ô này không tới được
                tb.log("  · Không đo được bản đồ dịch bao nhiêu")
                veBanDo(); return false
            }
            // trục nào đi được quá ít → mép bản đồ phía đó
            var chan = false
            if (dxx != 0f && abs(d.first) < abs(dxx) * 0.25f) {
                datMep(if (dxx > 0) 2 else 0, camX)
                chan = true
            }
            if (dyy != 0f && abs(d.second) < abs(dyy) * 0.25f) {
                datMep(if (dyy > 0) 3 else 1, camY)
                chan = true
            }
            if (chan) {
                tb.log("  · Tới mép bản đồ (camera ${camX.toInt()}, ${camY.toInt()})")
                // vừa dời được một đoạn đáng kể thì màn này (sát mép) vẫn đáng xem
                return abs(camX - x0) > 150f || abs(camY - y0) > 120f
            }
        }
        return abs(tx0.coerceIn(gioiHan[0], gioiHan[2]) - camX) < BUOC_X * 0.5f && abs(ty0.coerceIn(gioiHan[1], gioiHan[3]) - camY) < BUOC_Y * 0.5f
    }

    /** Chạm các điểm nhiều chi tiết trên màn đang thấy (chưa chạm), mở được khu nào thì quét khu đó. */
    private fun lamManHinh() {
        val k0 = khung() ?: return
        // điểm lưới (toạ độ bản đồ), bỏ vùng cấm, bỏ chỗ đã chạm / gần khu đã biết, bỏ chỗ phẳng (đường, cỏ, vùng đen)
        val diem = ArrayList<Triple<Float, Float, Float>>()
        for (y in LUOI_Y) for (x in LUOI_X) {
            if (DocCQ.trongVungCam(x, y)) continue
            val ax = camX + x; val ay = camY + y
            if (daCham.any { abs(it.first - ax) < 95f && abs(it.second - ay) < 75f }) continue
            if (khuViTri.values.any { abs(it.first - ax) < BK_X && abs(it.second - ay) < BK_Y }) continue
            val ct = DocCQ.doChiTiet(k0.g, x, y)
            if (ct < CHI_TIET_TOI_THIEU) { daCham += Pair(ax, ay); continue }
            diem += Triple(ax, ay, ct)
        }
        for ((ax, ay, _) in diem.sortedByDescending { it.third }) {
            if (dung || duSoLan()) return
            // điểm có thể đã bị bỏ qua vì vừa mở một khu gần đó
            if (khuViTri.values.any { abs(it.first - ax) < BK_X && abs(it.second - ay) < BK_Y }) continue
            val sx = ax - camX; val sy = ay - camY
            if (DocCQ.trongVungCam(sx, sy) || sx < 60f || sx > 1940f || sy < 60f || sy > 1060f) continue
            daCham += Pair(ax, ay)
            val truoc = khung() ?: return
            val (x, y) = truoc.ra(sx, sy)
            tb.cham(x, y)
            val m = choSauCham(truoc) ?: continue
            when (m.loai) {
                LoaiCQ.POPUP -> {
                    var mk: ManCQ? = m
                    var lanMo = 0
                    while (mk != null && mk.loai == LoaiCQ.POPUP && lanMo++ < 6) {
                        val tenK = khoa(mk.ten)
                        if (tenK !in khuViTri) khuViTri[tenK] = Pair(ax, ay)
                        xuLyKhu(mk)
                        val v = veBanDo()
                        if (v.loai != LoaiCQ.BAN_DO) return
                        capNhatTheLuc(v)
                        doLaiCamera(truoc)
                        if (tenK in daXong || duSoLan() || dung) break
                        // khu còn lượt (game đóng bảng giữa chừng / vừa thám hiểm xong): chạm lại toà nhà để quét tiếp
                        val kk = khung() ?: return
                        val p = khuViTri[tenK] ?: Pair(ax, ay)
                        val sx2 = p.first - camX; val sy2 = p.second - camY
                        if (DocCQ.trongVungCam(sx2, sy2) || sx2 < 60f || sx2 > 1940f || sy2 < 60f || sy2 > 1060f) break
                        tb.log("  Mở lại ${mk.ten ?: "khu"} để quét tiếp")
                        val (x2, y2) = kk.ra(sx2, sy2)
                        tb.cham(x2, y2)
                        mk = choSauCham(kk)
                    }
                    if (mk != null && mk.loai != LoaiCQ.POPUP) veBanDo()
                }
                LoaiCQ.CHUONG -> return
                else -> veBanDo()
            }
        }
    }

    /** Sau khi chạm: có gì mở ra không (so ảnh nhanh, có thay đổi mới đọc chữ). null: không có gì. */
    private fun choSauCham(truoc: Khung): ManCQ? {
        ngu(250)
        repeat(4) {
            val sau = khung() ?: return null
            if (khacNhieu(truoc, sau)) {
                ngu(250)
                val m = nhin()
                return if (m.loai == LoaiCQ.BAN_DO) null else m
            }
            ngu(150)
        }
        return null
    }

    // ================= một khu =================
    /** Quét một khu tới khi hết lượt. true nếu vừa thám hiểm (cần mở lại khu để quét). */
    private fun xuLyKhu(dau: ManCQ): Boolean {
        var m = dau
        val ten = khoa(m.ten)
        if (ten in daXong) { cham(m, "DONG"); ngu(500); return false }
        var lan = 0
        while (!dung && lan++ < 30) {
            if (m.loai != LoaiCQ.POPUP) return false
            if (lan == 1 || m.conLai != null) tb.log("• Khu ${m.ten ?: "?"} (còn ${m.conLai ?: "?"} lượt)")
            if (duSoLan()) { cham(m, "DONG"); return false }
            if (m.conLai == 0) { danhDauXong(ten, m.ten); cham(m, "DONG"); return false }
            if (!m.nut.containsKey("CAN_QUET")) {
                val th = thamHiemLan[ten] ?: 0
                if (cd.thamHiem && m.nut.containsKey("THAM_HIEM") && th < 2) {
                    thamHiemLan[ten] = th + 1
                    tb.log("  Chưa mở càn quét → Thám hiểm ${m.ten}")
                    cham(m, "THAM_HIEM"); ngu(1500)
                    danhTran()
                    return true
                }
                tb.log("  ${m.ten}: chưa mở càn quét → bỏ qua")
                danhDauXong(ten, m.ten); cham(m, "DONG"); return false
            }
            val n = cd.kieu
            val dungBoi = n > 1 && ten !in boiHong && m.nut.containsKey("X$n") &&
                (m.conLai ?: n) >= n && conDuocQuet() >= n && (theLuc ?: Int.MAX_VALUE) >= n * cd.chiPhi
            if (dungBoi) quetBoi(m, n, ten) else quetLe(m, ten)
            if (ten in daXong || duSoLan()) { veBanDo(); return false }
            m = cho(3000) { it.loai == LoaiCQ.POPUP || it.loai == LoaiCQ.BAN_DO } ?: return false
            if (m.loai == LoaiCQ.BAN_DO) {
                capNhatTheLuc(m)
                // về bản đồ mà khu chưa hết lượt: mở lại ở vòng ngoài (chạm lại toà nhà) – thường do game đóng bảng
                return false
            }
        }
        return false
    }

    private fun danhDauXong(ten: String, tenHien: String?) {
        if (daXong.add(ten)) { soKhu++; tb.log("  ✔ ${tenHien ?: "Khu"}: xong") }
    }

    /** x5 / x10: bấm xN → bảng hỏi đúng là càn quét → Xác định; rồi "Quét lại" liên tục khi còn đủ lượt. */
    private fun quetBoi(p: ManCQ, n: Int, ten: String) {
        tb.log("  Càn quét x$n")
        cham(p, "X$n")
        var m = cho(4000) { it.loai == LoaiCQ.HOI || it.loai == LoaiCQ.QUET_LAI || it.loai == LoaiCQ.KET_QUA }
        var lan = 0
        while (!dung && m != null && lan++ < 40) {
            when (m.loai) {
                LoaiCQ.HOI -> {
                    if (!m.hoiCanQuet || m.hoiSo != n) {
                        tb.log("  Bảng hỏi không phải càn quét x$n → huỷ, khu này quét lẻ")
                        tb.quayLai(); boiHong += ten; ngu(800); return
                    }
                    cham(m, "XAC_DINH")
                    soLan += n
                    theLuc = theLuc?.let { it - n * cd.chiPhi }
                    tb.log("  ✓ x$n – tổng $soLan lần")
                    m = cho(4000) { it.loai == LoaiCQ.QUET_LAI || it.loai == LoaiCQ.POPUP || it.loai == LoaiCQ.KET_QUA || it.loai == LoaiCQ.BAN_DO || it.loai == LoaiCQ.HOI }
                }
                LoaiCQ.QUET_LAI -> {
                    val con = m.conLai
                    if (con == 0) { danhDauXong(ten, null) }
                    val duTL = (theLuc ?: Int.MAX_VALUE) >= n * cd.chiPhi
                    if (con != null && con >= n && conDuocQuet() >= n && duTL && !duSoLan()) {
                        cham(m, "QUET_LAI")
                        m = cho(4000) { it.loai == LoaiCQ.HOI }
                        if (m == null) { tb.log("  'Quét lại' không ra bảng hỏi → quét lẻ"); boiHong += ten; return }
                    } else {
                        if (!cham(m, "DONG")) tb.quayLai()
                        ngu(800); return
                    }
                }
                LoaiCQ.KET_QUA -> { if (!cham(m, "DONG")) tb.quayLai(); ngu(800); return }
                else -> return
            }
        }
        if (m == null) { tb.log("  x$n không ra bảng hỏi → khu này quét lẻ"); boiHong += ten }
    }

    /** Quét lẻ: bấm Càn quét, rồi bấm "Càn quét lần nữa" liên tục (luồng bấm riêng), đếm theo "Số lần" giảm. */
    private fun quetLe(p: ManCQ, ten: String) {
        cham(p, "CAN_QUET")
        val kq = cho(4000) { it.loai == LoaiCQ.KET_QUA || it.loai == LoaiCQ.HOI || it.loai == LoaiCQ.KHAC }
        if (kq == null) { tb.log("  Bấm Càn quét không ra kết quả → bỏ khu"); danhDauXong(ten, null); return }
        if (kq.loai != LoaiCQ.KET_QUA) {
            // bảng hỏi mua thể lực / màn lạ: không mua, huỷ rồi dừng
            tb.quayLai(); ngu(800)
            throw DungCQ("Không quét được (hết thể lực? game hỏi mua) → dừng")
        }
        soLan++
        theLuc = theLuc?.let { it - cd.chiPhi }
        var con = kq.conLai
        if (con == 0) { danhDauXong(ten, null); cham(kq, "DONG"); return }
        val nut = kq.nut["LAN_NUA"] ?: run { cham(kq, "DONG"); return }
        // luồng bấm "lần nữa" liên tục; luồng chính đọc "Số lần" để đếm và biết khi nào dừng
        val gioiHanBam = minOf(conDuocQuet(), con ?: Int.MAX_VALUE, theLuc?.let { it / cd.chiPhi } ?: Int.MAX_VALUE)
        val bam = MayBam(tb, nut.first, nut.second, cd.nhipMs.toLong(), gioiHanBam)
        bam.start()
        try {
            var doiCuoi = System.nanoTime()
            var khongThay = 0
            var docKhongDoi = 0 // số lần đọc được "Số lần" mà không đổi
            while (!dung) {
                ngu(450)
                val m = tb.nhin() ?: continue
                if (m.loai == LoaiCQ.KET_QUA) {
                    khongThay = 0
                    val c = m.conLai
                    if (c != null && con != null && c < con && con - c <= 60) {
                        soLan += con - c; theLuc = theLuc?.let { it - (con!! - c) * cd.chiPhi }
                        doiCuoi = System.nanoTime(); docKhongDoi = 0
                    } else if (c != null) docKhongDoi++
                    if (c != null) con = c
                    if (con == 0) { danhDauXong(ten, null); break }
                    if (duSoLan()) break
                    if (bam.xong && (System.nanoTime() - doiCuoi) / 1_000_000 > 1500) break
                    val lau = (System.nanoTime() - doiCuoi) / 1_000_000
                    if ((lau > 4000 && docKhongDoi >= 5) || lau > 15000) {
                        tb.log("  'Lần nữa' không còn tác dụng (hết thể lực?)")
                        theLuc = 0
                        break
                    }
                } else if (m.loai == LoaiCQ.HOI || m.loai == LoaiCQ.BAN_DO || m.loai == LoaiCQ.POPUP) {
                    break
                } else if (++khongThay > 8) break // hiệu ứng giữa các lần quét: bấm tiếp
            }
        } finally {
            bam.dung = true
            bam.join(2000)
        }
        tb.log("  Tổng $soLan lần" + (con?.let { " (khu còn $it)" } ?: ""))
        val m = nhin()
        if (m.loai == LoaiCQ.HOI) { tb.quayLai(); ngu(800) }
        else if (m.loai == LoaiCQ.KET_QUA) cham(m, "DONG")
        ngu(700)
        if (theLuc == 0) {
            val v = veBanDo()
            capNhatTheLuc(v)
        }
    }

    // ================= qua ải =================
    private fun veChuong(): ManCQ {
        repeat(15) {
            val m = veBanDo()
            if (m.loai == LoaiCQ.CHUONG) return m
            chamRef(m, DocCQ.TRO_LAI)
            cho(4000) { it.loai == LoaiCQ.CHUONG }?.let { return it }
        }
        throw DungCQ("Không về được màn chương")
    }

    private fun xongAi(key: String) {
        val hn = tb.homNay()
        if (cd.ngay != hn) { cd.ngay = hn; cd.xong.clear() }
        cd.xong += key
        tb.luu(cd)
    }

    private fun daXongAi(key: String): Boolean {
        if (cd.ngay != tb.homNay()) return false
        return key in cd.xong
    }

    /** Vào ải: chạm vào toà nhà phía trên nhãn (chạm chữ không vào), chưa vào thì chạm cao hơn / thấp hơn. */
    private fun vaoAi(m: ManCQ, ai: AiChuong): Boolean {
        for (cao in listOf(0.125f, 0.16f, 0.09f)) {
            val dy = cao * DocCQ.REF_H * m.k
            tb.cham(ai.x, maxOf(m.gy + 0.05f * DocCQ.REF_H * m.k, ai.y - dy))
            val v = cho(9000, 700) { it.loai == LoaiCQ.BAN_DO || (it.loai == LoaiCQ.KHAC && it.nut.isNotEmpty()) }
            if (v?.loai == LoaiCQ.BAN_DO) return true
            if (v?.loai == LoaiCQ.KHAC) { cham(v, "TIEP"); cho(6000, 700) { it.loai == LoaiCQ.BAN_DO }?.let { return true } }
        }
        return false
    }

    private fun quaAi() {
        val thatBai = HashMap<String, Int>()
        var docHong = 0
        while (!dung && !duSoLan()) {
            val m = veChuong()
            if (m.ai.isEmpty()) {
                if (++docHong >= 3) throw DungCQ("Không đọc được nhãn ải trên màn chương")
                ngu(1500); continue
            }
            docHong = 0
            val nuoc = m.nuoc ?: "?"
            val ds = if (cd.nguoc) m.ai.sortedByDescending { it.so } else m.ai
            val ai = ds.firstOrNull { !daXongAi("$nuoc ${it.so}") && (thatBai["$nuoc ${it.so}"] ?: 0) < 2 }
            if (ai == null) {
                // sang nước sau (hoặc trước khi đi ngược)
                chamRef(m, if (cd.nguoc) DocCQ.MUI_TEN_TRAI else DocCQ.MUI_TEN_PHAI)
                ngu(2500)
                val m2 = nhin()
                if (m2.loai != LoaiCQ.CHUONG || m2.nuoc == null || VanBan.chuan(m2.nuoc) == VanBan.chuan(nuoc)) {
                    tb.log("✔ Đã đi hết các ải các nước mở được"); return
                }
                tb.log("${if (cd.nguoc) "◀" else "▶"} Sang nước ${m2.nuoc}")
                continue
            }
            val key = "$nuoc ${ai.so}"
            tb.log("══ $nuoc – ải ${ai.so}: ${ai.chu} ══")
            if (!vaoAi(m, ai)) {
                thatBai[key] = (thatBai[key] ?: 0) + 1
                tb.log("  Không vào được ải $key (chưa mở?)")
                if (thatBai[key]!! >= 2) xongAi(key)
                continue
            }
            quetBanDo(key)
            xongAi(key)
        }
    }

    fun chay() {
        try {
            tb.log("▶ Càn quét: ${if (cd.kieu > 1) "x${cd.kieu}" else "lẻ"}${if (cd.quaAi) ", qua ải" else ""}${if (cd.thamHiem) ", thám hiểm" else ""}" +
                (if (cd.dungSau > 0) ", dừng sau ${cd.dungSau} lần" else ""))
            val m = veBanDo()
            if (m.loai == LoaiCQ.BAN_DO) quetBanDo()
            else if (!cd.quaAi) throw DungCQ("Đang ở màn chương: vào bản đồ một ải rồi bấm ▶ (hoặc bật Qua ải)")
            if (cd.quaAi && !duSoLan()) quaAi()
            if (duSoLan()) { veBanDo(); tb.log("✔ Đã quét đủ ${cd.dungSau} lần → dừng") }
        } catch (e: DungCQ) {
            tb.log(if (dung) "■ Đã dừng" else "⛔ ${e.message}")
        } finally {
            tb.log("Tổng: $soLan lần càn quét, $soKhu khu xong")
        }
    }
}

/** Luồng bấm một điểm đều nhịp (như auto click); luồng chính vẫn đọc màn song song. */
class MayBam(private val tb: ThietBiCQ, val x: Float, val y: Float, private val nhip: Long, private val toiDa: Int) : Thread() {
    @Volatile var dung = false
    @Volatile var daBam = 0; private set
    val xong get() = daBam >= toiDa

    init { isDaemon = true }

    override fun run() {
        try {
            while (!dung && daBam < toiDa) {
                tb.cham(x, y)
                daBam++
                sleep(nhip)
            }
        } catch (e: InterruptedException) { }
    }
}
