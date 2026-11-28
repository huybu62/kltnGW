package vn.hoitu.banco

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.banco.core.BanCo
import vn.hoitu.banco.core.CaiDatBC
import vn.hoitu.banco.core.DocBC
import vn.hoitu.banco.core.HangDau
import vn.hoitu.banco.core.LoaiBC
import vn.hoitu.banco.core.ManBC
import vn.hoitu.banco.core.O
import vn.hoitu.banco.core.ThietBiBC
import kotlin.math.abs

/** Game giả: các bàn lần lượt theo [bans]; Tẩy úp bàn, Mua mở bảng, Take-away + OK lấy hết, Tạo mới + OK sang bàn kế. */
class GameBC(private val bans: List<List<O>>, var xu: Int = 1_000_000) : ThietBiBC {
    private val vung = intArrayOf(0, 0, 2000, 1125)
    var ban = 0
    var up = false
    var daLay = false // bàn hiện tại đã Take-away
    var man = LoaiBC.BANG
    val nhatKy = ArrayList<String>()
    var tayBiLo = 0 // số lần bấm Tẩy đầu tiên game không nhận
    var soTakeAway = 0; var soTaoMoi = 0; var xuTaoMoi = 0
    private var vuaLay = false

    private fun gan(x: Float, y: Float, p: Pair<Float, Float>, d: Float = 40f) = abs(x - p.first) < d && abs(y - p.second) < d

    override fun nhin() = ManBC(man, vung, takeAway = if (man == LoaiBC.MUA) DocBC.TAKE_AWAY else null,
        giaHoi = if (man == LoaiBC.HOI_TAO_MOI) (if (vuaLay) 0 else 20) else null)

    override fun hang(): HangDau? = when {
        man != LoaiBC.BANG -> HangDau(List(5) { O.KHAC })
        up || daLay -> HangDau(List(5) { O.UP })
        else -> HangDau(bans[ban % bans.size])
    }

    override fun cham(x: Float, y: Float) {
        when (man) {
            LoaiBC.BANG -> when {
                gan(x, y, DocBC.TAY) -> { if (tayBiLo > 0) tayBiLo-- else { up = true; nhatKy += "tay $ban" } }
                gan(x, y, DocBC.MUA) -> man = LoaiBC.MUA
                gan(x, y, DocBC.TAO_MOI) -> man = LoaiBC.HOI_TAO_MOI
            }
            LoaiBC.MUA -> when {
                gan(x, y, DocBC.TAKE_AWAY) -> man = LoaiBC.HOI_TAKE_AWAY
                gan(x, y, DocBC.CHO_TRONG, 200f) -> man = LoaiBC.BANG
            }
            LoaiBC.HOI_TAKE_AWAY -> when {
                gan(x, y, DocBC.OK) -> {
                    assertTrue("Take-away khi chưa Tẩy", up); assertFalse("Take-away 2 lần một bàn", daLay)
                    xu -= CaiDatBC.GIA; soTakeAway++; daLay = true; vuaLay = true; nhatKy += "lay $ban"; man = LoaiBC.MUA
                }
                gan(x, y, DocBC.HUY) -> man = LoaiBC.MUA
            }
            LoaiBC.HOI_TAO_MOI -> when {
                gan(x, y, DocBC.OK) -> {
                    val g = if (vuaLay) 0 else 20
                    xu -= g; xuTaoMoi += g; soTaoMoi++; vuaLay = false
                    ban++; up = false; daLay = false; man = LoaiBC.BANG; nhatKy += "moi $ban"
                }
                gan(x, y, DocBC.HUY) -> man = LoaiBC.BANG
            }
            else -> {}
        }
    }

    override fun ngu(ms: Long) {}
    override fun log(s: String) { println(s) }
}

class BanCoTest {
    private val xau = List(5) { O.CO } // 5 ô cờ, không Tướng/Soái
    private val tuong = listOf(O.CO, O.TUONG, O.CO, O.CO, O.CO)
    private val soai = listOf(O.CO, O.CO, O.CO, O.CO, O.SOAI)
    private val bon = listOf(O.CO, O.CO, O.KHAC, O.CO, O.CO) // 4 ô đỏ + đá vận mệnh

    @Test
    fun soLanTuXu() {
        assertEquals(1, CaiDatBC.soLanTuXu(6000))
        assertEquals(2, CaiDatBC.soLanTuXu(6001))
        assertEquals(17, CaiDatBC.soLanTuXu(100000)) // 102000 ≥ 100000
        assertEquals(0, CaiDatBC.soLanTuXu(0))
    }

    @Test
    fun th1RoiTh3RoiTimTiep() {
        // bàn 0 xấu, 1 xấu, 2 có Tướng (TH1) → lấy; bàn 3 lấy luôn (TH3); bàn 4 xấu; bàn 5 có Soái → lấy
        val g = GameBC(listOf(xau, xau, tuong, xau, xau, soai, xau, xau))
        val cd = CaiDatBC(soLan = 3)
        val b = BanCo(g, cd)
        b.chay()
        assertEquals(listOf("lay 2", "lay 3", "lay 5"), g.nhatKy.filter { it.startsWith("lay") })
        assertEquals(3, b.daLay)
        assertTrue(cd.choTH3) // lần cuối là TH1 → lần chạy sau lấy luôn bàn kế
        // Tạo mới: 0→1 (20), 1→2 (20), 2→3 (miễn phí), 3→4 (miễn phí), 4→5 (20), 5→6 (miễn phí)
        assertEquals(60, g.xuTaoMoi)
        assertEquals(60, b.xuTaoMoi)
        assertEquals(1_000_000 - 3 * 6000 - 60, g.xu)
    }

    @Test
    fun th2BonODo() {
        val g = GameBC(listOf(xau, bon, xau))
        BanCo(g, CaiDatBC(soLan = 1)).chay()
        assertEquals(listOf("lay 1"), g.nhatKy.filter { it.startsWith("lay") })
    }

    @Test
    fun choTh3TuLanTruoc() {
        val g = GameBC(listOf(xau, xau))
        val cd = CaiDatBC(soLan = 1, choTH3 = true)
        BanCo(g, cd).chay()
        assertEquals(listOf("lay 0"), g.nhatKy.filter { it.startsWith("lay") })
        assertFalse(cd.choTH3)
    }

    @Test
    fun tayKhongAnThiBamLai() {
        val g = GameBC(listOf(tuong, xau))
        g.tayBiLo = 1
        BanCo(g, CaiDatBC(soLan = 1)).chay()
        assertEquals(1, g.soTakeAway)
    }

    @Test
    fun batDauKhiDangMoBangMua() {
        val g = GameBC(listOf(xau, soai, xau))
        g.man = LoaiBC.MUA
        BanCo(g, CaiDatBC(soLan = 1)).chay()
        assertEquals(listOf("lay 1"), g.nhatKy.filter { it.startsWith("lay") })
    }
}
