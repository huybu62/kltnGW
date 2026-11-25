# Vòng Quay Auto (app Android)

App Android **chạy độc lập** (không cần máy tính) để tự quay **Vòng quay liên server**. Chạy được trên **BlueStacks** và **điện thoại Android 7 trở lên**.

## App làm gì
- Bấm **"Khởi động 10 lần"** liên tục. Mỗi lần bấm, bộ đếm +1.
- Bấm xong, app **chạm chỗ trống liên tục như auto click** để bỏ hoạt ảnh quay và tắt danh sách quà. App không chạm vào vật phẩm.
- Tốc độ chạm chỉnh ở ô *Nghỉ giữa 2 lần chạm* (mặc định 80 ms). Nếu app đếm sai trên máy yếu, tăng lên 150.
- Tới **lần bấm thứ 73** (mốc, sửa được): app bấm **"Tạo mới"** cho tới khi vòng quay có món hạn định thật bạn đã chọn, rồi mới bấm x10. Sau đó bộ đếm về **0**.
  - 3 món thật: **Phiếu Hủy Diệt** (rương vàng nền đỏ), **Đá vận mệnh** (rương vàng), **Tướng hạn định** (hiện là Vegeta).
  - Các tướng khác có nhãn "Hạn định" là món **giả**, app không tính.
- App **chỉ chạm 3 chỗ**: Khởi động 10 lần, Tạo mới, chỗ trống. App không bấm Nạp thẻ hay nút mua nào.

## Cài đặt
1. Tải file **`VongQuayAuto.apk`** về máy.
   - **BlueStacks:** kéo thả file APK vào cửa sổ BlueStacks, hoặc bấm nút *Cài APK* ở thanh bên.
   - **Điện thoại:** mở file APK, cho phép *Cài ứng dụng không rõ nguồn gốc* khi máy hỏi.
2. Mở app **Vòng Quay Auto**:
   - **Bước 1:** bấm *Mở cài đặt Trợ năng*, tìm **Vòng Quay Auto**, bật lên. App cần quyền này để chạm giúp.
   - **Bước 2:** bấm **Cho phép quay màn hình**, chọn *Bắt đầu* hoặc *Cho phép*. App cần quyền này để nhìn thấy game. Mỗi lần khởi động lại máy phải cho phép lại.
3. Nhập **Đã bấm x10** (bộ đếm bạn đang tự đếm), **Mốc** (73), tick các món muốn ra ở lượt mốc, rồi bấm **Lưu cài đặt**.

## Dùng
1. Mở game, vào màn **Vòng quay liên server**.
2. Trên **nút nổi**:
   - **▶ Chạy**: bắt đầu. **■ Dừng**: dừng.
   - **− / +**: sửa bộ đếm.
   - Kéo dòng *🎡 Đã bấm x10* để dời nút nổi. Đừng để nút nổi che vòng quay hay các nút của game.
3. **Sự kiện đổi tướng hạn định** (hoặc app không nhận ra *Đá vận mệnh*): khi món đó nằm trên vòng quay, bấm **Mẫu** trên nút nổi, chạm ô chứa món đó rồi chọn đúng loại. App lưu ảnh ô đó làm mẫu mới.
4. **Tắt các app auto click khác** khi chạy. Vòng tròn hay nút nổi của chúng có thể che nút và làm app nhận diện sai.

## Lưu ý
- **Android 13+ báo "Restricted setting" khi bật Trợ năng:** vào Cài đặt → Ứng dụng → Vòng Quay Auto → dấu ⋮ → *Allow restricted settings*, rồi bật Trợ năng lại.
- Nếu cài bản mới mà báo lỗi chữ ký, gỡ bản cũ rồi cài lại. Khi đó bộ đếm sẽ mất, bạn nhập lại.
- App tìm vòng quay nhờ nút **"Khởi động-1 lần"**. Nếu game đổi giao diện màn này, app sẽ báo *Không thấy màn Vòng quay*.

## Cho người phát triển
- `core/`: phần nhận diện và điều khiển viết bằng Kotlin thuần, có kiểm thử trên ảnh chụp thật: `./gradlew :core:test`.
- `app/`: phần Android, gồm dịch vụ Trợ năng (chạm, nút nổi), dịch vụ chụp màn hình (MediaProjection) và màn cài đặt.
- Build APK: `./gradlew :app:assembleRelease` (cần Android SDK, khai trong `local.properties`).
