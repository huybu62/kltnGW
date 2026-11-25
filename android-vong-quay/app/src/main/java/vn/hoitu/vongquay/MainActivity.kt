package vn.hoitu.vongquay

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
import android.text.InputType
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import vn.hoitu.vongquay.core.Loai

/** Màn cài đặt: bật Trợ năng, cho phép quay màn hình, nhập bộ đếm / mốc / món muốn ra. */
class MainActivity : Activity() {
    private lateinit var ttTroNang: TextView
    private lateinit var ttChup: TextView
    private lateinit var oDem: EditText
    private lateinit var oMoc: EditText
    private lateinit var oTaoMoi: EditText
    private lateinit var oDungSau: EditText
    private val chon = HashMap<Loai, CheckBox>()

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(16), dp(16), dp(24)) }
        fun chu(s: String, co: Float = 15f, dam: Boolean = false) = TextView(this).apply {
            text = s; textSize = co; if (dam) setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, dp(6), 0, dp(2))
        }
        fun so(goiY: String) = EditText(this).apply { inputType = InputType.TYPE_CLASS_NUMBER; hint = goiY }
        fun nut(s: String, bam: (View) -> Unit) = Button(this).apply { text = s; isAllCaps = false; setOnClickListener(bam) }

        col.addView(chu("🎡 Vòng Quay Auto", 22f, true))
        col.addView(chu("Tự bấm \"Khởi động 10 lần\" ở màn Vòng quay liên server. Lần bấm thứ 73: bấm \"Tạo mới\" tới khi vòng có món hạn định bạn chọn rồi mới quay, sau đó bộ đếm về 0.", 13f))

        col.addView(chu("Bước 1 – Bật Trợ năng (để app chạm giúp)", 16f, true))
        ttTroNang = chu("", 13f); col.addView(ttTroNang)
        col.addView(nut("Mở cài đặt Trợ năng → bật \"Vòng Quay Auto\"") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        })

        col.addView(chu("Bước 2 – Cho phép quay màn hình (để app nhìn thấy game)", 16f, true))
        ttChup = chu("", 13f); col.addView(ttChup)
        col.addView(nut("Cho phép quay màn hình") { xinQuayManHinh() })

        col.addView(chu("Cài đặt", 16f, true))
        col.addView(chu("Đã bấm x10 (bộ đếm bạn tự đếm):", 13f)); oDem = so("0"); col.addView(oDem)
        col.addView(chu("Mốc chắc chắn ra hạn định:", 13f)); oMoc = so("73"); col.addView(oMoc)
        col.addView(chu("Tạo mới tối đa ở lượt mốc:", 13f)); oTaoMoi = so("60"); col.addView(oTaoMoi)
        col.addView(chu("Dừng sau N lần bấm (0 = không giới hạn):", 13f)); oDungSau = so("0"); col.addView(oDungSau)
        col.addView(chu("Ở lượt mốc, Tạo mới tới khi vòng quay có:", 13f))
        for (loai in Loai.values()) {
            val cb = CheckBox(this).apply { text = loai.ten }
            chon[loai] = cb; col.addView(cb)
        }
        col.addView(nut("💾 Lưu cài đặt") { luu() })
        col.addView(nut("Xoá mẫu tự chọn (dùng lại mẫu có sẵn)") {
            Kho.xoaMauRieng(this); Toast.makeText(this, "Đã xoá mẫu tự chọn", Toast.LENGTH_SHORT).show()
        })

        col.addView(chu("Cách dùng", 16f, true))
        col.addView(chu(
            "1. Làm bước 1 và 2.\n" +
            "2. Mở game, vào màn Vòng quay liên server.\n" +
            "3. Trên nút nổi: bấm ▶ Chạy. Bấm ■ Dừng để dừng; − / + để sửa bộ đếm.\n" +
            "4. Sự kiện đổi tướng hạn định: khi tướng mới nằm trên vòng quay, bấm \"Mẫu\" trên nút nổi → chạm ô tướng đó → chọn \"Tướng hạn định\". " +
            "Đá vận mệnh cũng nên lấy mẫu như vậy khi nó xuất hiện trên vòng.\n" +
            "App chỉ chạm 3 chỗ: Khởi động 10 lần, Tạo mới, và chỗ trống để tắt danh sách quà.", 13f))

        setContentView(ScrollView(this).apply { addView(col) })
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
    }

    override fun onResume() {
        super.onResume()
        val cd = Kho.docCaiDat(this)
        oDem.setText(cd.dem.toString()); oMoc.setText(cd.moc.toString())
        oTaoMoi.setText(cd.taoMoiToiDa.toString()); oDungSau.setText(cd.dungSau.toString())
        for ((loai, cb) in chon) cb.isChecked = loai in cd.muon
        val bat = troNangDangBat()
        ttTroNang.text = if (bat) "✔ Đã bật" else "✘ Chưa bật"
        ttTroNang.setTextColor(if (bat) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
        val chup = ChupManHinhService.instance != null
        ttChup.text = if (chup) "✔ Đang được phép" else "✘ Chưa cho phép (mỗi lần mở lại máy / app cần cho phép lại)"
        ttChup.setTextColor(if (chup) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
    }

    private fun luu() {
        val cd = Kho.docCaiDat(this)
        cd.moc = oMoc.text.toString().toIntOrNull()?.coerceAtLeast(1) ?: 73
        cd.dem = (oDem.text.toString().toIntOrNull() ?: 0).coerceIn(0, cd.moc - 1)
        cd.taoMoiToiDa = oTaoMoi.text.toString().toIntOrNull()?.coerceAtLeast(0) ?: 60
        cd.dungSau = oDungSau.text.toString().toIntOrNull()?.coerceAtLeast(0) ?: 0
        cd.muon = chon.filter { it.value.isChecked }.keys.toMutableSet()
        if (cd.muon.isEmpty()) { Toast.makeText(this, "Chọn ít nhất 1 món", Toast.LENGTH_SHORT).show(); return }
        Kho.luuCaiDat(this, cd)
        Toast.makeText(this, "Đã lưu", Toast.LENGTH_SHORT).show()
        onResume()
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
            Toast.makeText(this, "Đã cho phép. Mở game và bấm ▶ trên nút nổi.", Toast.LENGTH_LONG).show()
            ttChup.postDelayed({ onResume() }, 800)
        }
    }
}
