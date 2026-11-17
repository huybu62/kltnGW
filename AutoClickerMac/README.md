# Auto Clicker cho macOS

App tự động click chuột cho macOS 13 trở lên (đã viết cho **macOS 15 Sequoia**), chạy được trên chip Apple Silicon (M1/M2/M3/M4) lẫn Intel.

## Tính năng
- Chỉnh khoảng cách giữa các lần click: giờ / phút / giây / mili-giây (nhanh nhất 1 ms)
- Chọn nút chuột **Trái / Phải / Giữa**, kiểu nhấn **Đơn / Đúp / Ba**
- **Lặp đến khi dừng** hoặc **lặp N lần**
- Click tại **vị trí con trỏ hiện tại** hoặc tại **toạ độ cố định** (lấy toạ độ bằng phím F7 hoặc nút đếm ngược 3 giây)
- Chờ vài giây rồi mới bắt đầu, cửa sổ luôn nằm trên cùng
- **Phím tắt toàn cục**: `F6` hoặc `⌃⌥S` để bắt đầu/dừng, `F7` hoặc `⌃⌥P` để lấy vị trí chuột
- **Dừng khẩn cấp**: rê chuột vào góc trên-trái màn hình
- Tự lưu cài đặt cho lần mở sau

## Cách build (chỉ làm 1 lần)
1. Cài công cụ dòng lệnh của Xcode (nếu chưa có):
   ```bash
   xcode-select --install
   ```
2. Mở Terminal, vào thư mục này rồi build:
   ```bash
   cd đường/dẫn/tới/AutoClickerMac
   ./build.sh
   ```
3. Mở app:
   ```bash
   open AutoClicker.app
   ```
   (Bạn có thể kéo `AutoClicker.app` vào thư mục **Applications**.)

## Cấp quyền Trợ năng (bắt buộc)
macOS chỉ cho app điều khiển chuột khi được cấp quyền:

**Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng → bật AutoClicker**

> Sau mỗi lần build lại, macOS coi đó là app mới. Nếu app vẫn báo thiếu quyền dù đã bật, hãy chọn AutoClicker trong danh sách, bấm nút **−** để xoá, rồi bấm **+** để thêm lại (hoặc tắt rồi bật lại).

## Lưu ý
- Trên MacBook, các phím F6/F7 mặc định là phím chức năng đặc biệt, nên cần giữ `fn` khi bấm, hoặc dùng `⌃⌥S` / `⌃⌥P`.
- Toạ độ tính bằng điểm (point), gốc (0,0) ở góc trên-trái của màn hình chính.
- Ở chế độ toạ độ cố định với tốc độ click nhanh, con trỏ liên tục bị kéo về điểm đó, nên hãy dùng **F6** để dừng.
