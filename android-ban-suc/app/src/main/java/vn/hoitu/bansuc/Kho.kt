package vn.hoitu.bansuc

import android.content.Context
import android.graphics.Bitmap
import vn.hoitu.bansuc.core.Anh
import vn.hoitu.bansuc.core.CaiDat
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.He

/** Lưu cài đặt. Ngoài [CaiDat] còn lưu cách nhập số lượng (theo bộ hay tùy chỉnh) để hiện lại cho đúng. */
object Kho {
    private const val TEN = "ban_suc"

    data class CachNhap(var tuyChinh: Boolean = false, var soBo: Int = 1, var coBan: ChiSo = ChiSo.PHONG)

    fun docCaiDat(ctx: Context): CaiDat {
        val p = ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE)
        val sl = mutableMapOf<ChiSo, Int>()
        for (cs in ChiSo.values()) {
            val mac = when (cs) { ChiSo.HP -> 3; ChiSo.PHONG -> 1; else -> 0 }
            sl[cs] = p.getInt("sl_${cs.name}", mac)
        }
        return CaiDat(
            he = runCatching { He.valueOf(p.getString("he", He.LANHCHUA.name)!!) }.getOrDefault(He.LANHCHUA),
            mucTieu = p.getString("muc_tieu", "A")!!.firstOrNull() ?: 'A',
            soLuong = sl,
            nhaMayLv6 = p.getBoolean("nha_may_lv6", false),
            nghiMs = p.getInt("nghi_ms", 600),
        )
    }

    fun luuCaiDat(ctx: Context, cd: CaiDat) {
        val e = ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE).edit()
            .putString("he", cd.he.name).putString("muc_tieu", cd.mucTieu.toString())
            .putBoolean("nha_may_lv6", cd.nhaMayLv6).putInt("nghi_ms", cd.nghiMs)
        for (cs in ChiSo.values()) e.putInt("sl_${cs.name}", cd.soLuong[cs] ?: 0)
        e.apply()
    }

    fun docCachNhap(ctx: Context): CachNhap {
        val p = ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE)
        return CachNhap(
            p.getBoolean("tuy_chinh", false), p.getInt("so_bo", 1),
            runCatching { ChiSo.valueOf(p.getString("co_ban", ChiSo.PHONG.name)!!) }.getOrDefault(ChiSo.PHONG),
        )
    }

    fun luuCachNhap(ctx: Context, c: CachNhap) {
        ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE).edit()
            .putBoolean("tuy_chinh", c.tuyChinh).putInt("so_bo", c.soBo).putString("co_ban", c.coBan.name).apply()
    }

    fun bitmapTuAnh(a: Anh): Bitmap = Bitmap.createBitmap(a.px, a.w, a.h, Bitmap.Config.ARGB_8888)
}
