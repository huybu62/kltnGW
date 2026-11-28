package vn.hoitu.canquet

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.canquet.core.DocCQ
import vn.hoitu.canquet.core.LoaiCQ
import vn.hoitu.canquet.core.ManCQ
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.abs

/** Ảnh chụp thật 1280×720 + chữ đọc bằng OCR (file .ocr.tsv). */
object MauCQ {
    fun anh(ten: String): Anh {
        val bi = ImageIO.read(File(javaClass.classLoader!!.getResource("$ten.jpg")!!.toURI()))
        return Anh(bi.width, bi.height, bi.getRGB(0, 0, bi.width, bi.height, null, 0, bi.width))
    }

    fun chu(ten: String): List<Chu> = File(javaClass.classLoader!!.getResource("$ten.ocr.tsv")!!.toURI()).readLines()
        .filter { it.isNotBlank() }.map { val p = it.split('\t'); Chu(p[4], p[0].toFloat(), p[1].toFloat(), p[2].toFloat(), p[3].toFloat()) }

    fun man(ten: String): ManCQ = anh(ten).let { DocCQ.doc(chu(ten), DocCQ.vungGame(it.w, it.h)) }
}

class DocCQTest {
    private fun gan(p: Pair<Float, Float>?, x: Float, y: Float, sai: Float = 40f) =
        p != null && abs(p.first - x) < sai && abs(p.second - y) < sai

    @Test
    fun banDo() {
        val m = MauCQ.man("ban_do")
        assertEquals(LoaiCQ.BAN_DO, m.loai)
        assertEquals(43, m.theLuc)
        assertEquals(120, m.theLucMax)
    }

    @Test
    fun banDoKhiChuDinhNhau() {
        // ML Kit hay đọc dính "Thể lực" với số, hoặc cả thanh EXP thành một dòng
        val goc = MauCQ.chu("ban_do").filter { it.text != "The luc" && it.text != "43/120" && it.text != "6253/9840" && it.text != "EXP" }
        val v = DocCQ.vungGame(1280, 720)
        for (dong in listOf("Thể lực 43/120", "EXP 6253/9840 Thể lực 43/120", "Thểlực43/120")) {
            val m = DocCQ.doc(goc + Chu(dong, 267f, 22f, 710f, 46f), v)
            assertEquals(dong, LoaiCQ.BAN_DO, m.loai)
            assertEquals(dong, 43, m.theLuc)
        }
        // không đọc được chữ Thể lực: vẫn nhận ra bản đồ nhờ Trở lại + nút đáy
        assertEquals(LoaiCQ.BAN_DO, DocCQ.doc(goc, v).loai)
    }

    @Test
    fun theLucDocDinhKyHieu() {
        assertEquals(Pair(176, 120), DocCQ.soPhanSo("17611/120", 999))
        assertEquals(Pair(78, 120), DocCQ.soPhanSo("7825/120", 360))
        assertEquals(Pair(43, 120), DocCQ.soPhanSo("43/120", 999))
    }

    @Test
    fun bangKhu() {
        val m = MauCQ.man("popup_khu")
        assertEquals(LoaiCQ.POPUP, m.loai)
        assertEquals("Cong xuong", m.ten)
        assertEquals(99, m.conLai)
        assertTrue("Càn quét", gan(m.nut["CAN_QUET"], 785f, 625f))
        assertTrue("Thám hiểm", gan(m.nut["THAM_HIEM"], 570f, 623f))
        assertTrue(m.nut["X5"] == null && m.nut["X10"] == null)

        val x = MauCQ.man("popup_x10")
        assertEquals(LoaiCQ.POPUP, x.loai)
        assertEquals("Ngoi dinh nho", x.ten)
        assertTrue("x5", gan(x.nut["X5"], 783f, 624f))
        assertTrue("x10", gan(x.nut["X10"], 881f, 623f))
        // nút X đỏ của bảng (ảnh 1280 rộng: góc phải trên bảng)
        assertTrue("X", gan(x.nut["DONG"], 886f, 54f))
    }

    @Test
    fun ketQua() {
        val m = MauCQ.man("ket_qua")
        assertEquals(LoaiCQ.KET_QUA, m.loai)
        assertEquals(98, m.conLai)
        // đầu lâu phía trên chữ "Càn quét lần nữa", dấu X phía trên chữ "Đóng"
        assertTrue("lần nữa ${m.nut["LAN_NUA"]}", gan(m.nut["LAN_NUA"], 1128f, 302f))
        assertTrue("đóng ${m.nut["DONG"]}", gan(m.nut["DONG"], 1125f, 542f))
    }

    @Test
    fun bangHoi() {
        for ((ten, so) in listOf("hoi_x10" to 10, "hoi_x5" to 5)) {
            val m = MauCQ.man(ten)
            assertEquals(ten, LoaiCQ.HOI, m.loai)
            assertTrue(ten, m.hoiCanQuet)
            assertEquals(so, m.hoiSo)
            assertNotNull(m.nut["XAC_DINH"])
        }
    }

    @Test
    fun manChuong() {
        val m = MauCQ.man("chuong")
        assertEquals(LoaiCQ.CHUONG, m.loai)
        assertEquals("Singapore", m.nuoc)
        assertEquals(listOf(1, 2, 3, 4), m.ai.map { it.so })
        val m2 = MauCQ.man("chuong2") // nhân vật che mất số ải 1
        assertEquals(listOf(1, 2, 3, 4), m2.ai.map { it.so })
        val ac = MauCQ.man("chuong_ai_cap")
        assertEquals("Ai Cap", ac.nuoc)
        assertEquals(listOf(1, 2, 3, 4), ac.ai.map { it.so })
        assertTrue(vn.hoitu.bansuc.core.VanBan.chuan(ac.ai.first { it.so == 1 }.chu).contains("LANDAU"))
    }

    @Test
    fun tranDanh() {
        val m = MauCQ.man("tran_danh")
        assertEquals(LoaiCQ.TRAN, m.loai)
        assertTrue(gan(m.nut["TIEN_LEN"], 1063f, 479f))
    }

    @Test
    fun doLechBanDo() {
        // dịch ảnh bản đồ đi một đoạn đã biết, đo lại
        val a = MauCQ.anh("ban_do")
        val dx = 96; val dy = 48 // điểm ảnh (ảnh 1280 rộng) → chuẩn ×(2000/1280)
        val b = Anh(a.w, a.h, IntArray(a.w * a.h) { i -> val x = i % a.w + dx; val y = i / a.w + dy; if (x < a.w && y < a.h) a.px[y * a.w + x] else 0 })
        val d = DocCQ.doLech(DocCQ.xamNho(a), DocCQ.xamNho(b))
        assertNotNull(d)
        // nội dung dịch sang trái/lên: (-dx, -dy) theo chuẩn
        assertEquals(-dx * 2000f / 1280f, d!!.first, 12f)
        assertEquals(-dy * 2000f / 1280f, d.second, 12f)
    }

    @Test
    fun vungCam() {
        // icon "Điểm thu hồi" góc trái dưới và chữ của nó nằm trong vùng cấm
        assertTrue(DocCQ.trongVungCam(74f / 0.64f, 676f / 0.64f))
        assertTrue(DocCQ.trongVungCam(120f / 0.64f, 600f / 0.64f))
        assertTrue(DocCQ.trongVungCam(900f / 0.64f, 640f / 0.64f)) // Đồng đội
        assertTrue(!DocCQ.trongVungCam(640f / 0.64f, 300f / 0.64f)) // toà nhà giữa bản đồ
    }

    @Test
    fun hangNutDocDinhMotDong() {
        // ML Kit hay đọc cả hàng nút thành một dòng: "Thám hiểm Càn quét x5 x10"
        val goc = MauCQ.chu("popup_x10").filter { it.y0 < 600f }
        val v = DocCQ.vungGame(1280, 720)
        val m = DocCQ.doc(goc + Chu("Thám hiểm   Càn quét   x5   x10", 413f, 607f, 910f, 643f), v)
        assertEquals(LoaiCQ.POPUP, m.loai)
        assertTrue("càn quét ${m.nut["CAN_QUET"]}", gan(m.nut["CAN_QUET"], 647f, 625f, 70f))
        assertTrue("thám hiểm ${m.nut["THAM_HIEM"]}", gan(m.nut["THAM_HIEM"], 483f, 625f, 70f))
        assertTrue("x5 ${m.nut["X5"]}", gan(m.nut["X5"], 783f, 625f, 70f))
        assertTrue("x10 ${m.nut["X10"]}", gan(m.nut["X10"], 881f, 625f, 70f))
    }

    @Test
    fun manKetQuaCanQuetXong() {
        // ảnh người chơi: "Càn quét lần nữa" đọc lệch ("Canquetlanmia"), Số lần 1/3, Đóng
        val m = MauCQ.man("ket_qua_2")
        assertEquals(LoaiCQ.KET_QUA, m.loai)
        assertEquals(1, m.conLai)
        assertTrue("đóng ${m.nut["DONG"]}", gan(m.nut["DONG"], 1125f, 542f, 45f))
        // không đọc được chữ "Càn quét lần nữa" chút nào: vẫn nhận ra nhờ "Số lần: N/M" / "Đóng"
        val v = DocCQ.vungGame(1280, 720)
        val m2 = DocCQ.doc(MauCQ.chu("ket_qua_2").filter { !it.text.startsWith("Canquet") }, v)
        assertEquals(LoaiCQ.KET_QUA, m2.loai)
        assertTrue("lần nữa ${m2.nut["LAN_NUA"]}", gan(m2.nut["LAN_NUA"], 1127f, 300f, 50f))
        assertTrue("đóng ${m2.nut["DONG"]}", gan(m2.nut["DONG"], 1125f, 542f, 45f))
    }
}
