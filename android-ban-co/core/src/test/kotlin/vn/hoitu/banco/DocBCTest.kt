package vn.hoitu.banco

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.banco.core.DocBC
import vn.hoitu.banco.core.LoaiBC
import vn.hoitu.banco.core.O
import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.Chu
import java.io.File
import javax.imageio.ImageIO
import kotlin.math.abs

/** Ảnh chụp thật (thu về 1600 rộng như app chụp) + chữ đọc bằng OCR (.ocr.tsv). */
object MauBC {
    private fun file(ten: String) = File(javaClass.classLoader!!.getResource(ten)!!.toURI())
    fun anh(ten: String): Anh {
        val bi = ImageIO.read(file(ten))
        return Anh(bi.width, bi.height, bi.getRGB(0, 0, bi.width, bi.height, null, 0, bi.width))
    }
    fun chu(ten: String): List<Chu> = file("$ten.ocr.tsv").readLines().filter { it.isNotBlank() }
        .map { val p = it.split('\t'); Chu(p[4], p[0].toFloat(), p[1].toFloat(), p[2].toFloat(), p[3].toFloat()) }
    fun man(ten: String) = anh("$ten.jpg").let { DocBC.doc(chu(ten), DocBC.vungGame(it)) }

    /** Vùng chữ trên ảnh thẻ người dùng cắt gửi. */
    fun chuTrenThe(ten: String): FloatArray {
        val a = anh(ten)
        return DocBC.hinhChu(a.cat((a.w * 0.2).toInt(), (a.h * 0.1).toInt(), (a.w * 0.8).toInt(), (a.h * 0.66).toInt()))!!
    }
}

class DocBCTest {
    @Test
    fun vungGame() {
        val v = DocBC.vungGame(MauBC.anh("mo_bai.jpg"))
        assertTrue(v.toList().toString(), abs(v[1] - 84) <= 6 && abs(v[2] - 1600) <= 8)
    }

    @Test
    fun mauKhopVoiAnhGoc() {
        // mẫu trong code phải đúng là hình lấy từ ảnh người dùng gửi
        fun hex(f: FloatArray) = f.joinToString("") { Integer.toHexString((it * 15f + 0.5f).toInt().coerceIn(0, 15)) }
        val t = MauBC.chuTrenThe("tuong.png"); val s = MauBC.chuTrenThe("soai.png")
        println("TUONG=" + hex(t)); println("SOAI=" + hex(s))
        assertTrue(DocBC.ncc(t, DocBC.MAU_TUONG) > 0.98f)
        assertTrue(DocBC.ncc(s, DocBC.MAU_SOAI) > 0.98f)
    }

    @Test
    fun nhanCacMan() {
        assertEquals(LoaiBC.BANG, MauBC.man("mo_bai").loai)
        assertEquals(LoaiBC.BANG, MauBC.man("up_bai").loai)
        val mua = MauBC.man("mua")
        assertEquals(LoaiBC.MUA, mua.loai)
        assertNotNull(mua.takeAway)
        assertTrue(abs(mua.takeAway!!.first - 1385) < 60 && abs(mua.takeAway!!.second - 967) < 40)
        val tm = MauBC.man("hoi_tao_moi")
        assertEquals(LoaiBC.HOI_TAO_MOI, tm.loai)
        assertEquals(20, tm.giaHoi)
        assertEquals(LoaiBC.HOI_TAKE_AWAY, MauBC.man("hoi_take_away").loai)
    }

    @Test
    fun docNamODau() {
        val a = MauBC.anh("mo_bai.jpg") // 炮 炮 士 车 车
        val h = DocBC.docHang(a)
        assertEquals(h.toString() + " " + h.diem, List(5) { O.CO }, h.o)
        assertEquals(5, h.soCo)
        println("DIEM mo_bai=${h.diem}")
        val up = DocBC.docHang(MauBC.anh("up_bai.jpg"))
        assertTrue(up.toString(), up.up)
        val soai = DocBC.docHang(MauBC.anh("hoi_tao_moi.jpg")) // 象 兵 士 帅 兵 (ảnh tối vì hộp thoại)
        println("DIEM soai=${soai.diem}")
        assertEquals(soai.toString() + " " + soai.diem, listOf(O.CO, O.CO, O.CO, O.SOAI, O.CO), soai.o)
    }

    @Test
    fun docTuongDanVaoBan() {
        // dán ảnh thẻ 将 người dùng gửi vào ô 1 của bàn thật
        val a = MauBC.anh("mo_bai.jpg")
        val the = MauBC.anh("tuong.png")
        val v = DocBC.vungGame(a); val k = v[2] / DocBC.REF_W
        val co = (84 * k).toInt() // cỡ ô
        val nho = the.doiCo((the.w * co / the.h.toFloat()).toInt(), co)
        val px = a.px.copyOf()
        val x0 = (v[0] + DocBC.O_X[0] * k - nho.w / 2f).toInt(); val y0 = (v[1] + DocBC.O_Y * k - co / 2f).toInt()
        for (y in 0 until nho.h) for (x in 0 until nho.w) px[(y0 + y) * a.w + x0 + x] = nho.px[y * nho.w + x] or (0xFF shl 24)
        val h = DocBC.docHang(Anh(a.w, a.h, px))
        assertEquals(h.toString() + " " + h.diem, O.TUONG, h.o[0])
        assertTrue(h.coTuongSoai)
        println("DIEM dan=${h.diem}")
    }
}
