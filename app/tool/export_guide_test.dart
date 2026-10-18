// Tạo / cập nhật notebook mẫu cho thư viện GitHub: flutter test tool/export_guide_test.dart
// Cập nhật bằng commit mới trên CÙNG notebook (giữ repoId) để người dùng tự nhận nội dung mới.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/templates.dart';
import 'package:so_tay_dsa/core/vcs.dart';

void main() {
  test('xuất / cập nhật sổ hướng dẫn trong content/', () {
    final f = File('../content/huong-dan.dsanote.json');
    Repo r;
    if (f.existsSync()) {
      final bundle = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      r = Repo.fromBundle(bundle)..id = bundle['repoId'] as String;
      r.upstream = null;
    } else {
      r = Repo.create(title: 'Hướng dẫn sử dụng', author: 'Sổ tay DSA', snapshot: guideSnapshot());
    }
    // Bản cập nhật: thêm phần Bảng trắng nếu chưa có.
    final page = pagesOf(r.working).first;
    final blocks = page['blocks'] as List;
    if (!blocks.any((b) => (b as Map)['type'] == 'board')) {
      var i = blocks.indexWhere((b) => (b as Map)['type'] == 'heading' && b['text'] == 'Bài tập và contest');
      if (i < 0) i = blocks.length;
      var n = 0;
      blocks.insertAll(i, whiteboardDemo(() => 'wb${n++}${DateTime.now().microsecondsSinceEpoch}'));
      r.commit(message: 'Thêm phần Bảng trắng', author: 'Sổ tay DSA');
    }
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(r.exportBundle(author: 'Sổ tay DSA')));
  });
}
