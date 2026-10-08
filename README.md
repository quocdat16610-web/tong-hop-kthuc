# Sổ tay DSA C++

Ứng dụng ghi chú để học Cấu trúc dữ liệu & Giải thuật bằng C++: tự tổng hợp video bài giảng tiếng Việt, viết ghi chú, lưu code, **tạo mô phỏng thuật toán bằng kéo thả (kiểu Scratch)** và **ra bài tập có chấm điểm như Codeforces**. Notebook có **nhánh, commit, merge** và **chia sẻ** như GitHub.

Chạy trên **Windows, macOS, Linux** (ứng dụng máy tính) và **Android** (file APK). Ghi chú do người dùng tự viết.

## Cài đặt

Tải file cài đặt ở trang **Actions** của repo (chọn lượt chạy mới nhất của workflow *Build ứng dụng* → mục *Artifacts*), hoặc ở trang **Releases** nếu đã tạo bản phát hành:

| Hệ điều hành | File | Ghi chú |
|---|---|---|
| Windows | `SoTayDSA-Setup-x.y.z.exe` | **Có sẵn trình biên dịch g++** (MinGW-w64) — chấm bài không cần Internet. |
| Android | `SoTayDSA-x.y.z-android.apk` | Bật "Cài ứng dụng không rõ nguồn gốc". Code C++ được chạy online. |
| Linux | `SoTayDSA-x.y.z-linux-x86_64.AppImage` | `chmod +x` rồi chạy. Dùng g++ của máy (`sudo apt install g++`). |
| macOS | `SoTayDSA-x.y.z-mac-arm64.dmg` / `-x64.dmg` | App chưa ký: chuột phải → Open. Cần `xcode-select --install`. |

Tạo bản phát hành: push một tag dạng `v2.0.0`, workflow sẽ tự đính kèm tất cả file vào Release.

### Chạy từ mã nguồn

```bash
npm install
npm start            # mở ứng dụng máy tính (Electron)
npm test             # chạy kiểm thử
```

## Dùng thế nào

**Một trang chứa được mọi thứ.** Mỗi trang gồm các khối, chèn bằng nút **+** giữa các khối hoặc thanh *Thêm khối* cuối trang:

| Khối | Dùng để |
|---|---|
| Tiêu đề | Tạo mục; cột **Mục lục** bên trái tự cập nhật (cả các dòng `#`, `##` trong văn bản). |
| Văn bản | Ghi chú Markdown; dán ảnh trực tiếp bằng Ctrl+V. |
| Ảnh | Chọn ảnh từ máy, dán link, hoặc kéo thả file vào trang. |
| Video | Link YouTube / playlist / Google Drive / Facebook / TikTok / Vimeo / Dailymotion phát **ngay trong app**; hoặc file video từ máy. Thêm mốc thời gian để nhảy tới đoạn cần xem. |
| Code C++ | Soạn code có tô màu, nhập stdin, bấm **Chạy**. |
| Mô phỏng kéo thả | Ghép khối như Scratch: mảng, stack/queue, lưới, đồ thị, cây… rồi xem thuật toán chạy từng bước. |
| Mô phỏng bằng code | Như trên nhưng viết bằng JavaScript (thư viện `viz`, có mẫu sẵn). |
| Bài tập | Đề bài + test + code chuẩn. Người học nộp bài và được chấm. |

**Khu code** (nút trên thanh công cụ): khung soạn và chạy C++ tự do bên cạnh ghi chú, có thể chèn vào trang.

### Bài tập và contest (giống Codeforces)

1. Chèn khối **Bài tập**, bấm **Sửa** (⋮ → Sửa):
   - *Đề bài*: tên, giới hạn thời gian/bộ nhớ, cách so output, nội dung đề.
   - *Code chuẩn*: lời giải đúng của tác giả.
   - *Test*: nhập input, bấm **Tạo output bằng code chuẩn**. Đánh dấu vài test là *test mẫu* để hiện trong đề.
   - *Sinh test*: viết generator C++ in ra input ngẫu nhiên từ seed; app chạy generator rồi code chuẩn để **tự tạo hàng loạt test**.
2. Người học dán code vào ô *Bài làm*, bấm **Nộp bài** → kết quả `Accepted`, `Wrong answer on test N`, `Time limit exceeded`, `Runtime error`, `Compilation error`. Test ẩn không bị lộ dữ liệu.
3. Nút **Contest** → tạo kỳ thi từ các bài (A, B, C…) với thời gian làm bài. Thí sinh bấm **Bắt đầu làm bài**; bảng xếp hạng theo luật ICPC (số bài giải, rồi thời gian + 20 phút mỗi lần sai).
4. **Xuất đề cho thí sinh** tạo file đề *không kèm code chuẩn*. Thí sinh làm xong bấm **Xuất kết quả** gửi lại; người ra đề bấm **Nhập kết quả** để có bảng xếp hạng chung.

Chấm bài: bản máy tính dùng **g++ trên máy** (Windows có sẵn trong bộ cài; có thể chọn g++ khác trong *Cài đặt*). Android/web dùng [Compiler Explorer](https://godbolt.org) online.

### Nhánh, lịch sử, chia sẻ

- **Commit** (Ctrl+S) lưu một phiên bản. **Lịch sử** xem đồ thị commit, so sánh, khôi phục.
- **Nhánh**: tạo nhánh để thử cách ghi chú khác; **Merge** gộp lại, có màn hình giải quyết xung đột.
- **Chia sẻ**: lưu file `.dsanote.json` (kèm ảnh/video) hoặc tạo link. Trên Android mở bảng chia sẻ (Zalo, Messenger, Drive…).
- **Nhập**: mở thành notebook riêng (*fork*), hoặc gộp vào notebook có sẵn — nhánh của người gửi hiện dạng `tên/nhánh` để xem và merge.

## Cấu trúc mã nguồn

```
index.html, css/        giao diện
js/vcs.js               commit, nhánh, diff, merge 3 chiều, fork/fetch
js/judge.js             chấm bài, so output, bảng xếp hạng ICPC, backend online
js/sim.js               chạy mô phỏng trong iframe sandbox + Web Worker (giới hạn thời gian)
js/blocks.js            khối kéo thả (Blockly) sinh code cho mô phỏng
js/contest.js           khối bài tập, sinh test, contest
js/ui.js, js/app.js     giao diện
js/services.js          lưu trữ IndexedDB, ảnh/video, chia sẻ, chọn nơi chạy code
electron/               ứng dụng máy tính: máy chủ nội bộ, chấm bài bằng g++
android/                dự án Android (Capacitor)
.github/workflows/      đóng gói Windows / macOS / Linux / Android
vendor/                 thư viện đi kèm (marked, DOMPurify, highlight.js, CodeMirror, Blockly)
```

## Giới hạn

- Dữ liệu lưu trên từng máy; cộng tác bằng cách gửi file/link cho nhau (không có máy chủ đồng bộ). Hãy xuất file để sao lưu.
- Giới hạn bộ nhớ trong đề chỉ để hiển thị, chưa được kiểm tra khi chấm.
- Dữ liệu test nằm trong file đề, nên người rành kỹ thuật vẫn đọc được — phù hợp luyện tập/thi trong lớp, không chống gian lận tuyệt đối.
- Android và web cần Internet để chạy C++ (chấm online chậm hơn: mỗi test là một lượt gửi lên Compiler Explorer).
- Code mô phỏng chạy trong sandbox nên mở notebook người khác gửi vẫn an toàn; code C++ chỉ chạy khi bạn bấm.
