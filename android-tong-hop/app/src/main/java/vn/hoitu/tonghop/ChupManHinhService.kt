package vn.hoitu.tonghop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Dịch vụ chụp màn hình (MediaProjection). Ảnh được thu nhỏ để cạnh dài ≤ 1600 cho nhanh;
 * [heSo] = cỡ ảnh chụp / cỡ màn hình thật (để đổi toạ độ chạm). Tự tạo lại khi xoay màn hình.
 */
class ChupManHinhService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private lateinit var luong: HandlerThread
    private lateinit var handler: Handler
    private var coThat = Pair(0, 0)
    @Volatile var heSo = 1f
        private set
    @Volatile private var anhCuoi: Khung? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        batDauTienCanh()
        val ma = intent?.getIntExtra(EXTRA_MA, 0) ?: 0
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        else @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
        if (data == null) { stopSelf(); return START_NOT_STICKY }
        luong = HandlerThread("chup").also { it.start() }
        handler = Handler(luong.looper)
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val p = mpm.getMediaProjection(ma, data) ?: run { stopSelf(); return START_NOT_STICKY }
        projection = p
        p.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() { dungChup(); stopSelf() }
        }, handler)
        taoManHinhAo()
        instance = this
        return START_NOT_STICKY
    }

    private fun batDauTienCanh() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(KENH, "Chụp màn hình", NotificationManager.IMPORTANCE_LOW))
        }
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, KENH) else @Suppress("DEPRECATION") Notification.Builder(this)
        val tb = b.setContentTitle("Hội Tụ Auto").setContentText("Đang được phép xem màn hình để chạy tool")
            .setSmallIcon(android.R.drawable.ic_menu_rotate).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(1, tb, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        else startForeground(1, tb)
    }

    private fun coManHinh(): Triple<Int, Int, Int> {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        return if (Build.VERSION.SDK_INT >= 30) {
            val b = wm.currentWindowMetrics.bounds
            Triple(b.width(), b.height(), resources.displayMetrics.densityDpi)
        } else {
            @Suppress("DEPRECATION") wm.defaultDisplay.getRealMetrics(dm)
            Triple(dm.widthPixels, dm.heightPixels, dm.densityDpi)
        }
    }

    @Synchronized
    private fun taoManHinhAo() {
        val (w, h, dpi) = coManHinh()
        coThat = Pair(w, h)
        val s = min(1f, 1600f / max(w, h))
        heSo = s
        val cw = (w * s).roundToInt(); val ch = (h * s).roundToInt()
        val r = ImageReader.newInstance(cw, ch, PixelFormat.RGBA_8888, 2)
        val cu = reader
        reader = r
        val d = display
        if (d == null) {
            display = projection?.createVirtualDisplay("hoi_tu", cw, ch, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler)
        } else {
            d.resize(cw, ch, dpi)
            d.surface = r.surface
        }
        cu?.close()
        anhCuoi = null
    }

    /** Ảnh màn hình mới nhất (cỡ đã thu nhỏ), hoặc null nếu chưa có. */
    fun chup(): Khung? {
        val (w, h, _) = coManHinh()
        if (Pair(w, h) != coThat) taoManHinhAo() // xoay màn hình
        val r = reader ?: return anhCuoi
        val img = try { r.acquireLatestImage() } catch (e: Exception) { null } ?: return anhCuoi
        try {
            val pl = img.planes[0]
            val buf = pl.buffer
            val ps = pl.pixelStride; val rs = pl.rowStride
            val iw = img.width; val ih = img.height
            val px = IntArray(iw * ih)
            if (ps == 4) {
                // đọc cả hàng một lần (nhanh hơn nhiều so với từng byte), rồi đổi RGBA → ARGB
                val ib = buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asIntBuffer()
                val moiHang = rs / 4
                for (y in 0 until ih) { ib.position(y * moiHang); ib.get(px, y * iw, iw) }
                for (i in px.indices) {
                    val v = px[i] // little-endian: 0xAABBGGRR
                    px[i] = (0xFF shl 24) or ((v and 0xFF) shl 16) or (v and 0xFF00) or ((v shr 16) and 0xFF)
                }
            } else {
                for (y in 0 until ih) {
                    var o = y * rs
                    for (x in 0 until iw) {
                        val rr = buf.get(o).toInt() and 0xFF
                        val gg = buf.get(o + 1).toInt() and 0xFF
                        val bb = buf.get(o + 2).toInt() and 0xFF
                        px[y * iw + x] = (0xFF shl 24) or (rr shl 16) or (gg shl 8) or bb
                        o += ps
                    }
                }
            }
            anhCuoi = Khung(iw, ih, px)
        } finally {
            img.close()
        }
        return anhCuoi
    }

    private fun dungChup() {
        display?.release(); display = null
        reader?.close(); reader = null
        instance = null
    }

    override fun onDestroy() {
        dungChup()
        projection?.stop(); projection = null
        if (::luong.isInitialized) luong.quitSafely()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_MA = "ma"
        const val EXTRA_DATA = "data"
        private const val KENH = "chup_man_hinh"
        @Volatile var instance: ChupManHinhService? = null
            private set
    }
}

/** Một khung hình chụp được (ARGB), đổi sang kiểu ảnh của từng tool mà không chép dữ liệu. */
class Khung(val w: Int, val h: Int, val px: IntArray) {
    fun vq() = vn.hoitu.vongquay.core.Anh(w, h, px)
    fun bs() = vn.hoitu.bansuc.core.Anh(w, h, px)
}
