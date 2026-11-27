package vn.hoitu.bansuc

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
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import vn.hoitu.bansuc.core.ChiSo
import vn.hoitu.bansuc.core.He

/** Màn cài đặt: bật Trợ năng, cho phép quay màn hình, chọn hệ / phẩm / số lượng. */
class MainActivity : Activity() {
    private lateinit var ttTroNang: TextView
    private lateinit var ttChup: TextView
    private lateinit var spHe: Spinner
    private lateinit var rA: RadioButton
    private lateinit var rS: RadioButton
    private lateinit var cbTuyChinh: CheckBox
    private lateinit var khungBo: LinearLayout
    private lateinit var khungTuyChinh: LinearLayout
    private lateinit var oSoBo: EditText
    private lateinit var spCoBan: Spinner
    private val oSoLuong = HashMap<ChiSo, EditText>()
    private lateinit var cbNhaMay: CheckBox
    private lateinit var oNghi: EditText
    private val coBan = listOf(ChiSo.PHONG, ChiSo.TOCDO, ChiSo.VATCONG, ChiSo.MACONG)

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
        fun <T> danhSach(ds: List<T>, ten: (T) -> String) = Spinner(this).apply {
            adapter = ArrayAdapter(this@MainActivity, android.R.layout.simple_spinner_dropdown_item, ds.map(ten))
        }

        col.addView(chu("💎 Ban Sức Auto", 22f, true))
        col.addView(chu("Tự Điểm Hóa / Thác Ấn đá vận mệnh LV6 tới phẩm A hoặc S theo hệ bạn chọn. Hết đá điểm hóa B-SS thì dùng đá LV5 làm nhà máy (Điểm Hóa B-S tới B → Thác Ấn bằng Đá In SS).", 13f))

        col.addView(chu("Bước 1 – Bật Trợ năng (để app chạm giúp)", 16f, true))
        ttTroNang = chu("", 13f); col.addView(ttTroNang)
        col.addView(nut("Mở cài đặt Trợ năng → bật \"Ban Sức Auto\"") { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) })
        col.addView(chu("Android 13+ báo \"Restricted setting\": vào Cài đặt → Ứng dụng → Ban Sức Auto → ⋮ → Allow restricted settings rồi bật lại.", 12f))

        col.addView(chu("Bước 2 – Cho phép quay màn hình (để app đọc được game)", 16f, true))
        ttChup = chu("", 13f); col.addView(ttChup)
        col.addView(nut("Cho phép quay màn hình") { xinQuayManHinh() })

        col.addView(chu("Cài đặt", 16f, true))
        col.addView(chu("Hệ:", 13f)); spHe = danhSach(He.values().toList()) { it.ten }; col.addView(spHe)
        col.addView(chu("Phẩm mục tiêu (đá LV6):", 13f))
        rA = RadioButton(this).apply { text = "A (dùng đá điểm hóa B-SS)"; id = View.generateViewId() }
        rS = RadioButton(this).apply { text = "S (dùng đá điểm hóa A-SSS)"; id = View.generateViewId() }
        col.addView(RadioGroup(this).apply { addView(rA); addView(rS) })
        cbNhaMay = CheckBox(this).apply { text = "Nhà máy LV6: hết A-SSS thì tự đưa 1 viên LV6 lên A rồi Thác Ấn bằng Đá In SSS" }
        col.addView(cbNhaMay)

        col.addView(chu("Số lượng đá thành phẩm:", 13f))
        cbTuyChinh = CheckBox(this).apply { text = "Tùy chỉnh từng loại" }
        col.addView(cbTuyChinh)
        khungBo = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        khungBo.addView(chu("Số bộ (1 bộ = 1 đá cơ bản + 3 đá HP):", 13f)); oSoBo = so("1"); khungBo.addView(oSoBo)
        khungBo.addView(chu("Đá cơ bản:", 13f)); spCoBan = danhSach(coBan) { it.ten }; khungBo.addView(spCoBan)
        col.addView(khungBo)
        khungTuyChinh = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        for (cs in ChiSo.values()) {
            khungTuyChinh.addView(chu("Số viên ${cs.ten}:", 13f))
            val e = so("0"); oSoLuong[cs] = e; khungTuyChinh.addView(e)
        }
        col.addView(khungTuyChinh)
        cbTuyChinh.setOnCheckedChangeListener { _, b -> hienCachNhap(b) }

        col.addView(chu("Chờ sau mỗi lần bấm (ms, máy chậm thì tăng):", 13f)); oNghi = so("600"); col.addView(oNghi)
        col.addView(nut("💾 Lưu cài đặt") { luu() })

        col.addView(chu("Cách dùng", 16f, true))
        col.addView(chu(
            "1. Làm bước 1 và 2, chọn hệ / phẩm / số lượng rồi Lưu.\n" +
            "2. Giữ ít nhất 1 đá LV5 làm nhà máy. Đá LV6 dùng để làm: chưa ban sức hoặc đúng hệ đã chọn (đá hệ khác app để yên).\n" +
            "3. Mở game: màn Ban Sức Đá Quý Vận Mệnh (bảng danh sách đá bên trái), bấm ▶ trên nút nổi.\n" +
            "4. App dừng khi đủ số đá, hoặc hết đá điểm hóa / Đá In / đá LV6.", 13f))

        setContentView(ScrollView(this).apply { addView(col) })
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        }
    }

    private fun hienCachNhap(tuyChinh: Boolean) {
        khungBo.visibility = if (tuyChinh) View.GONE else View.VISIBLE
        khungTuyChinh.visibility = if (tuyChinh) View.VISIBLE else View.GONE
    }

    override fun onResume() {
        super.onResume()
        val cd = Kho.docCaiDat(this)
        val cn = Kho.docCachNhap(this)
        spHe.setSelection(cd.he.ordinal)
        rA.isChecked = cd.mucTieu == 'A'; rS.isChecked = cd.mucTieu == 'S'
        cbNhaMay.isChecked = cd.nhaMayLv6
        cbTuyChinh.isChecked = cn.tuyChinh; hienCachNhap(cn.tuyChinh)
        oSoBo.setText(cn.soBo.toString()); spCoBan.setSelection(coBan.indexOf(cn.coBan).coerceAtLeast(0))
        for ((cs, e) in oSoLuong) e.setText((cd.soLuong[cs] ?: 0).toString())
        oNghi.setText(cd.nghiMs.toString())
        val bat = troNangDangBat()
        ttTroNang.text = if (bat) "✔ Đã bật" else "✘ Chưa bật"
        ttTroNang.setTextColor(if (bat) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
        val chup = ChupManHinhService.instance != null
        ttChup.text = if (chup) "✔ Đang được phép" else "✘ Chưa cho phép (mỗi lần mở lại máy cần cho phép lại)"
        ttChup.setTextColor(if (chup) Color.rgb(30, 140, 60) else Color.rgb(190, 40, 40))
    }

    private fun luu() {
        val cd = Kho.docCaiDat(this)
        cd.he = He.values()[spHe.selectedItemPosition]
        cd.mucTieu = if (rS.isChecked) 'S' else 'A'
        cd.nhaMayLv6 = cbNhaMay.isChecked
        cd.nghiMs = (oNghi.text.toString().toIntOrNull() ?: 600).coerceIn(150, 5000)
        val cn = Kho.CachNhap(cbTuyChinh.isChecked, (oSoBo.text.toString().toIntOrNull() ?: 1).coerceIn(0, 50), coBan[spCoBan.selectedItemPosition])
        val sl = mutableMapOf<ChiSo, Int>()
        if (cn.tuyChinh) for ((cs, e) in oSoLuong) sl[cs] = (e.text.toString().toIntOrNull() ?: 0).coerceIn(0, 200)
        else { for (cs in ChiSo.values()) sl[cs] = 0; sl[ChiSo.HP] = cn.soBo * 3; sl[cn.coBan] = cn.soBo }
        if (sl.values.sum() == 0) { Toast.makeText(this, "Số lượng đang là 0", Toast.LENGTH_SHORT).show(); return }
        cd.soLuong = sl
        Kho.luuCaiDat(this, cd); Kho.luuCachNhap(this, cn)
        Toast.makeText(this, "Đã lưu: " + sl.filter { it.value > 0 }.entries.joinToString { "${it.key.ten} ${it.value}" }, Toast.LENGTH_LONG).show()
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
