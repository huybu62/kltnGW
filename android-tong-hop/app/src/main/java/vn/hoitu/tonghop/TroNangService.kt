package vn.hoitu.tonghop

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.CheckBox
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import vn.hoitu.bansuc.core.BanSuc
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.He
import vn.hoitu.bansuc.core.ManHinh
import vn.hoitu.vongquay.core.Loai
import vn.hoitu.vongquay.core.NhanDien
import vn.hoitu.vongquay.core.VongQuay
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import vn.hoitu.bansuc.core.ThietBi as ThietBiBS
import vn.hoitu.vongquay.core.CaiDat as CaiDatVQ
import vn.hoitu.vongquay.core.ThietBi as ThietBiVQ

/**
 * Dịch vụ Trợ năng của Hội Tụ Auto: bong bóng nổi → danh sách tool → bảng cài đặt + Chạy/Dừng,
 * nhật ký. Thực hiện chạm/vuốt và đọc chữ (ML Kit, chạy trên máy) cho các tool.
 */
class TroNangService : AccessibilityService() {
    private val ui = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private lateinit var bongBong: TextView
    private lateinit var lpBong: WindowManager.LayoutParams
    private lateinit var chip: TextView
    private lateinit var lpChip: WindowManager.LayoutParams
    private var bang: View? = null // bảng đang mở (menu / cài đặt / nhật ký)
    private var lpBang: WindowManager.LayoutParams? = null

    private enum class Tool(val ten: String, val bieuTuong: String) { CQ("Càn quét bản đồ", "🗺"), VQ("Vòng quay liên server", "🎡"), BS("Ban sức vận mệnh", "💎") }

    private var dangChay: Tool? = null
    private var luong: Thread? = null
    private var vq: VongQuay? = null
    private var bs: BanSuc? = null
    private var cq: vn.hoitu.canquet.core.CanQuet? = null
    private var docChu: TextRecognizer? = null
    private var capNhatBang: (() -> Unit)? = null

    override fun onServiceConnected() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        taoBongBong()
        NhatKy.khiDoi = { ui.post { capNhatBang?.invoke() } }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        dung()
        for (v in listOf(bang, if (::bongBong.isInitialized) bongBong else null, if (::chip.isInitialized) chip else null)) v?.let { runCatching { wm.removeView(it) } }
        docChu?.close()
        super.onDestroy()
    }

    // ================= giao diện =================
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun nen(mau: Int, bo: Float = 12f) = GradientDrawable().apply { setColor(mau); cornerRadius = dp(bo.toInt()).toFloat() }

    private fun thamSo(x: Int, y: Int, w: Int = WindowManager.LayoutParams.WRAP_CONTENT) = WindowManager.LayoutParams(
        w, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.START; this.x = x; this.y = y }

    private fun chu(s: String, co: Float = 13f, dam: Boolean = false, mau: Int = Color.WHITE) = TextView(this).apply {
        text = s; textSize = co; setTextColor(mau); if (dam) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(3), 0, dp(3))
    }

    private fun nut(s: String, mau: Int = Color.rgb(70, 70, 90), bam: () -> Unit) = Button(this).apply {
        text = s; textSize = 13f; isAllCaps = false; setTextColor(Color.WHITE)
        background = nen(mau, 8f); minHeight = dp(36); minimumHeight = dp(36); minWidth = dp(36); minimumWidth = dp(36)
        setPadding(dp(10), 0, dp(10), 0)
        setOnClickListener { bam() }
    }

    private fun hang(vararg v: View) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        for (x in v) addView(x, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) })
    }

    /** Ô số có nút − / + (không cần bàn phím). */
    private fun oSo(nhan: String, giaTri: () -> Int, buoc: Int, min: Int, max: Int, dat: (Int) -> Unit, buocLon: Int = 0): View {
        val so = chu("", 15f, true).apply { minWidth = dp(54); gravity = Gravity.CENTER }
        fun hien() { so.text = giaTri().toString() }
        fun doi(d: Int) { dat((giaTri() + d).coerceIn(min, max)); hien() }
        val v = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            addView(chu(nhan).apply { minWidth = dp(120) })
            if (buocLon > 0) addView(nut("−$buocLon") { doi(-buocLon) })
            addView(nut("−") { doi(-buoc) }); addView(so); addView(nut("+") { doi(buoc) })
            if (buocLon > 0) addView(nut("+$buocLon") { doi(buocLon) })
        }
        hien()
        return v
    }

    /** Ô chọn vòng (◀ giá trị ▶). */
    private fun <T> oChon(nhan: String, ds: List<T>, ten: (T) -> String, giaTri: () -> T, dat: (T) -> Unit): View {
        val gt = chu("", 14f, true).apply { minWidth = dp(110); gravity = Gravity.CENTER }
        fun hien() { gt.text = ten(giaTri()) }
        fun doi(d: Int) { dat(ds[(ds.indexOf(giaTri()) + d + ds.size) % ds.size]); hien() }
        hien()
        return hang(chu(nhan).apply { minWidth = dp(120) }, nut("◀") { doi(-1) }, gt, nut("▶") { doi(1) })
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun taoBongBong() {
        bongBong = TextView(this).apply {
            text = "⚙"; textSize = 22f; gravity = Gravity.CENTER; setTextColor(Color.WHITE)
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(230, 110, 60, 200)); setStroke(dp(2), Color.WHITE) }
            width = dp(50); height = dp(50)
        }
        lpBong = thamSo(dp(4), dp(8))
        chip = TextView(this).apply {
            textSize = 11f; setTextColor(Color.WHITE); background = nen(Color.argb(200, 20, 20, 28), 8f)
            setPadding(dp(8), dp(4), dp(8), dp(4)); maxWidth = dp(240); maxLines = 2; visibility = View.GONE
        }
        lpChip = thamSo(dp(58), dp(14))
        var dx = 0f; var dy = 0f; var x0 = 0f; var y0 = 0f; var keo = false
        bongBong.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { dx = lpBong.x - e.rawX; dy = lpBong.y - e.rawY; x0 = e.rawX; y0 = e.rawY; keo = false }
                MotionEvent.ACTION_MOVE -> {
                    if (abs(e.rawX - x0) + abs(e.rawY - y0) > dp(8)) keo = true
                    if (keo) {
                        lpBong.x = (e.rawX + dx).toInt(); lpBong.y = (e.rawY + dy).toInt(); wm.updateViewLayout(bongBong, lpBong)
                        lpChip.x = lpBong.x + dp(54); lpChip.y = lpBong.y + dp(6); wm.updateViewLayout(chip, lpChip)
                    }
                }
                MotionEvent.ACTION_UP -> if (!keo) bamBongBong()
            }
            true
        }
        wm.addView(chip, lpChip)
        wm.addView(bongBong, lpBong)
    }

    private fun trangThai(s: String) = ui.post {
        chip.text = s
        chip.visibility = if (dangChay != null) View.VISIBLE else View.GONE
    }

    private fun capNhatBongBong() {
        val t = dangChay
        bongBong.text = t?.bieuTuong ?: "⚙"
        (bongBong.background as GradientDrawable).setColor(if (t != null) Color.argb(230, 30, 150, 70) else Color.argb(230, 110, 60, 200))
        chip.visibility = if (t != null) View.VISIBLE else View.GONE
    }

    private fun bamBongBong() {
        if (bang != null) { dongBang(); return }
        val t = dangChay
        if (t != null) moTool(t) else moMenu()
    }

    private fun dongBang() {
        bang?.let { runCatching { wm.removeView(it) } }
        bang = null; capNhatBang = null
    }

    private fun hienBang(noiDung: View, rong: Int = dp(340)) {
        dongBang()
        val khung = ScrollView(this).apply {
            background = nen(Color.argb(240, 28, 26, 38)); setPadding(dp(12), dp(10), dp(12), dp(10))
            addView(noiDung)
        }
        val man = resources.displayMetrics
        val lp = thamSo(dp(60), dp(8), minOf(rong, man.widthPixels - dp(70)))
        lp.height = minOf(WindowManager.LayoutParams.WRAP_CONTENT, man.heightPixels - dp(16)).let { if (it <= 0) WindowManager.LayoutParams.WRAP_CONTENT else it }
        wm.addView(khung, lp)
        lpBang = lp
        // không cho bảng cao quá màn hình
        khung.post {
            if (khung.height > man.heightPixels - dp(16)) { lp.height = man.heightPixels - dp(16); wm.updateViewLayout(khung, lp) }
        }
        bang = khung
    }

    private fun cot(vararg v: View) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        for (x in v) addView(x)
    }

    private fun moMenu() {
        val c = cot(chu("Hội Tụ Auto", 17f, true), chu("Chọn tool:", 12f, mau = Color.LTGRAY))
        for (t in Tool.values()) c.addView(nut("${t.bieuTuong}  ${t.ten}") { moTool(t) }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)).apply { setMargins(0, dp(3), 0, dp(3)) })
        c.addView(hang(nut("📜 Nhật ký") { moNhatKy(null) }, nut("✕ Đóng") { dongBang() }))
        hienBang(c, dp(300))
    }

    private fun moNhatKy(quayVe: Tool?) {
        val noi = chu("", 11f, mau = Color.rgb(220, 220, 220)).apply { setTextIsSelectable(false) }
        val c = cot(chu("📜 Nhật ký (100 dòng gần nhất)", 15f, true), noi,
            hang(nut("Xoá") { NhatKy.xoa() }, nut("‹ Quay lại") { if (quayVe != null) moTool(quayVe) else moMenu() }, nut("✕") { dongBang() }))
        fun hien() { noi.text = NhatKy.tatCa().reversed().joinToString("\n").ifEmpty { "(trống)" } }
        hien()
        hienBang(c, dp(420))
        capNhatBang = { hien() }
    }

    private fun moTool(t: Tool) {
        when (t) {
            Tool.CQ -> moCQ()
            Tool.VQ -> moVQ()
            Tool.BS -> moBS()
        }
    }

    private fun dongChay(t: Tool, chay: () -> Unit): View {
        val chayDay = dangChay
        return when {
            chayDay == t -> nut("■ Dừng", Color.rgb(180, 50, 50)) { dung() }
            chayDay != null -> chu("Đang chạy ${chayDay.ten} – dừng trước khi chạy tool khác", 12f, mau = Color.rgb(255, 200, 120))
            else -> nut("▶ Chạy", Color.rgb(30, 140, 70)) { chay() }
        }
    }

    // ---------- Vòng quay ----------
    private fun moVQ() {
        val cd = Kho.docVQ(this)
        fun luu() = Kho.luuVQ(this, cd)
        val dangChayVQ = dangChay == Tool.VQ
        val c = cot(chu("🎡 Vòng quay liên server", 16f, true))
        val trangThaiChu = chu(NhatKy.tatCa().lastOrNull() ?: "", 11f, mau = Color.LTGRAY)
        if (dangChayVQ) {
            c.addView(chu("Đang chạy – dừng để sửa cài đặt", 12f, mau = Color.rgb(255, 200, 120)))
            val demChu = chu("Đã bấm x10: ${cd.dem}/${cd.moc}", 15f, true)
            c.addView(demChu)
            capNhatBang = { val m = Kho.docVQ(this); demChu.text = "Đã bấm x10: ${m.dem}/${m.moc}"; trangThaiChu.text = NhatKy.tatCa().lastOrNull() ?: "" }
        } else {
            c.addView(oSo("Đã bấm x10:", { cd.dem }, 1, 0, 999, { cd.dem = it.coerceAtMost(cd.moc - 1); luu() }, buocLon = 10))
            c.addView(oSo("Mốc:", { cd.moc }, 1, 1, 999, { cd.moc = it; cd.dem = cd.dem.coerceAtMost(it - 1); luu() }))
            c.addView(oSo("Tạo mới tối đa:", { cd.taoMoiToiDa }, 10, 0, 500, { cd.taoMoiToiDa = it; luu() }))
            c.addView(oSo("Dừng sau (0 = không):", { cd.dungSau }, 10, 0, 9999, { cd.dungSau = it; luu() }))
            c.addView(oSo("Nghỉ chạm (ms):", { cd.nhip }, 10, 20, 1000, { cd.nhip = it; luu() }))
            c.addView(chu("Ở lượt mốc, Tạo mới tới khi có:", 12f, mau = Color.LTGRAY))
            for (loai in Loai.values()) c.addView(CheckBox(this).apply {
                text = loai.ten; setTextColor(Color.WHITE); isChecked = loai in cd.muon
                setOnCheckedChangeListener { _, b -> if (b) cd.muon.add(loai) else if (cd.muon.size > 1) cd.muon.remove(loai) else isChecked = true; luu() }
            })
        }
        c.addView(hang(dongChay(Tool.VQ) { chayVQ() }, nut("Mẫu") { moChonMau() }, nut("📜") { moNhatKy(Tool.VQ) }, nut("‹") { moMenu() }, nut("✕") { dongBang() }))
        c.addView(trangThaiChu)
        hienBang(c, dp(400))
        if (!dangChayVQ) capNhatBang = { trangThaiChu.text = NhatKy.tatCa().lastOrNull() ?: "" }
    }

    private fun chayVQ() {
        if (!coChup()) return
        val cd: CaiDatVQ = Kho.docVQ(this)
        val tb = object : ThietBiVQ {
            override fun chup() = ChupManHinhService.instance?.chup()?.vq()
            override fun cham(x: Float, y: Float) = this@TroNangService.cham(x, y, 15)
            override fun ngu(ms: Long) = Thread.sleep(ms)
            override fun log(s: String) = this@TroNangService.log(s)
            override fun luu(cd: CaiDatVQ) { Kho.luuVQ(this@TroNangService, cd); trangThai("🎡 x10: ${cd.dem}/${cd.moc}"); ui.post { capNhatBang?.invoke() } }
        }
        val v = VongQuay(tb, cd, Kho.mauX1(this), Kho.mauMon(this))
        vq = v
        batDau(Tool.VQ) { v.chay() }
        trangThai("🎡 x10: ${cd.dem}/${cd.moc}")
    }

    /** Chọn ô trên vòng quay đang hiện làm mẫu món hạn định (tướng mới / Đá vận mệnh). */
    private fun moChonMau() {
        if (dangChay != null) { Toast.makeText(this, "Dừng tool trước khi chọn mẫu", Toast.LENGTH_SHORT).show(); return }
        if (!coChup()) return
        dongBang()
        ui.postDelayed({
            val a = ChupManHinhService.instance?.chup()?.vq()
            val neo = a?.let { NhanDien.timVong(it, Kho.mauX1(this)) }
            if (a == null || neo == null) { Toast.makeText(this, "Mở màn Vòng quay liên server trước", Toast.LENGTH_LONG).show(); return@postDelayed }
            val luoi = GridLayout(this).apply { columnCount = 4 }
            for (ten in NhanDien.O.keys) {
                val o = NhanDien.catO(a, neo, ten)
                luoi.addView(ImageView(this).apply {
                    setImageBitmap(Kho.bitmap(o.w, o.h, o.px))
                    layoutParams = GridLayout.LayoutParams().apply { width = dp(60); height = dp(62); setMargins(dp(3), dp(3), dp(3), dp(3)) }
                    setOnClickListener {
                        val c2 = cot(chu("Ô này là món nào?", 14f, true), ImageView(this@TroNangService).apply { setImageBitmap(Kho.bitmap(o.w, o.h, o.px)) })
                        for (loai in Loai.values()) c2.addView(nut(loai.ten) { Kho.luuMau(this@TroNangService, loai, o); Toast.makeText(this@TroNangService, "Đã lưu mẫu ${loai.ten}", Toast.LENGTH_SHORT).show(); moVQ() })
                        c2.addView(hang(nut("Xoá mẫu tự chọn") { Kho.xoaMauRieng(this@TroNangService); moVQ() }, nut("‹") { moVQ() }))
                        hienBang(c2, dp(300))
                    }
                })
            }
            hienBang(cot(chu("Chạm ô chứa món hạn định thật để làm mẫu:", 13f, true), luoi, hang(nut("‹ Quay lại") { moVQ() })), dp(320))
        }, 300) // chờ bảng đóng hẳn rồi mới chụp
    }

    // ---------- Ban sức ----------
    private fun moBS() {
        val cd = Kho.docBS(this)
        val cn = Kho.docCachNhap(this)
        val tc = Kho.docSoTuyChinh(this)
        fun luu() { Kho.luuCachNhap(this, cn); Kho.luuBS(this, cd, tc) }
        val c = cot(chu("💎 Ban sức vận mệnh", 16f, true))
        val trangThaiChu = chu(NhatKy.tatCa().lastOrNull() ?: "", 11f, mau = Color.LTGRAY)
        if (dangChay == Tool.BS) {
            c.addView(chu("Đang chạy: ${cd.mucTieu}·${cd.he.ten} – dừng để sửa cài đặt", 12f, mau = Color.rgb(255, 200, 120)))
        } else {
            c.addView(oChon("Hệ:", He.values().toList(), { it.ten }, { cd.he }) { cd.he = it; luu() })
            c.addView(oChon("Phẩm mục tiêu:", listOf('A', 'S'), { if (it == 'A') "A (dùng B-SS)" else "S (dùng A-SSS)" }, { cd.mucTieu }) { cd.mucTieu = it; luu() })
            c.addView(CheckBox(this).apply {
                text = "Nhà máy LV6: viên đang ở A thì Thác Ấn SSS rồi điểm hóa lại"; setTextColor(Color.WHITE); isChecked = cd.nhaMayLv6
                setOnCheckedChangeListener { _, b -> cd.nhaMayLv6 = b; luu() }
            })
            val khungSo = cot()
            fun veSo() {
                khungSo.removeAllViews()
                if (cn.tuyChinh) for (cs in ChiSo.values()) khungSo.addView(oSo("${cs.ten}:", { tc[cs] ?: 0 }, 1, 0, 99, { tc[cs] = it; luu() }))
                else {
                    khungSo.addView(oSo("Số bộ (1 cơ bản + 3 HP):", { cn.soBo }, 1, 0, 50, { cn.soBo = it; luu() }))
                    khungSo.addView(oChon("Đá cơ bản:", listOf(ChiSo.PHONG, ChiSo.TOCDO, ChiSo.VATCONG, ChiSo.MACONG), { it.ten }, { cn.coBan }) { cn.coBan = it; luu() })
                }
            }
            c.addView(CheckBox(this).apply {
                text = "Tùy chỉnh số viên từng loại"; setTextColor(Color.WHITE); isChecked = cn.tuyChinh
                setOnCheckedChangeListener { _, b -> cn.tuyChinh = b; luu(); veSo() }
            })
            veSo()
            c.addView(khungSo)
            c.addView(oSo("Chờ sau bấm (ms):", { cd.nghiMs }, 50, 150, 5000, { cd.nghiMs = it; luu() }))
            c.addView(chu("Giữ ít nhất 1 đá LV5 làm nhà máy. Đá hệ khác app để yên.", 11f, mau = Color.LTGRAY))
        }
        c.addView(hang(dongChay(Tool.BS) { chayBS() }, nut("📜") { moNhatKy(Tool.BS) }, nut("‹") { moMenu() }, nut("✕") { dongBang() }))
        c.addView(trangThaiChu)
        hienBang(c, dp(400))
        capNhatBang = { trangThaiChu.text = NhatKy.tatCa().lastOrNull() ?: "" }
    }

    /** Vùng màn hình (toạ độ ảnh chụp) đang có giao diện của app: bong bóng, dòng trạng thái, bảng. */
    @Volatile private var vungApp: List<android.graphics.RectF> = emptyList()

    private fun capNhatVungApp() {
        val s = ChupManHinhService.instance?.heSo ?: 1f
        val ds = ArrayList<android.graphics.RectF>()
        for (v in listOf<View?>(bongBong, chip, bang)) {
            if (v == null || v.visibility != View.VISIBLE || v.width == 0) continue
            val p = IntArray(2); v.getLocationOnScreen(p)
            ds += android.graphics.RectF(p[0] * s - 4, p[1] * s - 4, (p[0] + v.width) * s + 4, (p[1] + v.height) * s + 4)
        }
        vungApp = ds
    }

    /** Chụp + đọc chữ (ML Kit), bỏ chữ nằm trên giao diện của app (để không đọc nhầm dòng trạng thái là chữ của game). */
    private fun docChuManHinh(): Pair<Khung, List<Chu>>? {
        val k = ChupManHinhService.instance?.chup() ?: return null
        val nd = docChu ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { docChu = it }
        val kq = try {
            Tasks.await(nd.process(InputImage.fromBitmap(Kho.bitmap(k.w, k.h, k.px), 0)), 8, TimeUnit.SECONDS)
        } catch (e: Exception) { return null }
        ui.post { capNhatVungApp() }
        val app = vungApp
        val chu = ArrayList<Chu>()
        for (b in kq.textBlocks) for (l in b.lines) {
            val r = l.boundingBox ?: continue
            if (app.any { it.contains(r.exactCenterX(), r.exactCenterY()) }) continue
            chu += Chu(l.text, r.left.toFloat(), r.top.toFloat(), r.right.toFloat(), r.bottom.toFloat())
        }
        return Pair(k, chu)
    }

    /** Chụp màn hình, đọc chữ, đọc màn Ban Sức. */
    private fun nhinBS(): ManHinh? {
        val (k, chu) = docChuManHinh() ?: return null
        val a = k.bs()
        return DocMan.doc(chu, a, DocMan.vungGame(a))
    }

    // ---------- Càn quét ----------
    private fun moCQ() {
        val cd = Kho.docCQ(this)
        fun luu() = Kho.luuCQ(this, cd)
        val c = cot(chu("🗺 Càn quét bản đồ", 16f, true))
        val trangThaiChu = chu(NhatKy.tatCa().lastOrNull() ?: "", 11f, mau = Color.LTGRAY)
        if (dangChay == Tool.CQ) {
            c.addView(chu("Đang chạy – dừng để sửa cài đặt", 12f, mau = Color.rgb(255, 200, 120)))
        } else {
            c.addView(oChon("Kiểu quét:", listOf(10, 5, 1), { if (it == 1) "Lẻ (lần nữa)" else "x$it" }, { cd.kieu }) { cd.kieu = it; luu() })
            c.addView(CheckBox(this).apply {
                text = "Qua ải: xong bản đồ thì sang ải kế, hết ải thì sang nước sau"; setTextColor(Color.WHITE); isChecked = cd.quaAi
                setOnCheckedChangeListener { _, b -> cd.quaAi = b; luu() }
            })
            c.addView(CheckBox(this).apply {
                text = "Đi ngược (ải 4 → 1, nước sau → trước)"; setTextColor(Color.WHITE); isChecked = cd.nguoc
                setOnCheckedChangeListener { _, b -> cd.nguoc = b; luu() }
            })
            c.addView(CheckBox(this).apply {
                text = "Khu chưa mở càn quét: tự Thám hiểm (đánh) rồi quét"; setTextColor(Color.WHITE); isChecked = cd.thamHiem
                setOnCheckedChangeListener { _, b -> cd.thamHiem = b; luu() }
            })
            c.addView(oSo("Dừng sau (0 = không):", { cd.dungSau }, 10, 0, 9999, { cd.dungSau = it; luu() }))
            c.addView(oSo("Nhịp 'lần nữa' (ms):", { cd.nhipMs }, 10, 50, 1000, { cd.nhipMs = it; luu() }))
            val daXong = if (cd.ngay == Kho.homNay()) cd.xong.size else 0
            if (daXong > 0) c.addView(hang(chu("Hôm nay đã xong $daXong ải", 12f, mau = Color.LTGRAY),
                nut("Quét lại từ đầu") { cd.xong.clear(); luu(); moCQ() }))
            if (cd.khuAi.isNotEmpty()) c.addView(hang(chu("Dữ liệu bản đồ: ${cd.khuAi.size} ải đã dò", 12f, mau = Color.LTGRAY),
                nut("Xoá, dò lại") { cd.khuAi.clear(); luu(); moCQ() }))
            c.addView(chu("Mở bản đồ một ải (hoặc màn chương nếu bật Qua ải) rồi bấm Chạy. Hết thể lực app dừng, không mua.", 11f, mau = Color.LTGRAY))
        }
        c.addView(hang(dongChay(Tool.CQ) { chayCQ() }, nut("📜") { moNhatKy(Tool.CQ) }, nut("‹") { moMenu() }, nut("✕") { dongBang() }))
        c.addView(trangThaiChu)
        hienBang(c, dp(420))
        capNhatBang = { trangThaiChu.text = NhatKy.tatCa().lastOrNull() ?: "" }
    }

    private fun chayCQ() {
        if (!coChup()) return
        val cd = Kho.docCQ(this)
        val tb = object : vn.hoitu.canquet.core.ThietBiCQ {
            override fun nhin(): vn.hoitu.canquet.core.ManCQ? {
                val (k, chu) = docChuManHinh() ?: return null
                return vn.hoitu.canquet.core.DocCQ.doc(chu, vn.hoitu.canquet.core.DocCQ.vungGame(k.w, k.h))
            }
            override fun anh() = ChupManHinhService.instance?.chup()?.bs()
            override fun cham(x: Float, y: Float) = this@TroNangService.cham(x, y, 40)
            override fun vuot(x0: Float, y0: Float, x1: Float, y1: Float, ms: Long) = this@TroNangService.vuot(x0, y0, x1, y1, ms)
            override fun quayLai() { performGlobalAction(GLOBAL_ACTION_BACK) }
            override fun ngu(ms: Long) = Thread.sleep(ms)
            override fun log(s: String) = this@TroNangService.log(s)
            override fun luu(cd: vn.hoitu.canquet.core.CaiDatCQ) = Kho.luuCQ(this@TroNangService, cd)
            override fun homNay() = Kho.homNay()
        }
        val c = vn.hoitu.canquet.core.CanQuet(tb, cd)
        cq = c
        batDau(Tool.CQ) { c.chay() }
        trangThai("🗺 Càn quét")
    }

    private fun chayBS() {
        if (!coChup()) return
        val cd = Kho.docBS(this)
        if (cd.soLuong.values.sum() == 0) { Toast.makeText(this, "Số lượng đang là 0", Toast.LENGTH_SHORT).show(); return }
        val tb = object : ThietBiBS {
            override fun nhin(): ManHinh? = nhinBS()
            override fun anh() = ChupManHinhService.instance?.chup()?.bs()
            override fun bacCacO(): List<Int?>? = ChupManHinhService.instance?.chup()?.let { DocMan.bacCacO(it.bs()) }
            override fun oCoDa(diemHoa: Boolean): Boolean? = ChupManHinhService.instance?.chup()?.bs()?.let { DocMan.oCoDa(it, DocMan.vungGame(it), diemHoa) }
            override fun cham(x: Float, y: Float) = this@TroNangService.cham(x, y, 40)
            override fun quayLai() { performGlobalAction(GLOBAL_ACTION_BACK) }
            override fun vuot(x0: Float, y0: Float, x1: Float, y1: Float) = this@TroNangService.vuot(x0, y0, x1, y1, 1000)
            override fun vuotNhanh(x0: Float, y0: Float, x1: Float, y1: Float) = this@TroNangService.vuot(x0, y0, x1, y1, 280)
            override fun trang(): Pair<Int, Int>? = ChupManHinhService.instance?.chup()?.let { DocMan.trangChon(it.bs()) }
            override fun manNhanh(): vn.hoitu.bansuc.core.ManNhanh? = ChupManHinhService.instance?.chup()?.let { DocMan.manNhanh(it.bs()) }
            override fun ngu(ms: Long) = Thread.sleep(ms)
            override fun log(s: String) = this@TroNangService.log(s)
        }
        val b = BanSuc(tb, cd)
        bs = b
        batDau(Tool.BS) { b.chay() }
        trangThai("💎 ${cd.mucTieu}·${cd.he.ten}")
    }

    // ================= chạy / dừng =================
    private fun coChup(): Boolean {
        if (ChupManHinhService.instance != null) return true
        Toast.makeText(this, "Chưa cho phép quay màn hình: mở app Hội Tụ Auto, bấm bước 2", Toast.LENGTH_LONG).show()
        return false
    }

    private fun batDau(t: Tool, viec: () -> Unit) {
        dangChay = t
        dongBang() // đóng bảng để không che game
        capNhatBongBong()
        NhatKy.ghi("▶ Bắt đầu ${t.ten}")
        luong = Thread {
            try { viec() } catch (e: InterruptedException) { } catch (e: Exception) { log("Lỗi: ${e.message}") }
            ui.post {
                dangChay = null; vq = null; bs = null; cq = null
                capNhatBongBong()
                NhatKy.ghi("■ Kết thúc ${t.ten}")
                if (bang != null) moTool(t)
            }
        }.also { it.start() }
    }

    private fun dung() {
        vq?.dung = true
        bs?.dung = true
        cq?.dung = true
        luong?.interrupt()
    }

    private fun log(s: String) {
        NhatKy.ghi(s)
        val t = dangChay
        if (t != null) trangThai("${t.bieuTuong} ${s.trim()}")
    }

    // ================= chạm / vuốt =================
    private fun cu(x: Float, y: Float): Pair<Float, Float> {
        val s = ChupManHinhService.instance?.heSo ?: 1f
        return Pair(x / s, y / s)
    }

    /** Các cửa sổ của app (bong bóng, dòng trạng thái, bảng) đang che điểm (x, y) màn hình. */
    private fun cheDiem(diem: List<Pair<Float, Float>>): List<Pair<View, WindowManager.LayoutParams>> {
        val ds = ArrayList<Pair<View, WindowManager.LayoutParams>>()
        for ((v, lp) in listOf<Pair<View?, WindowManager.LayoutParams?>>(bongBong to lpBong, chip to lpChip, bang to lpBang)) {
            if (v == null || lp == null || v.visibility != View.VISIBLE || v.width == 0) continue
            val p = IntArray(2); v.getLocationOnScreen(p)
            if (diem.any { (x, y) -> x >= p[0] - 8 && x <= p[0] + v.width + 8 && y >= p[1] - 8 && y <= p[1] + v.height + 8 }) ds += Pair(v, lp)
        }
        return ds
    }

    private fun xuyen(ds: List<Pair<View, WindowManager.LayoutParams>>, bat: Boolean) {
        for ((v, lp) in ds) {
            lp.flags = if (bat) lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE else lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            runCatching { wm.updateViewLayout(v, lp) }
        }
    }

    /**
     * Thực hiện cử chỉ. Nếu điểm chạm nằm dưới bong bóng / bảng của app thì tạm cho chúng "trong suốt với chạm"
     * để cú chạm xuống tới game (vd nút quay lại xanh của game nằm dưới bong bóng), xong thì bật lại.
     */
    private fun lamCu(path: Path, ms: Long, diem: List<Pair<Float, Float>>) {
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, ms)).build()
        val xong = CountDownLatch(1)
        ui.post {
            val che = cheDiem(diem)
            fun guiDi() {
                val ok = dispatchGesture(g, object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) { if (che.isNotEmpty()) xuyen(che, false); xong.countDown() }
                    override fun onCancelled(gestureDescription: GestureDescription?) { if (che.isNotEmpty()) xuyen(che, false); xong.countDown() }
                }, null)
                if (!ok) { if (che.isNotEmpty()) xuyen(che, false); xong.countDown() }
            }
            if (che.isEmpty()) guiDi() else { xuyen(che, true); ui.postDelayed({ guiDi() }, 60) }
        }
        xong.await(ms + 2000, TimeUnit.MILLISECONDS)
    }

    private fun cham(x: Float, y: Float, ms: Long) {
        val (a, b) = cu(x, y)
        lamCu(Path().apply { moveTo(a, b) }, ms, listOf(Pair(a, b)))
    }

    private fun vuot(x0: Float, y0: Float, x1: Float, y1: Float, ms: Long) {
        val (a, b) = cu(x0, y0); val (c, d) = cu(x1, y1)
        lamCu(Path().apply { moveTo(a, b); lineTo(c, d) }, ms, listOf(Pair(a, b), Pair((a + c) / 2, (b + d) / 2), Pair(c, d))) // vuốt chậm để không trôi theo quán tính
        Thread.sleep(if (ms < 500) 80 else 300)
    }
}
