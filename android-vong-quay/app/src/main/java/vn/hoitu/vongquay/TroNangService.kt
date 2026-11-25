package vn.hoitu.vongquay

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import vn.hoitu.vongquay.core.Anh
import vn.hoitu.vongquay.core.CaiDat
import vn.hoitu.vongquay.core.Loai
import vn.hoitu.vongquay.core.NhanDien
import vn.hoitu.vongquay.core.ThietBi
import vn.hoitu.vongquay.core.VongQuay
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Dịch vụ Trợ năng: hiện nút nổi (Chạy/Dừng, bộ đếm, chọn mẫu) và thực hiện các cú chạm.
 * Chỉ chạm theo lệnh của bộ điều khiển vòng quay; không đọc nội dung app khác.
 */
class TroNangService : AccessibilityService() {
    private val ui = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private var panel: LinearLayout? = null
    private var chonMau: View? = null
    private lateinit var txtDem: TextView
    private lateinit var txtLog: TextView
    private lateinit var btnChay: Button
    private var vq: VongQuay? = null
    private var luong: Thread? = null

    override fun onServiceConnected() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        taoPanel()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        dung()
        panel?.let { runCatching { wm.removeView(it) } }
        chonMau?.let { runCatching { wm.removeView(it) } }
        super.onDestroy()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun nen(mau: Int) = GradientDrawable().apply { setColor(mau); cornerRadius = dp(10).toFloat() }

    private fun thamSo(x: Int, y: Int) = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.START; this.x = x; this.y = y }

    private fun nut(ten: String, bam: () -> Unit) = Button(this).apply {
        text = ten; textSize = 12f; minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0
        setPadding(dp(8), dp(2), dp(8), dp(2)); isAllCaps = false
        setOnClickListener { bam() }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun taoPanel() {
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = nen(Color.argb(215, 20, 20, 28))
            setPadding(dp(6), dp(4), dp(6), dp(4))
        }
        txtDem = TextView(this).apply { setTextColor(Color.WHITE); textSize = 13f }
        txtLog = TextView(this).apply { setTextColor(Color.rgb(200, 200, 200)); textSize = 10f; maxLines = 2; maxWidth = dp(190) }
        btnChay = nut("▶ Chạy") { if (vq == null) chay() else dung() }
        val hang = LinearLayout(this).apply {
            addView(btnChay)
            addView(nut("−") { doiDem(-1) })
            addView(nut("+") { doiDem(+1) })
            addView(nut("Mẫu") { moChonMau() })
        }
        p.addView(txtDem); p.addView(hang); p.addView(txtLog)
        val lp = thamSo(dp(4), dp(60))
        // kéo bằng dòng bộ đếm
        var dx = 0f; var dy = 0f
        txtDem.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { dx = lp.x - e.rawX; dy = lp.y - e.rawY }
                MotionEvent.ACTION_MOVE -> { lp.x = (e.rawX + dx).toInt(); lp.y = (e.rawY + dy).toInt(); wm.updateViewLayout(p, lp) }
            }
            true
        }
        wm.addView(p, lp)
        panel = p
        capNhatDem(Kho.docCaiDat(this))
        log("Mở màn Vòng quay liên server rồi bấm ▶ (kéo dòng trên để dời nút)")
    }

    private fun capNhatDem(cd: CaiDat) { ui.post { txtDem.text = "🎡 Đã bấm x10: ${cd.dem}/${cd.moc}  ✥" } }

    private fun log(s: String) { ui.post { txtLog.text = s } }

    private fun doiDem(d: Int) {
        if (vq != null) { Toast.makeText(this, "Dừng trước khi sửa bộ đếm", Toast.LENGTH_SHORT).show(); return }
        val cd = Kho.docCaiDat(this)
        cd.dem = (cd.dem + d).coerceIn(0, cd.moc - 1)
        Kho.luuCaiDat(this, cd); capNhatDem(cd)
    }

    /** Chạm tại (x, y) theo toạ độ ảnh chụp; đổi ra toạ độ màn hình thật. */
    private fun cham(x: Float, y: Float) {
        val s = ChupManHinhService.instance?.heSo ?: 1f
        val path = Path().apply { moveTo(x / s, y / s) }
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, 60)).build()
        val xong = CountDownLatch(1)
        ui.post {
            dispatchGesture(g, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) { xong.countDown() }
                override fun onCancelled(gestureDescription: GestureDescription?) { xong.countDown() }
            }, null)
        }
        xong.await(2, TimeUnit.SECONDS)
    }

    private fun chay() {
        val chup = ChupManHinhService.instance
        if (chup == null) {
            Toast.makeText(this, "Chưa cho phép quay màn hình: mở app Vòng Quay Auto, bấm bước 2", Toast.LENGTH_LONG).show()
            return
        }
        val cd = Kho.docCaiDat(this)
        val tb = object : ThietBi {
            override fun chup(): Anh? = ChupManHinhService.instance?.chup()
            override fun cham(x: Float, y: Float) = this@TroNangService.cham(x, y)
            override fun ngu(ms: Long) = Thread.sleep(ms)
            override fun log(s: String) = this@TroNangService.log(s)
            override fun luu(cd: CaiDat) { Kho.luuCaiDat(this@TroNangService, cd); capNhatDem(cd) }
        }
        val v = VongQuay(tb, cd, Kho.mauX1(this), Kho.mauMon(this))
        vq = v
        btnChay.text = "■ Dừng"
        luong = Thread {
            try { v.chay() } catch (e: InterruptedException) { } catch (e: Exception) { log("Lỗi: ${e.message}") }
            ui.post { vq = null; btnChay.text = "▶ Chạy"; capNhatDem(Kho.docCaiDat(this)) }
        }.also { it.start() }
    }

    private fun dung() {
        vq?.dung = true
        luong?.interrupt()
    }

    // ---------- chọn mẫu món từ vòng quay đang hiện ----------
    private fun moChonMau() {
        if (vq != null) { Toast.makeText(this, "Dừng trước khi chọn mẫu", Toast.LENGTH_SHORT).show(); return }
        val a = ChupManHinhService.instance?.chup()
        if (a == null) { Toast.makeText(this, "Chưa cho phép quay màn hình", Toast.LENGTH_LONG).show(); return }
        val neo = NhanDien.timVong(a, Kho.mauX1(this))
        if (neo == null) { Toast.makeText(this, "Mở màn Vòng quay liên server trước", Toast.LENGTH_LONG).show(); return }
        val khung = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; background = nen(Color.argb(235, 25, 25, 35))
            setPadding(dp(10), dp(8), dp(10), dp(8))
        }
        val tieuDe = TextView(this).apply { setTextColor(Color.WHITE); textSize = 14f; text = "Chạm ô chứa món hạn định thật để làm mẫu:" }
        khung.addView(tieuDe)
        val luoi = GridLayout(this).apply { columnCount = 4 }
        for (ten in NhanDien.O.keys) {
            val o = NhanDien.catO(a, neo, ten)
            luoi.addView(ImageView(this).apply {
                setImageBitmap(Kho.bitmapTuAnh(o)); layoutParams = GridLayout.LayoutParams().apply {
                    width = dp(64); height = dp(66); setMargins(dp(4), dp(4), dp(4), dp(4))
                }
                setOnClickListener { chonLoai(khung, o) }
            })
        }
        khung.addView(luoi)
        khung.addView(nut("Đóng") { dongChonMau() })
        chonMau = khung
        wm.addView(khung, thamSo(dp(40), dp(40)))
    }

    private fun chonLoai(khung: LinearLayout, o: Anh) {
        khung.removeAllViews()
        khung.addView(ImageView(this).apply { setImageBitmap(Kho.bitmapTuAnh(o)) })
        khung.addView(TextView(this).apply { setTextColor(Color.WHITE); text = "Ô này là món nào?" })
        for (loai in Loai.values()) khung.addView(nut(loai.ten) {
            Kho.luuMau(this, loai, o)
            Toast.makeText(this, "Đã lưu mẫu ${loai.ten}", Toast.LENGTH_SHORT).show()
            dongChonMau()
        })
        khung.addView(nut("Huỷ") { dongChonMau() })
    }

    private fun dongChonMau() {
        chonMau?.let { runCatching { wm.removeView(it) } }
        chonMau = null
    }
}
