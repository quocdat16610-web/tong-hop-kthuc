// Mẫu có sẵn: code C++, bài tập, mô phỏng, notebook hướng dẫn.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'scratch.dart';
import 'scratch_templates.dart';
import 'vcs.dart';

const cppTemplate = '''#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    return 0;
}
''';

const pyTemplate = '''import sys
input = sys.stdin.readline


def main():
    n = int(input())
    a = list(map(int, input().split()))
    print(sum(a))


main()
''';

const pyIdeNewCode = '''n = int(input("Nhap n: "))
print("n * n =", n * n)
''';

const ideNewCode = '''#include <bits/stdc++.h>
using namespace std;

int main() {
    int n;
    cout << "Nhap n: ";
    cin >> n;
    cout << "n * n = " << n * n << endl;
    return 0;
}
''';

const genTemplate = r'''// Generator: đọc số seed, in ra MỘT bộ test (input).
// App chạy generator với seed = 1, 2, 3, … rồi dùng code chuẩn để tạo output.
#include <bits/stdc++.h>
using namespace std;

int main() {
    long long seed;
    cin >> seed;
    mt19937_64 rng(seed);
    auto rnd = [&](long long l, long long r) {
        return uniform_int_distribution<long long>(l, r)(rng);
    };
    int n = rnd(1, 10);
    cout << n << '\n';
    for (int i = 0; i < n; i++) cout << rnd(1, 100) << ' ';
    cout << '\n';
}
''';

const statementTemplate = '''Mô tả đề bài ở đây.

### Dữ liệu vào
- ...

### Kết quả
- ...

### Giới hạn
- ...''';

const checkers = [
  ('tokens', 'So từng từ (bỏ qua khoảng trắng thừa)'),
  ('exact', 'Khớp chính xác từng dòng'),
  ('float:1e-6', 'Số thực, sai số 1e-6'),
  ('float:1e-9', 'Số thực, sai số 1e-9'),
];

Json newProblem() => {
      'title': 'Bài mới',
      'statement': statementTemplate,
      'timeLimit': 1000,
      'memoryLimit': 256,
      'checker': 'tokens',
      'reference': cppTemplate,
      'generator': genTemplate,
      'genCount': 10,
      'tests': <dynamic>[],
    };

class SimTemplate {
  final String id, name, input, code;
  SimTemplate(this.id, this.name, this.input, this.code);
}

List<SimTemplate> simTemplates = [];
String simApiDoc = '';

Future<void> loadTemplates() async {
  final d = jsonDecode(await rootBundle.loadString('assets/templates.json')) as Map;
  simTemplates = (d['simTemplates'] as List).cast<Map>().map((t) => SimTemplate(t['id'], t['name'], t['input'], t['code'])).toList();
  simApiDoc = d['apiDoc'] as String;
}

Json guideSnapshot() {
  String id() => newId(12);
  return {
    'title': 'Hướng dẫn sử dụng',
    'description': 'Notebook mẫu giới thiệu các tính năng. Bạn có thể xoá và bắt đầu ghi chú của mình.',
    'contests': <dynamic>[],
    'pages': [
      {
        'id': id(),
        'title': 'Hướng dẫn sử dụng',
        'chapter': 'Bắt đầu',
        'blocks': [
          {'id': id(), 'type': 'heading', 'level': 1, 'text': 'Cách dùng sổ tay'},
          {
            'id': id(),
            'type': 'markdown',
            'text': 'Mọi thứ có thể nằm chung **một trang**: tiêu đề, ghi chú, ảnh, video, code, mô phỏng và bài tập. '
                'Cột **Mục lục** bên trái tự tạo từ các tiêu đề.\n\n'
                '- Bấm **+** giữa hai khối hoặc thanh *Thêm khối* cuối trang để chèn khối mới.\n'
                '- Bấm nút **⋮** ở góc khối để sửa, di chuyển, xoá.\n'
                '- Bấm **Commit** (Ctrl+S) để lưu một phiên bản. Mỗi nhánh là một hướng ghi chú riêng, có thể **Merge** lại.\n'
                '- Chuyển sang **IDE C++** ở thanh bên trái để lập trình với nhiều tab, Build/Chạy (F9) và gỡ lỗi (F8).',
          },
          {'id': id(), 'type': 'heading', 'level': 2, 'text': 'Video bài giảng'},
          {'id': id(), 'type': 'video', 'title': 'Dán link YouTube hoặc chọn file video trên máy', 'url': '', 'timestamps': '00:00 Mở đầu\n05:30 Ví dụ'},
          {'id': id(), 'type': 'heading', 'level': 2, 'text': 'Code C++'},
          {
            'id': id(),
            'type': 'code',
            'title': 'bubble_sort.cpp',
            'code': '#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    int n; cin >> n;\n    vector<int> a(n);\n    for (int &x : a) cin >> x;\n    for (int i = 0; i < n - 1; i++)\n        for (int j = 0; j < n - 1 - i; j++)\n            if (a[j] > a[j + 1]) swap(a[j], a[j + 1]);\n    for (int x : a) cout << x << \' \';\n    cout << \'\\n\';\n}',
            'stdin': '6\n5 1 4 2 8 3',
          },
          {'id': id(), 'type': 'heading', 'level': 2, 'text': 'Mô phỏng thuật toán'},
          {
            'id': id(),
            'type': 'markdown',
            'text': 'Mô phỏng được ghép bằng **khối kéo thả** như Scratch: kéo khối từ bảng bên trái vào chương trình, thả khối giá trị vào ô. '
                'Có sẵn mẫu sắp xếp, tìm kiếm nhị phân, stack, BFS, DFS đệ quy, cây BST. Muốn viết tay thì chuyển sang **Code JS**.',
          },
          {'id': id(), 'type': 'sim', 'mode': 'blocks', 'title': 'Sắp xếp nổi bọt (kéo thả)', 'scratch': blockTemplates.first.program(), 'code': generateJs(blockTemplates.first.program()), 'input': blockTemplates.first.input},
          {'id': id(), 'type': 'sim', 'mode': 'blocks', 'title': 'DFS đệ quy (kéo thả, dùng hàm)', 'scratch': blockTemplates[6].program(), 'code': generateJs(blockTemplates[6].program()), 'input': blockTemplates[6].input},
          ...whiteboardDemo(id),
          {'id': id(), 'type': 'heading', 'level': 2, 'text': 'Bài tập và contest'},
          {
            'id': id(),
            'type': 'markdown',
            'text': 'Khối **Bài tập** có đề, test, code chuẩn và trình sinh test. Người học nộp bài và được chấm như Codeforces. '
                'Mở **Contest** để gom các bài thành một kỳ thi có giờ và bảng xếp hạng.',
          },
          {
            'id': id(),
            'type': 'problem',
            'title': 'Tổng hai số',
            'statement': 'Cho hai số nguyên **a** và **b** (|a|, |b| ≤ 9·10^18). Hãy in ra **a + b**.\n\n### Dữ liệu vào\nMột dòng gồm hai số nguyên `a b`.\n\n### Kết quả\nMột số nguyên là tổng `a + b`.\n\n*Gợi ý: tổng có thể vượt `long long`, hãy dùng `__int128`.*',
            'timeLimit': 1000,
            'memoryLimit': 256,
            'checker': 'tokens',
            'reference': r'''#include <bits/stdc++.h>
using namespace std;

string toStr(__int128 x) {
    if (x == 0) return "0";
    bool neg = x < 0; if (neg) x = -x;
    string s;
    while (x > 0) { s += char('0' + x % 10); x /= 10; }
    if (neg) s += '-';
    reverse(s.begin(), s.end());
    return s;
}

int main() {
    long long a, b;
    cin >> a >> b;
    cout << toStr((__int128)a + b) << '\n';
}
''',
            'generator': r'''#include <bits/stdc++.h>
using namespace std;

int main() {
    long long seed;
    cin >> seed;
    mt19937_64 rng(seed);
    long long M = 9000000000000000000LL;
    auto rnd = [&]() { return (long long)(rng() % (2 * (unsigned long long)M + 1)) - M; };
    cout << rnd() << ' ' << rnd() << '\n';
}
''',
            'genCount': 10,
            'tests': [
              {'input': '1 2\n', 'output': '3\n', 'sample': true},
              {'input': '9000000000000000000 9000000000000000000\n', 'output': '18000000000000000000\n', 'sample': true},
              {'input': '-5 3\n', 'output': '-2\n', 'sample': false},
              {'input': '-9000000000000000000 -9000000000000000000\n', 'output': '-18000000000000000000\n', 'sample': false},
            ],
          },
        ],
      },
    ],
  };
}

// ---------- Video ----------
int parseTime(String t) {
  if (RegExp(r'^\d+$').hasMatch(t)) return int.parse(t);
  final m = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$').firstMatch(t);
  if (m != null && (m.group(1) != null || m.group(2) != null || m.group(3) != null)) {
    return (int.tryParse(m.group(1) ?? '') ?? 0) * 3600 + (int.tryParse(m.group(2) ?? '') ?? 0) * 60 + (int.tryParse(m.group(3) ?? '') ?? 0);
  }
  return t.split(':').map((x) => int.tryParse(x) ?? 0).fold(0, (a, x) => a * 60 + x);
}

class Timestamp {
  final int sec;
  final String time, label;
  Timestamp(this.sec, this.time, this.label);
}

List<Timestamp> parseTimestamps(String? text) => (text ?? '')
    .split('\n')
    .map((line) => RegExp(r'^((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[-–:]?\s*(.*)$').firstMatch(line.trim()))
    .whereType<RegExpMatch>()
    .map((m) => Timestamp(parseTime(m.group(1)!), m.group(1)!, m.group(2)!))
    .toList();

class VideoSource {
  final String kind; // asset | youtube | file | link
  final String value;
  final int start;
  VideoSource(this.kind, this.value, [this.start = 0]);
}

/// Nhận link video hoặc mã nhúng (<iframe src="…">) và cho biết cách phát.
VideoSource? parseVideo(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  url = url.trim();
  if (url.startsWith('asset:')) return VideoSource('asset', url);
  // Mã nhúng: <iframe src="..."> hoặc <video src="..."> → lấy link bên trong.
  final embed = RegExp('<(?:iframe|video|source|embed)[^>]*\\ssrc\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false).firstMatch(url);
  if (embed != null) url = embed.group(1)!.replaceAll('&amp;', '&');
  if (url.startsWith('//')) url = 'https:$url';
  if (!url.contains('://') && RegExp(r'^(www\.|m\.)?(youtube\.com|youtu\.be|drive\.google\.com)').hasMatch(url)) url = 'https://$url';
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme) return null;
  final host = u.host.replaceFirst(RegExp(r'^(www|m|music)\.'), '');
  if (host == 'youtu.be' || host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    String? id = host == 'youtu.be' ? (u.pathSegments.isNotEmpty ? u.pathSegments.first : null) : u.queryParameters['v'];
    if (id == null) {
      final m = RegExp(r'^/(embed|shorts|live|v|e)/([\w-]+)').firstMatch(u.path);
      id = m?.group(2);
    }
    final t = u.queryParameters['t'] ?? u.queryParameters['start'];
    if (id != null && id != 'videoseries') return VideoSource('youtube', id, t != null ? parseTime(t.endsWith('s') && RegExp(r'^\d+s$').hasMatch(t) ? t.substring(0, t.length - 1) : t) : 0);
  }
  if (host == 'drive.google.com') {
    final id = RegExp(r'/file/d/([\w-]+)').firstMatch(u.path)?.group(1) ?? u.queryParameters['id'];
    if (id != null) return VideoSource('drive', id);
  }
  if (RegExp(r'\.(mp4|webm|mov|m4v|mkv|m3u8|mp3|m4a)$', caseSensitive: false).hasMatch(u.path)) return VideoSource('file', url);
  if (u.scheme == 'http' || u.scheme == 'https') return VideoSource('link', url);
  return null;
}

/// Phần "Bảng trắng" trong sổ hướng dẫn: hình minh hoạ mảng và hai con trỏ.
List<Json> whiteboardDemo(String Function() id) {
  List<num> box(num x, num y) => [x, y, x + 70, y + 60];
  final strokes = <Json>[
    for (var i = 0; i < 6; i++) {'t': 'rect', 'c': 0xFF1F2328, 'w': 3, 'p': box(160 + i * 80, 160)},
    for (var i = 0; i < 6; i++) {'t': 'text', 'c': 0xFF1F2328, 'w': 4, 'p': [185 + i * 80, 172], 'text': '${[1, 3, 5, 7, 9, 11][i]}'},
    for (var i = 0; i < 6; i++) {'t': 'text', 'c': 0xFF6E7781, 'w': 2, 'p': [190 + i * 80, 228], 'text': '$i'},
    {'t': 'arrow', 'c': 0xFF0969DA, 'w': 3, 'p': [195, 330, 195, 255]},
    {'t': 'text', 'c': 0xFF0969DA, 'w': 4, 'p': [185, 340], 'text': 'l'},
    {'t': 'arrow', 'c': 0xFFCF222E, 'w': 3, 'p': [595, 330, 595, 255]},
    {'t': 'text', 'c': 0xFFCF222E, 'w': 4, 'p': [585, 340], 'text': 'r'},
    {'t': 'highlighter', 'c': 0xFFBF8700, 'w': 3, 'p': [160, 140, 300, 138, 450, 140, 630, 138]},
    {'t': 'text', 'c': 0xFF1A7F37, 'w': 4, 'p': [160, 60], 'text': 'Hai con trỏ: tìm cặp có tổng = 12'},
  ];
  return [
    {'id': id(), 'type': 'heading', 'level': 2, 'text': 'Bảng trắng'},
    {
      'id': id(),
      'type': 'markdown',
      'text': 'Khối **Bảng trắng** để vẽ tay minh hoạ thuật toán: bút, bút dạ, đường thẳng, mũi tên, hình chữ nhật, hình tròn, chữ, tẩy, hoàn tác. '
          'Nét vẽ được lưu trong notebook nên cũng có lịch sử, commit và chia sẻ như các nội dung khác.',
    },
    {'id': id(), 'type': 'board', 'title': 'Hai con trỏ trên mảng đã sắp xếp', 'height': 420, 'bg': 'grid', 'strokes': strokes},
  ];
}

