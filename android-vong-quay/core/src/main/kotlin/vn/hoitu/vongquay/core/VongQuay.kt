package vn.hoitu.vongquay.core

/** Cài đặt (lưu lại giữa các lần chạy). */
data class CaiDat(
    var dem: Int = 0, // số lần đã bấm x10 kể từ lần ra hạn định gần nhất
    var moc: Int = 73, // lần bấm thứ "moc" chắc chắn ra hạn định
    var taoMoiToiDa: Int = 60, // số lần Tạo mới tối đa ở lượt mốc
    var dungSau: Int = 0, // dừng sau N lần bấm (0 = không giới hạn)
    var muon: MutableSet<Loai> = mutableSetOf(Loai.PHIEU_HUY_DIET, Loai.DA_VAN_MENH, Loai.TUONG),
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
 * Lần bấm thứ [CaiDat.moc]: bấm "Tạo mới" tới khi vòng quay có món người chơi muốn, rồi bấm → về 0.
 * Quay xong game hiện danh sách quà: chạm chỗ trống để tắt.
 * Chỉ bấm 3 chỗ: Khởi động 10 lần, Tạo mới, chỗ trống.
 */
class VongQuay(
    private val tb: ThietBi,
    private val cd: CaiDat,
    private val mauX1: Anh,
    private val mau: Map<Loai, MauMon>,
    private val choKetQuaMs: Long = 8000,
    private val choManMs: Long = 60000,
) {
    @Volatile var dung = false
    var daBam = 0
        private set

    private fun ngu(ms: Long) { if (!dung) tb.ngu(ms) }

    /** Chờ tới khi thấy màn vòng quay; trong lúc chờ thì chạm chỗ trống nếu [chamTat] (đang có danh sách quà). */
    private fun choVong(chamTat: Boolean, han: Long = choManMs): Pair<Anh, Neo>? {
        var t = 0L
        var lanCham = 0L
        while (!dung && t < han) {
            val a = tb.chup()
            if (a != null) {
                val neo = NhanDien.timVong(a, mauX1)
                if (neo != null) return Pair(a, neo)
                if (chamTat && t >= lanCham) {
                    val (x, y) = NhanDien.choTrong(a)
                    tb.cham(x, y)
                    lanCham = t + 1500
                }
            }
            ngu(300); t += 300
        }
        return null
    }

    /** Chờ màn vòng quay biến mất (danh sách quà hiện ra) sau khi bấm. */
    private fun choRoiVong(): Boolean {
        var t = 0L
        while (!dung && t < choKetQuaMs) {
            ngu(250); t += 250
            val a = tb.chup() ?: continue
            if (NhanDien.timVong(a, mauX1) == null) return true
        }
        return false
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
            val (x, y) = neo.ra(NhanDien.NUT_TAO_MOI.first, NhanDien.NUT_TAO_MOI.second)
            tb.cham(x, y)
            ngu(1200)
            val moi = choVong(chamTat = false) ?: return null
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
            val (x, y) = neo.ra(NhanDien.NUT_X10.first, NhanDien.NUT_X10.second)
            tb.cham(x, y)
            if (!choRoiVong()) {
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
