package vn.hoitu.bansuc

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
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import vn.hoitu.bansuc.core.BanSuc
import vn.hoitu.bansuc.core.Chu
import vn.hoitu.bansuc.core.DocMan
import vn.hoitu.bansuc.core.ManHinh
import vn.hoitu.bansuc.core.ThietBi
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Dịch vụ Trợ năng: nút nổi (Chạy/Dừng + dòng trạng thái), thực hiện chạm/vuốt,
 * đọc chữ trên ảnh chụp màn hình bằng ML Kit (chạy trên máy, không cần mạng).
 */
class TroNangService : AccessibilityService() {
    private val ui = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private var panel: LinearLayout? = null
    private lateinit var txtTrangThai: TextView
    private lateinit var txtLog: TextView
    private lateinit var btnChay: Button
    private var bs: BanSuc? = null
    private var luong: Thread? = null
    private var docChu: TextRecognizer? = null

    override fun onServiceConnected() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        taoPanel()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    override fun onDestroy() {
        dung()
        panel?.let { runCatching { wm.removeView(it) } }
        docChu?.close()
        super.onDestroy()
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun nut(ten: String, bam: () -> Unit) = Button(this).apply {
        text = ten; textSize = 12f; minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0
        setPadding(dp(10), dp(2), dp(10), dp(2)); isAllCaps = false
        setOnClickListener { bam() }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun taoPanel() {
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(Color.argb(215, 20, 20, 28)); cornerRadius = dp(10).toFloat() }
            setPadding(dp(6), dp(4), dp(6), dp(4))
        }
        txtTrangThai = TextView(this).apply { setTextColor(Color.WHITE); textSize = 13f; text = "💎 Ban Sức  ✥" }
        txtLog = TextView(this).apply { setTextColor(Color.rgb(200, 200, 200)); textSize = 10f; maxLines = 3; maxWidth = dp(220) }
        btnChay = nut("▶ Chạy") { if (bs == null) chay() else dung() }
        p.addView(txtTrangThai); p.addView(btnChay); p.addView(txtLog)
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START; x = dp(4); y = dp(4) }
        var dx = 0f; var dy = 0f
        txtTrangThai.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { dx = lp.x - e.rawX; dy = lp.y - e.rawY }
                MotionEvent.ACTION_MOVE -> { lp.x = (e.rawX + dx).toInt(); lp.y = (e.rawY + dy).toInt(); wm.updateViewLayout(p, lp) }
            }
            true
        }
        wm.addView(p, lp)
        panel = p
        log("Mở màn Ban Sức Đá Quý Vận Mệnh rồi bấm ▶. Kéo dòng trên để dời nút, đừng che danh sách đá.")
    }

    private fun log(s: String) { ui.post { txtLog.text = s } }

    private fun cu(x: Float, y: Float): Pair<Float, Float> {
        val s = ChupManHinhService.instance?.heSo ?: 1f
        return Pair(x / s, y / s)
    }

    private fun lamCu(path: Path, ms: Long) {
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, ms)).build()
        val xong = CountDownLatch(1)
        ui.post {
            val ok = dispatchGesture(g, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) { xong.countDown() }
                override fun onCancelled(gestureDescription: GestureDescription?) { xong.countDown() }
            }, null)
            if (!ok) xong.countDown()
        }
        xong.await(ms + 2000, TimeUnit.MILLISECONDS)
    }

    private fun cham(x: Float, y: Float) {
        val (a, b) = cu(x, y)
        lamCu(Path().apply { moveTo(a, b) }, 40)
    }

    private fun vuot(x0: Float, y0: Float, x1: Float, y1: Float) {
        val (a, b) = cu(x0, y0); val (c, d) = cu(x1, y1)
        lamCu(Path().apply { moveTo(a, b); lineTo(c, d) }, 450)
    }

    /** Chụp màn hình, đọc chữ, đọc màn. */
    private fun nhin(): ManHinh? {
        val a = ChupManHinhService.instance?.chup() ?: return null
        val nd = docChu ?: TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS).also { docChu = it }
        val kq = try {
            Tasks.await(nd.process(InputImage.fromBitmap(Kho.bitmapTuAnh(a), 0)), 8, TimeUnit.SECONDS)
        } catch (e: Exception) { return null }
        val chu = ArrayList<Chu>()
        for (b in kq.textBlocks) for (l in b.lines) {
            val r = l.boundingBox ?: continue
            chu += Chu(l.text, r.left.toFloat(), r.top.toFloat(), r.right.toFloat(), r.bottom.toFloat())
        }
        return DocMan.doc(chu, a, DocMan.vungGame(a))
    }

    private fun chay() {
        if (ChupManHinhService.instance == null) {
            Toast.makeText(this, "Chưa cho phép quay màn hình: mở app Ban Sức Auto, bấm bước 2", Toast.LENGTH_LONG).show()
            return
        }
        val cd = Kho.docCaiDat(this)
        val tb = object : ThietBi {
            override fun nhin(): ManHinh? = this@TroNangService.nhin()
            override fun cham(x: Float, y: Float) = this@TroNangService.cham(x, y)
            override fun vuot(x0: Float, y0: Float, x1: Float, y1: Float) = this@TroNangService.vuot(x0, y0, x1, y1)
            override fun ngu(ms: Long) = Thread.sleep(ms)
            override fun log(s: String) = this@TroNangService.log(s)
        }
        val b = BanSuc(tb, cd)
        bs = b
        btnChay.text = "■ Dừng"
        ui.post { txtTrangThai.text = "💎 ${cd.mucTieu}·${cd.he.ten}  ✥" }
        luong = Thread {
            try { b.chay() } catch (e: InterruptedException) { } catch (e: Exception) { log("Lỗi: ${e.message}") }
            ui.post {
                bs = null; btnChay.text = "▶ Chạy"
                txtTrangThai.text = "💎 Điểm hóa ${b.soLanDiemHoa} · Thác ấn ${b.soLanThacAn}  ✥"
            }
        }.also { it.start() }
    }

    private fun dung() {
        bs?.dung = true
        luong?.interrupt()
    }
}
