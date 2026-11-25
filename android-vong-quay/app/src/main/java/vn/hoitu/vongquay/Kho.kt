package vn.hoitu.vongquay

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import vn.hoitu.vongquay.core.Anh
import vn.hoitu.vongquay.core.CaiDat
import vn.hoitu.vongquay.core.Loai
import vn.hoitu.vongquay.core.MauMon
import java.io.File
import java.io.FileOutputStream

/** Lưu cài đặt và mẫu món (mẫu người chơi tự chọn ghi đè mẫu có sẵn). */
object Kho {
    private const val TEN = "vong_quay"

    fun docCaiDat(ctx: Context): CaiDat {
        val p = ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE)
        val muon = (p.getStringSet("muon", null) ?: Loai.values().map { it.name }.toSet())
            .mapNotNull { runCatching { Loai.valueOf(it) }.getOrNull() }.toMutableSet()
        return CaiDat(
            dem = p.getInt("dem", 0),
            moc = p.getInt("moc", 73),
            taoMoiToiDa = p.getInt("tao_moi_toi_da", 60),
            dungSau = p.getInt("dung_sau", 0),
            muon = muon,
        )
    }

    fun luuCaiDat(ctx: Context, cd: CaiDat) {
        ctx.getSharedPreferences(TEN, Context.MODE_PRIVATE).edit()
            .putInt("dem", cd.dem).putInt("moc", cd.moc).putInt("tao_moi_toi_da", cd.taoMoiToiDa)
            .putInt("dung_sau", cd.dungSau).putStringSet("muon", cd.muon.map { it.name }.toSet())
            .apply()
    }

    fun anhTuBitmap(bm: Bitmap): Anh {
        val px = IntArray(bm.width * bm.height)
        bm.getPixels(px, 0, bm.width, 0, 0, bm.width, bm.height)
        return Anh(bm.width, bm.height, px)
    }

    fun bitmapTuAnh(a: Anh): Bitmap = Bitmap.createBitmap(a.px, a.w, a.h, Bitmap.Config.ARGB_8888)

    private fun docAsset(ctx: Context, ten: String): Anh =
        ctx.assets.open("$ten.png").use { anhTuBitmap(BitmapFactory.decodeStream(it)) }

    private fun fileMau(ctx: Context, loai: Loai) = File(ctx.filesDir, "mau_${loai.name}.png")

    fun mauX1(ctx: Context): Anh = docAsset(ctx, "x1")

    private fun asset(loai: Loai) = when (loai) {
        Loai.PHIEU_HUY_DIET -> "phieu_huy_diet"
        Loai.DA_VAN_MENH -> "da_van_menh"
        Loai.TUONG -> "tuong"
    }

    fun mauMon(ctx: Context): Map<Loai, MauMon> = Loai.values().associateWith { loai ->
        val f = fileMau(ctx, loai)
        val anh = if (f.exists()) BitmapFactory.decodeFile(f.path)?.let { anhTuBitmap(it) } else null
        MauMon(anh ?: docAsset(ctx, asset(loai)))
    }

    fun coMauRieng(ctx: Context, loai: Loai) = fileMau(ctx, loai).exists()

    fun luuMau(ctx: Context, loai: Loai, a: Anh) {
        FileOutputStream(fileMau(ctx, loai)).use { bitmapTuAnh(a).compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    fun xoaMauRieng(ctx: Context) = Loai.values().forEach { fileMau(ctx, it).delete() }
}
