# Ban Sức Auto (app Android)

App Android chạy độc lập để tự **Điểm Hóa** và **Thác Ấn** đá vận mệnh ở màn **Ban Sức Đá Quý Vận Mệnh**. Chạy trên BlueStacks và điện thoại **Android 7+**. Đây là app riêng, tách khỏi tool càn quét và Vòng Quay Auto.

## Quy tắc app làm theo
- Đá **LV6** (đá trong bộ) dùng đá điểm hóa đúng hệ đã chọn:
  - mục tiêu **A**: dùng **B-SS**;
  - mục tiêu **S**: dùng **A-SSS**.
  Bấm Điểm Hóa liên tục tới khi đạt phẩm. Kết quả có thể lên, giữ nguyên hoặc hạ 1 bậc.
- Đá LV6 rơi đúng phẩm **B** thì **Thác Ấn bằng Đá In SS** để lấy 1 viên B-SS, rồi điểm hóa tiếp viên đó.
- Hết **B-SS** thì dùng đá **LV5 nhà máy**:
  1. Điểm Hóa bằng **B-S** tới phẩm **B**.
  2. Thác Ấn bằng **Đá In SS** để được 1 viên B-SS. App làm **từng viên một**, không gom đá chờ bảo hiểm.
  3. Quay lại đá LV6.
- Hết **A-SSS** (mục tiêu S):
  - Nếu bật **Nhà máy LV6**: app đưa 1 viên LV6 khác lên A, Thác Ấn bằng **Đá In SSS** để được 1 viên A-SSS.
  - Nếu không bật: app dừng.
- App chỉ đụng tới đá **chưa ban sức** hoặc đá **đúng hệ đã chọn**. Đá hệ khác được để yên.
- App **dừng** khi đủ số lượng, hoặc khi hết đá điểm hóa, Đá In hay đá LV6. Lý do dừng hiện trên nút nổi.

## Số lượng
- Mặc định tính theo **bộ**: 1 bộ = **1 đá cơ bản** (Phòng thủ / Tốc độ / Vật công / Ma công) + **3 đá HP**.
- Tick **Tùy chỉnh từng loại** để tự nhập số viên mỗi loại, ví dụ 2 Phòng thủ + 5 HP.
- Trước khi làm, app đếm sẵn những viên LV6 đã đạt (đúng hệ, đủ phẩm).

## Cài đặt và dùng
1. Cài `BanSucAuto.apk`: kéo thả vào BlueStacks, hoặc mở file trên điện thoại.
2. Mở app, làm 2 bước:
   - **Bước 1 – Trợ năng:** bật "Ban Sức Auto". Android 13 trở lên báo *Restricted setting* thì vào Cài đặt → Ứng dụng → Ban Sức Auto → dấu ⋮ → *Allow restricted settings*, rồi bật lại.
   - **Bước 2 – Quay màn hình:** bấm cho phép.
3. Chọn **Hệ**, **Phẩm mục tiêu**, **Số lượng**, rồi bấm **Lưu**.
4. Trong game, mở màn **Ban Sức Đá Quý Vận Mệnh**, rồi bấm **▶ Chạy** trên nút nổi. Kéo dòng trên cùng của nút nổi để dời nó; đừng để nút nổi che danh sách đá hay các bảng.
5. Giữ ít nhất **1 đá LV5** làm nhà máy.

## Lưu ý
- App đọc chữ trên màn hình bằng ML Kit của Google. ML Kit chạy ngay trên máy, không cần mạng. Vì phải kèm bộ đọc chữ cho mọi loại máy nên file APK nặng khoảng 43 MB.
- Đá xếp chồng (vd "x4"): nếu app không đọc được số chồng, app tính là 1 viên.

## Cho người phát triển
- `core/`: đọc màn hình (từ chữ OCR và màu thẻ) và logic Điểm Hóa / Thác Ấn, viết bằng Kotlin thuần. Kiểm thử gồm ảnh chụp thật và một game giả có kết quả ngẫu nhiên: `./gradlew :core:test`.
- `app/`: Trợ năng (chạm, vuốt, nút nổi), MediaProjection (chụp màn hình), ML Kit (đọc chữ), màn cài đặt.
