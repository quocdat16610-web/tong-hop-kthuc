import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/gdb.dart';
import 'package:so_tay_dsa/core/judge.dart';
import 'package:so_tay_dsa/core/runner.dart';
import 'package:so_tay_dsa/core/vcs.dart';

Json page(String id, String title, [List<Json>? blocks]) => {'id': id, 'title': title, 'chapter': '', 'blocks': blocks ?? []};
Json md(String id, String text) => {'id': id, 'type': 'markdown', 'text': text};
List<Json> pages(Repo r) => pagesOf(r.working);

Repo setup() {
  final r = Repo.create(title: 'DSA', author: 'An');
  (r.working['pages'] as List).add(page('p1', 'Mảng', [md('b1', 'dòng 1\ndòng 2'), md('b2', 'hai')]));
  r.commit(message: 'thêm trang', author: 'An');
  return r;
}

/// Python 3 để kiểm thử: biến môi trường SOTAY_TEST_PYTHON (CI Windows dùng Python đóng gói) hoặc python3 / python.
final String? testPython = () {
  for (final c in [Platform.environment['SOTAY_TEST_PYTHON'], 'python3', 'python']) {
    if (c == null || c.isEmpty) continue;
    try {
      final r = Process.runSync(c, ['--version']);
      if (r.exitCode == 0 && '${r.stdout}${r.stderr}'.startsWith('Python 3')) return c;
    } catch (_) {}
  }
  return null;
}();

bool hasTool(String t) {
  try {
    return Process.runSync(t, ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  group('VCS', () {
    test('commit, dirty, lịch sử', () {
      final r = setup();
      expect(r.isDirty, false);
      expect(() => r.commit(message: 'x', author: 'a'), throwsA(isA<VcsError>()));
      pages(r)[0]['title'] = 'Mảng 1 chiều';
      expect(r.isDirty, true);
      r.commit(message: 'đổi tên', author: 'a');
      expect(r.log().length, 3);
    });

    test('nhánh và checkout', () {
      final r = setup();
      r.createBranch('ghi-chu-cua-binh');
      r.checkout('ghi-chu-cua-binh');
      (r.working['pages'] as List).add(page('p2', 'Stack'));
      expect(() => r.checkout('main'), throwsA(isA<VcsError>()));
      r.commit(message: 'stack', author: 'b');
      r.checkout('main');
      expect(pages(r).length, 1);
      expect(() => r.createBranch('a b'), throwsA(isA<VcsError>()));
    });

    test('merge 3 chiều không xung đột + fast-forward', () {
      final r = setup();
      r.createBranch('f');
      r.checkout('f');
      blocksOf(pages(r)[0])[0]['text'] = 'dòng 1 sửa\ndòng 2';
      (r.working['pages'] as List).add(page('p3', 'Đồ thị'));
      r.commit(message: 'f', author: 'a');
      r.checkout('main');
      (pages(r)[0]['blocks'] as List).add(md('b3', 'ba'));
      pages(r)[0]['title'] = 'Mảng (main)';
      r.commit(message: 'm', author: 'a');
      final prep = r.prepareMerge('f');
      expect(prep.kind, MergeKind.merge);
      expect(prep.conflicts, isEmpty);
      r.finishMerge(prep, snapshot: prep.snapshot, from: 'f');
      expect(pages(r)[0]['title'], 'Mảng (main)');
      expect(blocksOf(pages(r)[0]).map((b) => b['id']), ['b1', 'b2', 'b3']);
      expect(blocksOf(pages(r)[0])[0]['text'], 'dòng 1 sửa\ndòng 2');
      expect(r.prepareMerge('f').kind, MergeKind.upToDate);
    });

    test('merge có xung đột + giải quyết', () {
      final r = setup();
      r.createBranch('f');
      r.checkout('f');
      blocksOf(pages(r)[0])[1]['text'] = 'của họ';
      blocksOf(pages(r)[0])[0]['text'] = 'họ sửa b1';
      r.commit(message: 'f', author: 'a');
      r.checkout('main');
      blocksOf(pages(r)[0])[1]['text'] = 'của tôi';
      (pages(r)[0]['blocks'] as List).removeAt(0);
      r.commit(message: 'm', author: 'a');
      final prep = r.prepareMerge('f');
      expect(prep.conflicts.map((c) => c.type).toList()..sort(), ['block-delete', 'field']);
      final choices = prep.conflicts.map((c) => c.type == 'field' ? {'value': 'gộp'} : 'theirs').toList();
      final snap = applyResolutions(prep.snapshot!, prep.conflicts, choices);
      expect(blocksOf(pagesOf(snap)[0]).map((b) => [b['id'], b['text']]).toList(), [['b1', 'họ sửa b1'], ['b2', 'gộp']]);
    });

    test('chia sẻ: fork và fetch', () {
      final r = setup();
      final fork = Repo.fromBundle(r.exportBundle(author: 'An'));
      expect(fork.id, isNot(r.id));
      pages(fork)[0]['title'] = 'Bình sửa';
      fork.commit(message: 'bình', author: 'Bình');
      final back = r.fetchBundle(fork.exportBundle(), 'Bình');
      expect(back.added, 1);
      expect(back.refs, ['Bình/main']);
      expect(r.prepareMerge('Bình/main').kind, MergeKind.fastForward);
    });

    test('diff và đồ thị lịch sử', () {
      expect(diffLines('a\nb\nc', 'a\nx\nc').map((x) => '${x.op}${x.text}'), [' a', '-b', '+x', ' c']);
      final r = setup();
      r.createBranch('f');
      r.checkout('f');
      r.working['title'] = 'F';
      r.commit(message: 'f', author: 'a');
      r.checkout('main');
      r.working['description'] = 'M';
      r.commit(message: 'm', author: 'a');
      final prep = r.prepareMerge('f');
      r.finishMerge(prep, snapshot: prep.snapshot);
      final rows = graphLayout(r.log());
      expect((rows[0].commit['parents'] as List).length, 2);
      expect(rows.map((x) => x.col).reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(1));
    });
  });

  group('Chấm bài', () {
    test('so output và bảng xếp hạng', () {
      expect(checkOutput('tokens', '1 2\n3', '1  2 3\n\n'), true);
      expect(checkOutput('exact', 'a b\nc\n', 'a b  \nc'), true);
      expect(checkOutput('float:1e-6', '0.3333333', '0.33333334'), true);
      expect(checkOutput('float:1e-6', '0.33', '0.34'), false);
      const t0 = 1000000;
      final rows = standings({'durationMin': 60, 'problems': ['A', 'B']}, [
        {'user': 'An', 'startedAt': t0, 'subs': [
          {'problemId': 'A', 'time': t0 + 10 * 60000, 'verdict': 'WA'},
          {'problemId': 'A', 'time': t0 + 12 * 60000, 'verdict': 'AC'},
        ]},
        {'user': 'Bình', 'startedAt': t0, 'subs': [{'problemId': 'A', 'time': t0 + 20 * 60000, 'verdict': 'AC'}]},
      ]);
      expect(rows[0].user, 'Bình');
      expect(rows[1].penalty, 32);
      expect(verdictText('WA', 3), 'Wrong answer on test 3');
    });

    test('chấm bằng g++: AC / WA / TLE / RE / CE', () async {
      final be = LocalBackend('g++', '-O2 -std=c++17');
      const sum = '#include <bits/stdc++.h>\nint main(){long long a,b;std::cin>>a>>b;std::cout<<a+b<<"\\n";}';
      final tests = [
        {'input': '1 2', 'output': '3'},
        {'input': '2000000000 2000000000', 'output': '4000000000'},
      ];
      expect((await judge(source: sum, tests: tests, backend: be)).verdict, 'AC');
      final wa = await judge(source: sum.replaceAll('long long', 'int'), tests: tests, backend: be);
      expect([wa.verdict, wa.test], ['WA', 2]);
      final tle = await judge(source: 'int main(){volatile long long x=0;while(true)x++;}', tests: tests, timeLimit: 300, backend: be);
      expect(tle.verdict, 'TLE');
      expect((await judge(source: '#include <cstdlib>\nint main(){std::abort();}', tests: tests, backend: be)).verdict, 'RE');
      final ce = await judge(source: 'int main(){ return x; }', tests: tests, backend: be);
      expect(ce.verdict, 'CE');
      expect(ce.message, contains('main.cpp'));
      expect((await runAll(sum, ['2 2', '3 4'], be)).map((s) => s.trim()), ['4', '7']);
    }, skip: !hasTool('g++'));

    test('chấm Python: AC / WA / TLE / RE / CE', () async {
      final be = LocalBackend('', '', python: testPython);
      const sum = 'a, b = map(int, input().split())\nprint(a + b)\n';
      final tests = [
        {'input': '1 2', 'output': '3'},
        {'input': '2000000000 2000000000', 'output': '4000000000'},
      ];
      expect((await judge(lang: 'py', source: sum, tests: tests, backend: be)).verdict, 'AC');
      final wa = await judge(lang: 'py', source: 'a, b = map(int, input().split())\nprint(min(a + b, 2**31 - 1))\n', tests: tests, backend: be);
      expect([wa.verdict, wa.test], ['WA', 2]);
      final tle = await judge(lang: 'py', source: 'while True:\n    pass\n', tests: tests, timeLimit: 300, backend: be);
      expect(tle.verdict, 'TLE');
      final re = await judge(lang: 'py', source: 'x = [1]\nprint(x[5])\n', tests: tests, backend: be);
      expect(re.verdict, 'RE');
      final ce = await judge(lang: 'py', source: 'def f(:\n    pass\n', tests: tests, backend: be);
      expect(ce.verdict, 'CE');
      expect(ce.message, contains('main.py'));
      expect((await runAll(sum, ['2 2', '3 4'], be, lang: 'py')).map((s) => s.trim()), ['4', '7']);
      // In tiếng Việt không bị lỗi mã hoá.
      expect((await runAll('print("Xin chào " + input())', ['bạn'], be, lang: 'py')).single.trim(), 'Xin chào bạn');
    }, skip: testPython == null);
  });

  group('IDE', () {
    test('đọc dòng GDB/MI', () {
      final r = parseMiLine('12^done,variables=[{name="a",value="1"}],stack=[frame={level="0",line="5"}]')!;
      expect(r.token, 12);
      expect(r.data['variables'], [{'name': 'a', 'value': '1'}]);
      expect(r.data['stack'], [{'level': '0', 'line': '5'}]);
      expect(parseMiLine('~"Hello\\n"')!.text, 'Hello\n');
      expect(parseMiLine('(gdb) '), isNull);
    });

    test('chạy tương tác', () async {
      final be = LocalBackend('g++', '-std=c++17');
      final c = await be.compile('#include <iostream>\nint main(){ std::cout << "n? "; int n; std::cin >> n; std::cout << n * 2 << "\\n"; }', unbuffered: true);
      expect(c.ok, true, reason: c.error);
      final proc = await be.spawn(c.id);
      var out = '';
      final done = Completer<void>();
      proc.stdout.listen((d) {
        out += String.fromCharCodes(d).replaceAll('\r\n', '\n');
        if (out == 'n? ') proc.stdin.writeln('21');
      }, onDone: done.complete);
      expect(await proc.exitCode, 0);
      await done.future;
      expect(out, 'n? 42\n');
      be.dispose(c.id);
    }, skip: !hasTool('g++'));

    test('gỡ lỗi với gdb', () async {
      const src = '#include <bits/stdc++.h>\nusing namespace std;\nint sq(int x) {\n    return x * x;\n}\nint main() {\n    int n; cin >> n;\n    int s = 0;\n    for (int i = 1; i <= n; i++)\n        s += sq(i);\n    cout << s << endl;\n}\n';
      final be = LocalBackend('g++', '-std=c++17');
      final c = await be.compile(src, debug: true);
      expect(c.ok, true, reason: c.error);
      final events = StreamController<DebugEvent>();
      final it = StreamIterator(events.stream);
      Future<T> next<T extends DebugEvent>() async {
        while (await it.moveNext()) {
          if (it.current is T) return it.current as T;
        }
        throw StateError('hết sự kiện');
      }

      final s = DebugSession(gdb: 'gdb', progId: c.id, input: '3\n', initialBreakpoints: [10], onEvent: events.add);
      await s.start();
      var st = await next<DebugStopped>();
      expect(st.line, 10);
      expect(st.locals.firstWhere((v) => v.name == 'n').value, '3');
      await s.control('step');
      st = await next<DebugStopped>();
      expect(st.func, 'sq');
      expect(st.frames.map((f) => f.func), ['sq', 'main']);
      await s.control('finish');
      st = await next<DebugStopped>();
      expect(st.func, 'main');
      await s.removeBreakpoint(10);
      await s.control('continue');
      final ex = await next<DebugExited>();
      expect(ex.code, 0);
      expect(ex.output.trim(), '14');
    }, skip: !(hasTool('g++') && hasTool('gdb')), timeout: const Timeout(Duration(seconds: 60)));
  });
}
