package vn.hoitu.bansuc.core

import java.text.Normalizer

/** Một dòng chữ đọc được trên màn hình (toạ độ màn hình/ảnh chụp). */
data class Chu(val text: String, val x0: Float, val y0: Float, val x1: Float, val y1: Float) {
    val cx get() = (x0 + x1) / 2
    val cy get() = (y0 + y1) / 2
}

/** Hệ ban sức. [ma] là tên đã bỏ dấu, viết hoa, liền nhau (để so với chữ đọc được). */
enum class He(val ten: String) {
    LANHCHUA("Lãnh Chúa"), TINHTHAN("Tinh Thần"), HUYDIET("Hủy Diệt"), AETHER("Aether"), TITAN("Titan"),
    THANTHU("Thần Thư"), CONLAC("Con Lắc"), QUANGNIEN("Quang Niên"), KHOINGUYEN("Khởi Nguyên"), VUONGTOA("Vương Tọa");

    val ma get() = name
}

/** Loại chỉ số của đá (phần cuối tên đá, vd "-HP", "-Phòng"). */
enum class ChiSo(val ten: String, val dau: String) {
    HP("HP", "HP"), PHONG("Phòng thủ", "PHON"), TOCDO("Tốc độ", "TOC"), VATCONG("Vật công", "VAT"), MACONG("Ma công", "MA");
}

/** Phẩm chất, thấp → cao. */
object Pham {
    const val THU_TU = "DCBAS"
    fun hang(p: Char?): Int = if (p == null) -1 else THU_TU.indexOf(p)
    fun datToi(p: Char?, muc: Char) = hang(p) >= hang(muc)
}

object VanBan {
    /** Bỏ dấu, Đ→D, viết hoa, chỉ giữ chữ và số. */
    fun chuan(s: String): String {
        val n = Normalizer.normalize(
            s.replace('Đ', 'D').replace('đ', 'd').replace('Ð', 'D').replace('ð', 'd').replace('Ɖ', 'D').replace('ɖ', 'd'),
            Normalizer.Form.NFD,
        )
        val b = StringBuilder()
        for (c in n) {
            if (Character.getType(c) == Character.NON_SPACING_MARK.toInt()) continue
            val u = c.uppercaseChar()
            if (u in 'A'..'Z' || u in '0'..'9') b.append(u)
        }
        return b.toString()
    }

    /** Khoảng cách sửa nhỏ nhất giữa [mau] và một đoạn bất kỳ trong [s] (tìm gần đúng). */
    fun khoangCachDoan(mau: String, s: String): Int {
        if (mau.isEmpty()) return 0
        var truoc = IntArray(s.length + 1) // hàng 0: 0 hết (bắt đầu ở đâu cũng được)
        for (i in 1..mau.length) {
            val nay = IntArray(s.length + 1)
            nay[0] = i
            for (j in 1..s.length) {
                val c = if (mau[i - 1] == s[j - 1]) 0 else 1
                nay[j] = minOf(truoc[j - 1] + c, truoc[j] + 1, nay[j - 1] + 1)
            }
            truoc = nay
        }
        return truoc.min()
    }

    fun coGanDung(mau: String, s: String, toiDa: Int = maxOf(1, mau.length / 4)) = khoangCachDoan(mau, s) <= toiDa

    /** Hệ xuất hiện trong chữ (đã chuẩn hoá), chọn hệ khớp nhất. */
    fun timHe(n: String): He? {
        var tot: He? = null; var diem = Int.MAX_VALUE
        for (h in He.values()) {
            val d = khoangCachDoan(h.ma, n)
            if (d <= maxOf(1, h.ma.length / 4) && (d < diem || (d == diem && h.ma.length > (tot?.ma?.length ?: 0)))) {
                tot = h; diem = d
            }
        }
        return tot
    }

    /** Chỉ số từ phần sau dấu "-" cuối cùng của tên đá (có thể bị cắt cụt, vd "Vật Cô"). */
    fun timChiSo(tho: String): ChiSo? {
        val i = tho.lastIndexOf('-')
        val duoi = chuan(if (i >= 0) tho.substring(i + 1) else tho)
        if (i >= 0) ChiSo.values().firstOrNull { duoi.startsWith(it.dau) }?.let { return it }
        // không đọc được dấu "-": xem đuôi tên (có thể cụt, vd "VATCO")
        val n = chuan(tho)
        val day = mapOf(ChiSo.HP to "HP", ChiSo.PHONG to "PHONG", ChiSo.TOCDO to "TOCDO", ChiSo.VATCONG to "VATCONG", ChiSo.MACONG to "MACONG")
        var tot: ChiSo? = null; var dai = 0
        for ((cs, du) in day) for (l in du.length downTo (if (cs == ChiSo.HP) 2 else 3)) {
            if (n.endsWith(du.take(l)) && l > dai) { tot = cs; dai = l }
        }
        return tot
    }
}
