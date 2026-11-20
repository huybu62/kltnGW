# Hội Tụ Auto: tool tự tiêu thể lực

Đây là cửa sổ nhỏ luôn nổi trên giả lập Android, có 2 chế độ:
- **Càn quét map** (mặc định): mở lần lượt từng khu (toà nhà) trên bản đồ, bấm *Càn quét*, rồi *Càn quét lần nữa* cho tới khi đủ số lần hoặc hết thể lực. Xong một khu thì đóng lại và sang khu kế.
- **Xúc xắc (sự kiện)**: tự đổ xúc xắc và xử lý các ô gặp trên bản đồ: oẳn tù xì, đánh boss (chọn team rồi xuất chiến), cửa hàng, phái đội chiếm giữ, nhận thưởng, đóng popup.

Tool dừng khi hết thể lực hoặc khi đủ số lần bạn đặt.

Tool chỉ **nhìn màn hình rồi chạm**, giống người bấm. Nó không đọc hay sửa dữ liệu của game.
Một tool cho chạy được **nhiều giả lập cùng lúc**, mỗi giả lập có nút Chạy/Dừng riêng.

> ⚠ Nhiều game cấm dùng công cụ tự động và có thể khoá tài khoản. Tự bạn cân nhắc khi dùng.

## 1. Cài đặt (một lần)
1. Cài **Python 3.10 trở lên** từ python.org. Khi cài nhớ tick **"Add python.exe to PATH"**.
2. Chỉnh giả lập:
   - Độ phân giải **1280×720** (hoặc mức khác, miễn là **giữ nguyên** từ lúc cắt mẫu về sau). Nếu chạy 2 giả lập, để **cùng độ phân giải** thì dùng chung được bộ ảnh mẫu.
   - Bật ADB:
     - **LDPlayer:** Cài đặt → Khác → Gỡ lỗi ADB → *Mở kết nối cục bộ*.
     - **BlueStacks:** Cài đặt → Nâng cao → *Android Debug Bridge*.
     - **MuMu / Nox:** đã bật sẵn.
3. Nháy đúp **`chay.bat`**. Lần đầu tool sẽ tự cài thư viện, mất 1–2 phút.

### Trên máy Mac
1. Cài Python bản macOS từ python.org/downloads/macos.
2. Mở **BlueStacks** → Cài đặt → **Nâng cao** → bật **Android Debug Bridge (ADB)**. Bên dưới sẽ hiện địa chỉ `127.0.0.1:5555`.
3. **Đừng** nháy đúp `main.py`: Mac sẽ mở bằng *Python Launcher*, không chạy được tool.
4. Lần đầu: **chuột phải** vào **`chay.command`** → **Mở** → **Mở**. Mac hỏi vì file tải từ mạng về. Từ lần sau chỉ cần nháy đúp.
   - Nếu Mac báo không có quyền chạy, mở **Terminal**, gõ `chmod +x ` (có dấu cách cuối), kéo file `chay.command` thả vào cửa sổ Terminal, rồi Enter.
5. Một cửa sổ Terminal mở ra. Lần đầu tool tự cài thư viện và tự tải `adb` của Google. Xong thì overlay hiện lên.
6. **Giữ cửa sổ Terminal đó**: đóng nó là tắt tool. Trên Mac, phím dừng F12 (có thể phải giữ thêm `fn`) chỉ có tác dụng khi đang bấm vào overlay.

Tool tự tìm `adb` có sẵn trong LDPlayer, MuMu, BlueStacks và Nox. Nếu không tìm thấy:
- ghi đường dẫn `adb.exe` vào `"adb_path"` trong `config.json`, ví dụ `"C:\\LDPlayer\\LDPlayer9\\adb.exe"`; hoặc
- tải [platform-tools](https://developer.android.com/tools/releases/platform-tools) và để thư mục `platform-tools` cạnh `main.py`.

## 2. Kết nối giả lập
Bấm **🔄 Tìm giả lập**. Các giả lập đang mở sẽ hiện trong khung *Giả lập*.
Nếu chưa thấy, gõ địa chỉ vào ô bên cạnh rồi bấm **Kết nối**:

| Giả lập | Địa chỉ |
|---|---|
| LDPlayer | `127.0.0.1:5555` (máy thứ 2: `5557`) |
| BlueStacks 5 | `127.0.0.1:5555` (xem trong Cài đặt → Nâng cao) |
| MuMu 12 | `127.0.0.1:16384` (máy thứ 2: `16416`) |
| Nox | `127.0.0.1:62001` (máy thứ 2: `62025`) |

Một giả lập có thể hiện 2 dòng, ví dụ `emulator-5554` và `127.0.0.1:5555`. Đó là cùng một máy, **chỉ chạy một dòng**.

## 3. Chế độ Càn quét map
Thư mục `mau/` **đã có sẵn** các mẫu cắt từ ảnh chụp game: chữ *Thể lực*, nút *Càn quét*, *Thám hiểm*, X của popup, *Càn quét lần nữa*, *Đóng*, và toà *Công xưởng*. Mẫu tự co giãn theo độ phân giải giả lập, nên thường không cần cắt lại.

1. Mở game tới **bản đồ có các toà nhà**, nơi thấy thanh *Thể lực*.
2. Trên overlay chọn **Chế độ: Càn quét map**.
3. **Lập danh sách khu**, chọn một trong hai cách:
   - **🔎 Dò khu tự động** (nên dùng): trong lúc dò **đừng bấm gì**. Tool vuốt về góc trên-trái bản đồ, rồi **lướt hết bản đồ** theo hình chữ chi: dò xong một màn thì vuốt sang màn bên cạnh, hết hàng thì xuống hàng dưới. Ở mỗi màn, tool chạm theo lưới và bỏ qua những chỗ đã chạm ở màn trước. Bản đồ cỡ 2×2 màn hình mất khoảng 6–10 phút. Chỗ nào mở ra popup *Thám hiểm / Càn quét* thì ghi lại thành một khu, kèm vị trí trên cả bản đồ. Khu chưa có nút *Càn quét* sẽ được thêm nhưng để **bỏ tick**. Ảnh tiêu đề từng khu lưu ở `mau/tieu_de_khu/khu_1.png`, `khu_2.png`..., để bạn biết Khu 1, Khu 2 là toà nào. Muốn đổi tên thì sửa `"ten"` trong `config.json`.
   - **Thêm tay:** bấm **✂**, **chạm 1 điểm** vào toà nhà trên ảnh, bấm **➕ Thêm khu** rồi đặt tên.

   Tool quét các khu theo thứ tự trong danh sách. Dùng **↑** để đổi thứ tự, **✕** để xoá, bỏ tick để tạm bỏ qua một khu.
4. Đặt các tuỳ chọn:
   - **Mỗi khu quét N lần rồi sang khu khác.** Để `0` (mặc định) thì quét một khu **tới khi hết 99 lượt** rồi mới sang khu kế. Tool tự nhận ra khi khu hết lượt, kể cả khi hôm nay bạn đã quét tay một phần.
   - **Thể lực tối đa:** số sau dấu `/` trên thanh thể lực, ví dụ `43/120` thì nhập 120. Nhân vật lên cấp mà số này đổi thì nhớ sửa lại.
   - **Mỗi lần tốn:** số thể lực mỗi lần quét, ví dụ ⚡4. Khu nào tốn khác thì thêm `"chi_phi": 6` vào khu đó trong `config.json`.
   - **Bấm 'lần nữa' mỗi … giây:** nhịp bấm *Càn quét lần nữa*, mặc định 0,35 giây. Tool bấm liên tục theo nhịp này và đếm số lần quét theo con số *Số lần* trên màn hình. Thấy game bỏ lỡ cú bấm thì tăng lên 0,5; muốn nhanh hơn thì giảm còn 0,2.
   - **Lướt cả bản đồ:** để tick thì lúc quét, tool tự vuốt bản đồ tới đúng khu, kể cả khu nằm ngoài màn hình. Mỗi lần chạy, tool vuốt về góc trên-trái để lấy mốc. Nếu mở nhầm khu (tiêu đề popup khác lúc dò), tool đóng lại, lấy mốc lại rồi thử tiếp.
5. Bấm **▶ Chạy**.

Cách tool tiêu thể lực:
- Mỗi lần về bản đồ, tool **đọc thanh thể lực cam** để biết còn bao nhiêu. Khi không đủ cho 1 lần quét, tool đóng hết popup rồi **dừng**. Tool không bấm mua thể lực.
- **Thể lực đã mua vượt mức** (ví dụ 500/120, thanh đầy): tool không ước tính theo thanh nữa mà cứ quét tiếp. Khi hết thật, bấm *Càn quét lần nữa* sẽ không còn tác dụng; tool về bản đồ đọc lại thanh rồi dừng.
- Nếu bấm *Càn quét lần nữa* mà *Số lần* không đổi, tool về bản đồ đọc lại thể lực. Thể lực vẫn đủ thì khu đó **đã hết 99 lượt**, tool tự sang khu kế. Thể lực không đủ thì tool dừng.
- Nếu game hiện popup báo **không đủ thể lực**, bạn nên cắt mẫu đó đặt tên `cq_khong_du`. Gặp popup này tool sẽ bấm X rồi dừng, **không bao giờ bấm mua**.
- Gặp màn lạ quá 90 giây thì tool dừng.

## 4. Cắt ảnh mẫu (cho chế độ Xúc xắc, hoặc khi cần cắt lại)
Tool nhận ra nút nhờ ảnh mẫu do **bạn cắt từ chính game của mình**.

1. Trong game, mở đến màn hình có nút cần cắt.
2. Bấm **✂** ở dòng giả lập đó (hoặc **✂ Cắt mẫu**). Cửa sổ hiện ảnh màn hình giả lập.
3. **Kéo chuột** khoanh quanh nút, chọn **Tên mẫu** trong danh sách rồi bấm **💾 Lưu mẫu**.
4. Bấm **🔍 Thử nhận diện** để kiểm tra. Mẫu khớp sẽ có khung xanh và điểm khớp (từ 0.85 trở lên là đạt).

Các mẫu cần có. Thiếu mẫu nào thì luật dùng mẫu đó tự bỏ qua, nên cứ cắt dần cũng được:

| Tên mẫu | Cắt cái gì |
|---|---|
| `nut_xuc_xac` | Nút đổ xúc xắc trên bản đồ |
| `het_the_luc` | Thông báo hết thể lực (tiêu đề hoặc biểu tượng) |
| `nut_dung_binh` | Nút dùng bình hồi thể lực (nếu muốn tự uống bình) |
| `man_oan_tu_xi` | Dấu hiệu màn oẳn tù xì, ví dụ tiêu đề |
| `keo`, `bua`, `bao` | 3 nút Kéo / Búa / Bao |
| `nut_danh_boss` | Nút khiêu chiến khi vào ô boss |
| `man_chon_team` | Dấu hiệu màn chọn đội hình, ví dụ tiêu đề |
| `team_chon` | Ô / tab đội hình **bạn muốn dùng** |
| `nut_xuat_chien` | Nút bắt đầu / xuất chiến |
| `nut_auto_tat` | Nút Auto trong trận lúc đang **tắt** |
| `dang_trong_tran` | Thứ chỉ có trong trận (nút tạm dừng, tốc độ...) |
| `man_cua_hang` | Dấu hiệu ô cửa hàng |
| `nut_mua` | Nút Mua (lúc còn bấm được) |
| `nut_roi_cua_hang` | Nút rời / đóng cửa hàng |
| `nut_phai_doi` | Nút phái đội chiếm giữ |
| `nut_tiep_tuc` | Nút Tiếp tục / Nhận ở màn kết quả, phần thưởng |
| `cham_de_tiep_tuc` | Chữ "chạm để tiếp tục" (nếu game có) |
| `nut_xac_nhan` | Nút Xác nhận / OK |
| `nut_dong` | Nút X đóng popup |

**Mẹo cắt mẫu**
- Cắt **vừa khít** phần đặc trưng của nút (chữ và biểu tượng). **Tránh** con số thay đổi (vàng, thể lực, hẹn giờ) và hiệu ứng nhấp nháy.
- Nút có nhiều kiểu (ví dụ 2 kiểu nút Xác nhận): lưu trùng tên rồi chọn **"Không"** để thêm biến thể. Tool lưu thành `nut_xac_nhan@2.png`, và khớp kiểu nào cũng được.
- Nút đang **bị làm tối** sau popup hoặc **bị xám** thì tool tự bỏ qua, không bấm nhầm.
- Nhận nhầm thì tăng ngưỡng riêng cho mẫu đó trong `config.json`, ví dụ `"nguong_rieng": {"nut_dong": 0.92}`. Không nhận ra thì cắt lại mẫu nhỏ hơn hoặc hạ ngưỡng (0.8).
- Chạm 1 điểm (không kéo) trên ảnh để xem **toạ độ**. Dùng khi cần chạm vào vị trí cố định (xem mục 6).

## 5. Chạy
- Tick hoặc bỏ tick từng việc trong *Tuỳ chọn*. **Mua vật phẩm** và **Dùng bình hồi thể lực** mặc định **tắt** để tránh tiêu tiền hoặc kim cương ngoài ý muốn.
- *Dừng sau N lần*: đếm theo lượt xúc xắc hoặc lần càn quét. Để `0` thì chạy tới khi hết thể lực.
- Bấm **▶ Chạy** ở từng giả lập. Bấm **⏹ Dừng** hoặc **F12** để dừng tất cả.
- Bấm **▾** để thu gọn overlay, chỉ còn các dòng giả lập.

Tool tự dừng khi:
- thấy thông báo hết thể lực;
- đổ đủ số lượt đã đặt;
- **5 phút liền** không nhận ra màn hình nào;
- adb mất kết nối.

## 6. Tuỳ chỉnh luật xúc xắc (`config.json`)
Mục `"luat"` là danh sách việc, **xét từ trên xuống**. Luật đầu tiên mà các mẫu trong `"thay"` đều đang hiện sẽ được thực hiện. Sửa xong bấm **↻ Tải lại cấu hình**, không cần tắt tool.

| `lam` | Ý nghĩa |
|---|---|
| `cham` | Chạm vào mẫu (hoặc vào `muc_tieu` nếu có) |
| `cham_xy` | Chạm toạ độ cố định `"xy": [x, y]` |
| `cham_ngau_nhien` | Chạm ngẫu nhiên một mẫu trong `muc_tieu` (dùng cho oẳn tù xì) |
| `chuoi` | Làm nhiều bước liên tiếp (`buoc`), ví dụ chọn team rồi xuất chiến |
| `cho` | Chỉ chờ, ví dụ đang trong trận |
| `back` | Bấm nút Quay lại của Android |
| `dung` | Dừng tool |

Ví dụ: chọn team bằng **toạ độ** thay cho ảnh mẫu.
```json
"buoc": [
  {"cham_xy": [210, 330], "nghi_sau": 0.8},
  {"cham": "nut_xuat_chien", "cho_toi_da": 3}
]
```

Khi bị kẹt (lâu không nhận ra màn hình nào), đặt `"khi_ket"` để tool tự gỡ:
- `"bao"`: chỉ ghi log;
- `"back"`: bấm Quay lại;
- `"cham_xy"`: chạm vào toạ độ `"xy_khi_ket"`.

## Kiểm tra phần nhận diện
```
python test_bot.py
python test_sweep.py
python test_discover.py
python test_ban_do.py
```
Hai lệnh này chạy thử bộ luật xúc xắc trên màn hình tổng hợp, và chế độ càn quét trên ảnh chụp thật của game trong `anh_test/`. Không cần giả lập.
