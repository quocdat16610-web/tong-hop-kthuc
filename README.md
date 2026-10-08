# Sổ tay DSA C++

Ứng dụng ghi chú để học Cấu trúc dữ liệu & Giải thuật bằng C++: tự tổng hợp video bài giảng tiếng Việt, viết ghi chú, lưu code, **tạo mô phỏng thuật toán bằng kéo thả (kiểu Scratch)** và **ra bài tập có chấm điểm như Codeforces**. Notebook có **nhánh, commit, merge** và **chia sẻ** như GitHub.

Chạy trên **Windows, macOS, Linux** (ứng dụng máy tính) và **Android** (file APK). Ghi chú do người dùng tự viết.

## Cài đặt (tải file chạy trực tiếp)

Vào trang **[Releases](https://github.com/quocdat16610-web/tong-hop-kthuc/releases)** của repo, mở bản **"Bản mới nhất"** và tải file:

| Máy | File | Ghi chú |
|---|---|---|
| Windows | `SoTayDSA-Setup-x.y.z.exe` | Bộ cài: bấm đúp để cài, app chạy trong cửa sổ riêng. **Có sẵn g++ và gdb** — chạy, chấm bài, gỡ lỗi không cần Internet. |
| Windows (không cần cài) | `SoTayDSA-x.y.z-win-x64.zip` | Giải nén rồi bấm đúp `SoTayDSA.exe`. |
| Android | `SoTayDSA-x.y.z-android.apk` | Mở file trên điện thoại để cài (cho phép "cài ứng dụng không rõ nguồn gốc"). Code C++ chạy online. |
| Linux | `SoTayDSA-x.y.z-linux-x86_64.AppImage` | `chmod +x` rồi chạy. Cần `g++` (và `gdb` để gỡ lỗi). |
| macOS | `SoTayDSA-x.y.z-mac-arm64.dmg` / `-x64.dmg` | Chưa ký: chuột phải → Open. Cần `xcode-select --install`. |

Mỗi lần có thay đổi mới, GitHub Actions tự build lại và cập nhật "Bản mới nhất". Muốn đánh số phiên bản cố định thì push tag dạng `v2.1.0`.

### Chạy từ mã nguồn

```bash
npm install
npm start            # mở ứng dụng (Electron)
npm test             # kiểm thử
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

Nút **sáng/tối** (biểu tượng mặt trăng / mặt trời) trên thanh công cụ đổi nền trắng ↔ tối.

### IDE C++ (giống Code::Blocks / Thonny)

Bấm **IDE C++** trên thanh công cụ để chuyển sang chế độ lập trình:

- **Nhiều tab** như trình duyệt: mỗi file một tab, chấm ● là chưa lưu; trên điện thoại kéo ngang để đổi tab.
- **Mở file / mở thư mục thật** trên máy (cây thư mục bên trái), `#include "file.h"` trong cùng thư mục dùng được. Trên Android, file được lưu trong app và có thể xuất ra để gửi.
- **Build và chạy** với phím tắt giống Code::Blocks. Chương trình chạy trong **Console**: gõ input trực tiếp khi chương trình đang chờ `cin`.
- **Thông báo build**: liệt kê lỗi/cảnh báo, bấm để nhảy tới đúng dòng; dòng lỗi được tô đỏ.
- **Gỡ lỗi từng dòng** (bản máy tính, dùng gdb): bấm lề trái để đặt điểm dừng, xem **biến** và **ngăn xếp gọi** ở bảng bên phải như Thonny. Input khi gỡ lỗi lấy từ tab *Input*.
- **Đưa vào sổ tay**: chèn code đang mở thành khối Code trong trang; ngược lại khối Code trong sổ tay có nút *Mở trong IDE*.

| Phím | Việc |
|---|---|
| F9 | Build và chạy |
| Ctrl+F9 / Ctrl+F10 | Build / Chạy |
| F8 | Bắt đầu gỡ lỗi / chạy tới điểm dừng kế |
| F7 · Shift+F7 · Ctrl+F7 | Dòng kế · Vào hàm · Ra khỏi hàm |
| Shift+F8 | Dừng |
| F5 | Đặt / bỏ điểm dừng ở dòng con trỏ |
| Ctrl+N · Ctrl+O · Ctrl+S · Ctrl+W | Tab mới · Mở file · Lưu · Đóng tab |

> IDE được viết lại bên trong app theo cách dùng của Code::Blocks và Thonny (không nhúng trực tiếp mã nguồn hai phần mềm đó, vì Code::Blocks viết bằng C++/wxWidgets và Thonny viết bằng Python/Tkinter — không chạy được bên trong ứng dụng này). Phần gỡ lỗi dùng gdb giống Code::Blocks.

### Bài tập và contest (giống Codeforces)

1. Chèn khối **Bài tập**, bấm **Sửa** (⋮ → Sửa):
   - *Đề bài*: tên, giới hạn thời gian/bộ nhớ, cách so output, nội dung đề.
   - *Code chuẩn*: lời giải đúng của tác giả.
   - *Test*: nhập input, bấm **Tạo output bằng code chuẩn**. Đánh dấu vài test là *test mẫu* để hiện trong đề.
   - *Sinh test*: viết generator C++ in ra input ngẫu nhiên từ seed; app chạy generator rồi code chuẩn để **tự tạo hàng loạt test**.
2. Người học dán code vào ô *Bài làm*, bấm **Nộp bài** → kết quả `Accepted`, `Wrong answer on test N`, `Time limit exceeded`, `Runtime error`, `Compilation error`. Test ẩn không bị lộ dữ liệu.
3. Nút **Contest** → tạo kỳ thi từ các bài (A, B, C…) với thời gian làm bài. Thí sinh bấm **Bắt đầu làm bài**; bảng xếp hạng theo luật ICPC (số bài giải, rồi thời gian + 20 phút mỗi lần sai).
4. **Xuất đề cho thí sinh** tạo file đề *không kèm code chuẩn*. Thí sinh làm xong bấm **Xuất kết quả** gửi lại; người ra đề bấm **Nhập kết quả** để có bảng xếp hạng chung.

Chấm bài: bản máy tính dùng **g++ trên máy** (Windows có sẵn trong bộ cài; có thể chọn g++ khác trong *Cài đặt*). Android dùng [Compiler Explorer](https://godbolt.org) online.

### Nhánh, lịch sử, chia sẻ

- **Commit** (Ctrl+S) lưu một phiên bản. **Lịch sử** xem đồ thị commit, so sánh, khôi phục.
- **Nhánh**: tạo nhánh để thử cách ghi chú khác; **Merge** gộp lại, có màn hình giải quyết xung đột.
- **Chia sẻ**: lưu file `.dsanote.json` (kèm ảnh/video) hoặc tạo link dạng `sotaydsa://share/…` — bấm link sẽ mở thẳng app (nếu ứng dụng chat không cho bấm, dán link vào nút **Nhập**). Trên Android mở bảng chia sẻ (Zalo, Messenger, Drive…).
- **Nhập**: mở thành notebook riêng (*fork*), hoặc gộp vào notebook có sẵn — nhánh của người gửi hiện dạng `tên/nhánh` để xem và merge.

## Cấu trúc mã nguồn

```
index.html, css/        giao diện
js/vcs.js               commit, nhánh, diff, merge 3 chiều, fork/fetch
js/judge.js             chấm bài, so output, bảng xếp hạng ICPC, backend online
js/sim.js               chạy mô phỏng trong iframe sandbox + Web Worker (giới hạn thời gian)
js/blocks.js            khối kéo thả (Blockly) sinh code cho mô phỏng
js/contest.js           khối bài tập, sinh test, contest
js/ide.js               chế độ IDE: tab, build/chạy, console, gỡ lỗi
js/ui.js, js/app.js     giao diện
js/services.js          lưu trữ IndexedDB, ảnh/video, chia sẻ, chọn nơi chạy code
electron/               ứng dụng máy tính: chấm bài bằng g++, file, console, gỡ lỗi gdb (mi.js, ide.js)
android/                dự án Android (Capacitor)
.github/workflows/      đóng gói Windows / macOS / Linux / Android
vendor/                 thư viện đi kèm (marked, DOMPurify, highlight.js, CodeMirror, Blockly)
```

## Giới hạn

- Dữ liệu lưu trên từng máy; cộng tác bằng cách gửi file/link cho nhau (không có máy chủ đồng bộ). Hãy xuất file để sao lưu.
- Giới hạn bộ nhớ trong đề chỉ để hiển thị, chưa được kiểm tra khi chấm.
- Dữ liệu test nằm trong file đề, nên người rành kỹ thuật vẫn đọc được — phù hợp luyện tập/thi trong lớp, không chống gian lận tuyệt đối.
- Android cần Internet để chạy C++ (chấm online chậm hơn: mỗi test là một lượt gửi lên Compiler Explorer); chưa có gỡ lỗi từng dòng và console tương tác trên Android.
- Khi gỡ lỗi, output hiện sau mỗi bước nếu chương trình không tắt đồng bộ (`ios::sync_with_stdio(false)`).
- Code mô phỏng chạy trong sandbox nên mở notebook người khác gửi vẫn an toàn; code C++ chỉ chạy khi bạn bấm.
