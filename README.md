# 📚 Sổ tay DSA C++

Ứng dụng web (có giao diện đồ hoạ) để **tự tổng hợp video bài giảng Cấu trúc dữ liệu & Giải thuật bằng tiếng Việt**, viết ghi chú, lưu code C++ và **tự tạo mô phỏng thuật toán** — tất cả trong một "quyển sổ" có **nhánh, lịch sử, merge và chia sẻ giống GitHub**.

> Nội dung ghi chú do người dùng tự viết. App chỉ cung cấp công cụ và vài mẫu mô phỏng để bắt đầu.

## Chạy app

Không cần cài đặt, không cần build:

- **Cách 1 — mở trực tiếp:** nhấp đúp `index.html`.
- **Cách 2 — chạy server cục bộ** (nên dùng để link chia sẻ hoạt động):
  ```bash
  python3 -m http.server 8000
  # mở http://localhost:8000
  ```
- **Cách 3 — đưa lên mạng để chia sẻ link:** bật **GitHub Pages** cho repo (Settings → Pages → Deploy from branch → chọn nhánh, thư mục `/`). Người khác chỉ cần mở link.

Dữ liệu lưu trong trình duyệt (IndexedDB). Nên **xuất file** định kỳ để sao lưu.

## Tính năng

| | |
|---|---|
| 📄 **Trang & chương** | Notebook gồm nhiều trang, nhóm theo chương (Sắp xếp, Đồ thị…). Tìm kiếm toàn bộ nội dung. |
| 📝 **Ghi chú** | Markdown: tiêu đề, bảng, danh sách, khối code có tô màu. |
| 🎬 **Video** | Dán link YouTube (video, playlist, `?t=`), hoặc file `.mp4`. Thêm **mốc thời gian** (`05:30 Ý tưởng`) — bấm để nhảy tới. Tab **Video** ở cột trái tổng hợp mọi video trong notebook. |
| 💻 **Code C++** | Trình soạn có tô màu cú pháp, ô **stdin**, nút **▶ Chạy** biên dịch online qua [Compiler Explorer](https://godbolt.org) (đổi trình biên dịch/cờ trong ⚙ Cài đặt), tải file `.cpp`. |
| ▶️ **Mô phỏng** | Tự viết mô phỏng bằng JavaScript với thư viện `viz` (mảng, lưới, đồ thị, cây, stack, queue). Có trình phát tua tới/lui từng bước, chỉnh tốc độ, bảng biến, log. Mẫu sẵn: Bubble/Insertion sort, Binary search, Stack, BFS lưới, DFS, Dijkstra, BST. |
| ⎇ **Nhánh** | Tạo nhánh để thử cách ghi chú khác, chuyển nhánh, đổi tên, xoá. |
| ✔ **Commit & lịch sử** | Lưu phiên bản kèm mô tả (Ctrl+S). Xem đồ thị lịch sử, diff từng dòng, xem lại bản cũ, khôi phục, tạo nhánh từ commit bất kỳ. |
| ⑂ **Merge** | Gộp nhánh kiểu 3 chiều (fast-forward khi được). Khi hai bên sửa cùng chỗ: chọn *của mình / của họ / tự gộp*. |
| 🔗 **Chia sẻ** | Xuất file `.dsanote.json` hoặc **link** (dữ liệu nén trong link). Chọn nhánh muốn chia sẻ. |
| ⬆ **Nhập** | Mở thành notebook riêng (**fork**), hoặc **gộp vào notebook có sẵn**: các nhánh của người gửi hiện dạng `tên-người/nhánh` (như `git fetch`) để xem và merge. |

### Quy trình làm việc nhóm (giống GitHub)

1. **An** tạo notebook, ghi chú, commit, rồi **Chia sẻ** → gửi file/link cho Bình.
2. **Bình** **Nhập** → *Mở như notebook mới* (fork), tạo nhánh `them-do-thi`, viết thêm, commit, chia sẻ lại cho An.
3. **An** **Nhập** → *Gộp vào notebook có sẵn* → thấy nhánh `Bình/them-do-thi` → xem trước → **Merge** vào `main`.

## Viết mô phỏng

Khối mô phỏng chạy JavaScript (cú pháp `for`, `if`, `while` giống C++). Ví dụ:

```js
const a = viz.array(readNumbers(), { name: 'a', bars: true });
for (let i = 0; i < a.length; i++)
  for (let j = 0; j + 1 < a.length - i; j++)
    if (a.compare(j, j + 1) > 0) a.swap(j, j + 1);   // mỗi thao tác = 1 bước
```

Bấm **📖 API** trong khối mô phỏng để xem đầy đủ các hàm (`viz.grid`, `viz.graph`, `viz.tree`, `viz.stack`, `viz.queue`, `viz.var`, `viz.step`, …).

**An toàn:** code mô phỏng chạy trong `iframe` sandbox + Web Worker, không đọc được dữ liệu của app, tự dừng sau 4 giây hoặc 5000 bước — nên mở notebook người khác chia sẻ vẫn an toàn.

## Cấu trúc mã nguồn

```
index.html          giao diện
css/style.css       giao diện sáng/tối, responsive
js/vcs.js           "git mini": commit, nhánh, lịch sử, diff, merge 3 chiều, fork/fetch
js/sim.js           bộ chạy mô phỏng (Worker ghi bước + trình phát SVG trong iframe sandbox)
js/templates.js     mẫu mô phỏng, tài liệu API, notebook hướng dẫn
js/services.js      IndexedDB, cài đặt, nén link chia sẻ, chạy C++ qua Compiler Explorer
js/app.js           giao diện chính
vendor/             marked, DOMPurify, highlight.js, CodeMirror 5 (kèm sẵn để chạy offline)
tests/              kiểm thử: node --test tests/*.test.js
```

## Kiểm thử

```bash
node --test tests/*.test.js
```

## Giới hạn

- Dữ liệu nằm trong trình duyệt của từng người; cộng tác bằng cách trao đổi file/link (không có máy chủ đồng bộ).
- Nút **Chạy** C++ cần Internet (gọi API godbolt.org). Mọi tính năng khác chạy offline.
- Link chia sẻ chứa toàn bộ dữ liệu nên notebook lớn sẽ có link dài — khi đó dùng file.
