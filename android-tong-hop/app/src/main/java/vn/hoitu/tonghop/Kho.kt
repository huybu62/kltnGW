package vn.hoitu.tonghop

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import vn.hoitu.bansuc.core.CaiDat as CaiDatBS
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.He
import vn.hoitu.vongquay.core.CaiDat as CaiDatVQ
import vn.hoitu.vongquay.core.Loai
import vn.hoitu.vongquay.core.MauMon

/** Nhật ký chung của các tool: giữ 100 dòng gần nhất. */
object NhatKy {
    private val dong = ArrayDeque<String>()
    private val gio = SimpleDateFormat("HH:mm:ss", Locale.US)
    var khiDoi: (() -> Unit)? = null

    @Synchronized fun ghi(s: String) {
        dong.addLast("${gio.format(Date())} $s")
        while (dong.size > 100) dong.removeFirst()
        khiDoi?.invoke()
    }

    @Synchronized fun tatCa(): List<String> = dong.toList()
    @Synchronized fun xoa() { dong.clear(); khiDoi?.invoke() }
}

/** Lưu cài đặt của từng tool. */
object Kho {
    // ---------- Vòng quay ----------
    private const val VQ = "vong_quay"

    fun docVQ(ctx: Context): CaiDatVQ {
        val p = ctx.getSharedPreferences(VQ, Context.MODE_PRIVATE)
        val muon = (p.getStringSet("muon", null) ?: Loai.values().map { it.name }.toSet())
            .mapNotNull { runCatching { Loai.valueOf(it) }.getOrNull() }.toMutableSet()
        return CaiDatVQ(
            dem = p.getInt("dem", 0), moc = p.getInt("moc", 73), taoMoiToiDa = p.getInt("tao_moi_toi_da", 60),
            dungSau = p.getInt("dung_sau", 0), muon = muon, nhip = p.getInt("nhip", 80),
        )
    }

    fun luuVQ(ctx: Context, cd: CaiDatVQ) {
        ctx.getSharedPreferences(VQ, Context.MODE_PRIVATE).edit()
            .putInt("dem", cd.dem).putInt("moc", cd.moc).putInt("tao_moi_toi_da", cd.taoMoiToiDa)
            .putInt("dung_sau", cd.dungSau).putInt("nhip", cd.nhip).putStringSet("muon", cd.muon.map { it.name }.toSet())
            .apply()
    }

    private fun anhTuBitmap(bm: Bitmap): vn.hoitu.vongquay.core.Anh {
        val px = IntArray(bm.width * bm.height)
        bm.getPixels(px, 0, bm.width, 0, 0, bm.width, bm.height)
        return vn.hoitu.vongquay.core.Anh(bm.width, bm.height, px)
    }

    fun bitmap(w: Int, h: Int, px: IntArray): Bitmap = Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)

    private fun docAsset(ctx: Context, ten: String) = ctx.assets.open("$ten.png").use { anhTuBitmap(BitmapFactory.decodeStream(it)) }
    private fun fileMau(ctx: Context, loai: Loai) = File(ctx.filesDir, "mau_${loai.name}.png")

    fun mauX1(ctx: Context) = docAsset(ctx, "x1")

    fun mauMon(ctx: Context): Map<Loai, MauMon> = Loai.values().associateWith { loai ->
        val f = fileMau(ctx, loai)
        val anh = if (f.exists()) BitmapFactory.decodeFile(f.path)?.let { anhTuBitmap(it) } else null
        MauMon(anh ?: docAsset(ctx, when (loai) { Loai.PHIEU_HUY_DIET -> "phieu_huy_diet"; Loai.DA_VAN_MENH -> "da_van_menh"; Loai.TUONG -> "tuong" }))
    }

    fun luuMau(ctx: Context, loai: Loai, a: vn.hoitu.vongquay.core.Anh) {
        FileOutputStream(fileMau(ctx, loai)).use { bitmap(a.w, a.h, a.px).compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    fun xoaMauRieng(ctx: Context) = Loai.values().forEach { fileMau(ctx, it).delete() }

    // ---------- Càn quét ----------
    private const val CQ = "can_quet"

    fun docCQ(ctx: Context): vn.hoitu.canquet.core.CaiDatCQ {
        val p = ctx.getSharedPreferences(CQ, Context.MODE_PRIVATE)
        // bản cũ ghi nhầm ải vào không được là "đã xong" → xoá danh sách ải đã xong một lần
        if (!p.getBoolean("da_xoa_xong_v2", false)) p.edit().remove("xong").putBoolean("da_xoa_xong_v2", true).commit()
        return vn.hoitu.canquet.core.CaiDatCQ(
            kieu = p.getInt("kieu", 10), quaAi = p.getBoolean("qua_ai", true), nguoc = p.getBoolean("nguoc", false),
            thamHiem = p.getBoolean("tham_hiem", false), dungSau = p.getInt("dung_sau", 0), nhipMs = p.getInt("nhip", 150),
            ngay = p.getString("ngay", "")!!, xong = (p.getStringSet("xong", null) ?: emptySet()).toMutableSet(),
            khuAi = (p.getStringSet("khu_ai", null) ?: emptySet()).mapNotNull { it.split('\t').takeIf { x -> x.size == 2 } }
                .groupBy({ it[0] }, { it[1] }).mapValues { it.value.toMutableSet() }.toMutableMap(),
        )
    }

    fun luuCQ(ctx: Context, cd: vn.hoitu.canquet.core.CaiDatCQ) {
        ctx.getSharedPreferences(CQ, Context.MODE_PRIVATE).edit()
            .putInt("kieu", cd.kieu).putBoolean("qua_ai", cd.quaAi).putBoolean("nguoc", cd.nguoc)
            .putBoolean("tham_hiem", cd.thamHiem).putInt("dung_sau", cd.dungSau).putInt("nhip", cd.nhipMs)
            .putString("ngay", cd.ngay).putStringSet("xong", cd.xong.toSet())
            .putStringSet("khu_ai", cd.khuAi.flatMap { (ai, ds) -> ds.map { "$ai\t$it" } }.toSet())
            .apply()
    }

    // ---------- Bàn Cờ Lửa ----------
    private const val BC = "ban_co"

    /** (xu muốn tiêu, cài đặt) */
    fun docBC(ctx: Context): Pair<Int, vn.hoitu.banco.core.CaiDatBC> {
        val p = ctx.getSharedPreferences(BC, Context.MODE_PRIVATE)
        val xu = p.getInt("xu", 6000)
        return Pair(xu, vn.hoitu.banco.core.CaiDatBC(soLan = p.getInt("so_lan", vn.hoitu.banco.core.CaiDatBC.soLanTuXu(xu)), choTH3 = p.getBoolean("cho_th3", false), canTaoMoi = p.getBoolean("can_tao_moi", false)))
    }

    fun luuBC(ctx: Context, xu: Int, cd: vn.hoitu.banco.core.CaiDatBC) {
        ctx.getSharedPreferences(BC, Context.MODE_PRIVATE).edit()
            .putInt("xu", xu).putInt("so_lan", cd.soLan).putBoolean("cho_th3", cd.choTH3).putBoolean("can_tao_moi", cd.canTaoMoi).apply()
    }

    fun homNay(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    // ---------- Ban sức ----------
    private const val BS = "ban_suc"

    data class CachNhap(var tuyChinh: Boolean = false, var soBo: Int = 1, var coBan: ChiSo = ChiSo.PHONG)

    fun docBS(ctx: Context): CaiDatBS {
        val p = ctx.getSharedPreferences(BS, Context.MODE_PRIVATE)
        val cn = docCachNhap(ctx)
        val sl = mutableMapOf<ChiSo, Int>()
        if (cn.tuyChinh) for (cs in ChiSo.values()) sl[cs] = p.getInt("sl_${cs.name}", 0)
        else { for (cs in ChiSo.values()) sl[cs] = 0; sl[ChiSo.HP] = cn.soBo * 3; sl[cn.coBan] = cn.soBo }
        return CaiDatBS(
            he = runCatching { He.valueOf(p.getString("he", He.LANHCHUA.name)!!) }.getOrDefault(He.LANHCHUA),
            mucTieu = p.getString("muc_tieu", "A")!!.firstOrNull() ?: 'A',
            soLuong = sl,
            nhaMayLv6 = p.getBoolean("nha_may_lv6", false),
            nghiMs = p.getInt("nghi_ms", 600),
        )
    }

    /** Số viên tùy chỉnh (chỉ dùng khi bật tùy chỉnh). */
    fun docSoTuyChinh(ctx: Context): MutableMap<ChiSo, Int> {
        val p = ctx.getSharedPreferences(BS, Context.MODE_PRIVATE)
        return ChiSo.values().associateWith { p.getInt("sl_${it.name}", if (it == ChiSo.HP) 3 else if (it == ChiSo.PHONG) 1 else 0) }.toMutableMap()
    }

    fun luuBS(ctx: Context, cd: CaiDatBS, tuyChinh: Map<ChiSo, Int>?) {
        val e = ctx.getSharedPreferences(BS, Context.MODE_PRIVATE).edit()
            .putString("he", cd.he.name).putString("muc_tieu", cd.mucTieu.toString())
            .putBoolean("nha_may_lv6", cd.nhaMayLv6).putInt("nghi_ms", cd.nghiMs)
        tuyChinh?.forEach { (cs, n) -> e.putInt("sl_${cs.name}", n) }
        e.apply()
    }

    fun docCachNhap(ctx: Context): CachNhap {
        val p = ctx.getSharedPreferences(BS, Context.MODE_PRIVATE)
        return CachNhap(
            p.getBoolean("tuy_chinh", false), p.getInt("so_bo", 1),
            runCatching { ChiSo.valueOf(p.getString("co_ban", ChiSo.PHONG.name)!!) }.getOrDefault(ChiSo.PHONG),
        )
    }

    fun luuCachNhap(ctx: Context, c: CachNhap) {
        ctx.getSharedPreferences(BS, Context.MODE_PRIVATE).edit()
            .putBoolean("tuy_chinh", c.tuyChinh).putInt("so_bo", c.soBo).putString("co_ban", c.coBan.name).apply()
    }
}
