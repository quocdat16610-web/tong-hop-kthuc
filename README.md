# Sổ tay DSA C++

Ứng dụng **chạy trực tiếp trên máy** (cửa sổ riêng trên Windows, app trên Android — không phải website) để học Cấu trúc dữ liệu & Giải thuật bằng C++:

- **Sổ tay**: mỗi trang chứa chung tiêu đề, ghi chú (Markdown), ảnh, video (file trên máy, link hoặc mã nhúng `<iframe>` YouTube / Google Drive, link .mp4 — phát ngay trong app, có mốc thời gian), code C++ chạy được, mô phỏng thuật toán và bài tập. Cột **Mục lục** tự tạo từ các tiêu đề. Ghi chú do người dùng tự viết.
- **Phiên bản như Git**: commit, lịch sử dạng đồ thị, nhánh, merge 3 chiều có giải quyết xung đột, chia sẻ notebook (file `.dsanote.json` hoặc link) để người khác mở thành bản riêng hoặc gộp vào như một nhánh.
- **IDE C++** kiểu Code::Blocks / Thonny: nhiều tab, mở file/thư mục, Build (Ctrl+F9), Build & Run (F9) với console tương tác, bấm vào lỗi để nhảy tới dòng, **gỡ lỗi từng dòng** bằng gdb (F8 bắt đầu/chạy tiếp, F7 dòng tiếp, Shift+F7 vào hàm, Ctrl+F7 ra khỏi hàm, F5 hoặc bấm lề trái để đặt điểm dừng), xem biến và ngăn xếp lời gọi.
- **Bài tập & contest kiểu Codeforces**: tác giả viết đề, code chuẩn và trình sinh test — app tự tạo output đúng; người học nộp bài và nhận Accepted / Wrong answer on test N / TLE / RE / CE. Contest có giờ thi và bảng xếp hạng ICPC.
- **Bảng trắng**: tab riêng (biểu tượng bút ở thanh bên trái, Alt+3; trên điện thoại ở thanh dưới) với nhiều bảng, và khối vẽ tay ngay trong trang để minh hoạ thuật toán — bút, bút dạ, đường thẳng, mũi tên, hình chữ nhật, hình tròn, chữ, tẩy, 8 màu, nền kẻ ô / chấm, hoàn tác / làm lại, lưu thành ảnh PNG, vẽ toàn màn hình (trên điện thoại chạm vào bảng để vẽ). Nét vẽ lưu dạng vector nên có lịch sử, commit, merge và chia sẻ như ghi chú.
- **Mô phỏng ghép khối kiểu Scratch**: kéo khối màu từ bảng 12 nhóm (Hiển thị, Dữ liệu vào, Điều khiển, Toán, Chữ, Biến, Danh sách, Mảng vẽ, Stack/Queue, Lưới, Đồ thị/Cây, Hàm) vào chương trình; thả khối giá trị vào ô; vòng lặp (kể cả `for (char c : s)`, `for (auto x : mảng)`, `for (int i = a; i < b; i++)`, `while`, `do … while`, `while (true)` như C++), nếu/không thì, biến, hàm có tham số và đệ quy. Có 8 mẫu (sắp xếp nổi bọt/chọn/chèn, tìm kiếm nhị phân, stack ngoặc, BFS lưới, DFS đệ quy, cây BST). Mô phỏng khối của bản cũ tự chuyển sang khối mới.
- **Tự cập nhật từ GitHub**: app kiểm tra bản mới mỗi 5 phút và khi mở lại cửa sổ; Windows tự tải ngầm rồi cài khi bấm "Khởi động lại" hoặc khi đóng app, Android tải APK mới; **Thư viện bài tập** tự nhận nội dung mới mà tác giả đăng trong thư mục [`content/`](content/README.md) — ai chưa sửa thì cập nhật tự động, ai đã ghi chú thì được mời merge, không mất ghi chú.
- **Thư viện code mẫu C++** (nút **Code mẫu** trong IDE và khối code): khung bài thi, DSU, Fenwick, cây phân đoạn, Sparse Table, BFS, DFS, Dijkstra, sắp xếp tô-pô, Kruskal, tìm kiếm nhị phân, hai con trỏ, LIS, cái túi, LCS, KMP, sàng nguyên tố, luỹ thừa nhanh, GCD/LCM — tất cả đều được kiểm thử biên dịch.
- **Tìm nhanh (Ctrl+K)** trong mọi notebook: trang, ghi chú, code, bài tập, video, bảng trắng — bấm kết quả để nhảy tới đúng chỗ.
- **Tiến độ luyện tập**: mọi bài tập trong các notebook với trạng thái đã giải / đang làm / chưa làm và số lần nộp.
- **Giao diện sáng / tối** (theo hệ thống hoặc chọn tay), menu kiểu ứng dụng Windows; trên điện thoại có thanh điều hướng dưới và mục lục dạng ngăn kéo.

## Tải về

Vào **[Releases](https://github.com/quocdat16610-web/tong-hop-kthuc/releases)**, mở bản **"Bản mới nhất"**:

| Máy | File | Ghi chú |
|---|---|---|
| Windows | `SoTayDSA-Setup-x.y.z.exe` | Bộ cài, không cần quyền admin. **Có sẵn g++ 14 và gdb** — chạy code, chấm bài, gỡ lỗi không cần Internet. |
| Windows (không cần cài) | `SoTayDSA-x.y.z-win-x64-portable.zip` | Giải nén rồi bấm đúp `SoTayDSA.exe`. |
| Android | `SoTayDSA-x.y.z-android.apk` | Mở file trên điện thoại để cài (cho phép cài ứng dụng không rõ nguồn gốc). Code C++ được biên dịch online qua Compiler Explorer nên cần Internet. |

Mỗi lần push, GitHub Actions build lại và cập nhật "Bản mới nhất". Push tag dạng `v3.1.0` để tạo bản phát hành có số phiên bản.

### Cập nhật không mất dữ liệu

- Notebook, bài nộp và cài đặt được lưu trong thư mục dữ liệu của người dùng (Windows: `%APPDATA%`, Android: bộ nhớ riêng của app), **không** nằm trong thư mục cài app, nên cài bản mới / cập nhật tự động không đụng tới.
- Trước mỗi lần tự cập nhật, app tự sao lưu toàn bộ dữ liệu (giữ 5 bản gần nhất). **Cài đặt → Sao lưu tất cả** để lưu ra file; **Notebook → Nhập** để khôi phục (không ghi đè dữ liệu đang có).
- APK được ký bằng một khoá cố định (`app/android/app/sotaydsa-release.jks`) nên bản mới cài đè lên bản cũ. Bản APK 3.0.0 đầu tiên ký bằng khoá tạm, nên lần đầu chuyển sang bản mới cần **sao lưu → gỡ bản cũ → cài bản mới → nhập lại file sao lưu**.
- Nội dung bài tập mới từ thư viện được gộp như một nhánh Git: ghi chú của bạn luôn được giữ.

## Dùng nhanh

1. Mở app → **Sổ hướng dẫn** để xem ví dụ đủ các loại khối, hoặc **Notebook mới**.
2. Bấm **+** giữa các khối hoặc thanh **Thêm khối** cuối trang để chèn tiêu đề, văn bản, ảnh, video, code, mô phỏng, bài tập.
3. **Ctrl+S** (hoặc nút ✓ trên điện thoại) để commit. Menu **Phiên bản** có Lịch sử, Nhánh, Merge.
4. **Notebook → Chia sẻ** để lưu file `.dsanote.json` / tạo link; người nhận dùng **Nhập**.
5. **Alt+2** (hoặc biểu tượng `</>`) để sang IDE; nút **Mở trong IDE** trên khối code và **Đưa vào sổ tay** trong IDE để chuyển code qua lại.

6. **Mô phỏng**: thêm khối **Mô phỏng** → **Sửa** → kéo khối từ bảng bên trái vào chương trình (bấm vào khối để thêm vào cuối), kéo khối về bảng để xoá, chuột phải để nhân bản; **Toàn màn hình** để có chỗ ghép rộng. Muốn viết tay thì chuyển sang **Code JS**.
7. **Notebook → Thư viện bài tập (GitHub)** để tải và tự nhận bài tập mới; **Notebook → Kiểm tra cập nhật** để cập nhật app.

Khối kéo thả được dịch sang JavaScript (thư viện `viz`) và chạy bằng engine QuickJS tích hợp, vẽ bằng giao diện gốc của app.

## Mã nguồn

```
app/            Ứng dụng Flutter (Dart) — Windows, Android (và Linux/macOS khi build từ nguồn)
  lib/core/     VCS (commit/nhánh/merge), chấm bài, chạy g++ / online, gdb MI, lưu trữ, mô phỏng
  lib/ui/       Giao diện: khung app, sổ tay, khối nội dung, IDE, hộp thoại Git, contest
  test/         Kiểm thử (merge, chấm bài, chạy tương tác, gỡ lỗi gdb…)
  windows/installer/  Script Inno Setup tạo bộ cài .exe
  tool/build_library.py  Gom content/*.dsanote.json thành thư viện noi-dung.json (CI chạy)
content/        Notebook đăng cho mọi người dùng (thư viện bài tập)
assets-src/     Biểu tượng app
legacy-html/    Bản cũ (Electron + HTML), giữ để tham khảo; dữ liệu và link chia sẻ của bản cũ vẫn nhập được
```

Chạy từ nguồn (cần [Flutter](https://docs.flutter.dev/get-started/install) 3.47+):

```bash
cd app
flutter pub get
flutter run -d windows     # hoặc: -d linux, hoặc cắm điện thoại Android
flutter test               # kiểm thử (cần g++ và gdb trong PATH để chạy đủ)
```

Trên Windows khi chạy từ nguồn, app tìm `g++` theo thứ tự: đường dẫn trong Cài đặt → `mingw64\bin` cạnh file exe → `PATH` → MSYS2 / Dev-C++ / Code::Blocks / các vị trí cài phổ biến.
