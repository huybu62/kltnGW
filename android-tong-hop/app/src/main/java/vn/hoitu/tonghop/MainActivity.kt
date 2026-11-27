package vn.hoitu.tonghop

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/** Màn cấp quyền lần đầu. Mọi cài đặt của tool chỉnh ngay trong bong bóng nổi. */
class MainActivity : Activity() {
    private lateinit var ttTroNang: TextView
    private lateinit var ttChup: TextView

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(16), dp(16), dp(24)) }
        fun chu(s: String, co: Float = 15f, dam: Boolean = false) = TextView(this).apply {
            text = s; textSize = co; if (dam) setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, dp(6), 0, dp(2))
        }
        fun nut(s: String, bam: (View) -> Unit) = Button(this).apply { text = s; isAllCaps = false; setOnClickListener(bam) }

        col.addView(chu("⚙ Hội Tụ Auto", 22f, true))
        col.addView(chu("Gộp các tool: 🎡 Vòng quay liên server, 💎 Ban sức vận mệnh (🗺 Càn quét sẽ có sau). Bấm bong bóng nổi để chọn tool, chỉnh cài đặt và Chạy / Dừng ngay trong game.", 13f))

        col.addView(chu("Bước 1 – Bật Trợ năng (để app chạm giúp)", 16f, true))
        ttTroNang = chu("", 13f); col.addView(ttTroNang)
        col.addView(nut("Mở cài đặt Trợ năng → bật \"Hội Tụ Auto\"") { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) })
        col.addView(chu("Android 13+ báo \"Restricted setting\": vào Cài đặt → Ứng dụng → Hội Tụ Auto → ⋮ → Allow restricted settings rồi bật lại.", 12f))

        col.addView(chu("Bước 2 – Cho phép quay màn hình (để app nhìn thấy game)", 16f, true))
        ttChup = chu("", 13f); col.addView(ttChup)
        col.addView(nut("Cho phép quay màn hình") { xinQuayManHinh() })

        col.addView(chu("Cách dùng", 16f, true))
        col.addView(chu(
            "1. Làm bước 1 và 2 (bước 2 cần làm lại mỗi lần mở lại máy).\n" +
            "2. Vào game. Bấm bong bóng ⚙ → chọn tool → chỉnh cài đặt → ▶ Chạy.\n" +
            "3. Đang chạy: bong bóng chuyển xanh, dòng trạng thái hiện cạnh bong bóng. Bấm bong bóng để Dừng hoặc xem 📜 Nhật ký.\n" +
            "4. Kéo bong bóng để dời chỗ; đừng để nó che nút / danh sách của game.\n" +
            "5. Nếu còn cài app lẻ Vòng Quay Auto / Ban Sức Auto, nên tắt Trợ năng của chúng để khỏi có 2 nút nổi.", 13f))

        setContentView(ScrollView(this).apply { addView(col) })
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
    }

    override fun onResume() {
        super.onResume()
        val bat = troNangDangBat()
        ttTroNang.text = if (bat) "✔ Đã bật" else "✘ Chưa bật"
        ttTroNang.setTextColor(if (bat) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
        val chup = ChupManHinhService.instance != null
        ttChup.text = if (chup) "✔ Đang được phép" else "✘ Chưa cho phép"
        ttChup.setTextColor(if (chup) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
    }

    private fun troNangDangBat(): Boolean {
        val ds = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val ten = ComponentName(this, TroNangService::class.java).flattenToString()
        return ds.split(':').any { it.equals(ten, ignoreCase = true) }
    }

    private fun xinQuayManHinh() {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), 1)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1 && resultCode == RESULT_OK && data != null) {
            val i = Intent(this, ChupManHinhService::class.java)
                .putExtra(ChupManHinhService.EXTRA_MA, resultCode).putExtra(ChupManHinhService.EXTRA_DATA, data)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
            Toast.makeText(this, "Đã cho phép. Vào game và bấm bong bóng ⚙.", Toast.LENGTH_LONG).show()
            ttChup.postDelayed({ onResume() }, 800)
        }
    }
}
