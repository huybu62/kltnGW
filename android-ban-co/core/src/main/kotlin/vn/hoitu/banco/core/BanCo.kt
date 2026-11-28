package vn.hoitu.banco.core

/**
 * Cài đặt Bàn Cờ Lửa.
 * [soLan]: số lần Take-away muốn làm (mỗi lần [GIA] xu). [choTH3]: vừa lấy bàn đẹp → bàn kế tiếp lấy luôn.
 */
data class CaiDatBC(var soLan: Int = 1, var choTH3: Boolean = false) {
    companion object {
        const val GIA = 6000
        /** Số lần Take-away cho số xu muốn tiêu: làm tròn lên (xu có thể dư, không thiếu). */
        fun soLanTuXu(xu: Int) = if (xu <= 0) 0 else (xu + GIA - 1) / GIA
    }
}

interface ThietBiBC {
    fun nhin(): ManBC? // chụp + đọc chữ
    fun hang(): HangDau? // chụp, đọc 5 ô đầu bằng ảnh (nhanh)
    fun cham(x: Float, y: Float)
    fun ngu(ms: Long)
    fun log(s: String)
    fun luu(cd: CaiDatBC) {}
}

private class DungBC(msg: String) : Exception(msg)

/**
 * TH1: 5 ô đầu là 5 ô cờ đỏ, có Tướng hoặc Soái → Tẩy, Mua, Take-away.
 * TH2: chỉ có 4 ô cờ đỏ (ô còn lại là đá vận mệnh) → Tẩy, Mua, Take-away.
 * TH3: bàn ngay sau TH1/TH2 → Tẩy, Take-away luôn không cần xem.
 * Lấy xong luôn Tạo mới (miễn phí). Bàn không đạt → Tạo mới (20 xu).
 */
class BanCo(private val tb: ThietBiBC, private val cd: CaiDatBC) {
    @Volatile var dung = false
    var daLay = 0; private set
    var xuTaoMoi = 0; private set
    var soTaoMoi = 0; private set
    private var vuaLay = false // Tạo mới ngay sau Take-away thì miễn phí

    private fun ngu(ms: Long) { if (dung) throw DungBC("Đã dừng"); tb.ngu(ms) }
    private fun nhin(): ManBC { for (i in 0 until 5) { tb.nhin()?.let { return it }; ngu(300) }; throw DungBC("Không chụp/đọc được màn hình") }
    private fun cham(m: ManBC, p: Pair<Float, Float>) { val (x, y) = m.ra(p); tb.cham(x, y) }

    private fun cho(ms: Long, dk: (ManBC) -> Boolean): ManBC? {
        var t = 0L
        while (t <= ms) { val m = nhin(); if (dk(m)) return m; ngu(120); t += 300 }
        return null
    }

    fun chay() {
        tb.log("🔥 Bàn Cờ Lửa: ${cd.soLan} lần Take-away (~${cd.soLan * CaiDatBC.GIA} xu)" + if (cd.choTH3) " – đang chờ TH3" else "")
        try {
            while (!dung && daLay < cd.soLan) {
                val m = veBang()
                if (cd.choTH3) {
                    tb.log("TH3: bàn sau bàn đẹp → Tẩy + Take-away luôn")
                    layHet(m)
                    cd.choTH3 = false; tb.luu(cd)
                    taoMoi()
                    continue
                }
                val h = docHangChac()
                when {
                    h == null -> { tb.log("Bàn đang úp / chưa rõ → Tạo mới"); taoMoi(m) }
                    h.soCo == 5 && h.coTuongSoai -> {
                        tb.log("✅ TH1: $h (giống mẫu ${h.diem.joinToString("/") { "%.2f".format(it) }}) → lấy")
                        layHet(m); cd.choTH3 = true; tb.luu(cd); taoMoi()
                    }
                    h.soCo == 4 -> {
                        tb.log("✅ TH2 (4 ô đỏ): $h → lấy")
                        layHet(m); cd.choTH3 = true; tb.luu(cd); taoMoi()
                    }
                    else -> { tb.log("Bàn: $h → Tạo mới"); taoMoi(m) }
                }
            }
            tb.log("🏁 Xong: $daLay lần Take-away (${daLay * CaiDatBC.GIA} xu) + $soTaoMoi lần Tạo mới ($xuTaoMoi xu)")
        } catch (e: DungBC) {
            tb.log("⛔ ${e.message} – đã lấy $daLay lần (${daLay * CaiDatBC.GIA} xu), Tạo mới $soTaoMoi lần ($xuTaoMoi xu)")
        }
    }

    /** Đưa về bảng chính (đóng hộp thoại / bảng Mua còn sót). */
    private fun veBang(): ManBC {
        var khac = 0
        for (lan in 0 until 12) {
            val m = nhin()
            when (m.loai) {
                LoaiBC.BANG -> return m
                LoaiBC.HOI_TAO_MOI, LoaiBC.HOI_TAKE_AWAY -> { tb.log("  (hộp thoại sót: $m → Hủy)"); cham(m, DocBC.HUY); ngu(600) }
                LoaiBC.HOI_KHAC -> throw DungBC("Hộp thoại lạ: \"${m.chuHoi}\"")
                LoaiBC.MUA -> { cham(m, DocBC.CHO_TRONG); ngu(600) }
                LoaiBC.KHAC -> { if (++khac >= 6) throw DungBC("Không thấy bảng Bàn Cờ Lửa (mở sự kiện rồi chạy)"); ngu(500) }
            }
        }
        throw DungBC("Không về được bảng Bàn Cờ Lửa")
    }

    /** Đọc 5 ô đầu 2 lần liên tiếp giống nhau (tránh đọc lúc bàn đang lật). null nếu bàn úp. */
    private fun docHangChac(): HangDau? {
        var truoc: HangDau? = null
        for (lan in 0 until 10) {
            val h = tb.hang()
            if (h != null && h == truoc) return if (h.up) null else h
            truoc = h
            ngu(120)
        }
        tb.log("  (5 ô đầu đọc không ổn định: $truoc)")
        return null
    }

    /** Tẩy → Mua → Take-away → OK. */
    private fun layHet(m0: ManBC) {
        var m = m0
        if (m.loai != LoaiBC.BANG) m = veBang()
        // Tẩy: chờ bàn úp (đọc ảnh, nhanh)
        var up = false
        for (lan in 0 until 2) {
            cham(m, DocBC.TAY)
            for (i in 0 until 25) {
                ngu(100)
                val h = tb.hang()
                if (h != null && h.up) { up = true; break }
                if (i == 12) {
                    val x = nhin()
                    if (x.loai == LoaiBC.HOI_KHAC || x.loai == LoaiBC.HOI_TAO_MOI || x.loai == LoaiBC.HOI_TAKE_AWAY) {
                        cham(x, DocBC.HUY); throw DungBC("Bấm Tẩy hiện hộp thoại: \"${x.chuHoi}\" (đã Hủy)")
                    }
                }
            }
            if (up) break
            tb.log("  Tẩy chưa thấy bàn úp → bấm lại (5 ô: ${tb.hang()?.let { "$it · ${it.chiTiet}" }})")
            m = veBang()
        }
        if (!up) throw DungBC("Bấm Tẩy mà bàn không úp")
        // Mua → bảng Take-away
        var mua: ManBC? = null
        for (lan in 0 until 2) {
            cham(if (lan == 0) m else veBang(), DocBC.MUA)
            mua = cho(3000) { it.loai == LoaiBC.MUA || it.loai == LoaiBC.HOI_KHAC }
            if (mua?.loai == LoaiBC.MUA) break
            if (mua?.loai == LoaiBC.HOI_KHAC) { cham(mua, DocBC.HUY); throw DungBC("Bấm Mua hiện hộp thoại: \"${mua.chuHoi}\" (đã Hủy)") }
            tb.log("  Bấm Mua chưa thấy nút Take-away → bấm lại")
        }
        if (mua?.loai != LoaiBC.MUA) throw DungBC("Không mở được bảng Mua")
        cham(mua, mua.takeAway ?: DocBC.TAKE_AWAY)
        val hoi = cho(3000) { it.loai == LoaiBC.HOI_TAKE_AWAY || it.loai == LoaiBC.HOI_KHAC }
            ?: throw DungBC("Bấm Take-away không thấy hộp xác nhận")
        if (hoi.loai != LoaiBC.HOI_TAKE_AWAY) { cham(hoi, DocBC.HUY); throw DungBC("Hộp thoại lạ: \"${hoi.chuHoi}\" (đã Hủy)") }
        cham(hoi, DocBC.OK) // chỉ bấm OK đúng 1 lần
        val sau = cho(5000) { it.loai != LoaiBC.HOI_TAKE_AWAY }
        if (sau?.loai == LoaiBC.HOI_KHAC) throw DungBC("Sau Take-away hiện: \"${sau.chuHoi}\" (có thể thiếu xu)")
        daLay++
        vuaLay = true
        tb.log("🎁 Take-away lần $daLay/${cd.soLan} (${daLay * CaiDatBC.GIA} xu)")
    }

    /** Tạo mới + OK, chờ bàn mới. */
    private fun taoMoi(m0: ManBC? = null) {
        for (lan in 0 until 2) {
            val m = if (lan == 0 && m0?.loai == LoaiBC.BANG) m0 else veBang()
            val truoc = tb.hang()
            cham(m, DocBC.TAO_MOI)
            val hoi = cho(3000) { it.loai == LoaiBC.HOI_TAO_MOI || it.loai == LoaiBC.HOI_KHAC || it.loai == LoaiBC.HOI_TAKE_AWAY }
            if (hoi == null) {
                // không hiện hỏi: có thể đã tạo luôn
                if (tb.hang() != truoc) { demTaoMoi(null); return }
                tb.log("  Bấm Tạo mới chưa thấy hộp xác nhận → bấm lại"); continue
            }
            if (hoi.loai != LoaiBC.HOI_TAO_MOI) { cham(hoi, DocBC.HUY); throw DungBC("Bấm Tạo mới hiện hộp thoại lạ: \"${hoi.chuHoi}\" (đã Hủy)") }
            cham(hoi, DocBC.OK)
            val sau = cho(4000) { it.loai != LoaiBC.HOI_TAO_MOI }
            if (sau?.loai == LoaiBC.HOI_KHAC) throw DungBC("Sau Tạo mới hiện: \"${sau.chuHoi}\" (có thể thiếu xu)")
            demTaoMoi(hoi.giaHoi)
            ngu(400)
            return
        }
        throw DungBC("Không Tạo mới được")
    }

    private fun demTaoMoi(gia: Int?) {
        val g = gia ?: if (vuaLay) 0 else 20
        soTaoMoi++; xuTaoMoi += g; vuaLay = false
    }
}
