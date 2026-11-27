# Hội Tụ Auto (app Android tổng hợp)

Một app gộp các tool cho game: **🎡 Vòng quay liên server** và **💎 Ban sức vận mệnh**. Mục **🗺 Càn quét** sẽ thêm ở bản sau. Mọi thao tác làm ngay trong game, qua **bong bóng nổi**. Chạy trên BlueStacks và điện thoại **Android 7+**.

## Cài đặt (làm 1 lần)
1. Cài `HoiTuAuto.apk`: kéo thả vào BlueStacks, hoặc mở file trên điện thoại.
2. Mở app **Hội Tụ Auto** và làm 2 bước:
   - **Bước 1 – Trợ năng:** bật "Hội Tụ Auto". Nếu Android 13+ báo *Restricted setting*: vào Cài đặt → Ứng dụng → Hội Tụ Auto → ⋮ → *Allow restricted settings*, rồi bật lại.
   - **Bước 2 – Quay màn hình:** bấm cho phép. Mỗi lần mở lại máy phải cho phép lại.
3. Nếu vẫn còn cài **Vòng Quay Auto** / **Ban Sức Auto** (app lẻ), hãy tắt Trợ năng của chúng hoặc gỡ chúng đi, để khỏi có 2 nút nổi.

## Dùng
- Bấm **bong bóng ⚙** để mở danh sách tool, chọn tool, rồi bảng cài đặt của tool đó hiện ra:
  - **Vòng quay:** bộ đếm x10 (−10 / − / + / +10), mốc, Tạo mới tối đa, dừng sau N lần, nghỉ giữa 2 lần chạm, món muốn ra, nút **Mẫu** (lấy mẫu tướng hạn định mới hoặc Đá vận mệnh).
  - **Ban sức:** hệ (◀ ▶), phẩm A/S, Nhà máy LV6, số bộ + đá cơ bản (hoặc **tùy chỉnh** số viên từng loại), thời gian chờ sau mỗi lần bấm.
  - Mọi thứ chỉnh bằng nút bấm, không cần bàn phím, và **tự lưu**.
- Bấm **▶ Chạy**: bảng tự đóng để không che game. Bong bóng chuyển **xanh**, cạnh bong bóng hiện dòng trạng thái.
- Bấm bong bóng khi đang chạy để mở lại bảng, có nút **■ Dừng**.
- **📜 Nhật ký:** xem 100 dòng gần nhất, có giờ. Tiện chụp màn hình gửi khi có lỗi.
- Kéo bong bóng để dời chỗ. Đừng để bong bóng che nút hay danh sách của game.
- Mỗi lần chỉ chạy được 1 tool.

## Cho người phát triển
- App dùng chung phần lõi (đã có kiểm thử) của 2 app lẻ: `../android-vong-quay/core` (`:vq`) và `../android-ban-suc/core` (`:bs`). Vì vậy sửa lõi một chỗ là cả app lẻ lẫn app tổng hợp cùng được.
- Build: `./gradlew :app:assembleRelease`. Kiểm thử lõi: `./gradlew :vq:test :bs:test`.
