package vn.hoitu.canquet

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.bansuc.core.Anh
import vn.hoitu.canquet.core.AiChuong
import vn.hoitu.canquet.core.CaiDatCQ
import vn.hoitu.canquet.core.CanQuet
import vn.hoitu.canquet.core.DocCQ
import vn.hoitu.canquet.core.LoaiCQ
import vn.hoitu.canquet.core.ManCQ
import vn.hoitu.canquet.core.ThietBiCQ
import kotlin.math.abs
import kotlin.random.Random

/** Một toà nhà trên bản đồ giả (toạ độ bản đồ, chuẩn 2000 rộng). */
class ToaNha(val ten: String, val x0: Float, val y0: Float, val x1: Float, val y1: Float, var conLai: Int, var moCQ: Boolean = true, val coBoi: Boolean = false)

/** Một ải giả: bản đồ (rộng × cao, chuẩn) + các toà nhà. */
class AiGia(val rong: Float, val cao: Float, val nha: List<ToaNha>, val seed: Int)

/**
 * Game giả: bản đồ lớn hơn màn hình (ảnh có vân để đo dịch), camera bị chặn ở mép, các bảng / màn như game thật.
 * Ảnh chụp rộng 800 (k = 0,4). Ghi lại mọi lần chạm vào vùng nút giao diện.
 */
class GameCQ(
    val nuoc: List<Pair<String, List<AiGia>>>, // các nước, mỗi nước các ải
    var theLuc: Int = 1000,
    var nuocI: Int = 0,
    var aiI: Int = 0,
    var man: LoaiCQ = LoaiCQ.BAN_DO,
    camX0: Float = 0f, camY0: Float = 0f,
    val tiLeKeo: Float = 1f, // bản đồ dịch bao nhiêu so với ngón tay
    val docHong: Double = 0.0, // tỉ lệ đọc hụt "Số lần" ở màn kết quả
) : ThietBiCQ {
    private val rr = Random(99)
    val k = 0.4f
    val W = 800; val H = 450
    var camX = camX0; var camY = camY0
    var nha: ToaNha? = null
    var hoiSo = 0
    var tranLan = 0
    var demQuet = 0
    val chamCam = ArrayList<Pair<Float, Float>>()
    var soVuot = 0
    var soCham = 0
    val chamBanDo = ArrayList<Pair<Float, Float>>() // các điểm chạm trên bản đồ (toạ độ bản đồ thật)
    private val vanCache = HashMap<Int, Pair<FloatArray, Pair<Int, Int>>>()
    val ai get() = nuoc[nuocI].second[aiI]

    init { camX = camX.coerceIn(0f, maxOf(0f, ai.rong - 2000f)); camY = camY.coerceIn(0f, maxOf(0f, ai.cao - 1125f)) }

    /** Vân bản đồ (mỗi ô 8 đơn vị chuẩn): nền phẳng có ít nhiễu, toà nhà nhiều chi tiết. */
    private fun van(a: AiGia): Pair<FloatArray, Pair<Int, Int>> = vanCache.getOrPut(System.identityHashCode(a)) {
        val w = (a.rong / 8).toInt(); val h = (a.cao / 8).toInt()
        val r = Random(a.seed)
        // nền: các mảng màu to (đường, cỏ) + chút nhiễu để đo dịch được
        val nen = FloatArray(w * h)
        val mang = List(60) { Triple(r.nextInt(w), r.nextInt(h), 60f + r.nextFloat() * 120f) }
        for (y in 0 until h) for (x in 0 until w) {
            val m = mang.minBy { (mx, my, _) -> (mx - x) * (mx - x) + (my - y) * (my - y) }
            nen[y * w + x] = m.third + r.nextFloat() * 50f - 25f // bản đồ thật nhiều chi tiết ở khắp nơi
        }
        for (t in a.nha) for (y in (t.y0 / 8).toInt() until (t.y1 / 8).toInt()) for (x in (t.x0 / 8).toInt() until (t.x1 / 8).toInt()) {
            if (x in 0 until w && y in 0 until h) nen[y * w + x] = if ((x + y) % 2 == 0) 40f + r.nextFloat() * 60f else 170f + r.nextFloat() * 70f
        }
        Pair(nen, Pair(w, h))
    }

    @Synchronized override fun anh(): Anh {
        val (v, wh) = van(ai)
        val (vw, vh) = wh
        val toi = man != LoaiCQ.BAN_DO
        val px = IntArray(W * H) { i ->
            val sx = i % W; val sy = i / W
            val mx = ((camX + sx / k) / 8).toInt(); val my = ((camY + sy / k) / 8).toInt()
            var g = if (mx in 0 until vw && my in 0 until vh) v[my * vw + mx] else 0f
            if (toi) g *= 0.45f
            val c = g.toInt().coerceIn(0, 255)
            (0xFF shl 24) or (c shl 16) or (c shl 8) or c
        }
        return Anh(W, H, px)
    }

    private fun p(x: Float, y: Float) = Pair(x * k, y * k)

    @Synchronized override fun nhin(): ManCQ {
        val t = nha
        return when (man) {
            LoaiCQ.BAN_DO -> ManCQ(LoaiCQ.BAN_DO, 0f, 0f, k, theLuc = theLuc, theLucMax = 120)
            LoaiCQ.POPUP -> {
                val nut = mutableMapOf("DONG" to p(1384f, 84f), "THAM_HIEM" to p(870f, 975f))
                if (t!!.moCQ) nut["CAN_QUET"] = p(1150f, 975f)
                if (t.moCQ && t.coBoi) { nut["X5"] = p(1220f, 975f); nut["X10"] = p(1380f, 975f) }
                ManCQ(LoaiCQ.POPUP, 0f, 0f, k, ten = t.ten, conLai = t.conLai, nut = nut)
            }
            LoaiCQ.KET_QUA -> ManCQ(LoaiCQ.KET_QUA, 0f, 0f, k, conLai = if (rr.nextDouble() < docHong) null else t!!.conLai, nut = mapOf("LAN_NUA" to p(1760f, 470f), "DONG" to p(1760f, 840f)))
            LoaiCQ.QUET_LAI -> ManCQ(LoaiCQ.QUET_LAI, 0f, 0f, k, conLai = t!!.conLai, nut = mapOf("QUET_LAI" to p(1200f, 900f), "DONG" to p(1760f, 840f)))
            LoaiCQ.HOI -> ManCQ(LoaiCQ.HOI, 0f, 0f, k, hoiCanQuet = hoiSo > 0, hoiSo = if (hoiSo > 0) hoiSo else null, nut = mapOf("XAC_DINH" to p(950f, 715f)))
            LoaiCQ.TRAN -> ManCQ(LoaiCQ.TRAN, 0f, 0f, k, nut = mapOf("TIEN_LEN" to p(1660f, 750f)))
            LoaiCQ.CHUONG -> {
                val ds = nuoc[nuocI].second.indices.map { i -> AiChuong(i + 1, "${nuocI + 1}-${i + 1} Ải", (600f + i * 300f) * k, 700f * k) }
                ManCQ(LoaiCQ.CHUONG, 0f, 0f, k, nuoc = nuoc[nuocI].first, ai = ds)
            }
            LoaiCQ.KHAC -> ManCQ(LoaiCQ.KHAC, 0f, 0f, k)
        }
    }

    private fun gan(x: Float, y: Float, q: Pair<Float, Float>, sai: Float = 20f) = abs(x - q.first) < sai && abs(y - q.second) < sai

    @Synchronized override fun cham(x: Float, y: Float) {
        soCham++
        val rx = x / k; val ry = y / k
        val t = nha
        when (man) {
            LoaiCQ.BAN_DO -> {
                if (rx < 300 && ry < 210) { man = LoaiCQ.CHUONG; return } // nút Trở lại (bấm có chủ đích)
                if (DocCQ.trongVungCam(rx, ry)) {
                    chamCam += Pair(rx, ry)
                    if (rx < 600 && ry > 700) man = LoaiCQ.KHAC // mở nhầm "Điểm thu hồi"
                    return
                }
                val ax = camX + rx; val ay = camY + ry
                chamBanDo += Pair(ax, ay)
                nha = ai.nha.firstOrNull { ax in it.x0..it.x1 && ay in it.y0..it.y1 }
                if (nha != null) man = LoaiCQ.POPUP
            }
            LoaiCQ.POPUP -> when {
                gan(x, y, p(1384f, 84f)) -> man = LoaiCQ.BAN_DO
                t!!.moCQ && gan(x, y, p(1150f, 975f)) -> quet(1, LoaiCQ.KET_QUA)
                t.moCQ && t.coBoi && gan(x, y, p(1380f, 975f)) -> if (t.conLai >= 10) { hoiSo = 10; man = LoaiCQ.HOI }
                t.moCQ && t.coBoi && gan(x, y, p(1220f, 975f)) -> if (t.conLai >= 5) { hoiSo = 5; man = LoaiCQ.HOI }
                gan(x, y, p(870f, 975f)) -> { man = LoaiCQ.TRAN; tranLan = 0 }
            }
            LoaiCQ.KET_QUA -> when {
                gan(x, y, p(1760f, 470f), 30f) -> if (t!!.conLai > 0 && theLuc >= 4) { t.conLai--; theLuc -= 4; demQuet++ }
                gan(x, y, p(1760f, 840f), 30f) -> man = LoaiCQ.BAN_DO
            }
            LoaiCQ.HOI -> if (gan(x, y, p(950f, 715f))) {
                if (hoiSo > 0 && t!!.conLai >= hoiSo && theLuc >= hoiSo * 4) { t.conLai -= hoiSo; theLuc -= hoiSo * 4; demQuet += hoiSo; man = LoaiCQ.QUET_LAI }
            }
            LoaiCQ.QUET_LAI -> when {
                gan(x, y, p(1200f, 900f)) -> { hoiSo = 10; man = LoaiCQ.HOI }
                gan(x, y, p(1760f, 840f)) -> man = LoaiCQ.POPUP
            }
            LoaiCQ.TRAN -> if (gan(x, y, p(1660f, 750f)) && ++tranLan >= 3) { t!!.moCQ = true; man = LoaiCQ.BAN_DO }
            LoaiCQ.CHUONG -> {
                // chạm vào toà nhà phía trên nhãn ải
                for (i in nuoc[nuocI].second.indices) {
                    val lx = (600f + i * 300f) * k; val ly = 700f * k
                    if (abs(x - lx) < 60f && y < ly - 20f && y > ly - 120f) {
                        aiI = i; camX = 0f; camY = 0f; man = LoaiCQ.BAN_DO; return
                    }
                }
                if (gan(x, y, p(1820f, 560f), 40f) && nuocI + 1 < nuoc.size) nuocI++
                if (gan(x, y, p(566f, 560f), 40f) && nuocI > 0) nuocI--
            }
            LoaiCQ.KHAC -> {}
        }
    }

    private fun quet(n: Int, sau: LoaiCQ) {
        val t = nha!!
        if (t.conLai >= n && theLuc >= 4 * n) { t.conLai -= n; theLuc -= 4 * n; demQuet += n; man = sau }
        else if (theLuc < 4 * n) { hoiSo = 0; man = LoaiCQ.HOI } // game hỏi mua thể lực
    }

    @Synchronized override fun vuot(x0: Float, y0: Float, x1: Float, y1: Float, ms: Long) {
        soVuot++
        if (man != LoaiCQ.BAN_DO) return
        camX = (camX - (x1 - x0) / k * tiLeKeo).coerceIn(0f, maxOf(0f, ai.rong - 2000f))
        camY = (camY - (y1 - y0) / k * tiLeKeo).coerceIn(0f, maxOf(0f, ai.cao - 1125f))
    }

    @Synchronized override fun quayLai() {
        man = when (man) {
            LoaiCQ.HOI -> if (hoiSo > 0) LoaiCQ.POPUP else LoaiCQ.BAN_DO
            LoaiCQ.POPUP, LoaiCQ.KET_QUA, LoaiCQ.QUET_LAI, LoaiCQ.KHAC -> LoaiCQ.BAN_DO
            LoaiCQ.BAN_DO -> LoaiCQ.CHUONG
            else -> man
        }
    }

    override fun ngu(ms: Long) {}
    override fun log(s: String) { println(s) }
    override fun homNay() = "2026-11-27"
}

class CanQuetTest {
    /** Bản đồ 2,2 × 2 màn, 6 toà nhà rải khắp (có cái ở góc xa). */
    private fun aiMau(seed: Int = 1, coBoi: Boolean = false) = AiGia(4400f, 2250f, listOf(
        ToaNha("Công xưởng", 700f, 400f, 950f, 620f, 20, coBoi = coBoi),
        ToaNha("Ngôi đình nhỏ", 1500f, 300f, 1720f, 520f, 15, coBoi = coBoi),
        ToaNha("Trường học", 3900f, 250f, 4150f, 480f, 12),
        ToaNha("Kho hàng", 600f, 1700f, 850f, 1950f, 8),
        ToaNha("Bến cảng", 3800f, 1750f, 4100f, 2000f, 10, coBoi = coBoi),
        ToaNha("Nhà máy", 2300f, 1000f, 2550f, 1250f, 9),
    ), seed)

    @Test
    fun quetHetBanDoKhongChamVungCam() {
        val g = GameCQ(listOf("Singapore" to listOf(aiMau())), camX0 = 1200f, camY0 = 500f) // bắt đầu giữa bản đồ
        val cq = CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false))
        cq.chay()
        val con = g.ai.nha.filter { it.conLai > 0 }.map { it.ten }
        assertTrue("còn lượt: $con", con.isEmpty())
        assertEquals(74, g.demQuet)
        assertEquals(g.demQuet, cq.soLan)
        assertTrue("chạm vùng cấm: ${g.chamCam}", g.chamCam.isEmpty())
        println("vuốt ${g.soVuot} lần, chạm ${g.soCham} lần")
        assertTrue("vuốt quá nhiều: ${g.soVuot}", g.soVuot <= 40)
    }

    @Test
    fun banDoKeoNhanhHoacChamHonNgonTay() {
        for (tl in listOf(1.6f, 0.6f)) {
            val g = GameCQ(listOf("Singapore" to listOf(aiMau(6))), camX0 = 1200f, camY0 = 500f, tiLeKeo = tl)
            val cq = CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false))
            cq.chay()
            assertTrue("kéo ×$tl còn: ${g.ai.nha.filter { it.conLai > 0 }.map { it.ten }}", g.ai.nha.all { it.conLai == 0 })
            assertTrue(g.chamCam.isEmpty())
        }
    }

    @Test
    fun docHutSoLanVanQuetHet() {
        val g = GameCQ(listOf("Singapore" to listOf(aiMau(7))), docHong = 0.5)
        val cq = CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false))
        cq.chay()
        assertTrue("còn: ${g.ai.nha.filter { it.conLai > 0 }.map { it.ten to it.conLai }}", g.ai.nha.all { it.conLai == 0 })
        assertEquals(74, g.demQuet)
    }

    @Test
    fun aiDaCoDuLieuThiKhongDoLai() {
        fun ai1() = AiGia(4400f, 2250f, listOf(ToaNha("A", 700f, 400f, 950f, 620f, 3), ToaNha("B", 1500f, 300f, 1720f, 520f, 3)), 21)
        val cd = CaiDatCQ(kieu = 1, quaAi = true)
        val g1 = GameCQ(listOf("Singapore" to listOf(ai1())), man = LoaiCQ.CHUONG)
        CanQuet(g1, cd).chay()
        assertEquals(setOf("A", "B"), cd.khuAi["Singapore 1"])
        // hôm sau: cùng ải, đã có dữ liệu → quét xong 2 khu là thôi, không vuốt khắp bản đồ
        cd.xong.clear()
        val g2 = GameCQ(listOf("Singapore" to listOf(ai1())), man = LoaiCQ.CHUONG)
        CanQuet(g2, cd).chay()
        assertTrue(g2.ai.nha.all { it.conLai == 0 })
        println("lần đầu vuốt ${g1.soVuot}, lần sau vuốt ${g2.soVuot}")
        assertTrue("lần sau phải ít vuốt hơn", g2.soVuot < g1.soVuot)
    }

    @Test
    fun quetX10RoiLe() {
        val g = GameCQ(listOf("Singapore" to listOf(aiMau(2, coBoi = true))))
        val cq = CanQuet(g, CaiDatCQ(kieu = 10, quaAi = false))
        cq.chay()
        assertTrue(g.ai.nha.all { it.conLai == 0 })
        assertEquals(74, g.demQuet)
        assertEquals(74, cq.soLan)
    }

    @Test
    fun hetTheLucThiDungKhongMua() {
        val g = GameCQ(listOf("Singapore" to listOf(aiMau(3))), theLuc = 40)
        val cq = CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false))
        cq.chay()
        assertEquals(10, g.demQuet)
        assertTrue(g.theLuc < 4)
    }

    @Test
    fun dungSauNLan() {
        val g = GameCQ(listOf("Singapore" to listOf(aiMau(4, coBoi = true))))
        val cq = CanQuet(g, CaiDatCQ(kieu = 10, quaAi = false, dungSau = 25))
        cq.chay()
        assertEquals(25, g.demQuet)
    }

    @Test
    fun thamHiemKhuChuaMo() {
        val a = aiMau(5)
        a.nha[0].moCQ = false
        val g = GameCQ(listOf("Singapore" to listOf(a)))
        CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false, thamHiem = true)).chay()
        assertEquals(0, a.nha[0].conLai)
    }

    @Test
    fun quaAiNhieuNuoc() {
        fun nho(seed: Int) = AiGia(2600f, 1300f, listOf(ToaNha("A$seed", 800f, 400f, 1050f, 640f, 5), ToaNha("B$seed", 2200f, 900f, 2450f, 1150f, 4)), seed)
        val g = GameCQ(listOf("Singapore" to listOf(nho(1), nho(2)), "Ai Cap" to listOf(nho(3), nho(4), nho(5))), man = LoaiCQ.CHUONG)
        val cd = CaiDatCQ(kieu = 1, quaAi = true)
        CanQuet(g, cd).chay()
        assertTrue(g.nuoc.all { (_, ds) -> ds.all { a -> a.nha.all { it.conLai == 0 } } })
        assertEquals(5, cd.xong.size)
        assertTrue(g.chamCam.isEmpty())
    }

    @Test
    fun nhieuBanDoNgauNhien() {
        for (seed in 10..17) {
            val r = Random(seed)
            val rong = 2000f + r.nextInt(0, 3) * 900f; val cao = 1125f + r.nextInt(0, 3) * 500f
            val ds = ArrayList<ToaNha>()
            repeat(5) { i ->
                // toà nhà không nằm dưới vùng cấm khi camera ở mép (đủ xa mép)
                val x = 400f + r.nextFloat() * (rong - 800f); val y = 300f + r.nextFloat() * (cao - 650f)
                if (ds.none { abs(it.x0 - x) < 400 && abs(it.y0 - y) < 350 }) ds += ToaNha("Khu$i", x, y, x + 240f, y + 220f, 3 + r.nextInt(8))
            }
            val tong = ds.sumOf { it.conLai }
            val a = AiGia(rong, cao, ds, seed)
            val g = GameCQ(listOf("X" to listOf(a)), camX0 = r.nextFloat() * rong, camY0 = r.nextFloat() * cao)
            val g0x = g.camX; val g0y = g.camY
            val cq = CanQuet(g, CaiDatCQ(kieu = 1, quaAi = false))
            cq.chay()
            assertTrue("seed $seed bản đồ ${rong}x$cao còn: ${ds.filter { it.conLai > 0 }.map { "${it.ten} ${it.x0},${it.y0}" }} camera đầu ${g0x},${g0y}", ds.all { it.conLai == 0 })
            assertEquals("seed $seed", tong, g.demQuet)
            assertTrue("seed $seed chạm vùng cấm", g.chamCam.isEmpty())
        }
    }
}
