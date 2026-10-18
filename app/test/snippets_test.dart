import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/snippets.dart';

bool get hasGpp {
  try {
    return Process.runSync('g++', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  test('mọi code mẫu biên dịch được với g++', () {
    final dsu = snippets.firstWhere((s) => s.name.startsWith('DSU')).code;
    final dir = Directory.systemTemp.createTempSync('snip');
    for (final s in snippets.where((s) => s.lang == 'cpp')) {
      final hasMain = s.code.contains('int main(');
      final src = [
        if (!s.code.contains('#include')) '#include <bits/stdc++.h>\nusing namespace std;\nusing ll = long long;',
        if (s.name.startsWith('Kruskal')) dsu,
        s.code,
        if (!hasMain) 'int main() {}',
      ].join('\n');
      final f = File('${dir.path}/a.cpp')..writeAsStringSync(src);
      final r = Process.runSync('g++', ['-std=c++17', '-fsyntax-only', f.path]);
      expect(r.exitCode, 0, reason: '${s.name}\n${r.stderr}');
    }
    dir.deleteSync(recursive: true);
  }, skip: !hasGpp);

  test('code mẫu Python đúng cú pháp', () {
    final dir = Directory.systemTemp.createTempSync('snippy');
    final py = snippets.where((s) => s.lang == 'py').toList();
    expect(py, isNotEmpty);
    for (final s in py) {
      final f = File('${dir.path}/a.py')..writeAsStringSync(s.code);
      final r = Process.runSync(pyExe!, ['-m', 'py_compile', f.path]);
      expect(r.exitCode, 0, reason: '${s.name}\n${r.stderr}');
    }
    dir.deleteSync(recursive: true);
  }, skip: pyExe == null);
}

final String? pyExe = () {
  for (final c in [Platform.environment['SOTAY_TEST_PYTHON'], 'python3', 'python']) {
    if (c == null || c.isEmpty) continue;
    try {
      final r = Process.runSync(c, ['--version']);
      if (r.exitCode == 0 && '${r.stdout}${r.stderr}'.startsWith('Python 3')) return c;
    } catch (_) {}
  }
  return null;
}();
