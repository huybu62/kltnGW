package vn.hoitu.vongquay.core

import kotlin.math.abs

/** Cài đặt (lưu lại giữa các lần chạy). */
data class CaiDat(
    var dem: Int = 0, // số lần đã bấm x10 kể từ lần ra hạn định gần nhất
    var moc: Int = 73, // lần bấm thứ "moc" chắc chắn ra hạn định
    var taoMoiToiDa: Int = 60, // số lần Tạo mới tối đa ở lượt mốc
    var dungSau: Int = 0, // dừng sau N lần bấm (0 = không giới hạn)
    var muon: MutableSet<Loai> = mutableSetOf(Loai.PHIEU_HUY_DIET, Loai.DA_VAN_MENH, Loai.TUONG),
    var nhip: Int = 80, // ms nghỉ giữa 2 lần chạm liên tục (càng nhỏ càng nhanh)
)

/** Những gì bộ điều khiển cần từ điện thoại (chụp màn hình, chạm...), để chạy thử được trên máy tính. */
interface ThietBi {
    fun chup(): Anh?
    fun cham(x: Float, y: Float)
    fun ngu(ms: Long)
    fun log(s: String)
    fun luu(cd: CaiDat)
}

/**
 * Vòng quay liên server: bấm "Khởi động 10 lần" liên tục, đếm số lần bấm.
 * Sau khi bấm, chạm chỗ trống liên tục (như auto click) để bỏ hoạt ảnh quay và tắt danh sách quà.
 * Lần bấm thứ [CaiDat.moc]: bấm "Tạo mới" tới khi vòng quay có món người chơi muốn, rồi bấm → về 0.
 * Chỉ bấm 3 chỗ: Khởi động 10 lần, Tạo mới, chỗ trống.
 */
class VongQuay(
    private val tb: ThietBi,
    private val cd: CaiDat,
    private val mauX1: Anh,
    private val mau: Map<Loai, MauMon>,
    private val choKetQuaMs: Long = 5000,
    private val choManMs: Long = 60000,
    private val choTaoMoiMs: Long = 3000,
) {
    @Volatile var dung = false
    var daBam = 0
        private set

    private val nhip get() = cd.nhip.coerceIn(20, 1000).toLong()

    private fun ngu(ms: Long) { if (!dung) tb.ngu(ms) }

    private fun chamTrong(a: Anh) { val (x, y) = NhanDien.choTrong(a); tb.cham(x, y) }

    /** Độ sáng trung bình (để nhận ra danh sách quà làm tối màn hình). */
    private fun sang(a: Anh): Float = Anh.trungBinh(a.doiCo(64, 36).xam())

    /** Chờ tới khi thấy màn vòng quay; nếu [chamTat] thì chạm chỗ trống liên tục trong lúc chờ (tắt danh sách quà). */
    private fun choVong(chamTat: Boolean, han: Long = choManMs): Pair<Anh, Neo>? {
        var t = 0L
        while (!dung && t < han) {
            val a = tb.chup()
            if (a != null) {
                val neo = NhanDien.timVong(a, mauX1)
                if (neo != null) return Pair(a, neo)
                if (chamTat) chamTrong(a)
            }
            ngu(nhip); t += nhip
        }
        return null
    }

    /**
     * Sau khi bấm x10: chạm chỗ trống liên tục để bỏ hoạt ảnh quay, tới khi danh sách quà hiện
     * (không thấy vòng quay, hoặc màn hình tối hẳn đi). Trả về false nếu bấm chưa ăn.
     */
    private fun choQuayXong(sangTruoc: Float): Boolean {
        var t = 0L
        while (!dung && t < choKetQuaMs) {
            ngu(nhip); t += nhip
            val a = tb.chup() ?: continue
            if (NhanDien.timVong(a, mauX1) == null || sang(a) < sangTruoc * 0.8f) return true
            chamTrong(a)
        }
        return false
    }

    /** "Chữ ký" các ô trên vòng quay để biết Tạo mới đã đổi món chưa. */
    private fun dau(a: Anh, neo: Neo): List<FloatArray> =
        NhanDien.O.keys.map { NhanDien.catO(a, neo, it).doiCo(12, 12).xam() }

    private fun soODoi(a: List<FloatArray>, b: List<FloatArray>): Int = a.indices.count { i ->
        var s = 0f
        for (j in a[i].indices) s += abs(a[i][j] - b[i][j])
        s / a[i].size > 15f
    }

    /** Bấm Tạo mới rồi chờ các món trên vòng đổi xong (đa số ô đổi, rồi đứng yên). */
    private fun taoMoi(a0: Anh, neo0: Neo): Pair<Anh, Neo>? {
        val truoc = dau(a0, neo0)
        val (x, y) = neo0.ra(NhanDien.NUT_TAO_MOI.first, NhanDien.NUT_TAO_MOI.second)
        tb.cham(x, y)
        var t = 0L
        var cuoi: Pair<Anh, Neo>? = null
        var dauCu: List<FloatArray>? = null
        while (!dung && t < choTaoMoiMs) {
            ngu(nhip); t += nhip
            val m = choVong(chamTat = false, han = 5000) ?: return null
            cuoi = m
            val d = dau(m.first, m.second)
            val cu = dauCu
            if (cu == null) { if (soODoi(d, truoc) >= 4) dauCu = d; continue }
            if (soODoi(d, cu) <= 1) return m // đã đổi và đứng yên
            dauCu = d
        }
        return cuoi
    }

    private fun taoMoiToiKhiCoMon(batDau: Pair<Anh, Neo>): Pair<Anh, Neo>? {
        var (a, neo) = batDau
        for (lan in 0..cd.taoMoiToiDa) {
            if (dung) return null
            val co = NhanDien.monTrenVong(a, neo, mau).filter { it.loai != null && it.loai in cd.muon }
            if (co.isNotEmpty()) {
                tb.log("  Vòng quay có ${co.joinToString { it.loai!!.ten }} (sau $lan lần Tạo mới)")
                return Pair(a, neo)
            }
            if (lan == cd.taoMoiToiDa) break
            val moi = taoMoi(a, neo) ?: return null
            a = moi.first; neo = moi.second
        }
        tb.log("  ⚠ Tạo mới ${cd.taoMoiToiDa} lần chưa ra món đã chọn → quay luôn")
        return Pair(a, neo)
    }

    fun chay() {
        tb.log("🎡 Bắt đầu: đã bấm x10 ${cd.dem}/${cd.moc}")
        var luiLai = 0
        while (!dung) {
            val vong = choVong(chamTat = daBam > 0) ?: run {
                if (!dung) tb.log("⛔ Không thấy màn Vòng quay liên server → dừng")
                return
            }
            if (cd.dungSau > 0 && daBam >= cd.dungSau) { tb.log("✔ Đã bấm đủ $daBam lần → dừng"); return }
            val lanThu = cd.dem + 1
            var (a, neo) = vong
            if (lanThu >= cd.moc) {
                tb.log("★ Lần bấm thứ $lanThu (mốc ${cd.moc}) → Tạo mới để ra món hạn định")
                val sau = taoMoiToiKhiCoMon(vong) ?: return
                a = sau.first; neo = sau.second
            }
            val sangTruoc = sang(a)
            val (x, y) = neo.ra(NhanDien.NUT_X10.first, NhanDien.NUT_X10.second)
            tb.cham(x, y)
            if (!choQuayXong(sangTruoc)) {
                if (dung) return
                luiLai++
                tb.log("  Bấm chưa ăn → bấm lại")
                if (luiLai >= 5) { tb.log("⛔ Bấm 5 lần không ăn → dừng"); return }
                continue
            }
            luiLai = 0
            daBam++
            cd.dem = if (lanThu >= cd.moc) 0 else lanThu
            tb.log(if (cd.dem == 0) "🎉 Lần $lanThu: mốc ${cd.moc} → bộ đếm về 0" else "  Đã bấm x10: ${cd.dem}/${cd.moc}")
            tb.luu(cd)
        }
    }
}
