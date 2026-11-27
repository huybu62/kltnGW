package vn.hoitu.bansuc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.bansuc.core.BanSuc
import vn.hoitu.bansuc.core.CaiDat
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.Da
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.Hang
import vn.hoitu.bansuc.core.He
import vn.hoitu.bansuc.core.HieuQua
import vn.hoitu.bansuc.core.LoaiMan
import vn.hoitu.bansuc.core.ManHinh
import vn.hoitu.bansuc.core.Pham
import vn.hoitu.bansuc.core.The
import vn.hoitu.bansuc.core.ThietBi
import kotlin.math.abs
import kotlin.random.Random

/**
 * Game giả mô phỏng màn Ban Sức: danh sách đá (4 hàng/trang, vuốt được), bảng Điểm Hóa / Thác Ấn,
 * bảng chọn đá nhiều trang. Điểm Hóa: thành công / giữ nguyên / hạ 1 bậc ngẫu nhiên.
 * Toạ độ màn hình = toạ độ chuẩn (vùng game 2000×1125 bắt đầu ở 0,0).
 */
class GameGia(
    val da: MutableList<Da>,
    val diemHoa: MutableMap<Pair<Int, He>, Int>, // (bậc, hệ) → số viên
    val daIn: MutableMap<Int, Int>, // bậc → số viên
    seed: Int = 1,
    val tiLe: Double = 0.3, // tỉ lệ thành công
    val dongSauLam: Boolean = false, // game tự đóng bảng sau mỗi lần bấm (như game thật)
    val troi: Boolean = false, // vuốt bị trôi quán tính: danh sách đi xa hơn ngẫu nhiên
) : ThietBi {
    private val nhoO = HashMap<Pair<LoaiMan, Int>, Pair<Int, He?>>() // đá còn trong ô khi mở lại bảng của cùng viên
    private val r = Random(seed)
    var man = LoaiMan.CHINH
    var chon = 0
    var cuon = 0
    var oDa: Pair<Int, He?>? = null // đá đang nằm trong ô của bảng (bậc, hệ) – hệ null với Đá In
    var bangChon: LoaiMan? = null // bảng chọn đá đang mở cho bảng nào
    var trang = 0
    val nhatKy = ArrayList<String>()
    var soLanMoChon = 0
    var nhoTrang = false // bảng chọn mở lại ở trang lần trước (thay vì trang 1)
    var vuotLui = 0 // số lần vuốt về trang trước
    var xemKy = 0
    var mauLuonXanh = false // giả lập nhìn màu sai: thẻ tím cũng thấy là xanh // số lượt xem kỹ (về trang 1 rồi đọc chữ từng trang)
    override fun trang(): Pair<Int, Int>? = if (man == LoaiMan.CHON_DA && bangChon == LoaiMan.DIEM_HOA)
        Pair(trang, (1 + theHienCo().size + 7) / 8) else null
    var soLanMoDiemHoa = 0
    var soLanDoc = 0 // số lần đọc chữ (chậm trên máy thật)

    private val nhanDiemHoa = listOf<Pair<Int, He>?>(null) // ô "Bỏ trống" ở trang 1

    private fun theHienCo(): List<Pair<Int, He?>> =
        if (bangChon == LoaiMan.THAC_AN) daIn.filter { it.value > 0 }.keys.sorted().map { Pair(it, null) }
        else diemHoa.filter { it.value > 0 }.keys.sortedWith(compareBy({ it.second.ordinal }, { it.first })).map { Pair(it.first, it.second) }

    private fun trangThe(): List<Pair<Int, He?>?> =
        if (bangChon == LoaiMan.THAC_AN) // giống game: Bỏ trống | In S | khóa | khóa / In SS | In SSS | khóa | khóa
            if (trang > 0) emptyList() else listOf(null, Pair(1, null), null, null, Pair(2, null), Pair(3, null), null, null)
                .map { t -> t?.takeIf { (daIn[it.first] ?: 0) > 0 } }
        else (nhanDiemHoa + theHienCo()).chunked(8).getOrElse(trang) { emptyList() }

    private fun hq(d: Da) = HieuQua(d.pham, d.he)

    override fun bacCacO(): List<Int?> = if (man != LoaiMan.CHON_DA) List(8) { null } else
        trangThe().let { t -> List(8) { i -> t.getOrNull(i)?.first?.let { b -> if (mauLuonXanh) 1 else b } } }

    var docKhiChonDaIn = 0
    override fun nhin(): ManHinh = also { soLanDoc++; if (man == LoaiMan.CHON_DA && bangChon == LoaiMan.THAC_AN) docKhiChonDaIn++ }.let { nhinThat() }
    override fun oCoDa(diemHoa: Boolean): Boolean? = if (man == LoaiMan.DIEM_HOA || man == LoaiMan.THAC_AN) oDa != null else null

    private fun nhinThat(): ManHinh = when (man) {
        LoaiMan.CHINH -> {
            val hien = da.drop(cuon).take(4)
            ManHinh(
                LoaiMan.CHINH, 0f, 0f, 1f, daChon = da.getOrNull(chon),
                hang = hien.mapIndexed { i, d -> Hang(d, 600f, 300f + i * 176f, cuon + i == chon) },
            )
        }
        LoaiMan.DIEM_HOA, LoaiMan.THAC_AN -> {
            val d = da[chon]
            val sau = oDa?.let { (bac, h) ->
                if (man == LoaiMan.THAC_AN) HieuQua(null, null) else HieuQua("BAS"[bac - 1], h)
            }
            ManHinh(man, 0f, 0f, 1f, hien = hq(d), sau = sau, daThem = oDa != null)
        }
        LoaiMan.CHON_DA -> ManHinh(
            LoaiMan.CHON_DA, 0f, 0f, 1f,
            the = trangThe().mapIndexedNotNull { i, t ->
                if (t == null) null
                else {
                    val sl = if (t.second == null) daIn[t.first] else diemHoa[Pair(t.first, t.second!!)]
                    The(t.first, t.second == null, t.second, sl, DocMan.COT[i % 4], DocMan.HANG_CHAM[i / 4], "${t.first}${t.second}")
                }
            },
        )
        LoaiMan.KHAC -> ManHinh(LoaiMan.KHAC, 0f, 0f, 1f)
    }

    private fun gan(x: Float, y: Float, p: Pair<Float, Float>, d: Float = 30f) = abs(x - p.first) < d && abs(y - p.second) < d

    override fun cham(x: Float, y: Float) {
        when (man) {
            LoaiMan.CHINH -> {
                if (gan(x, y, DocMan.NUT_DIEM_HOA)) { man = LoaiMan.DIEM_HOA; oDa = nhoO[Pair(man, chon)]; soLanMoDiemHoa++; return }
                if (gan(x, y, DocMan.NUT_THAC_AN)) { man = LoaiMan.THAC_AN; oDa = nhoO[Pair(man, chon)]; return }
                for (i in 0 until 4) if (gan(x, y, Pair(600f, 300f + i * 176f), 60f) && cuon + i < da.size) chon = cuon + i
            }
            LoaiMan.DIEM_HOA, LoaiMan.THAC_AN -> {
                if (gan(x, y, DocMan.DONG_BANG)) { man = LoaiMan.CHINH; return }
                if (gan(x, y, DocMan.NUT_O)) { if (bangChon != man || !nhoTrang) trang = 0; bangChon = man; man = LoaiMan.CHON_DA; soLanMoChon++; return }
                if (gan(x, y, DocMan.NUT_LAM)) {
                    lam()
                    if (oDa != null) nhoO[Pair(man, chon)] = oDa!! else nhoO.remove(Pair(man, chon))
                    if (dongSauLam) man = LoaiMan.CHINH
                }
            }
            LoaiMan.CHON_DA -> {
                if (gan(x, y, DocMan.QUAY_LAI)) { man = bangChon!!; return }
                // như game thật: chạm mũi tên không lật trang (chỉ vuốt ngang mới lật)
                if (gan(x, y, DocMan.TRANG_SAU) || gan(x, y, DocMan.TRANG_TRUOC)) return
                trangThe().forEachIndexed { i, t ->
                    if (t != null && gan(x, y, Pair(DocMan.COT[i % 4], DocMan.HANG_CHAM[i / 4]), 80f)) {
                        // như game: chạm lại đúng viên đang nằm trong ô thì gỡ nó ra
                        oDa = if (oDa == t) null else t; man = bangChon!!; return
                    }
                }
            }
            else -> {}
        }
    }

    private fun lam() {
        val (bac, h) = oDa ?: return
        val d = da[chon]
        if (man == LoaiMan.DIEM_HOA) {
            val khoa = Pair(bac, h!!)
            if ((diemHoa[khoa] ?: 0) <= 0) return
            diemHoa[khoa] = diemHoa[khoa]!! - 1
            if (diemHoa[khoa] == 0) oDa = null
            val muc = "BAS"[bac - 1]
            val x = r.nextDouble()
            da[chon] = when {
                x < tiLe -> d.copy(pham = muc, he = h)
                x < tiLe + 0.35 || d.pham == null -> d
                else -> d.copy(pham = Pham.THU_TU[maxOf(0, Pham.hang(d.pham) - 1)])
            }
        } else {
            if (d.pham == null || (daIn[bac] ?: 0) <= 0) return
            daIn[bac] = daIn[bac]!! - 1
            if (daIn[bac] == 0) oDa = null
            val khoa = Pair(bac, d.he!!)
            diemHoa[khoa] = (diemHoa[khoa] ?: 0) + 1
            nhatKy += "thác ấn ${d} bằng In ${"S".repeat(bac)}"
            da[chon] = d.copy(pham = null, he = null)
            oDa = null
        }
    }

    override fun vuot(x0: Float, y0: Float, x1: Float, y1: Float) {
        if (man == LoaiMan.CHON_DA) {
            if (x1 < x0 - 300 && (trang + 1) * 8 < 1 + theHienCo().size) trang++
            if (x1 > x0 + 300) { vuotLui++; if (trang > 0) trang-- }
            return
        }
        if (man != LoaiMan.CHINH) return
        val hang = maxOf(1, (abs(y1 - y0) / 176f).toInt()) + (if (troi) r.nextInt(0, 4) else 0)
        cuon = if (y1 < y0) minOf(maxOf(0, da.size - 4), cuon + hang) else maxOf(0, cuon - hang)
    }

    override fun ngu(ms: Long) {}
    override fun log(s: String) { println(s); if ("Lượt nhanh chưa thấy" in s) xemKy++ }
}

class BanSucTest {
    private fun lv6(p: Char?, he: He?, cs: ChiSo) = Da(6, p, he, cs)

    private fun bo(): MutableList<Da> = mutableListOf(
        Da(4, null, null, ChiSo.PHONG), Da(4, null, null, ChiSo.HP),
        lv6('A', He.LANHCHUA, ChiSo.PHONG), lv6('C', He.LANHCHUA, ChiSo.HP),
        lv6(null, null, ChiSo.HP), lv6(null, null, ChiSo.HP), lv6('B', He.TITAN, ChiSo.HP), // đá hệ khác: không được đụng
        lv6(null, null, ChiSo.TOCDO), Da(5, null, null, ChiSo.HP),
    )

    @Test
    fun mucTieuA_1Bo() {
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 3000, Pair(1, He.TINHTHAN) to 50, Pair(2, He.HUYDIET) to 4), mutableMapOf(1 to 100, 2 to 500, 3 to 5))
        val cd = CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1))
        val b = BanSuc(g, cd)
        b.chay()
        val xong = g.da.filter { it.lv == 6 && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') }
        assertEquals(3, xong.count { it.chiSo == ChiSo.HP })
        assertEquals(1, xong.count { it.chiSo == ChiSo.PHONG })
        assertTrue("đá hệ Titan không bị đụng", g.da.contains(lv6('B', He.TITAN, ChiSo.HP)))
        assertTrue("đá Tốc độ không bị đụng", g.da.contains(lv6(null, null, ChiSo.TOCDO)))
        assertTrue("chỉ Thác Ấn bằng Đá In SS", g.nhatKy.all { it.endsWith("In SS") })
        assertEquals(5, g.daIn[3]) // không đụng Đá In SSS
    }

    @Test
    fun mucTieuS_khongNhaMay_hetASSS_thiDung() {
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 3000, Pair(3, He.LANHCHUA) to 3), mutableMapOf(2 to 500, 3 to 5), tiLe = 0.2)
        val cd = CaiDat(he = He.LANHCHUA, mucTieu = 'S', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1))
        BanSuc(g, cd).chay()
        assertEquals(0, g.diemHoa[Pair(3, He.LANHCHUA)] ?: 0) // dùng hết A-SSS rồi dừng
        assertEquals(5, g.daIn[3]) // không tự làm A-SSS khi chưa bật nhà máy LV6
    }

    @Test
    fun mucTieuS_coNhaMayLv6() {
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 100000), mutableMapOf(2 to 5000, 3 to 500), seed = 7, tiLe = 0.35)
        val cd = CaiDat(he = He.LANHCHUA, mucTieu = 'S', soLuong = mutableMapOf(ChiSo.HP to 1, ChiSo.PHONG to 0), nhaMayLv6 = true)
        BanSuc(g, cd).chay()
        assertEquals(1, g.da.count { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.LANHCHUA && it.pham == 'S' })
        assertTrue(g.nhatKy.any { it.endsWith("In SSS") })
    }

    @Test
    fun nhieuLanNgauNhien() {
        for (seed in 1..20) {
            val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 100000), mutableMapOf(2 to 5000, 3 to 500), seed = seed, tiLe = 0.15, dongSauLam = seed % 3 != 0)
            val cd = CaiDat(he = He.LANHCHUA, mucTieu = if (seed % 2 == 0) 'A' else 'S', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1), nhaMayLv6 = true)
            BanSuc(g, cd).chay()
            val xong = g.da.filter { it.lv == 6 && it.he == He.LANHCHUA && Pham.datToi(it.pham, cd.mucTieu) }
            // mục tiêu S cần 1 viên LV6 làm nhà máy: bộ test chỉ có 3 viên HP + Titan nên có thể thiếu 1 viên HP
            assertTrue("seed $seed: ${g.da}", xong.count { it.chiSo == ChiSo.HP } >= (if (cd.mucTieu == 'A') 3 else 2))
            assertTrue("seed $seed", xong.count { it.chiSo == ChiSo.PHONG } >= 1)
            assertTrue(g.da.contains(lv6('B', He.TITAN, ChiSo.HP)))
        }
    }

    @Test
    fun gameTuDongBangSauMoiLanBam() {
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 3000, Pair(1, He.TINHTHAN) to 50), mutableMapOf(1 to 100, 2 to 500, 3 to 5), seed = 3, dongSauLam = true)
        val cd = CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1))
        BanSuc(g, cd).chay()
        val xong = g.da.filter { it.lv == 6 && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') }
        assertEquals(3, xong.count { it.chiSo == ChiSo.HP })
    }

    @Test
    fun hetDaThiKhongMoBangChonNua() {
        // không có B-SS: mỗi viên B-SS phải làm ở nhà máy LV5; bảng chọn chỉ mở khi cần thật
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 100000, Pair(1, He.TINHTHAN) to 50, Pair(2, He.HUYDIET) to 4),
            mutableMapOf(1 to 100, 2 to 5000, 3 to 5), seed = 5, tiLe = 0.25, dongSauLam = true)
        val cd = CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1))
        val b = BanSuc(g, cd)
        b.chay()
        assertEquals(3, g.da.count { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') })
        val soThacAn = g.nhatKy.size
        println("điểm hóa ${b.soLanDiemHoa}, thác ấn $soThacAn, mở bảng chọn ${g.soLanMoChon}, đọc chữ ${g.soLanDoc}, đọc chữ khi chọn Đá In ${g.docKhiChonDaIn}")
        assertEquals("chọn Đá In không cần đọc chữ", 0, g.docKhiChonDaIn)
        // mỗi viên B-SS làm ra: 1 lần chọn B-SS + 1 lần chọn Đá In + vài lần chọn B-S khi đổi nhà máy
        assertTrue("mở bảng chọn ${g.soLanMoChon} lần cho $soThacAn lần thác ấn", g.soLanMoChon <= soThacAn * 3 + 5)
        // mỗi lần mở bảng Điểm Hóa đều phải có lần bấm Điểm Hóa (không mở thừa khi đã hết đá)
        println("mở bảng Điểm Hóa ${g.soLanMoDiemHoa} lần, bấm ${b.soLanDiemHoa} lần")
        assertTrue("mở thừa ${g.soLanMoDiemHoa - b.soLanDiemHoa} lần", g.soLanMoDiemHoa - b.soLanDiemHoa <= 2)
    }

    @Test
    fun danhSachDaiVuotBiTroiVanThayDaLv5() {
        // danh sách dài, đá LV5 nằm giữa, vuốt bị trôi xa hơn ngẫu nhiên
        for (seed in 1..15) {
            val ds = mutableListOf<Da>()
            // game thật gộp đá giống nhau thành 1 hàng "xN", nên các hàng liền nhau khác nhau
            for (i in 1..6) ds += lv6("DCBAS"[i % 5], He.values()[i], ChiSo.TOCDO)
            ds += listOf(lv6('C', He.LANHCHUA, ChiSo.HP), lv6(null, null, ChiSo.HP), lv6(null, null, ChiSo.HP))
            for (cs in listOf(ChiSo.MACONG, ChiSo.HP, ChiSo.TOCDO, ChiSo.VATCONG)) ds += Da(4, null, null, cs)
            ds += Da(5, null, null, ChiSo.HP)
            for (i in 1..8) ds += Da(4, "DCBAS"[i % 5], He.values()[i], ChiSo.PHONG)
            val g = GameGia(ds, mutableMapOf(Pair(1, He.LANHCHUA) to 100000), mutableMapOf(2 to 5000), seed = seed, tiLe = 0.3, dongSauLam = true, troi = true)
            BanSuc(g, CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 1))).chay()
            assertTrue("seed $seed", g.da.any { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') })
        }
    }

    @Test
    fun daDuThiKhongLamGi() {
        val g = GameGia(mutableListOf(lv6('A', He.LANHCHUA, ChiSo.PHONG), lv6('S', He.LANHCHUA, ChiSo.HP), Da(5, null, null, ChiSo.HP)), mutableMapOf(), mutableMapOf())
        val b = BanSuc(g, CaiDat(soLuong = mutableMapOf(ChiSo.HP to 1, ChiSo.PHONG to 1)))
        b.chay()
        assertEquals(0, b.soLanDiemHoa)
    }

    @Test
    fun daDiemHoaOTrang2() {
        // hệ Con Lắc: thẻ B-S Con Lắc nằm ở trang 2 (trang 1 đầy các hệ khác) – phải vuốt sang trang 2 mới thấy
        val nhieu = mutableMapOf<Pair<Int, He>, Int>()
        for (h in He.values()) nhieu[Pair(1, h)] = 1200
        nhieu[Pair(2, He.HUYDIET)] = 4
        val g = GameGia(bo().map { if (it.he == He.LANHCHUA) it.copy(he = null, pham = null) else it }.toMutableList(), nhieu,
            mutableMapOf(1 to 100, 2 to 5000, 3 to 5), seed = 4, tiLe = 0.3, dongSauLam = true)
        val cd = CaiDat(he = He.CONLAC, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 1))
        BanSuc(g, cd).chay()
        assertTrue(g.da.any { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.CONLAC && Pham.datToi(it.pham, 'A') })
        // bảng chọn mở ở trang 1 thì không vuốt lùi (trái → phải), trừ lượt xem kỹ khi thật sự không có thẻ
        assertTrue("vuốt lùi ${g.vuotLui}, xem kỹ ${g.xemKy}", g.vuotLui <= g.xemKy)

        // bảng chọn nhớ trang cũ (mở ra ở trang 2): vẫn tìm đúng
        val g2 = GameGia(bo().map { if (it.he == He.LANHCHUA) it.copy(he = null, pham = null) else it }.toMutableList(),
            nhieu.toMutableMap(), mutableMapOf(1 to 100, 2 to 5000, 3 to 5), seed = 5, tiLe = 0.3, dongSauLam = true)
        g2.nhoTrang = true
        BanSuc(g2, CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 1))).chay()
        assertTrue(g2.da.any { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') })
    }

    @Test
    fun nhinMauSaiVanTimRaThe() {
        val g = GameGia(bo(), mutableMapOf(Pair(1, He.LANHCHUA) to 3000, Pair(2, He.LANHCHUA) to 5, Pair(2, He.HUYDIET) to 4),
            mutableMapOf(2 to 500), seed = 3, tiLe = 0.3, dongSauLam = true)
        g.mauLuonXanh = true
        val b = BanSuc(g, CaiDat(he = He.LANHCHUA, mucTieu = 'A', soLuong = mutableMapOf(ChiSo.HP to 3, ChiSo.PHONG to 1)))
        b.chay()
        assertEquals(3, g.da.count { it.lv == 6 && it.chiSo == ChiSo.HP && it.he == He.LANHCHUA && Pham.datToi(it.pham, 'A') })
    }
}
