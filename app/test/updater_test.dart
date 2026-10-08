import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/storage.dart';
import 'package:so_tay_dsa/core/updater.dart';
import 'package:so_tay_dsa/core/vcs.dart';

void main() {
  setUpAll(() async {
    await Storage.init(override: Directory.systemTemp.createTempSync('sotay-update'));
  });

  Json page(String title) => {
        'id': 'p1',
        'title': title,
        'chapter': '',
        'blocks': [
          {'id': 'b1', 'type': 'markdown', 'text': title},
        ],
      };

  test('thư viện: tải về, tự cập nhật khi chưa sửa, cần merge khi đã sửa', () {
    // Tác giả tạo notebook và đăng lên thư viện.
    final author = Repo.create(title: 'Bài tập DP', author: 'Thầy A');
    author.working['pages'] = [page('Bài 1')];
    author.commit(message: 'Bài 1', author: 'Thầy A');
    var lib = parseLibrary({
      'notebooks': [
        {'file': 'dp.dsanote.json', 'title': 'Bài tập DP', 'bundle': author.exportBundle()},
      ],
    });
    expect(lib.single.title, 'Bài tập DP');

    // Học sinh tải về.
    final student = installContent(lib.single);
    expect(localCopy(lib.single, Storage.I.listRepos())?.id, student.id);
    expect(newCommits(lib.single, student), 0);

    // Tác giả thêm bài 2 → học sinh tự nhận (fast-forward).
    author.working['pages'] = [page('Bài 1'), {...page('Bài 2'), 'id': 'p2'}];
    author.commit(message: 'Thêm bài 2', author: 'Thầy A');
    lib = parseLibrary({'notebooks': [{'bundle': author.exportBundle()}]});
    expect(newCommits(lib.single, student), 1);
    final r1 = applyContent(student, lib.single);
    expect(r1.result, ContentResult.updated);
    expect(pagesOf(student.working).length, 2);
    expect(student.isDirty, isFalse);

    // Học sinh ghi chú riêng rồi tác giả lại cập nhật → cần merge, ghi chú không mất.
    pagesOf(student.working).first['title'] = 'Bài 1 (ghi chú của em)';
    student.commit(message: 'Ghi chú', author: 'Em');
    author.working['pages'] = [page('Bài 1'), {...page('Bài 2'), 'id': 'p2'}, {...page('Bài 3'), 'id': 'p3'}];
    author.commit(message: 'Thêm bài 3', author: 'Thầy A');
    lib = parseLibrary({'notebooks': [{'bundle': author.exportBundle()}]});
    final r2 = applyContent(student, lib.single);
    expect(r2.result, ContentResult.needsMerge);
    expect(pagesOf(student.working).first['title'], 'Bài 1 (ghi chú của em)');
    final prep = student.prepareMerge(r2.ref);
    expect(prep.conflicts, isEmpty);
    student.finishMerge(prep, snapshot: prep.snapshot, author: 'Em', message: 'Gộp nội dung mới', from: r2.ref);
    expect(pagesOf(student.working).map((p) => p['title']), ['Bài 1 (ghi chú của em)', 'Bài 2', 'Bài 3']);

    // Không có gì mới.
    expect(applyContent(student, lib.single).result, ContentResult.upToDate);
  });

  test('bỏ qua mục hỏng trong thư viện', () {
    expect(parseLibrary({'notebooks': [{'bundle': {'format': 'khac'}}, 'rác']}), isEmpty);
    expect(parseLibrary('không phải json'), isEmpty);
  });

  test('sao lưu và khôi phục không làm mất dữ liệu', () {
    final a = Repo.create(title: 'Ghi chú của em', author: 'Em');
    a.working['pages'] = [page('Trang 1')];
    a.commit(message: 'Trang 1', author: 'Em');
    Storage.I.putRepo(a);
    final backup = Storage.I.exportAll();
    expect((backup['repos'] as List).any((r) => r['id'] == a.id), isTrue);

    // Sau khi sao lưu, em sửa tiếp trên máy.
    a.working['pages'] = [page('Trang 1'), {...page('Trang 2'), 'id': 'p2'}];
    a.commit(message: 'Trang 2', author: 'Em');
    Storage.I.putRepo(a);

    // Khôi phục bản cũ: không ghi đè trang 2.
    final r = Storage.I.restoreAll(backup);
    expect(r.merged, greaterThan(0));
    final cur = Storage.I.getRepo(a.id)!;
    expect(pagesOf(cur.working).length, 2);

    // Máy mới (xoá hết) → khôi phục đủ.
    Storage.I.removeRepo(a.id);
    final r2 = Storage.I.restoreAll(backup);
    expect(r2.added, greaterThan(0));
    expect(pagesOf(Storage.I.getRepo(a.id)!.working).single['title'], 'Trang 1');
  });
}
