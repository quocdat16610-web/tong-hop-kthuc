# Thư viện nội dung (bài tập, ghi chú, video)

Mỗi file `*.dsanote.json` trong thư mục này là một notebook được đăng cho mọi người dùng app.
Mỗi lần push, GitHub Actions gom các file này thành `noi-dung.json` trên Release **ban-moi-nhat**.
App tự tải về (mục **Thư viện bài tập (GitHub)**) và kiểm tra nội dung mới mỗi 30 phút.

## Đăng hoặc cập nhật một notebook

1. Trong app, mở notebook, **commit** các thay đổi.
2. **Notebook → Chia sẻ… → Lưu file .dsanote.json**.
3. Đưa file vào thư mục `content/` (ghi đè file cũ cùng tên nếu là cập nhật), commit và push lên GitHub
   (hoặc dùng nút **Add file → Upload files** trên trang GitHub).

Luôn cập nhật **từ cùng một notebook** (đừng tạo notebook mới) để người dùng nhận được bản cập nhật như các commit mới.
Người dùng chưa sửa gì sẽ được cập nhật tự động; ai đã ghi chú thêm sẽ được mời gộp (merge), ghi chú của họ không bị mất.
