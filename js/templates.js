/*
 * templates.js — Mẫu mô phỏng có sẵn (người dùng chọn rồi tự sửa) và notebook hướng dẫn.
 * Nội dung ghi chú là do người dùng tự viết; ở đây chỉ có khung mẫu.
 */
(function (root) {
  'use strict';

  const SIM_TEMPLATES = [
    {
      id: 'blank',
      name: 'Trống',
      input: '',
      code: `// Viết mô phỏng bằng JavaScript (cú pháp gần giống C++).
// Xem nút "📖 API" để biết các hàm viz.*
const a = viz.array(readNumbers(), { name: 'a' });
`,
    },
    {
      id: 'bubble',
      name: 'Sắp xếp nổi bọt (Bubble sort)',
      input: '5 1 4 2 8 3',
      code: `const a = viz.array(readNumbers(), { name: 'a', bars: true });
const n = a.length;
for (let i = 0; i < n - 1; i++) {
  for (let j = 0; j < n - 1 - i; j++) {
    viz.var('i', i); viz.var('j', j);
    if (a.compare(j, j + 1) > 0) a.swap(j, j + 1);
  }
  a.mark(n - 1 - i, 'done', \`Phần tử \${a.get(n - 1 - i)} đã về đúng chỗ\`);
}
a.mark(0, 'done');
`,
    },
    {
      id: 'insertion',
      name: 'Sắp xếp chèn (Insertion sort)',
      input: '7 3 9 1 5 2',
      code: `const a = viz.array(readNumbers(), { name: 'a' });
for (let i = 1; i < a.length; i++) {
  let j = i;
  a.pointer('i', i);
  while (j > 0 && a.compare(j - 1, j) > 0) {
    a.swap(j - 1, j);
    j--;
  }
  a.markRange(0, i, 'sorted', \`Đoạn a[0..\${i}] đã được sắp xếp\`);
}
`,
    },
    {
      id: 'binsearch',
      name: 'Tìm kiếm nhị phân',
      input: '1 3 4 7 9 11 15 20 25\n11',
      code: `const nums = readNumbers();
const x = nums.pop();               // dòng 2 của dữ liệu vào là số cần tìm
const a = viz.array(nums.sort((p, q) => p - q), { name: 'a' });
viz.var('x', x);
let lo = 0, hi = a.length - 1;
viz.auto(false);                    // tự gọi viz.step() để kiểm soát từng bước
while (lo <= hi) {
  const mid = (lo + hi) >> 1;
  a.pointer('lo', lo); a.pointer('hi', hi); a.pointer('mid', mid);
  a.highlight(mid, 'compare');
  viz.step(\`lo=\${lo}, hi=\${hi}, mid=\${mid}: a[mid]=\${a.get(mid)}\`);
  if (a.get(mid) === x) { a.mark(mid, 'found'); viz.step(\`Tìm thấy \${x} tại vị trí \${mid}\`); break; }
  if (a.get(mid) < x) { a.markRange(lo, mid, 'dim'); lo = mid + 1; }
  else { a.markRange(mid, hi, 'dim'); hi = mid - 1; }
}
if (lo > hi) viz.step('Không tìm thấy');
`,
    },
    {
      id: 'stack',
      name: 'Stack: kiểm tra ngoặc',
      input: '{[()()]}',
      code: `const s = viz.stack([], { name: 'st' });
const pair = { ')': '(', ']': '[', '}': '{' };
let ok = true;
for (const ch of INPUT.trim()) {
  viz.var('ch', ch);
  if ('([{'.includes(ch)) s.push(ch);
  else if (s.empty() || s.top() !== pair[ch]) { ok = false; break; }
  else s.pop();
}
viz.step(ok && s.empty() ? 'Chuỗi ngoặc hợp lệ ✔' : 'Chuỗi ngoặc KHÔNG hợp lệ ✘');
`,
    },
    {
      id: 'bfsgrid',
      name: 'BFS trên lưới (tìm đường ngắn nhất)',
      input: `S..#......
.#.#.####.
.#...#....
.####.#.#.
......#.#E`,
      code: `const rows = INPUT.trim().split('\\n');
const g = viz.grid(rows.map(r => r.split('').map(ch => (ch === '.' || ch === '#') ? '' : ch)), { name: 'mê cung' });
let S, E;
viz.auto(false);
rows.forEach((r, i) => r.split('').forEach((ch, j) => {
  if (ch === '#') g.mark(i, j, 'wall');
  if (ch === 'S') { S = [i, j]; g.mark(i, j, 'start'); }
  if (ch === 'E') { E = [i, j]; g.mark(i, j, 'end'); }
}));
viz.step('Mê cung ban đầu');
viz.auto(true);
const q = [S], par = {}, seen = new Set([S + '']);
const dr = [-1, 1, 0, 0], dc = [0, 0, -1, 1];
while (q.length) {
  const [r, c] = q.shift();
  if (r === E[0] && c === E[1]) break;
  for (let k = 0; k < 4; k++) {
    const nr = r + dr[k], nc = c + dc[k];
    if (!g.inside(nr, nc) || g.state(nr, nc) === 'wall' || seen.has([nr, nc] + '')) continue;
    seen.add([nr, nc] + ''); par[[nr, nc]] = [r, c]; q.push([nr, nc]);
    if (g.state(nr, nc) !== 'end') g.mark(nr, nc, 'visited', \`Thăm ô (\${nr}, \${nc})\`);
  }
}
let cur = par[E], len = 1;
while (cur && cur + '' !== S + '') { g.mark(cur[0], cur[1], 'path', 'Truy vết đường đi'); cur = par[cur]; len++; }
viz.step(par[E] ? \`Đường đi ngắn nhất dài \${len} bước\` : 'Không có đường đi');
`,
    },
    {
      id: 'dfsgraph',
      name: 'DFS trên đồ thị',
      input: `0 1
0 2
1 3
1 4
2 5
4 5`,
      code: `const nums = readNumbers();
const edges = [];
for (let i = 0; i + 1 < nums.length; i += 2) edges.push([nums[i], nums[i + 1]]);
const G = viz.graph({ edges, name: 'G' });
const seen = new Set();
const order = [];
function dfs(u) {
  seen.add(u); order.push(u);
  G.visit(u, 'current', \`dfs(\${u})\`);
  for (const v of G.neighbors(u)) {
    if (seen.has(v)) continue;
    G.edge(u, v, 'path', \`Đi theo cạnh \${u} → \${v}\`);
    dfs(v);
    G.visit(u, 'current', \`Quay lại \${u}\`);
  }
  G.visit(u, 'done', \`Xong đỉnh \${u}\`);
}
dfs(0);
viz.log('Thứ tự duyệt:', order.join(' '));
`,
    },
    {
      id: 'dijkstra',
      name: 'Dijkstra (đường đi ngắn nhất có trọng số)',
      input: `0 1 4
0 2 1
2 1 2
1 3 1
2 3 5
3 4 3`,
      code: `const nums = readNumbers();
const edges = [];
for (let i = 0; i + 2 < nums.length; i += 3) edges.push([nums[i], nums[i + 1], nums[i + 2]]);
const G = viz.graph({ edges, name: 'G' });
const nodes = [...new Set(edges.flatMap(e => [e[0], e[1]]))];
const dist = {}; nodes.forEach(u => { dist[u] = Infinity; G.label(u, '∞'); });
dist[0] = 0; G.label(0, 0);
const done = new Set(), par = {};
while (done.size < nodes.length) {
  let u = null;
  for (const v of nodes) if (!done.has(v) && (u === null || dist[v] < dist[u])) u = v;
  if (dist[u] === Infinity) break;
  done.add(u);
  G.visit(u, 'current', \`Chọn đỉnh \${u} (dist = \${dist[u]})\`);
  for (const v of G.neighbors(u)) {
    const w = G.weight(u, v);
    G.edge(u, v, 'compare', \`Xét cạnh \${u}–\${v} (w = \${w})\`);
    if (dist[u] + w < dist[v]) {
      if (par[v] !== undefined) G.edge(par[v], v, null, \`Bỏ đường cũ tới \${v}\`);
      dist[v] = dist[u] + w; par[v] = u; G.label(v, dist[v]);
      G.edge(u, v, 'path', \`Cập nhật dist[\${v}] = \${dist[v]}\`);
    } else G.edge(u, v, par[v] === u || par[u] === v ? 'path' : null, 'Không cải thiện');
  }
  G.visit(u, 'done');
}
viz.step('Cây đường đi ngắn nhất (cạnh cam) từ đỉnh 0');
`,
    },
    {
      id: 'bst',
      name: 'Cây nhị phân tìm kiếm (BST)',
      input: '50 30 70 20 40 60 80 35',
      code: `const T = viz.tree({ name: 'BST' });
const L = {}, R = {};
let root = null;
for (const x of readNumbers()) {
  if (root === null) { root = x; T.addNode(x, \`Gốc = \${x}\`); continue; }
  let cur = root;
  while (true) {
    T.highlight(cur, 'compare', \`So sánh \${x} với \${cur}\`);
    const side = x < cur ? L : R;
    if (side[cur] === undefined) { side[cur] = x; T.addEdge(cur, x, '', \`Chèn \${x} vào \${x < cur ? 'trái' : 'phải'} của \${cur}\`); break; }
    cur = side[cur];
  }
}
`,
    },
  ];

  const API_DOC = `## API mô phỏng (JavaScript)

Script chạy **một lượt**, mọi thao tác được ghi lại thành từng bước để tua tới/lui.

| Hàm | Ý nghĩa |
|---|---|
| \`INPUT\` | chuỗi "Dữ liệu vào" của khối |
| \`readNumbers()\` | lấy mọi số trong INPUT thành mảng |
| \`viz.array(arr, {name, bars})\` | mảng; \`bars:true\` để vẽ dạng cột |
| \`a.get(i)\`, \`a.length\`, \`a.values()\` | đọc (không tạo bước) |
| \`a.set(i,x)\`, \`a.swap(i,j)\`, \`a.push(x)\`, \`a.pop()\` | sửa (tạo 1 bước) |
| \`a.compare(i,j)\` | tô màu so sánh, trả về -1/0/1 |
| \`a.highlight(i, state)\` | tô tạm thời trong 1 bước |
| \`a.mark(i, state)\`, \`a.markRange(l,r,state)\` | tô cố định (\`null\` để bỏ) |
| \`a.pointer('mid', i)\` | mũi tên chỉ số (không tạo bước) |
| \`viz.grid(rows, cols, fill)\` hoặc \`viz.grid(mảng2D)\` | lưới; \`g.mark(r,c,state)\`, \`g.set(r,c,x)\`, \`g.state(r,c)\`, \`g.inside(r,c)\` |
| \`viz.graph({nodes, edges:[[u,v,w]], directed})\` | đồ thị; \`G.visit(u,state)\`, \`G.edge(u,v,state)\`, \`G.neighbors(u)\`, \`G.weight(u,v)\`, \`G.label(u,text)\`, \`G.addNode\`, \`G.addEdge\` |
| \`viz.tree({...})\` | như graph nhưng vẽ dạng cây |
| \`viz.stack()\`, \`viz.queue()\` | \`push\`, \`pop\`, \`top\`, \`front\`, \`empty\`, \`size\` |
| \`viz.var(tên, giá trị)\` | hiện biến ở bảng biến |
| \`viz.log(...)\` / \`console.log(...)\` | in ra khung log |
| \`viz.step('ghi chú')\` | chụp một bước thủ công |
| \`viz.auto(false)\` | tắt tự tạo bước, chỉ tạo khi gọi \`viz.step\` |

**Trạng thái màu:** \`compare\`, \`swap\`, \`active\`, \`current\`, \`done\`, \`sorted\`, \`found\`, \`visited\`, \`path\`, \`wall\`, \`start\`, \`end\`, \`frontier\`, \`dim\` — hoặc mã màu như \`'#ff0088'\`.

Giới hạn: tối đa 5000 bước, 4 giây chạy. Code chạy trong sandbox nên an toàn khi mở notebook người khác chia sẻ.`;

  // Notebook hướng dẫn — chỉ giải thích cách dùng app, không phải nội dung bài học.
  function guideSnapshot() {
    const id = () => root.VCS.newId(12);
    const bubble = SIM_TEMPLATES.find((t) => t.id === 'bubble');
    return {
      title: 'Hướng dẫn sử dụng',
      description: 'Notebook mẫu giới thiệu các tính năng. Có thể xoá trang này và bắt đầu ghi chú của bạn.',
      pages: [
        {
          id: id(),
          title: 'Bắt đầu',
          chapter: 'Hướng dẫn',
          blocks: [
            {
              id: id(),
              type: 'markdown',
              text: `# Chào mừng 👋

Đây là **sổ ghi chú DSA** — bạn tự tổng hợp video bài giảng, ghi chú, code C++ và mô phỏng thuật toán.

- **Trang** (cột trái) được nhóm theo **chương**. Bấm "+ Trang" để thêm.
- Mỗi trang gồm các **khối**: 📝 ghi chú (Markdown), 🎬 video, 💻 code C++, ▶️ mô phỏng.
- Di chuột lên khối để **sửa / di chuyển / xoá**.
- Mọi thứ tự lưu vào trình duyệt. Khi xong một phần, bấm **Commit** để lưu một phiên bản.

## Nhánh như GitHub
- Ô **nhánh** trên thanh trên cùng: tạo nhánh mới để thử ghi chú theo cách khác, rồi **Merge** lại.
- **Lịch sử** xem các commit dạng đồ thị, so sánh thay đổi, khôi phục bản cũ.

## Chia sẻ
- **Chia sẻ** → xuất file \`.dsanote.json\` hoặc tạo link.
- Người nhận **Nhập** file/link: mở thành notebook riêng (fork) hoặc gộp vào notebook đang có như nhánh \`tên-người/nhánh\` rồi merge.`,
            },
            {
              id: id(),
              type: 'video',
              title: 'Dán link video bài giảng của bạn vào đây',
              url: '',
              timestamps: '00:00 Mở đầu\n05:30 Ví dụ',
            },
          ],
        },
        {
          id: id(),
          title: 'Ví dụ: code + mô phỏng',
          chapter: 'Hướng dẫn',
          blocks: [
            { id: id(), type: 'markdown', text: 'Khối code C++ có nút **Chạy** (biên dịch online qua Compiler Explorer) và ô nhập *stdin*.' },
            {
              id: id(),
              type: 'code',
              title: 'bubble_sort.cpp',
              code: `#include <bits/stdc++.h>
using namespace std;

int main() {
    int n; cin >> n;
    vector<int> a(n);
    for (int &x : a) cin >> x;
    for (int i = 0; i < n - 1; i++)
        for (int j = 0; j < n - 1 - i; j++)
            if (a[j] > a[j + 1]) swap(a[j], a[j + 1]);
    for (int x : a) cout << x << ' ';
    cout << '\\n';
}`,
              stdin: '6\n5 1 4 2 8 3',
            },
            { id: id(), type: 'markdown', text: 'Khối mô phỏng viết bằng JavaScript với thư viện `viz`. Bấm **Sửa** để xem code, **📖 API** để xem các hàm.' },
            { id: id(), type: 'sim', title: 'Mô phỏng Bubble sort', code: bubble.code, input: bubble.input },
          ],
        },
      ],
    };
  }

  root.TEMPLATES = { SIM_TEMPLATES, API_DOC, guideSnapshot };
})(typeof globalThis !== 'undefined' ? globalThis : this);
