// Tạo notebook mẫu cho thư viện GitHub: flutter test tool/export_guide_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/templates.dart';
import 'package:so_tay_dsa/core/vcs.dart';

void main() {
  test('xuất sổ hướng dẫn vào content/', () {
    final f = File('../content/huong-dan.dsanote.json');
    if (f.existsSync()) return; // giữ nguyên repoId để người dùng nhận được cập nhật
    final r = Repo.create(title: 'Hướng dẫn sử dụng', author: 'Sổ tay DSA', snapshot: guideSnapshot());
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(r.exportBundle(author: 'Sổ tay DSA')));
  });
}
