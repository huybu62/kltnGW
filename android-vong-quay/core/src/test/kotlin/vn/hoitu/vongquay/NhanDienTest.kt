package vn.hoitu.vongquay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.vongquay.core.Anh
import vn.hoitu.vongquay.core.CaiDat
import vn.hoitu.vongquay.core.Loai
import vn.hoitu.vongquay.core.MauMon
import vn.hoitu.vongquay.core.NhanDien
import vn.hoitu.vongquay.core.ThietBi
import vn.hoitu.vongquay.core.VongQuay
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.abs

/** Kiểm tra trên ảnh chụp thật màn Vòng quay liên server (cỡ gốc 2000×1293 có viền đen, và cỡ 1600×900). */
class NhanDienTest {
    private fun doc(f: File): Anh {
        val bi = ImageIO.read(f)
        return Anh(bi.width, bi.height, bi.getRGB(0, 0, bi.width, bi.height, null, 0, bi.width))
    }

    private fun anhTest(ten: String) = doc(File(javaClass.classLoader!!.getResource("$ten.png")!!.toURI()))
    private fun asset(ten: String) = doc(File("../app/src/main/assets/$ten.png"))

    private val x1 = asset("x1")
    private val mau = mapOf(
        Loai.PHIEU_HUY_DIET to MauMon(asset("phieu_huy_diet")),
        Loai.DA_VAN_MENH to MauMon(asset("da_van_menh")),
        Loai.TUONG to MauMon(asset("tuong")),
    )

    @Test
    fun nhanRaManVongQuay() {
        for (c in listOf("", "_1600")) {
            for (t in listOf("vq_a", "vq_b", "vq_c")) assertNotNull("$t$c", NhanDien.timVong(anhTest("$t$c"), x1))
            assertNull("danh sách quà$c", NhanDien.timVong(anhTest("vq_ket_qua$c"), x1))
        }
    }

    @Test
    fun nhanRaMonThat() {
        val mong = mapOf(
            // ảnh a: rương M (trên-trái), Vegeta (trái-dưới); rương đỏ-bạc trên-phải KHÔNG phải đá vận mệnh
            "vq_a" to mapOf("trên-trái" to Loai.PHIEU_HUY_DIET, "trái-dưới" to Loai.TUONG),
            // ảnh b: Cell có nhãn Hạn định nhưng là tướng giả; rương M đang sáng xanh ở trái-dưới
            "vq_b" to mapOf("trái-dưới" to Loai.PHIEU_HUY_DIET),
            // ảnh c: rương M trái-dưới; tướng tóc trắng dưới-phải là tướng thường
            "vq_c" to mapOf("trái-dưới" to Loai.PHIEU_HUY_DIET),
        )
        for (c in listOf("", "_1600")) for ((t, dung) in mong) {
            val a = anhTest("$t$c")
            val neo = NhanDien.timVong(a, x1)!!
            val kq = NhanDien.monTrenVong(a, neo, mau).associate { it.ten to it.loai }
            for ((o, loai) in kq) assertEquals("$t$c ô $o", dung[o], loai)
        }
    }

    /**
     * Game giả: màn vòng quay (lần lượt các vòng khi Tạo mới), hoạt ảnh quay, danh sách quà sau khi bấm x10.
     * Mỗi lần quay thật, vòng đổi sang ảnh kế tiếp trong [sauQuay] (khác "Điểm hiện tại", giống game thật).
     * [nhay]: sau khi tắt danh sách quà, màn hình nháy thêm vài khung không phải vòng quay (kiểu hiệu ứng),
     * là lý do bản cũ đếm gấp đôi.
     */
    private inner class GameGia(
        var vong: String, val taoMoi: MutableList<String>, val sauQuay: MutableList<String>, val nhay: Int = 0,
    ) : ThietBi {
        var danhSach = false
        var quay = 0 // số khung hình hoạt ảnh quay còn lại (chạm chỗ trống thì bỏ qua)
        var conNhay = 0
        var soBoHoatAnh = 0
        var soX10 = 0
        var soTaoMoi = 0
        val log = mutableListOf<String>()
        val dem = mutableListOf<Int>()
        private val anh = HashMap<String, Anh>()
        private fun lay(t: String) = anh.getOrPut(t) { anhTest(t) }

        override fun chup(): Anh {
            if (conNhay > 0) { conNhay--; return lay("vq_ket_qua_1600") }
            if (quay > 0 && --quay == 0) xongQuay()
            return anhHien()
        }
        private fun xongQuay() { danhSach = true; if (sauQuay.isNotEmpty()) vong = sauQuay.removeAt(0) }
        private fun anhHien() = if (danhSach) lay("vq_ket_qua_1600") else lay("${vong}_1600")
        override fun cham(x: Float, y: Float) {
            val a = anhHien()
            val (tx, ty) = NhanDien.choTrong(a)
            val trong = abs(x - tx) < 30 && abs(y - ty) < 30
            if (danhSach) { if (trong) { danhSach = false; conNhay = nhay }; return }
            if (quay > 0) { if (trong) { quay = 0; xongQuay(); soBoHoatAnh++ }; return }
            val neo = NhanDien.timVong(a, x1) ?: return
            val (bx, by) = neo.ra(NhanDien.NUT_X10.first, NhanDien.NUT_X10.second)
            val (mx, my) = neo.ra(NhanDien.NUT_TAO_MOI.first, NhanDien.NUT_TAO_MOI.second)
            if (abs(x - bx) < 40 && abs(y - by) < 25) { soX10++; quay = 20 }
            else if (abs(x - mx) < 40 && abs(y - my) < 25) { soTaoMoi++; if (taoMoi.isNotEmpty()) vong = taoMoi.removeAt(0) }
        }
        override fun ngu(ms: Long) {}
        override fun log(s: String) { log += s; println(s) }
        override fun luu(cd: CaiDat) { dem += cd.dem }
    }

    @Test
    fun toiMocThiTaoMoiRaMonDaChon() {
        // đang 70/73; chỉ muốn TƯỚNG. Quay 71 (b→c), 72 (c→b). Mốc: b chỉ có tướng giả Cell → Tạo mới → c → Tạo mới → a (Vegeta)
        val g = GameGia("vq_b", mutableListOf("vq_c", "vq_a"), mutableListOf("vq_c", "vq_b", "vq_b", "vq_c"))
        val cd = CaiDat(dem = 70, moc = 73, dungSau = 4, muon = mutableSetOf(Loai.TUONG))
        VongQuay(g, cd, x1, mau).chay()
        assertEquals(4, g.soX10)
        assertEquals(2, g.soTaoMoi)
        assertEquals(listOf(71, 72, 0, 1), g.dem)
        assertTrue(g.log.any { "Tướng hạn định" in it })
    }

    @Test
    fun chuaToiMocThiKhongTaoMoi() {
        val g = GameGia("vq_c", mutableListOf(), mutableListOf("vq_b", "vq_c", "vq_b"))
        val cd = CaiDat(dem = 10, moc = 73, dungSau = 3)
        VongQuay(g, cd, x1, mau).chay()
        assertEquals(3, g.soX10)
        assertEquals(0, g.soTaoMoi)
        assertEquals(listOf(11, 12, 13), g.dem)
        assertEquals(3, g.soBoHoatAnh) // chạm chỗ trống để bỏ hoạt ảnh quay
    }

    @Test
    fun manHinhNhaySauDanhSachQuaKhongDemGapDoi() {
        val g = GameGia("vq_c", mutableListOf(), mutableListOf("vq_b", "vq_c", "vq_b", "vq_c"), nhay = 2)
        val cd = CaiDat(dem = 0, moc = 73, dungSau = 4)
        VongQuay(g, cd, x1, mau).chay()
        assertEquals(4, g.soX10)
        assertEquals(listOf(1, 2, 3, 4), g.dem)
    }

    @Test
    fun bamKhongAnThiKhongDem() {
        // điểm không bao giờ đổi (vòng giữ nguyên) và không có danh sách quà → không được đếm
        val g = object : ThietBi {
            val a = anhTest("vq_c_1600")
            var dem = mutableListOf<Int>()
            override fun chup() = a
            override fun cham(x: Float, y: Float) {}
            override fun ngu(ms: Long) {}
            override fun log(s: String) { println(s) }
            override fun luu(cd: CaiDat) { dem += cd.dem }
        }
        val cd = CaiDat(dem = 5)
        VongQuay(g, cd, x1, mau).chay()
        assertTrue(g.dem.isEmpty())
        assertEquals(5, cd.dem)
    }
}
