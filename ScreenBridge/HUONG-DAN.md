# ScreenBridge: Hướng dẫn đầy đủ (tiếng Việt)

ScreenBridge biến một chiếc Mac, iMac hoặc iPad thành **màn hình phụ cho một chiếc Mac khác**, kể cả khi hai máy **đăng nhập hai Apple ID khác nhau**. Sidecar của Apple không làm được việc này.

> **Tình trạng hiện tại: đang ở Giai đoạn 3/4.**
> - **Giai đoạn 1 (đã chạy thật):** hai máy tự tìm thấy nhau, ghép đôi bằng mã 6 số, kết nối có mã hóa.
> - **Giai đoạn 2 (đã chạy thật):** màn hình Mac hiện lên iPad, chế độ Mở rộng / Phản chiếu, 30/60/120 Hz. Đo được ~100 hình/giây, độ trễ mạng 1–2 ms qua cáp, 7–15 ms qua Wi-Fi.
> - **Giai đoạn 3 (đã chạy thật):** chạm và Apple Pencil trên iPad điều khiển Mac; tự chuyển sang cáp khi cắm vào; tự kết nối lại khi rớt mạng.
> - **Giai đoạn 3b (mới viết, chờ thử):** bàn phím Folio và Magic Trackpad của iPad điều khiển Mac; âm thanh Mac phát trên iPad; **dùng khi gập MacBook**. Cách thử ở [mục 8D](#8d-bàn-phím-trackpad-âm-thanh-và-dùng-khi-gập-macbook).
> - Phần mới **chưa được biên dịch thử** (máy làm việc của Claude không có Xcode). Xem [mục 9](#9-khi-build-bị-lỗi) để biết cách gửi lỗi cho Claude sửa.

---

## Mục lục

1. [Ứng dụng gồm những gì](#1-ứng-dụng-gồm-những-gì)
2. [Cần chuẩn bị](#2-cần-chuẩn-bị)
3. [Cài công cụ (làm một lần)](#3-cài-công-cụ-làm-một-lần)
4. [Tải mã nguồn và tạo project Xcode](#4-tải-mã-nguồn-và-tạo-project-xcode)
5. [Thiết lập ký ứng dụng (Signing)](#5-thiết-lập-ký-ứng-dụng-signing)
6. [Chạy trên Mac (máy phát, Host)](#6-chạy-trên-mac-máy-phát-host)
7. [Chạy trên iPad hoặc Mac thứ hai (máy nhận, Display)](#7-chạy-trên-ipad-hoặc-mac-thứ-hai-máy-nhận-display)
8. [Kiểm tra Giai đoạn 1 từng bước](#8-kiểm-tra-giai-đoạn-1-từng-bước)
    - [8B. Kiểm tra Giai đoạn 2 (hình ảnh màn hình)](#8b-kiểm-tra-giai-đoạn-2-hình-ảnh-màn-hình)
    - [8C. Kiểm tra Giai đoạn 3 (điều khiển bằng cảm ứng, cáp, kết nối lại)](#8c-kiểm-tra-giai-đoạn-3-điều-khiển-bằng-cảm-ứng-cáp-kết-nối-lại)
    - [8D. Bàn phím, trackpad, âm thanh và dùng khi gập MacBook](#8d-bàn-phím-trackpad-âm-thanh-và-dùng-khi-gập-macbook)
9. [Khi build bị lỗi](#9-khi-build-bị-lỗi)
10. [Xử lý sự cố khi chạy](#10-xử-lý-sự-cố-khi-chạy)
11. [Dùng cáp Thunderbolt](#11-dùng-cáp-thunderbolt)
12. [Vì sao chạy được với Apple ID khác nhau](#12-vì-sao-chạy-được-với-apple-id-khác-nhau)
13. [Giới hạn kỹ thuật cần biết](#13-giới-hạn-kỹ-thuật-cần-biết)
14. [Cấu trúc mã nguồn](#14-cấu-trúc-mã-nguồn)
15. [Câu hỏi thường gặp](#15-câu-hỏi-thường-gặp)
16. [Lộ trình tiếp theo](#16-lộ-trình-tiếp-theo)

---

## 1. Ứng dụng gồm những gì

Có **3 ứng dụng**, cùng dùng chung một thư viện mạng tên **ScreenBridgeKit**:

| Ứng dụng (tên scheme trong Xcode) | Chạy trên | Vai trò |
|---|---|---|
| **ScreenBridgeHost** | Mac (macOS 13 trở lên) | **Máy phát**: Mac có màn hình cần chia sẻ. Chạy trên **thanh menu** (góc trên bên phải), không có biểu tượng ở Dock. |
| **ScreenBridgeDisplay-iOS** | iPad (iPadOS 16 trở lên) | **Máy nhận**: dùng iPad làm màn hình phụ. |
| **ScreenBridgeDisplay-macOS** | Mac / iMac (macOS 13 trở lên) | **Máy nhận**: dùng một Mac khác làm màn hình phụ. |

Ứng dụng Mac là **Universal Binary**: một bản chạy được cả trên Mac chip Apple (M1, M2, M3, M4…) lẫn Mac chip Intel đời 2017 trở về sau.

---

## 2. Cần chuẩn bị

| Thứ cần có | Ghi chú |
|---|---|
| Một chiếc **Mac để build** | Cài **macOS 13 Ventura** trở lên. Máy này cũng có thể làm máy phát. |
| **Xcode 15** trở lên | Miễn phí trên Mac App Store. |
| Một **Apple ID** để ký ứng dụng | **Tài khoản miễn phí là đủ.** Apple ID này *không* cần trùng với Apple ID đăng nhập iCloud trên iPad. |
| Máy nhận | iPad chạy iPadOS 16 trở lên, hoặc một Mac thứ hai chạy macOS 13 trở lên. |
| Cáp USB-C / Lightning | Chỉ dùng để **cài app lên iPad** lần đầu. |
| *(Tùy chọn)* Cáp **Thunderbolt** | Nối Mac với Mac để có kết nối nhanh nhất. Xem [mục 11](#11-dùng-cáp-thunderbolt). |

Hai máy nên **bật Wi-Fi**. Nếu dùng chung một mạng Wi-Fi thì tốt nhất. Không chung mạng (hoặc không có router) vẫn kết nối được qua **Wi-Fi trực tiếp giữa hai máy**, cùng công nghệ mà AirDrop đang dùng.

---

## 3. Cài công cụ (làm một lần)

### 3.1. Cài Xcode

1. Mở **App Store**, tìm **Xcode** và bấm **Nhận / Cài đặt**. Bản cài khá nặng, cỡ 10 GB trở lên.
2. Mở Xcode **một lần** để nó cài thêm thành phần. Ở màn hình chọn nền tảng, tick **iOS** nếu bạn sẽ chạy trên iPad.
3. Mở **Terminal** (Launchpad → Khác → Terminal) và chạy lệnh dưới đây để máy dùng đúng Xcode vừa cài. Máy sẽ hỏi mật khẩu đăng nhập Mac.

```bash
sudo xcode-select -s /Applications/Xcode.app
```

### 3.2. Cài Homebrew (nếu chưa có)

Homebrew là trình cài phần mềm dòng lệnh cho Mac. Kiểm tra máy đã có chưa:

```bash
brew --version
```

Nếu báo `command not found`, cài bằng lệnh:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Cài xong, Terminal in ra mục **"Next steps"**. **Bắt buộc** phải chạy 3 lệnh dưới đây, nếu không Terminal sẽ báo `zsh: command not found: brew`. Đây là lệnh cho Mac chip Apple (M1, M2…); Mac chip Intel thường không cần bước này.

```bash
echo >> ~/.zprofile
```

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> ~/.zprofile
```

```bash
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
```

> ⚠️ **Đừng gõ chữ `echo …` (có dấu ba chấm).** Phải chép **đúng nguyên văn** các lệnh ở trên, hoặc các lệnh Homebrew in ra ở mục "Next steps".

Kiểm tra lại. Lệnh phải in ra số phiên bản, ví dụ `Homebrew 4.x.x`:

```bash
brew --version
```

### 3.3. Cài XcodeGen

XcodeGen tạo file project Xcode từ file cấu hình `project.yml`:

```bash
brew install xcodegen
```

---

## 4. Tải mã nguồn và tạo project Xcode

### 4.1. Tải mã nguồn

```bash
cd ~/Desktop
```

```bash
git clone https://github.com/huybu62/kltnGW.git
```

```bash
cd kltnGW && git checkout claude/kind-bell-nai7c7
```

Nếu kho GitHub đang để riêng tư (private), Mac sẽ hỏi đăng nhập GitHub. Bạn cũng có thể tải file ZIP của nhánh `claude/kind-bell-nai7c7` trên trang GitHub rồi giải nén.

### 4.2. Tạo project Xcode

```bash
cd ~/Desktop/kltnGW/ScreenBridge && xcodegen generate
```

Lệnh này tạo ra `ScreenBridge.xcodeproj` cùng các file `Info.plist` và `.entitlements`.
**Mỗi khi sửa `project.yml`, chạy lại `xcodegen generate`.**

> ⚠️ Mọi chỉnh sửa bằng tay trong Xcode (Signing, Build Settings…) sẽ **bị ghi đè** khi chạy lại `xcodegen generate`. Hãy sửa trong `project.yml`, như hướng dẫn ở mục 5.

---

## 5. Thiết lập ký ứng dụng (Signing)

Muốn cài ứng dụng lên iPad, Apple bắt buộc phải ký ứng dụng bằng một Apple ID.

### 5.1. Thêm Apple ID vào Xcode

1. Mở Xcode → menu **Xcode → Settings… (⌘,)** → tab **Accounts**.
2. Bấm **+** → **Apple ID** → đăng nhập. Dùng Apple ID nào cũng được, kể cả tài khoản miễn phí.
3. Tài khoản miễn phí sẽ hiện ra với tên **"<Tên bạn> (Personal Team)"**.

### 5.2. Lấy mã Team ID

Cách dễ nhất:

1. Mở project vừa tạo:

   ```bash
   open ~/Desktop/kltnGW/ScreenBridge/ScreenBridge.xcodeproj
   ```

2. Ở cột bên trái, bấm vào **ScreenBridge** (biểu tượng màu xanh trên cùng) → chọn target **ScreenBridgeDisplay-iOS** → tab **Signing & Capabilities** → ở ô **Team**, chọn team của bạn.
3. Chuyển sang tab **Build Settings**, gõ `development team` vào ô tìm kiếm. Bạn sẽ thấy một mã gồm **10 ký tự**, ví dụ `A1B2C3D4E5`. Chép mã đó lại.

(Cách khác: mở **Keychain Access** → tìm chứng chỉ **"Apple Development: …"** → mục **Organizational Unit** chính là Team ID.)

### 5.3. Sửa `project.yml`

Mở `ScreenBridge/project.yml` bằng TextEdit hoặc VS Code, sửa **5 chỗ**. Thay `tenban` bằng một chữ riêng của bạn, viết thường, không dấu, không khoảng trắng:

```yaml
options:
  bundleIdPrefix: com.tenban.screenbridge          # (1)

settings:
  base:
    DEVELOPMENT_TEAM: "A1B2C3D4E5"                 # (2) Team ID của bạn

# trong target ScreenBridgeHost:
        PRODUCT_BUNDLE_IDENTIFIER: com.tenban.screenbridge.host          # (3)
# trong target ScreenBridgeDisplay-macOS:
        PRODUCT_BUNDLE_IDENTIFIER: com.tenban.screenbridge.display       # (4)
# trong target ScreenBridgeDisplay-iOS:
        PRODUCT_BUNDLE_IDENTIFIER: com.tenban.screenbridge.display.ios   # (5)
```

Tạo lại project. Nếu Xcode đang mở project thì đóng lại trước:

```bash
cd ~/Desktop/kltnGW/ScreenBridge && xcodegen generate && open ScreenBridge.xcodeproj
```

> **Vì sao phải đổi Bundle ID?** Mỗi Bundle ID chỉ thuộc về một tài khoản. Nếu Xcode báo *"… is not available"* hoặc *"Failed to register bundle identifier"*, nghĩa là ID đó đã có người dùng; chọn chữ `tenban` khác.

### 5.4. Lưu ý với tài khoản miễn phí

- App cài lên iPad **chỉ chạy được 7 ngày**. Hết hạn thì cắm iPad vào Mac và bấm **Run** lại là xong; dữ liệu ghép đôi vẫn giữ nguyên.
- Mỗi thiết bị chỉ cài được tối đa **3 app** ký bằng tài khoản miễn phí.
- Tài khoản Apple Developer trả phí (99 USD/năm) không có các giới hạn trên.

---

## 6. Chạy trên Mac (máy phát, Host)

1. Trong Xcode, nhìn thanh trên cùng, ở ô **scheme** (bên cạnh nút ▶︎), chọn **ScreenBridgeHost**.
2. Ở ô thiết bị bên cạnh, chọn **My Mac**.
3. Bấm **▶︎ Run** (hoặc **⌘R**).
4. Ứng dụng **không hiện cửa sổ, không có biểu tượng ở Dock**. Hãy nhìn lên **thanh menu** ở góc trên bên phải màn hình: sẽ có biểu tượng hai hình chữ nhật chồng lên nhau ⧉. Bấm vào để mở bảng điều khiển.
5. Nếu được hỏi:
   - **"ScreenBridge muốn tìm thiết bị trên mạng cục bộ"** → bấm **Cho phép / Allow**.
   - **"Cho phép ứng dụng nhận kết nối đến?"** (tường lửa) → bấm **Allow**.

Bảng điều khiển hiển thị tên máy, mã ID (8 ký tự đầu), cổng mạng (port), và danh sách **Nearby displays** (các màn hình ở gần).

---

## 7. Chạy trên iPad hoặc Mac thứ hai (máy nhận, Display)

### 7A. Chạy trên iPad

**Chuẩn bị iPad (làm một lần):**

1. Cắm iPad vào Mac bằng cáp. Trên iPad, bấm **Tin cậy (Trust)** và nhập mật mã iPad.
2. Bật **Chế độ nhà phát triển** (iPadOS 16+): **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển (Developer Mode)** → bật → iPad khởi động lại → xác nhận **Bật**.
   *Nếu chưa thấy mục này:* chọn iPad trong Xcode và bấm Run một lần, mục sẽ xuất hiện.

**Cài app:**

1. Trong Xcode, chọn scheme **ScreenBridgeDisplay-iOS**, ô thiết bị chọn **iPad của bạn**.
2. Bấm **⌘R**. Lần đầu Xcode có thể mất vài phút để chuẩn bị iPad.
3. Nếu iPad báo **"Nhà phát triển không được tin cậy"**: vào **Cài đặt → Cài đặt chung → Quản lý VPN & thiết bị** → chọn Apple ID của bạn → **Tin cậy**. Sau đó mở lại app.
4. Khi app hỏi quyền **Mạng cục bộ (Local Network)** → bấm **Cho phép**.

> iPad có thể đăng nhập **bất kỳ Apple ID nào**, khác với Apple ID trên Mac hay Apple ID dùng để ký app.

### 7B. Chạy trên Mac thứ hai

**Cách dễ nhất:** trên Mac thứ hai, làm lại các mục **3 → 5**, rồi chọn scheme **ScreenBridgeDisplay-macOS** → **My Mac** → **⌘R**.

**Cách chép app sang:**

1. Trên Mac đã build: menu **Product → Show Build Folder in Finder** → vào `Products/Debug/` → lấy **ScreenBridge Display.app**.
2. Chép sang Mac thứ hai (AirDrop, USB…) và đặt vào thư mục **Applications**.
3. Lần đầu mở: **chuột phải → Mở (Open)** → **Mở**. Nếu macOS vẫn chặn: **Cài đặt hệ thống → Quyền riêng tư & Bảo mật** → kéo xuống dưới → **Vẫn mở (Open Anyway)**.
4. Nếu báo *"app bị hỏng"*, gỡ cờ cách ly bằng lệnh sau, rồi mở lại:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/ScreenBridge Display.app"
   ```

---

## 8. Kiểm tra Giai đoạn 1 từng bước

Bố trí: **Mac A** chạy *ScreenBridgeHost*. **iPad** (hoặc **Mac B**) chạy *ScreenBridgeDisplay*. Nên thử với **hai Apple ID khác nhau** để thấy đúng điểm khác biệt so với Sidecar.

| Bước | Làm gì | Kết quả đúng |
|---|---|---|
| 1 | Mở app trên cả hai máy, **cho phép Mạng cục bộ**. | Dòng trạng thái hiện *"Visible as …"* (đang hiển thị với tên …). |
| 2 | Chờ 1–3 giây. | Mỗi máy thấy máy kia trong danh sách, kèm nhãn đường kết nối: **Wi-Fi**, **Direct Wi-Fi** (Wi-Fi trực tiếp), **Thunderbolt** (nếu cắm cáp). Với iPad còn hiện độ phân giải và tần số quét, ví dụ `2732×2048 @120Hz`. |
| 3 | Bấm **Connect** ở máy bất kỳ. | **Cả hai màn hình hiện cùng một mã 6 số**, ví dụ `482 913`. |
| 4 | So hai mã. **Giống nhau** thì bấm **Codes Match** trên **cả hai** máy. | Hiện **Connected to …** (đã kết nối), loại đường truyền và **RTT** (độ trễ khứ hồi): vài ms qua Wi-Fi, dưới 1 ms qua Thunderbolt. |
| 5 | Bấm **Disconnect**, rồi bấm **Connect** lại. | Kết nối **ngay, không hỏi mã nữa**, vì hai máy đã ghép đôi. Có biểu tượng 🔒 cạnh tên máy. |
| 6 | Ở mục **Paired devices** của một máy, bấm **Forget** (quên thiết bị), rồi Connect lại. | Mã 6 số **hiện lại**. Máy vẫn còn nhớ sẽ thấy thêm **cảnh báo màu cam**. |
| 7 | Trên iPad: vuốt ra màn hình chính, chờ vài giây, rồi mở lại app. | Mac lại thấy iPad sau vài giây. |
| 8 | *(Mac ↔ Mac)* Cắm cáp Thunderbolt, xem [mục 11](#11-dùng-cáp-thunderbolt). | Xuất hiện nhãn ⚡ **Thunderbolt**, và kết nối mới ưu tiên đường này. |

**Ý nghĩa các nút (giao diện tạm thời đang dùng tiếng Anh):**

| Chữ trên app | Nghĩa |
|---|---|
| Nearby displays / Nearby Macs | Màn hình / Mac ở gần |
| Connect | Kết nối |
| Codes Match | Mã trùng khớp (đồng ý ghép đôi) |
| Decline | Từ chối |
| Disconnect | Ngắt kết nối |
| Paired devices | Thiết bị đã ghép đôi |
| Forget | Quên thiết bị này |
| Busy | Máy đó đang bận kết nối với máy khác |
| Update needed | Cần cập nhật app (khác phiên bản) |

### Chạy kiểm thử tự động (không cần iPad)

Bộ kiểm thử có một bài thử thật: hai "thiết bị" với hai danh tính độc lập kết nối với nhau ngay trên một máy, mô phỏng đúng trường hợp khác Apple ID.

```bash
cd ~/Desktop/kltnGW/ScreenBridge/Packages/ScreenBridgeKit && swift test
```

Kết quả đúng: dòng cuối có chữ `Executed … tests, with 0 failures`.

### Kiểm tra bản Universal (Intel + Apple Silicon)

```bash
cd ~/Desktop/kltnGW/ScreenBridge && xcodebuild -project ScreenBridge.xcodeproj -scheme ScreenBridgeHost -configuration Release -derivedDataPath build
```

```bash
lipo -archs "build/Build/Products/Release/ScreenBridge.app/Contents/MacOS/ScreenBridge"
```

Kết quả đúng: `x86_64 arm64`.

---

## 8B. Kiểm tra Giai đoạn 2 (hình ảnh màn hình)

### Cập nhật và cài lại cả hai app

Phiên bản mới đổi giao thức kết nối, nên **phải cài lại cả app Mac lẫn app iPad**. App cũ sẽ hiện *"Update needed"*.

1. Thoát Xcode (**⌘Q**).
2. Lấy bản mới, tạo lại project, rồi chạy kiểm thử:

   ```bash
   cd ~/Desktop/kltnGW && git pull
   ```

   ```bash
   cd ScreenBridge && xcodegen generate
   ```

   ```bash
   cd Packages/ScreenBridgeKit && swift test
   ```

   Kiểm thử giờ có thêm bài **nén video bằng chip phần cứng rồi giải nén lại** ngay trên Mac. Dòng cuối phải là `with 0 failures`.
3. Mở project. Chạy **ScreenBridgeDisplay-iOS** lên iPad trước (**⌘R**), sau đó chạy **ScreenBridgeHost** trên **My Mac** (**⌘R**). Khi Xcode hỏi dừng app iPad thì cứ bấm **Stop**, rồi mở app trên iPad bằng tay.

### Lần đầu: ghép đôi lại và cấp quyền quay màn hình

- **Ghép đôi lại một lần:** app Mac giờ không còn chạy trong "hộp cát" (sandbox) nữa, vì chế độ Mở rộng cần như vậy. Do đó Mac lưu dữ liệu ở chỗ mới và quên iPad. iPad sẽ hiện mã kèm **cảnh báo cam** *"đã từng ghép đôi"*. Lần này là bình thường: so mã rồi bấm **Codes Match** trên cả hai máy.
- **Quyền quay màn hình (Screen Recording):** lần đầu kết nối, macOS hỏi cho phép ScreenBridge quay màn hình.
  1. Bấm **Mở Cài đặt hệ thống** (hoặc nút **Open Settings** trong menu ScreenBridge).
  2. Vào **Quyền riêng tư & Bảo mật → Ghi màn hình & âm thanh hệ thống**, bật **ScreenBridge**.
  3. macOS có thể đòi **thoát và mở lại** app. Làm theo, rồi kết nối lại (hoặc bấm **Try Again**).

### Thử từng chế độ

Khi đã kết nối, menu ScreenBridge trên Mac có thêm phần **Screen sharing**:

| Mục | Lựa chọn |
|---|---|
| **Mode** (chế độ) | **Extend** = iPad thành màn hình thứ hai (mặc định) · **Mirror** = iPad hiện y hệt màn hình Mac |
| **Quality** (chất lượng) | **Battery Saver** (tiết kiệm pin: nửa độ phân giải, ít dữ liệu) · **Balanced** (cân bằng: đủ độ phân giải, mặc định) · **Best Quality** (nét nhất, nhiều dữ liệu hơn) |
| **Refresh** (tần số quét) | **30 Hz** (tiết kiệm pin) · **60 Hz** (mặc định) · **120 Hz** (mượt nhất, chỉ iPad Pro có màn hình ProMotion) |

| Bước | Làm gì | Kết quả đúng |
|---|---|---|
| 1 | Kết nối Mac với iPad như Giai đoạn 1. | Menu Mac hiện **Streaming** màu xanh, kèm dòng số liệu dạng `HEVC 2732×2048 · 60 fps · 25.0 Mbps · 15 ms`. |
| 2 | Nhìn iPad. | iPad chuyển sang **toàn màn hình đen**, rồi hiện hình. Ở chế độ Extend đó là một **màn hình trống** (hình nền macOS). |
| 3 | Trên Mac, kéo một cửa sổ (ví dụ Safari) **ra mép phải màn hình** và tiếp tục kéo sang. | Cửa sổ "bay" sang iPad. |
| 4 | Nếu cửa sổ sang sai phía: **Cài đặt hệ thống → Màn hình (Displays) → Sắp xếp (Arrange)**. | Kéo ô màn hình iPad tới vị trí thật của iPad so với Mac. |
| 5 | Đổi **Mode** sang **Mirror**. | Sau 1–2 giây, iPad hiện **y hệt** màn hình Mac. Màn hình Mac rộng hơn iPad nên có viền đen trên dưới; đây là bình thường. |
| 6 | Đổi **Quality** sang **Battery Saver**. | Độ phân giải trong dòng số liệu giảm một nửa, Mbps giảm rõ. |
| 6b | Đổi **Refresh** sang **120 Hz**, rồi kéo cửa sổ qua lại trên iPad. | Dòng số liệu lên tới khoảng `120 fps` khi đang kéo; chuyển động mượt hơn rõ. |
| 7 | Trên iPad, **chạm 3 ngón cùng lúc**. (Trên Mac làm màn hình phụ: **⌘K**.) | Hiện thanh nhỏ phía trên: đường kết nối, số liệu, nút **Hide** (ẩn) và **Disconnect** (ngắt). |
| 8 | Bấm **Disconnect**. | Màn hình phụ biến mất khỏi Mac; các cửa sổ trên đó tự về màn hình Mac. |

**Ý nghĩa dòng số liệu** `HEVC 2732×2048 · 60 fps · 25.0 Mbps · 15 ms`:

| Phần | Nghĩa |
|---|---|
| HEVC / H.264 | Chuẩn nén video. HEVC nét hơn ở cùng dung lượng; Mac đời cũ tự dùng H.264. |
| 2732×2048 | Độ phân giải đang truyền |
| 60 fps | Số hình mỗi giây. **Khi màn hình đứng yên, con số này về gần 0**: không có gì thay đổi thì không gửi, nên tiết kiệm pin. |
| 25.0 Mbps | Lượng dữ liệu đang truyền |
| 15 ms | Độ trễ từ lúc Mac gửi tới lúc iPad nhận |

### Gửi Claude kết quả

Chụp màn hình gửi Claude:
1. Menu Mac lúc **Streaming** (có dòng số liệu).
2. iPad lúc đang hiện hình.
3. Nếu có: hình bị giật, trễ, mờ, sai màu, hoặc lỗi (chữ đỏ). Mô tả ngắn: *"kéo cửa sổ thì giật"*, *"chữ hơi mờ"*…

---

## 8C. Kiểm tra Giai đoạn 3 (điều khiển bằng cảm ứng, cáp, kết nối lại)

### Cập nhật

Giao thức không đổi, nhưng **cả hai app đều có code mới**, nên cài lại cả hai:

```bash
cd ~/Desktop/kltnGW && git pull
```

```bash
cd ScreenBridge && xcodegen generate && open ScreenBridge.xcodeproj
```

Chạy **ScreenBridgeDisplay-iOS** lên iPad, rồi **ScreenBridgeHost** trên **My Mac**.

### Cấp quyền điều khiển (một lần)

Muốn iPad bấm và kéo được trên Mac, macOS cần quyền **Trợ năng (Accessibility)**:

1. Kết nối và để Mac bắt đầu chia sẻ màn hình.
2. Trong menu ScreenBridge trên Mac, bấm **Open Accessibility Settings**.
3. Vào **Quyền riêng tư & Bảo mật → Trợ năng**, bật **ScreenBridge**. Nếu chưa có trong danh sách, bấm **+** và chọn app ScreenBridge.
4. Menu đổi thành **Touch & Apple Pencil control: on**.

> Mỗi lần Xcode build lại app, macOS có thể coi đó là app mới và tắt quyền này. Nếu chạm không còn tác dụng, vào lại Trợ năng: tắt rồi bật lại ScreenBridge (hoặc xóa bằng **−** rồi thêm lại).

### Thao tác trên iPad

| Thao tác trên iPad | Trên Mac |
|---|---|
| **Giữ yên 2 ngón khoảng nửa giây** | **Hiện / ẩn thanh trạng thái** của ScreenBridge |
| **Chạm 3 ngón** | **Hiện / ẩn thanh phím tắt** bên trái |
| **Chụm / mở 2 ngón** | Thu nhỏ / phóng to (gửi ⌘− / ⌘= cho app đang mở) |
| **Chạm 2 lần vào thân Apple Pencil** (Pencil 2 / Pencil Pro) | **Chuột phải**, tại chỗ bút đang trỏ |
| Chạm 1 ngón | Bấm chuột trái |
| Chạm nhanh 2 lần | Bấm đúp (mở file, chọn chữ) |
| Giữ 1 ngón rồi kéo | Kéo (di chuyển cửa sổ, kéo thả file, bôi đen chữ) |
| **Apple Pencil** chạm / kéo | Như ngón tay, nhưng phản hồi ngay, không có độ trễ chờ |
| **Apple Pencil để gần màn hình** (chưa chạm) | Con trỏ chuột di chuyển theo bút |
| Kéo 2 ngón | Cuộn trang, nhấc tay ra thì trang trôi tiếp một đoạn như trackpad Mac. **Vuốt ngang 2 ngón trong Safari/Chrome = Back/Forward** (cần bật trên Mac: Cài đặt hệ thống → Trackpad → Cử chỉ khác → *Vuốt giữa các trang*) |
| **Vuốt 3 ngón sang trái / phải** (trên màn hình iPad) | Chuyển màn hình Desktop / app toàn màn hình, như vuốt trackpad Mac. Cần **có từ 2 Desktop trở lên**, hoặc app đang ở chế độ toàn màn hình; mở Mission Control và bấm **+** để thêm Desktop. Vuốt 3 ngón trên **Magic Trackpad** thì iPadOS giữ cho nó, không sang Mac được |
| **Vuốt 3 ngón lên / xuống** | Mission Control / các cửa sổ của app đang dùng |
| **Bấm bằng Pencil rồi nhấc bút ra xa** | Con trỏ tự dời đi: nếu đang ở mép (Dock, thanh menu) thì lùi vào trong để **Dock tự ẩn**; nếu ở giữa thì dời sát mép phải, không che chỗ bạn vừa bấm. Chỉ áp dụng sau khi **bấm**, không áp dụng khi bút chỉ lơ lửng. (Muốn Dock tự ẩn: Cài đặt hệ thống → Desktop & Dock → bật *Tự động ẩn và hiện Dock*.) |
| Chạm 2 ngón | Bấm chuột phải (menu ngữ cảnh) |
| Bàn di chuột / chuột nối với iPad | Di chuyển con trỏ, bấm, cuộn |

### Bảng thử

| Bước | Làm gì | Kết quả đúng |
|---|---|---|
| 1 | Chế độ **Extend**: mở Finder rồi kéo cửa sổ sang iPad. Trên iPad, chạm vào một thư mục, chạm 2 lần để mở. | Chọn được thư mục; chạm 2 lần thì mở ra. |
| 2 | Kéo thanh tiêu đề cửa sổ bằng 1 ngón. | Cửa sổ di chuyển theo ngón tay. |
| 3 | Mở Safari trên iPad, kéo 2 ngón lên/xuống. | Trang cuộn **theo hướng ngón tay**, giống cuộn trên iPad. |
| 4 | Chạm 2 ngón vào màn hình nền. | Hiện menu chuột phải. |
| 5 | Đưa Apple Pencil lại gần màn hình, chưa chạm. | Con trỏ chuột chạy theo bút. |
| 6 | **Tự chuyển sang cáp:** kết nối bằng Wi-Fi (rút cáp ra trước), xác nhận menu Mac hiện *Wi-Fi*. Rồi cắm cáp. | Sau vài giây, đường kết nối đổi sang loại có dây và độ trễ (ms) giảm xuống còn 1–2. Hình chỉ đen chớp khoảng 1 giây. |
| 7 | **Rút cáp khi đang dùng.** | Hình đứng yên 1–3 giây, có chữ *Reconnecting…*, rồi chạy tiếp qua Wi-Fi. Các cửa sổ vẫn nằm trên màn hình iPad. |
| 8 | **Tắt Wi-Fi trên iPad 5 giây rồi bật lại** (không cắm cáp). | Hiện *Reconnecting…*, rồi tự chạy lại khi Wi-Fi có lại. Nếu quá 20 giây, màn hình phụ mới biến mất. |

Gửi Claude: mục nào chạy, mục nào không, và cảm nhận (ví dụ: *"cuộn bị ngược"*, *"chạm hơi trễ"*, *"Pencil chạy tốt"*).

---

## 8D. Bàn phím, trackpad, âm thanh và dùng khi gập MacBook

### Cập nhật

Cài lại **cả hai app**, như các lần trước:

```bash
cd ~/Desktop/kltnGW && git pull
```

```bash
cd ScreenBridge && xcodegen generate && open ScreenBridge.xcodeproj
```

Nếu sau khi build lại, chạm từ iPad không còn tác dụng: vào **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng**, tắt rồi bật lại ScreenBridge.

### Bàn phím Smart Keyboard Folio

Khi iPad đang hiện màn hình Mac, **mọi phím gõ trên Folio đều đi sang Mac**, kể cả ⌘ ⌥ ⌃ ⇧ và phím mũi tên. Giữ phím thì phím tự lặp, theo tốc độ lặp phím đã chỉnh trên Mac.

- **Gõ tiếng Việt:** dùng bộ gõ **trên Mac** (Telex/VNI của macOS, hoặc EVKey/OpenKey nếu cài trên Mac). Bộ gõ trên iPad không ảnh hưởng.
- **Phím tắt iPad giữ lại cho nó:** **⌘Tab**, **⌘Space** và phím 🌐 do iPadOS xử lý trước, không sang được Mac. Folio cũng không có phím Esc và F1–F12. Dùng **lớp phím thay thế**: giữ **⌃ Control + ⌥ Option** rồi bấm:

| Giữ ⌃⌥ + | Trên Mac thành |
|---|---|
| **Tab** | ⌘Tab (chuyển app) |
| **Space** | ⌘Space (Spotlight) |
| **`** (phím dấu huyền, cạnh số 1) | **Esc** |
| **1 … 9, 0, -, =** | **F1 … F12** |

- Rời màn hình video, chuyển sang app khác trên iPad, hoặc ngắt kết nối thì bàn phím lại gõ cho iPad như bình thường.

### Magic Trackpad / chuột nối với iPad

| Thao tác | Trên Mac |
|---|---|
| Di ngón tay | Di con trỏ. Con trỏ tròn của iPad được ẩn đi, chỉ còn con trỏ Mac. |
| Bấm | Bấm chuột trái (bấm 2 lần = bấm đúp) |
| Bấm bằng 2 ngón | Chuột phải |
| Vuốt 2 ngón | Cuộn |
| Bấm giữ rồi kéo | Kéo thả |

### Cử chỉ hệ thống của iPad (vuốt về màn hình chính, chuyển app)

- **Vuốt từ mép màn hình** (về Home, Trung tâm điều khiển, thông báo): khi đang hiện màn hình Mac, **phải vuốt 2 lần** mới có tác dụng. Vuốt nhầm một lần sẽ không thoát ra. Muốn về màn hình chính iPad: **vuốt lên từ đáy 2 lần**.
- **Vuốt 3–4 ngón trên Magic Trackpad** (chuyển app, về Home): đây là cử chỉ hệ thống của iPadOS, **app không tắt được**. Nếu không muốn bị chuyển app nhầm, tắt trong **Cài đặt → Đa nhiệm & cử chỉ** (Multitasking & Gestures), mục cử chỉ vuốt bằng nhiều ngón. Tên mục khác nhau tùy phiên bản iPadOS. Sau khi tắt, bạn vẫn về Home được bằng cách vuốt lên từ đáy màn hình 2 lần.
- **Thay cho cử chỉ trackpad của Mac**, dùng phím tắt có sẵn của macOS trên Folio: **⌃↑** = Mission Control, **⌃← / ⌃→** = chuyển giữa các màn hình Desktop (Spaces), **⌃↓** = các cửa sổ của app đang dùng.

### Con trỏ vẽ trên iPad, Apple Pencil cho app vẽ, chống chạm nhầm, thanh phím tắt

**Con trỏ vẽ trên iPad (bật sẵn).** Trong menu Mac: **Draw pointer on iPad (less lag)**.
- **Bật:** iPad tự vẽ con trỏ ngay tại chỗ bạn di trackpad hoặc Pencil, **không còn trễ**. Đổi lại con trỏ luôn là mũi tên thường, không đổi hình (chữ I, mũi tên kéo giãn…).
- **Tắt:** con trỏ là con trỏ thật của Mac nằm trong video, đổi hình đúng nhưng trễ một chút.
- Khi di chuột bằng trackpad của chính MacBook sang màn hình iPad, con trỏ vẫn hiện đúng chỗ.

**Apple Pencil cho app vẽ trên Mac.** Pencil hoạt động như **bảng vẽ** (giống Wacom): Photoshop, Illustrator, Krita, Affinity, Clip Studio… nhận **lực nhấn** (ấn mạnh thì nét đậm hơn) và **độ nghiêng** của bút. Các app khác coi Pencil như chuột bình thường.

**Chống chạm nhầm lòng bàn tay (tự động).** Khi đang dùng Pencil (bút đang lơ lửng, hoặc vừa dùng trong vòng 1 giây), mọi cú chạm bằng ngón tay và bàn tay đều bị bỏ qua. Bạn có thể tì tay lên màn hình khi viết hay vẽ. Chạm bằng phần rộng của bàn tay luôn bị bỏ qua.

**Thanh phím tắt bên trái màn hình iPad** (giống Sidecar):

| Nút | Cách dùng |
|---|---|
| **⌘ ⌥ ⌃ ⇧** | **Chạm 1 lần** để khóa phím (nút sáng màu; chạm lại để nhả). **Giữ** để chỉ nhấn trong lúc giữ. Ví dụ: tay trái giữ ⇧, tay phải dùng Pencil chọn nhiều file |
| **Esc, Undo, Redo, Cut, Copy, Paste, Save** | Chạm 1 lần (Undo = ⌘Z, Redo = ⇧⌘Z, Save = ⌘S…) |
| **🔅 🔆 · 🔈 🔊 🔇 · ⏯** (kéo thanh xuống dưới) | **Độ sáng** màn hình Mac, **âm lượng** Mac, phát / dừng nhạc. Thay cho hàng phím chức năng mà Folio không có |

Muốn ẩn hoặc hiện thanh này: **chạm 3 ngón** lên màn hình (hoặc bấm **Shortcut bar** trên thanh trạng thái).

### Chỉ dùng bàn phím, trackpad cho Mac: khóa cử chỉ của iPad bằng "Truy cập được hướng dẫn"

App không tự tắt được cử chỉ hệ thống của iPad, như vuốt 4–5 ngón, vuốt trackpad nhiều ngón, ⌘Tab, ⌘Space và phím 🌐. Nhưng iPad có sẵn tính năng **Truy cập được hướng dẫn (Guided Access)**: khóa iPad trong một app và tắt hết các cử chỉ đó.

1. **Cài đặt → Trợ năng → Truy cập được hướng dẫn**: bật lên, rồi đặt mật mã.
2. Mở ScreenBridge, kết nối với Mac.
3. **Bấm nhanh 3 lần nút nguồn** (nút trên cạnh iPad) → **Bắt đầu**.
4. Giờ iPad không thoát ra được, cử chỉ hệ thống bị tắt, và gần như mọi thao tác đều đi vào màn hình Mac.
5. Muốn thoát: bấm nhanh 3 lần nút nguồn → nhập mật mã → **Kết thúc**.

> Claude chưa thử được trên máy thật xem khi bật tính năng này, ⌘Tab và ⌘Space có sang được Mac không. Nếu vẫn không, tiếp tục dùng ⌃⌥Tab / ⌃⌥Space.

### Âm thanh trên iPad

Menu ScreenBridge trên Mac (khi đang kết nối) có thêm:
- **Play sound on iPad** (bật sẵn): âm thanh Mac phát ra loa iPad, hoặc tai nghe/AirPods đang nối với iPad.
- **Mute this Mac's speakers** (bật sẵn): tắt tiếng loa Mac để không bị nghe 2 lần. Ngắt kết nối thì loa Mac tự bật lại.

> **Cần bạn thử:** nếu bật *Mute this Mac's speakers* mà iPad **mất tiếng**, nghĩa là macOS ngừng thu âm khi Mac tắt tiếng. Khi đó tắt mục này và hạ âm lượng Mac xuống thấp. Báo Claude kết quả.

### Dùng khi gập MacBook

> **Khi MacBook đang cắm sạc, không cần bật gì cả.** macOS có sẵn chế độ dùng khi gập máy (clamshell): MacBook đang sạc và có màn hình ngoài thì gập lại vẫn chạy. Màn hình ScreenBridge được macOS tính là màn hình ngoài. Mục **Use with the lid closed** bên dưới **chỉ cần khi dùng pin**.

1. Cắm sạc cho MacBook (nên làm). Nên cắm cáp giữa Mac và iPad.
2. Kết nối như bình thường, chọn **Mode: Extend**.
3. Trong menu ScreenBridge, bật **Use with the lid closed**. macOS hỏi **mật khẩu Mac**, nhập vào.
4. **Gập MacBook lại.** Sau 2–3 giây, **iPad thành màn hình chính**: thanh menu, Dock và các cửa sổ chuyển sang iPad.
5. Dùng Mac bằng bàn phím Folio, trackpad, ngón tay và Apple Pencil như ở trên.
6. Dùng xong: mở nắp MacBook ra, rồi **tắt Use with the lid closed** (lại nhập mật khẩu).

> ⚠️ **Quan trọng:** khi *Use with the lid closed* đang bật, MacBook **không ngủ kể cả khi gập**. **Đừng bỏ vào túi** lúc này, máy sẽ nóng và hết pin. Khi chưa kết nối mà mục này vẫn bật, menu ScreenBridge hiện cảnh báo màu cam kèm nút **Turn Off**.

- **Mac tự khóa:** trong lúc kết nối, app giữ Mac không tự tắt màn hình hay khóa vì để lâu. Nhưng nếu Mac đã khóa trước đó, ô mật khẩu có thể không nhận phím từ iPad, vì macOS chặn vì lý do bảo mật. **Mở khóa Mac trước khi gập.**
- **Đang Mirror mà gập máy:** app tự chuyển sang **Extend**, vì màn hình MacBook đã tắt nên Mirror sẽ chỉ còn màu đen.

### Bảng thử

| Bước | Làm gì | Kết quả đúng |
|---|---|---|
| 1 | Mở TextEdit trên iPad (màn hình Mac), gõ vài chữ bằng Folio. | Chữ hiện ra trên Mac. |
| 2 | Gõ tiếng Việt (bật Telex trên Mac): *Việt Nam*. | Ra đúng dấu. |
| 3 | Giữ phím **Delete**. | Xóa liên tục. |
| 4 | **⌘C / ⌘V**, **⌘Z**. | Sao chép, dán, hoàn tác. |
| 5 | **⌃⌥Tab**, **⌃⌥Space**, **⌃⌥`**. | Chuyển app / Spotlight / Esc. |
| 6 | Dùng trackpad: di chuyển, bấm, bấm 2 ngón, cuộn. | Chỉ thấy 1 con trỏ (của Mac); các thao tác chạy đúng. |
| 7 | Mở YouTube trên Mac. | Tiếng phát ra **iPad**, loa Mac im. |
| 8 | Bật *Use with the lid closed*, gập MacBook. | iPad thành màn hình chính, vẫn gõ, bấm, nghe nhạc được. |
| 9 | Mở MacBook, tắt *Use with the lid closed*. | Mọi thứ về như cũ. |

---

## 9. Khi build bị lỗi

Mã nguồn chưa được biên dịch thử, nên lần đầu có thể gặp lỗi. Đây là việc bình thường. Cách gửi lỗi cho Claude sửa:

1. Trong Xcode, bấm **⌘5** (Issue Navigator) để xem danh sách lỗi màu đỏ.
2. Chuột phải vào lỗi → **Copy** (hoặc chụp màn hình), kèm **tên file và số dòng**.
3. Gửi cho Claude, ví dụ: *"Lỗi ở SessionHandshake.swift dòng 230: …"*.

Lỗi `swift test` thì chép phần chữ đỏ trong Terminal.

Các lỗi hay gặp không phải do mã nguồn:

| Thông báo | Cách xử lý |
|---|---|
| `xcodegen: command not found` | Chưa cài XcodeGen hoặc chưa thêm `brew` vào PATH. Xem mục 3.2–3.3. |
| `Signing for "…" requires a development team` | Chưa đặt `DEVELOPMENT_TEAM`. Xem mục 5. |
| `Failed to register bundle identifier` | Đổi chữ `tenban` trong Bundle ID. Xem mục 5.3. |
| `Developer Mode disabled` | Bật Chế độ nhà phát triển trên iPad. Xem mục 7A. |
| `iPad is not available` / `is busy` | Rút cáp ra cắm lại, mở khóa iPad, chờ Xcode chuẩn bị xong. |
| `No such module 'ScreenBridgeKit'` | Menu **File → Packages → Reset Package Caches**, rồi build lại. |

---

## 10. Xử lý sự cố khi chạy

| Hiện tượng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Khung đỏ **"Local Network access is off"** | Đã từ chối quyền Mạng cục bộ. | **iPad:** Cài đặt → Quyền riêng tư & Bảo mật → Mạng cục bộ → bật **ScreenBridge**. **Mac (macOS 15+):** Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Mạng cục bộ → bật, rồi thoát app và mở lại. |
| Hai máy **không thấy nhau** | Wi-Fi tắt; mạng công ty, khách sạn hoặc quán cà phê chặn các máy thấy nhau; VPN đang bật. | Bật Wi-Fi ở **cả hai máy**, kể cả khi không chung mạng: Wi-Fi trực tiếp vẫn hoạt động. Tắt VPN. Thử phát Wi-Fi từ điện thoại cho cả hai máy dùng chung. |
| Mac thấy iPad nhưng **iPad không thấy Mac** (hoặc ngược lại) | Tường lửa macOS chặn kết nối đến. | Cài đặt hệ thống → Mạng → **Tường lửa** → Tùy chọn → cho phép ScreenBridge, và tắt "Chặn mọi kết nối đến". |
| *"Discovery error … (retrying)"* (lỗi tìm kiếm, đang thử lại) | Mạng vừa đổi, hoặc iPad vừa vào nền. | App tự thử lại. Nếu kéo dài, đóng app và mở lại. |
| *"Couldn't open a listening socket"* (không mở được cổng nhận) | File entitlements bị mất. | Chạy lại `xcodegen generate` rồi build lại. |
| Cảnh báo cam *"Couldn't access secure storage"* (không truy cập được kho bảo mật) | App chưa được ký đúng nên không dùng được Keychain. | App vẫn chạy. Ký bằng Team (mục 5) để mất cảnh báo. |
| **Hai mã 6 số KHÁC nhau** | Có thể có thiết bị lạ chen giữa. | **Bấm Decline (Từ chối)**, rồi thử lại. Mã khớp mới đồng ý. |
| *"already connected to someone else"* | Máy kia đang kết nối với máy khác. | Ngắt kết nối bên đó trước. |
| *"incompatible ScreenBridge version"* | Hai máy cài hai phiên bản app khác nhau. | Build lại cùng một phiên bản mã nguồn cho cả hai. |
| Menu Mac báo **Screen Recording permission needed** | Chưa cấp quyền quay màn hình. | Bấm **Open Settings**, bật **ScreenBridge**, thoát và mở lại app nếu macOS yêu cầu, rồi bấm **Try Again**. |
| iPad **đen**, hoặc hiện mãi *"Waiting for the Mac to start sharing…"* | Mac chưa bắt đầu truyền (thiếu quyền, hoặc lỗi). | Mở menu ScreenBridge trên Mac xem dòng trạng thái màu đỏ/cam. Thử đổi Mode sang **Mirror**. |
| Chế độ **Extend** báo *"Couldn't create the extra display"* | macOS không cho tạo màn hình ảo. | Dùng **Mirror**, rồi gửi Claude ảnh lỗi. |
| Chữ trên iPad **hơi mờ** ở chế độ Extend | macOS đang chọn độ phân giải thấp cho màn hình ảo. | **Cài đặt hệ thống → Màn hình** → chọn màn hình *ScreenBridge* → chọn độ phân giải lớn nhất, hoặc chế độ có chữ *HiDPI*. Chọn Quality **Best Quality**. |
| App trên iPad **không mở được sau vài ngày** | Tài khoản miễn phí: hết hạn 7 ngày. | Cắm iPad vào Mac, bấm Run lại. |
| iPad tự tắt màn hình | — | Khi đã kết nối, app tự giữ màn hình sáng. Lúc chưa kết nối thì iPad tắt màn hình như bình thường. |

**Mẹo:** dòng `ID … · port 52790` ở đầu bảng điều khiển cho biết cổng mạng. Nếu máy dùng cổng khác 52790 thì thường là do đang chạy cả Host lẫn Display trên cùng một Mac. Chuyện này bình thường.

---

## 11. Dùng cáp Thunderbolt

Khi có kết nối Thunderbolt, app **luôn ưu tiên** nó trước Ethernet, Wi-Fi và Wi-Fi trực tiếp.

**Mac ↔ Mac (iMac, MacBook, Mac mini…):**

1. Dùng **cáp Thunderbolt 3/4 hoặc USB4** (in biểu tượng ⚡). Cáp sạc USB-C thường thường **không** truyền được dữ liệu tốc độ cao.
2. Cắm vào cổng Thunderbolt của hai máy.
3. Trên **cả hai** Mac: **Cài đặt hệ thống → Mạng → Cầu nối Thunderbolt (Thunderbolt Bridge)**. Mục này phải hiện **Đã kết nối**, với địa chỉ dạng `169.254.x.x`.
   - Nếu không thấy mục này: trong Cài đặt Mạng, bấm nút **⋯** → **Thêm dịch vụ** → Giao diện: **Cầu nối Thunderbolt** → Tạo.
4. Mở lại ScreenBridge. Tên máy kia sẽ có thêm nhãn ⚡ **Thunderbolt**.
5. Nếu đang kết nối qua Wi-Fi mà cắm cáp vào, app hiện *"A faster link is available"* (có đường nhanh hơn). Bấm **Disconnect** rồi **Connect** lại để chuyển sang cáp. Giai đoạn 3 sẽ tự chuyển.

**iPad:** cáp USB-C nối thẳng iPad với Mac **không tạo kết nối mạng**, xem mục 13. Nếu muốn dùng dây ngay bây giờ: cắm **bộ chuyển USB-C sang Ethernet** cho iPad, nối dây mạng vào cùng router với Mac. App sẽ nhận ra nhãn **Ethernet**.

---

## 12. Vì sao chạy được với Apple ID khác nhau

Sidecar dựa vào **iCloud** để hai máy tin nhau, nên bắt buộc cùng Apple ID. ScreenBridge **không dùng iCloud ở bất kỳ khâu nào**:

| Việc | Sidecar | ScreenBridge |
|---|---|---|
| Tìm máy | Qua tài khoản iCloud | **Bonjour** (tự tìm trong mạng cục bộ), cả qua Wi-Fi trực tiếp và Thunderbolt |
| Nhận diện máy | Apple ID | Mỗi máy tự tạo một **khóa bí mật riêng**, cất trong Keychain của chính máy đó, **không đồng bộ lên iCloud** |
| Tin nhau | Cùng tài khoản iCloud | **Ghép đôi một lần bằng mã 6 số** hiện trên cả hai màn hình |
| Bảo mật | Do Apple quản lý | Trao đổi khóa X25519, sau đó **mã hóa toàn bộ dữ liệu** bằng ChaCha20-Poly1305 |

**Quy trình ghép đôi, giải thích dễ hiểu:**

1. Hai máy trao đổi "khóa tạm" để cùng tạo ra một **bí mật chung** mà người nghe lén không tính ra được.
2. Từ bí mật đó, mỗi máy tự tính ra **mã 6 số**. Nếu có kẻ chen giữa, hai mã sẽ **khác nhau**. Máy gửi trước phải **cam kết khóa của mình trước** (gửi dấu vân tay của khóa, chưa gửi khóa), nên kẻ chen giữa không thể thử đi thử lại cho tới khi trùng mã. Mỗi lần thử, cơ hội thành công chỉ khoảng **1 phần triệu**, và mỗi lần như vậy người dùng đều thấy hộp thoại hỏi mã.
3. Người dùng xác nhận mã khớp, hai máy **ký xác nhận** bằng khóa riêng rồi **lưu khóa công khai của nhau**.
4. Từ lần sau, hai máy chứng minh danh tính bằng chữ ký, **không hỏi mã nữa**.

Những thứ có thể chặn app **chỉ phụ thuộc vào ứng dụng và mạng, không liên quan Apple ID**: quyền Mạng cục bộ, tường lửa, mạng chặn các máy thấy nhau. Mục 10 đã hướng dẫn xử lý từng trường hợp.

---

## 13. Giới hạn kỹ thuật cần biết

1. **Bluetooth không truyền được hình.** Bluetooth LE thực tế chỉ đạt dưới 1 Mbit/s, trong khi video 1080p 60Hz cần khoảng 15–40 Mbit/s, độ phân giải Retina còn cần nhiều hơn. Phần "không dây, không cần router" đã có **Wi-Fi trực tiếp** lo. Bluetooth có thể được thêm sau, chỉ để tìm hoặc đánh thức máy khi Wi-Fi đang tắt.
2. **iPad cắm cáp USB-C vào Mac không tạo kết nối mạng.** Mac ↔ Mac qua Thunderbolt thì được ngay. Muốn iPad chạy bằng dây thật sự cần một cơ chế riêng qua dịch vụ USB của Mac (cách thư viện PeerTalk làm). Việc này dự kiến ở Giai đoạn 3; trước mắt có thể dùng bộ chuyển USB-C sang Ethernet.
3. **Chế độ "mở rộng màn hình" cần màn hình ảo.** Chế độ **phản chiếu** (hiện y hệt màn hình Mac) chỉ dùng API công khai của Apple. Chế độ **mở rộng** (kéo cửa sổ sang màn hình iPad) cần macOS "thấy" thêm một màn hình. Tạo màn hình ảo bằng phần mềm phải dùng API nội bộ của Apple (`CGVirtualDisplay`). Nhiều app đang dùng cách này, nhưng app sẽ **không được lên Mac App Store**. Cách thay thế hoàn toàn hợp lệ: cắm một **đầu giả HDMI** (HDMI dummy plug, rất rẻ). Giai đoạn 2 sẽ hỗ trợ cả hai cách.
4. **iPad phải mở app ở màn hình chính** thì mới nhận được kết nối. iPadOS tạm dừng app khi nó chạy nền.

---

## 14. Cấu trúc mã nguồn

```
ScreenBridge/
├── HUONG-DAN.md                  ← tài liệu này
├── README.md                     ← tài liệu kỹ thuật (tiếng Anh)
├── project.yml                   ← cấu hình để XcodeGen tạo project
├── Packages/ScreenBridgeKit/     ← thư viện mạng dùng chung
│   ├── Sources/ScreenBridgeKit/
│   │   ├── Discovery/   tìm thiết bị: quảng bá Bonjour, duyệt, gộp kết quả, chẩn đoán quyền mạng
│   │   ├── Transport/   kết nối: phân loại đường (Thunderbolt/Wi-Fi…), đóng gói tin, chọn đường tốt nhất
│   │   ├── Identity/    danh tính máy, Keychain, danh sách máy đã ghép đôi, mã hóa
│   │   └── Session/     quy trình ghép đôi, phiên kết nối mã hóa, ConnectionCoordinator (nối với giao diện)
│   └── Tests/           kiểm thử tự động
└── Apps/
    ├── Host/            app máy phát (thanh menu Mac)
    ├── Display/         app máy nhận (iPad + Mac)
    └── Shared/          giao diện thử nghiệm Giai đoạn 1
```

Muốn hiểu luồng chạy, nên đọc theo thứ tự:
`ConnectionCoordinator.swift` → `DiscoveryService.swift` → `PeerConnector.swift` → `SessionHandshake.swift`.

---

## 15. Câu hỏi thường gặp

**Hỏi: Có cần mạng Internet không?**
Đáp: Không. Mọi thứ chạy trong mạng cục bộ, qua Wi-Fi trực tiếp hoặc qua cáp. Không có máy chủ nào ở giữa.

**Hỏi: Dữ liệu có đi qua máy chủ của ai không?**
Đáp: Không. Dữ liệu đi thẳng giữa hai máy và được mã hóa đầu cuối.

**Hỏi: Mac và iPad cách nhau tối đa bao xa?**
Đáp: Tùy đường kết nối:

| Đường kết nối | Khoảng cách | Ghi chú |
|---|---|---|
| **Cáp** | Bằng chiều dài cáp, thường 1–2 m | Độ trễ thấp nhất (~1–2 ms), ổn định nhất, sạc được iPad |
| **Cùng mạng Wi-Fi** | Hai máy cùng trong vùng phủ sóng của router. Tốt nhất **cùng phòng với router**, hoặc cách router dưới ~10 m, ít tường | Mỗi bức tường làm tăng độ trễ và gây giật. Dùng băng tần **5 GHz / 6 GHz**, đừng dùng 2,4 GHz |
| **Wi-Fi trực tiếp** (không có router) | Khoảng **10 m**, tương đương AirDrop | Tốt nhất khi hai máy ở gần nhau, cùng phòng |

Để dùng như màn hình phụ, nên để **Mac và iPad cách nhau dưới 3 m**. Nếu muốn mượt nhất thì cắm cáp.

**Hỏi: Làm sao bớt trễ và giật?**
Đáp: Theo thứ tự hiệu quả:
1. **Cắm cáp.** Gần như hết trễ và giật.
2. Dùng **Wi-Fi 5 GHz hoặc 6 GHz**, để hai máy gần router, và bớt thiết bị khác đang tải nặng trên cùng mạng.
3. Hạ **Refresh** xuống **60 Hz**, hoặc **Quality** xuống **Balanced**. Ít dữ liệu hơn thì ít bị nghẽn hơn.
4. Tắt **VPN** trên cả hai máy.

**Hỏi: Một máy phát nối được nhiều màn hình cùng lúc không?**
Đáp: Hiện tại mỗi lúc chỉ một kết nối. Máy đang bận sẽ hiện **Busy**. Hỗ trợ nhiều màn hình có thể tính sau Giai đoạn 4.

**Hỏi: Đổi tên máy hiển thị trên radar?**
Đáp: Mặc định là tên máy trong hệ thống. Trên iPadOS 16 trở lên, app chỉ đọc được chữ "iPad", nên app tự thêm 4 ký tự để phân biệt, ví dụ `iPad (4F2A)`. Mã nguồn đã có hàm `rename(to:)`, và Giai đoạn 4 sẽ thêm ô đổi tên trên giao diện.

**Hỏi: Xóa hết thông tin ghép đôi?**
Đáp: Bấm **Forget** từng máy trong mục *Paired devices*. Gỡ app cũng xóa danh sách này.

**Hỏi: Giao diện có tiếng Việt không?**
Đáp: Giao diện hiện tại chỉ để thử nghiệm và đang dùng tiếng Anh. Giao diện chính thức ở Giai đoạn 4 có thể làm song ngữ Việt/Anh. Hãy nhắn Claude nếu bạn muốn.

---

## 16. Lộ trình tiếp theo

| Giai đoạn | Nội dung | Trạng thái |
|---|---|---|
| **1** | Tìm thiết bị (Bonjour), chọn đường kết nối tốt nhất, ghép đôi khác Apple ID, mã hóa | ✅ Xong |
| **2** | Quay màn hình (ScreenCaptureKit), nén phần cứng H.264/HEVC (VideoToolbox) trên Mac; giải nén và hiển thị trên iPad/Mac; màn hình ảo cho chế độ mở rộng; truyền video mã hóa, tự giảm chất lượng khi mạng chậm; 30/60/120 Hz | ✅ Xong |
| **3** | Cảm ứng / Apple Pencil (cả khi bút chưa chạm) điều khiển Mac; tự chuyển sang cáp khi cắm vào giữa chừng; tự kết nối lại khi rớt mạng mà vẫn giữ màn hình phụ | ✅ Xong |
| **3b** | Bàn phím Folio + Magic Trackpad điều khiển Mac, âm thanh trên iPad, dùng khi gập MacBook | 🧪 Đang thử |
| **4** | Giao diện hoàn chỉnh: bảng điều khiển trên thanh menu, màn hình **radar** hiện thiết bị xung quanh, kết nối 1 chạm, hướng dẫn bằng hình khi không tìm thấy máy | ⏳ |

Khi đã thử xong (hoặc gặp lỗi), gửi Claude kết quả theo [mục 8D](#8d-bàn-phím-trackpad-âm-thanh-và-dùng-khi-gập-macbook), hoặc gửi lỗi theo hướng dẫn ở mục 9.
