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
    for (final s in snippets) {
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
}
