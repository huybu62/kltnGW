# Sổ Chi Tiêu

App ghi chép chi tiêu cho iPhone (web app cài lên Màn hình chính), từ đi chợ hằng ngày đến mua hàng cho kho, khu công nghiệp.
Giao diện chữ to, nút lớn, dạng bảng giống Excel.

## Chức năng
- **Bảng như Excel** theo từng ngày: STT, Tên hàng, Số lượng (+ đơn vị), Đơn giá, Thành tiền, Ghi chú. Chạm vào dòng để sửa hoặc xóa.
- **Ba cách nhập**: nhập tay · nói bằng giọng (tiếng Việt) · chụp ảnh hóa đơn/phiếu (tự đọc chữ). Giọng nói và ảnh luôn qua màn hình *kiểm tra lại* trước khi thêm vào bảng.
- **Tổng kết** theo Ngày / Tuần / Tháng / Quý / Năm, có chi tiết từng ngày (hoặc từng tháng) và các món chi nhiều nhất.
- **Xuất file**: Excel (.xlsx, có công thức tổng và sheet tổng hợp), PDF, hoặc ảnh PNG, rồi gửi qua Zalo/Mail hoặc lưu vào Tệp.
- **Sao lưu / khôi phục** dữ liệu bằng file .json.
- Mở được khi không có mạng (trừ lúc xuất file và đọc ảnh lần đầu, cần mạng để tải thư viện).

## Cách nói để nhập
- `Thịt ba chỉ 2 ký giá 120 nghìn`
- `Rau muống 3 bó mỗi bó 5 nghìn` → tiếp theo → `Cà chua 1 ký rưỡi hết 45 nghìn`
- Nói **“tiếp theo”** (hoặc “và”) để tách từng món. Nói **“hết …”** nếu biết tổng tiền.

## Đưa lên iPhone
App là các file tĩnh (`index.html`, `sw.js`, `manifest.webmanifest`, icon). iPhone cần mở qua địa chỉ **https** mới cài được:
1. Đưa thư mục này lên một nơi host tĩnh miễn phí (GitHub Pages, Netlify, Cloudflare Pages…).
2. Trên iPhone mở địa chỉ đó **bằng Safari** → nút Chia sẻ → **Thêm vào MH chính**.
3. Mở app từ biểu tượng ngoài Màn hình chính.

## Lưu ý
- Dữ liệu lưu **trong chính chiếc iPhone** (không có máy chủ, không ai khác thấy). Nếu xóa dữ liệu Safari hoặc đổi máy sẽ mất, nên **Sao lưu** định kỳ.
- Ghi âm trong app đã cài ở Màn hình chính có thể bị iOS hạn chế. Khi đó hãy chạm vào ô chữ rồi dùng nút 🎤 trên bàn phím iPhone.
- Đọc ảnh chính xác với hóa đơn in rõ nét; chữ viết tay có thể sai, luôn kiểm tra ở màn hình xác nhận.
- Thư viện Excel/PDF/đọc ảnh được tải từ CDN khi dùng lần đầu (cdnjs, jsDelivr).
