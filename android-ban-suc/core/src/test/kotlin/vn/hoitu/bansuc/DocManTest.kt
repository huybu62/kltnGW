package vn.hoitu.bansuc

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.Da
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.He
import vn.hoitu.bansuc.core.HieuQua
import vn.hoitu.bansuc.core.LoaiMan
import vn.hoitu.bansuc.core.ManHinh
import java.io.File
import javax.imageio.ImageIO

/** Ảnh chụp thật (thu về rộng 1600, có viền đen) + chữ đọc được bằng OCR (file .ocr.tsv). */
object Mau {
    fun anh(ten: String): Anh {
        val bi = ImageIO.read(File(javaClass.classLoader!!.getResource("$ten.png")!!.toURI()))
        return Anh(bi.width, bi.height, bi.getRGB(0, 0, bi.width, bi.height, null, 0, bi.width))
    }

    fun chu(ten: String): List<Chu> = File(javaClass.classLoader!!.getResource("$ten.ocr.tsv")!!.toURI()).readLines()
        .filter { it.isNotBlank() }.map { val p = it.split('\t'); Chu(p[4], p[0].toFloat(), p[1].toFloat(), p[2].toFloat(), p[3].toFloat()) }

    fun man(ten: String, coAnh: Boolean = true): ManHinh {
        val a = anh(ten)
        return DocMan.doc(chu(ten), if (coAnh) a else null, DocMan.vungGame(a))
    }
}

class DocManTest {
    @Test
    fun docTenDa() {
        assertEquals(Da(6, 'A', He.LANHCHUA, ChiSo.PHONG), DocMan.docTenDa("LV6A·Lãnh Chúa-Phòng"))
        assertEquals(Da(5, null, null, ChiSo.HP), DocMan.docTenDa("LV5Đá Vận Mệnh-HP"))
        assertEquals(Da(6, 'C', He.LANHCHUA, ChiSo.HP), DocMan.docTenDa("LV6C-LanhChua-HP"))
        assertEquals(Da(4, null, null, ChiSo.VATCONG), DocMan.docTenDa("LV4DaVanMenh-VatCo"))
        assertEquals(Da(4, null, null, ChiSo.TOCDO), DocMan.docTenDa("LV4Đá Vận Mệnh-Tốc Đ"))
        assertEquals(Da(6, 'D', He.AETHER, ChiSo.HP), DocMan.docTenDa("LV6D·Aether-HP"))
        assertEquals(Da(6, 'S', He.TINHTHAN, ChiSo.MACONG), DocMan.docTenDa("LV6S·Tinh Thần-Ma Công"))
        // chữ Đ bị đọc thành ký tự khác / mất / cách rời
        for (t in listOf("LV5Ðá Vận Mệnh-HP", "LV5á Vận Mệnh-HP", "LV5 Dá Van Menh - HP", "LV5Da VanMenh-HP", "LV5Đá Vận Mệnh-HP Quy"))
            assertEquals(t, Da(5, null, null, ChiSo.HP), DocMan.docTenDa(t))
    }

    @Test
    fun docHieuQua() {
        assertEquals(HieuQua('C', He.LANHCHUA), DocMan.docHieuQua("CLanh Chua"))
        assertEquals(HieuQua('B', He.LANHCHUA), DocMan.docHieuQua("B·Lãnh Chúa"))
        assertEquals(HieuQua(null, null), DocMan.docHieuQua("KhongcohieuquaBanSirc"))
        assertEquals(HieuQua('A', He.THANTHU), DocMan.docHieuQua("A·Thần Thư"))
    }

    @Test
    fun manChinh() {
        val m = Mau.man("chinh_lv5")
        assertEquals(LoaiMan.CHINH, m.loai)
        assertEquals(Da(5, null, null, ChiSo.HP), m.daChon)
        assertEquals(
            listOf(Da(6, 'A', He.LANHCHUA, ChiSo.PHONG), Da(6, 'C', He.LANHCHUA, ChiSo.HP), Da(6, null, null, ChiSo.HP), Da(5, null, null, ChiSo.HP)),
            m.hang.map { it.da },
        )
        assertEquals(listOf(false, false, false, true), m.hang.map { it.daChon })
        // chạm vào hàng: nằm trong danh sách bên trái (ảnh 1600 rộng, vùng game bắt đầu y≈84)
        for (h in m.hang) assertTrue(h.x in 250f..650f && h.y in 280f..800f)

        // màn chính sau khi game tự đóng bảng Điểm Hóa (có nút nổi của app ở góc trên trái)
        val sau = Mau.man("chinh_sau_diem_hoa")
        assertEquals(LoaiMan.CHINH, sau.loai)
        assertEquals(Da(6, 'C', He.LANHCHUA, ChiSo.HP), sau.daChon)
        assertEquals(Da(6, 'C', He.LANHCHUA, ChiSo.HP), sau.hang.first { it.daChon }.da)

        // cuối danh sách (toàn LV4), đá đang chọn là LV5 nằm ngoài trang đang xem; nút nổi của app đè lên mép trên
        val cuoi = Mau.man("chinh_cuoi_ds")
        assertEquals(LoaiMan.CHINH, cuoi.loai)
        assertEquals(Da(5, null, null, ChiSo.HP), cuoi.daChon)
        assertTrue(cuoi.hang.all { it.da.lv == 4 })

        val m4 = Mau.man("chinh_lv4")
        assertEquals(listOf(ChiSo.PHONG, ChiSo.HP, ChiSo.TOCDO, ChiSo.VATCONG), m4.hang.map { it.da.chiSo })
        assertTrue(m4.hang.all { it.da.lv == 4 && it.da.pham == null })
    }

    @Test
    fun bangDiemHoaVaThacAn() {
        val trong = Mau.man("diem_hoa_trong")
        assertEquals(LoaiMan.DIEM_HOA, trong.loai)
        assertEquals(HieuQua('C', He.LANHCHUA), trong.hien)
        assertEquals(false, trong.daThem)

        val co = Mau.man("diem_hoa_co_da")
        assertEquals(LoaiMan.DIEM_HOA, co.loai)
        assertEquals(HieuQua('C', He.LANHCHUA), co.hien)
        assertEquals(HieuQua('B', He.LANHCHUA), co.sau)
        assertEquals(true, co.daThem)

        val ta = Mau.man("thac_an")
        assertEquals(LoaiMan.THAC_AN, ta.loai)
        assertEquals(HieuQua('C', He.LANHCHUA), ta.hien)
        assertEquals(HieuQua(null, null), ta.sau)
        assertEquals(false, ta.daThem)
    }

    @Test
    fun bangChonDa() {
        for (coAnh in listOf(true, false)) {
            val m1 = Mau.man("chon_diem_hoa_1", coAnh)
            assertEquals(LoaiMan.CHON_DA, m1.loai)
            val t1 = m1.the.associate { Pair(it.he, it.bac) to it.soLuong }
            println(m1.the)
            assertEquals("ảnh=$coAnh", setOf(
                Pair(He.LANHCHUA, 1), Pair(He.TINHTHAN, 1), Pair(He.HUYDIET, 2),
                Pair(He.AETHER, 1), Pair(He.TITAN, 1), Pair(He.HUYDIET, 1), Pair(He.THANTHU, 1),
            ), t1.keys)
            assertTrue(m1.the.none { it.daIn })

            val m2 = Mau.man("chon_diem_hoa_2", coAnh)
            println(m2.the)
            assertEquals(setOf(He.CONLAC, He.QUANGNIEN, He.KHOINGUYEN, He.VUONGTOA), m2.the.map { it.he }.toSet())
            assertTrue(m2.the.all { it.bac == 1 })
        }
        val di = Mau.man("chon_da_in")
        assertEquals(LoaiMan.CHON_DA, di.loai)
        assertEquals(setOf(1, 2, 3), di.the.map { it.bac }.toSet())
        assertTrue(di.the.all { it.daIn })
        val ss = di.the.first { it.bac == 2 }
        assertNotNull(ss)
        assertEquals(1639, ss.soLuong)
    }
}
