// Hộp thoại kiểu Git: commit, nhánh, lịch sử, merge (giải quyết xung đột), chia sẻ / nhập, cài đặt.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/runner.dart';
import '../core/storage.dart';
import '../core/vcs.dart';
import 'theme.dart';
import 'widgets.dart';

Future<bool> ensureAuthor(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.author.isNotEmpty) return true;
  final name = await promptBox(context, 'Tên của bạn', 'Tên hiển thị trong commit, khi chia sẻ và trên bảng xếp hạng');
  if (name == null || name.isEmpty) return false;
  app.setSetting('author', name);
  return true;
}

// ---------- Danh sách thay đổi ----------
Widget changesList(BuildContext context, List<Change> changes) {
  Widget tag(String t, Color c) => Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontFamily: monoFont));
  final add = context.isDark ? okColorDark : okColor, del = context.cs.error;
  const mod = warnColor;
  if (changes.isEmpty) return const Text('Không có thay đổi.');
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final c in changes)
      Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: switch (c.kind) {
          'page-changed' => ExpansionTile(
              dense: true,
              leading: tag('M', mod),
              title: Text('Sửa trang "${c.after!['title']}"'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in c.fields) Text('${f == 'title' ? 'Tên' : 'Chương'}: "${c.before![f] ?? ''}" → "${c.after![f] ?? ''}"'),
                for (final x in c.blocks) ...[
                  Row(children: [
                    tag(x.kind == 'block-added' ? '+' : x.kind == 'block-removed' ? '−' : x.kind == 'reorder-blocks' ? '↕' : '~', x.kind == 'block-added' ? add : x.kind == 'block-removed' ? del : mod),
                    const SizedBox(width: 6),
                    Expanded(child: Text(x.kind == 'reorder-blocks' ? 'Đổi thứ tự khối' : blockName(x.after ?? x.before))),
                  ]),
                  if (x.kind == 'block-changed')
                    for (final k in {...x.before!.keys, ...x.after!.keys}.where((k) => k != 'id' && !same(x.before![k], x.after![k])))
                      Padding(padding: const EdgeInsets.only(left: 18, top: 2, bottom: 4), child: lineDiff(context, k, x.before![k], x.after![k])),
                ],
              ],
            ),
          _ => ListTile(
              dense: true,
              leading: tag(c.kind.endsWith('added') ? 'A' : c.kind.endsWith('removed') ? 'D' : 'M', c.kind.endsWith('added') ? add : c.kind.endsWith('removed') ? del : mod),
              title: Text(switch (c.kind) {
                'meta' => 'Thông tin notebook: ${c.field == 'title' ? 'tên' : 'mô tả'} → "${c.after!['v'] ?? ''}"',
                'reorder-pages' => 'Đổi thứ tự trang',
                'page-added' => 'Thêm trang "${c.after!['title']}" (${(c.after!['blocks'] as List).length} khối)',
                'page-removed' => 'Xoá trang "${c.before!['title']}"',
                'contest-added' => 'Thêm contest "${c.after!['title']}"',
                'contest-removed' => 'Xoá contest "${c.before!['title']}"',
                _ => 'Sửa contest "${c.after!['title']}"',
              }),
            ),
        },
      ),
  ]);
}

Widget lineDiff(BuildContext context, String field, dynamic a, dynamic b) {
  String str(dynamic v) => v == null ? '' : v is String ? v : const JsonEncoder.withIndent(' ').convert(v);
  final ops = diffLines(str(a), str(b));
  final rows = <Widget>[];
  var run = <String>[];
  void flush(bool end) {
    final head = rows.isEmpty ? 0 : 2;
    final tail = end ? 0 : 2;
    if (run.length > head + tail + 1) {
      rows.addAll(run.take(head).map((t) => Text('  $t')));
      rows.add(Text('… ${run.length - head - tail} dòng không đổi …', style: TextStyle(color: context.cs.onSurfaceVariant, fontStyle: FontStyle.italic)));
      rows.addAll(run.skip(run.length - tail).map((t) => Text('  $t')));
    } else {
      rows.addAll(run.map((t) => Text('  $t')));
    }
    run = [];
  }

  for (final o in ops) {
    if (o.op == ' ') {
      run.add(o.text);
      continue;
    }
    flush(false);
    rows.add(Container(
      color: o.op == '+' ? (context.isDark ? const Color(0xFF1B3A24) : const Color(0xFFDAFBE1)) : (context.isDark ? const Color(0xFF45201F) : const Color(0xFFFFEBE9)),
      child: Text('${o.op} ${o.text}'),
    ));
  }
  flush(true);
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(field, style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
    Container(
      color: context.cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: DefaultTextStyle.merge(style: TextStyle(fontFamily: monoFont, fontSize: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    ),
  ]);
}

// ---------- Commit ----------
Future<void> commitDialog(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.repo == null) return;
  if (app.readOnly) return toast(context, 'Đang ở chế độ xem. Quay về nhánh để commit.', error: true);
  final changes = diffSnapshots(app.repo!.headSnapshot, app.repo!.working);
  if (changes.isEmpty) return toast(context, 'Không có thay đổi nào để commit.');
  if (!await ensureAuthor(context) || !context.mounted) return;
  final msg = TextEditingController();
  void doCommit(BuildContext c) {
    app.repo!.commit(message: msg.text, author: app.authorOr);
    app.saveNow();
    app.changed();
    Navigator.pop(c);
    toast(context, 'Đã commit lên nhánh ${app.repo!.head}');
  }

  await showPanel<void>(
    context,
    title: 'Commit lên nhánh "${app.repo!.head}"',
    builder: (c, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: msg, autofocus: true, decoration: const InputDecoration(labelText: 'Mô tả thay đổi', hintText: 'VD: Thêm ghi chú Quick sort'), onSubmitted: (_) => doCommit(c)),
      const SizedBox(height: 12),
      Text('${changes.length} thay đổi', style: c.tt.bodySmall),
      const SizedBox(height: 6),
      changesList(c, changes),
    ]),
    actions: (c) => [
      TextButton(
        onPressed: () async {
          if (!await confirmBox(c, 'Bỏ thay đổi?', 'Mọi thay đổi chưa commit sẽ mất.', ok: 'Bỏ thay đổi', danger: true)) return;
          app.repo!.working = deepClone(app.repo!.headSnapshot) as Json;
          app.editing.clear();
          app.afterSwitch();
          if (c.mounted) Navigator.pop(c);
        },
        child: Text('Bỏ hết thay đổi', style: TextStyle(color: c.cs.error)),
      ),
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      FilledButton(onPressed: () => doCommit(c), child: const Text('Commit')),
    ],
  );
}

// ---------- Nhánh ----------
Future<void> switchBranch(BuildContext context, String name) async {
  final app = context.read<AppState>();
  final r = app.repo!;
  if (name == r.head) return;
  if (r.isDirty) {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Còn thay đổi chưa commit'),
        content: Text('Nhánh "${r.head}" có thay đổi chưa commit. Chuyển sang "$name" sẽ làm mất chúng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: Text('Bỏ thay đổi và chuyển', style: TextStyle(color: c.cs.error))),
          FilledButton(onPressed: () => Navigator.pop(c, 'commit'), child: const Text('Commit trước')),
        ],
      ),
    );
    if (choice == 'commit' && context.mounted) return commitDialog(context);
    if (choice != 'discard') return;
  }
  r.checkout(name, force: true);
  app.afterSwitch();
  if (context.mounted) toast(context, 'Đã chuyển sang nhánh $name');
}

Future<void> newBranchDialog(BuildContext context, {String? fromRef}) async {
  final app = context.read<AppState>();
  final r = app.repo!;
  final name = await promptBox(context, 'Nhánh mới', fromRef != null ? 'Tên nhánh (bắt đầu từ commit ${fromRef.substring(0, 7)})' : 'Tên nhánh (bắt đầu từ "${r.head}")', ok: 'Tạo nhánh');
  if (name == null || name.isEmpty || !context.mounted) return;
  try {
    r.createBranch(name, fromRef ?? r.head);
    if (fromRef != null) {
      r.checkout(name, force: true);
    } else {
      r.head = name; // mang theo thay đổi chưa commit, giống `git checkout -b`
    }
    app.afterSwitch();
    toast(context, 'Đã tạo và chuyển sang nhánh $name');
  } catch (e) {
    toast(context, '$e', error: true);
  }
}

Future<void> branchesDialog(BuildContext context) {
  final app = context.read<AppState>();
  return showPanel<void>(
    context,
    title: 'Nhánh',
    width: 900,
    builder: (c, setSt) {
      final r = app.repo!;
      Widget rows(Map<String, String> entries, bool remote) => Column(children: [
            for (final e in (entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
              () {
                final cm = r.commits[e.value]!;
                final ab = r.aheadBehind(e.value, r.headId);
                return ListTile(
                  dense: true,
                  leading: Icon(remote ? Icons.cloud_outlined : Icons.call_split, color: remote ? warnColor : c.cs.primary),
                  title: Text(e.key + (e.key == r.head ? '  (đang dùng)' : ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e.key == r.head ? '' : '${ab.ahead} commit mới · thiếu ${ab.behind} · '}${cm['message']} — ${cm['author']}, ${timeAgo(cm['time'] as int)}'),
                  trailing: Wrap(spacing: 4, children: [
                    if (remote)
                      TextButton(onPressed: () { Navigator.pop(c); app.preview(e.key); }, child: const Text('Xem'))
                    else if (e.key != r.head)
                      TextButton(onPressed: () { Navigator.pop(c); switchBranch(context, e.key); }, child: const Text('Chuyển')),
                    if (e.key != r.head) TextButton(onPressed: () { Navigator.pop(c); mergeDialog(context, preset: e.key); }, child: const Text('Merge')),
                    if (!remote)
                      IconButton(
                        tooltip: 'Đổi tên',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () async {
                          final to = await promptBox(c, 'Đổi tên nhánh', 'Tên mới', value: e.key);
                          if (to == null || to.isEmpty || to == e.key) return;
                          try {
                            r.renameBranch(e.key, to);
                            app.changed();
                            setSt(() {});
                          } catch (err) {
                            if (c.mounted) toast(c, '$err', error: true);
                          }
                        },
                      ),
                    if (e.key != r.head)
                      IconButton(
                        tooltip: 'Xoá',
                        icon: Icon(Icons.delete_outline, size: 18, color: c.cs.error),
                        onPressed: () async {
                          if (remote) {
                            r.remotes.remove(e.key);
                          } else {
                            final merged = r.isAncestor(e.value, r.headId);
                            if (!await confirmBox(c, 'Xoá nhánh?', 'Xoá nhánh "${e.key}"?${merged ? '' : ' Nhánh có commit chưa được merge.'}', ok: 'Xoá', danger: true)) return;
                            r.deleteBranch(e.key);
                          }
                          app.changed();
                          setSt(() {});
                        },
                      ),
                  ]),
                );
              }(),
          ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Nhánh của bạn', style: c.tt.titleSmall),
        rows(r.branches, false),
        const SizedBox(height: 12),
        Text('Nhánh nhận từ người khác', style: c.tt.titleSmall),
        if (r.remotes.isEmpty) const Text('Chưa có. Dùng "Nhập" để gộp notebook người khác gửi vào đây.') else rows(r.remotes, true),
      ]);
    },
    actions: (c) => [
      OutlinedButton(onPressed: () { Navigator.pop(c); newBranchDialog(context); }, child: const Text('Nhánh mới')),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Đóng')),
    ],
  );
}

// ---------- Lịch sử ----------
const _lanePalette = [Color(0xFF0969DA), Color(0xFF1A7F37), Color(0xFFBC4C00), Color(0xFF8250DF), Color(0xFFBF3989), Color(0xFF0A7EA4), Color(0xFFCF222E)];

class _LanePainter extends CustomPainter {
  final GraphRow row;
  _LanePainter(this.row);
  @override
  void paint(Canvas c, Size s) {
    double lx(int k) => 9 + k * 14.0;
    final h = s.height;
    final id = row.commit['id'];
    for (var k = 0; k < row.before.length; k++) {
      final x = row.before[k];
      if (x == null) continue;
      final p = Paint()..color = _lanePalette[k % _lanePalette.length]..strokeWidth = 2;
      if (x == id) {
        c.drawLine(Offset(lx(k), 0), Offset(lx(row.col), h / 2), p);
      } else {
        final to = row.after.indexOf(x);
        if (to != -1) c.drawLine(Offset(lx(k), 0), Offset(lx(to), h), p);
      }
    }
    for (final par in (row.commit['parents'] as List)) {
      final to = row.after.indexOf(par);
      if (to != -1) c.drawLine(Offset(lx(row.col), h / 2), Offset(lx(to), h), Paint()..color = _lanePalette[to % _lanePalette.length]..strokeWidth = 2);
    }
    c.drawCircle(Offset(lx(row.col), h / 2), 4.5, Paint()..color = _lanePalette[row.col % _lanePalette.length]);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

Future<void> historyDialog(BuildContext context) {
  final app = context.read<AppState>();
  final r = app.repo!;
  final commits = r.log();
  final rows = graphLayout(commits);
  final labels = <String, List<(String, bool)>>{};
  r.branches.forEach((n, id) => (labels[id] ??= []).add((n, false)));
  r.remotes.forEach((n, id) => (labels[id] ??= []).add((n, true)));
  final lanes = rows.fold<int>(1, (m, x) => [m, x.before.length, x.after.length, x.col + 1].reduce((a, b) => a > b ? a : b));
  Json? selected;
  bool vsCurrent = false;
  return showPanel<void>(
    context,
    title: 'Lịch sử (${commits.length} commit)',
    width: 1100,
    builder: (c, setSt) {
      final list = Column(children: [
        for (final row in rows)
          InkWell(
            onTap: () => setSt(() {
              selected = row.commit;
              vsCurrent = false;
            }),
            child: Container(
              color: selected == row.commit ? c.cs.primaryContainer.withValues(alpha: .4) : null,
              height: 44,
              child: Row(children: [
                CustomPaint(size: Size(lanes * 14.0 + 6, 44), painter: _LanePainter(row)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      for (final (n, remote) in labels[row.commit['id']] ?? <(String, bool)>[])
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(border: Border.all(color: remote ? warnColor : c.cs.primary), borderRadius: BorderRadius.circular(8)),
                          child: Text(n, style: TextStyle(fontSize: 11, color: remote ? warnColor : c.cs.primary)),
                        ),
                      Expanded(child: Text('${row.commit['message']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                    Text('${(row.commit['id'] as String).substring(0, 7)} · ${row.commit['author']} · ${timeAgo(row.commit['time'] as int)}', style: c.tt.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
      ]);
      Widget detail = const Text('Chọn một commit để xem chi tiết.');
      final sel = selected;
      if (sel != null) {
        final parents = (sel['parents'] as List).cast<String>();
        final parentSnap = parents.isEmpty ? null : (r.commits[parents.first]!['snapshot'] as Map).cast<String, dynamic>();
        final snap = (sel['snapshot'] as Map).cast<String, dynamic>();
        detail = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${sel['message']}', style: c.tt.titleMedium),
          Text('${sel['author']} · ${fullTime(sel['time'] as int)}', style: c.tt.bodySmall),
          SelectableText('commit ${sel['id']}${parents.length > 1 ? ' · merge ${parents.map((p) => p.substring(0, 7)).join(' + ')}' : ''}', style: TextStyle(fontFamily: monoFont, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton(onPressed: () { Navigator.pop(c); app.preview(sel['id'] as String); }, child: const Text('Xem bản này')),
            OutlinedButton(onPressed: () { Navigator.pop(c); newBranchDialog(context, fromRef: sel['id'] as String); }, child: const Text('Tạo nhánh từ đây')),
            OutlinedButton(
              onPressed: () async {
                if (!await confirmBox(c, 'Khôi phục?', 'Đưa nội dung về bản "${sel['message']}"? Thay đổi hiện như chưa commit để bạn xem lại.', ok: 'Khôi phục')) return;
                r.working = deepClone(snap) as Json;
                app.afterSwitch();
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Khôi phục bản này'),
            ),
            OutlinedButton(onPressed: () => setSt(() => vsCurrent = !vsCurrent), child: Text(vsCurrent ? 'So với commit trước' : 'So với hiện tại')),
          ]),
          const SizedBox(height: 8),
          Text(vsCurrent ? 'So với bản đang làm việc:' : parentSnap == null ? 'Commit đầu tiên:' : 'Thay đổi so với commit trước:', style: c.tt.bodySmall),
          const SizedBox(height: 4),
          changesList(c, vsCurrent ? diffSnapshots(snap, r.working) : diffSnapshots(parentSnap, snap)),
        ]);
      }
      return c.compact
          ? Column(children: [list, const Divider(height: 24), detail])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: list), const SizedBox(width: 16), Expanded(child: detail)]);
    },
  );
}

// ---------- Merge ----------
Future<void> mergeDialog(BuildContext context, {String? preset}) async {
  final app = context.read<AppState>();
  final r = app.repo!;
  app.endPreview();
  if (r.isDirty) return toast(context, 'Hãy commit hoặc bỏ thay đổi trước khi merge.', error: true);
  final sources = [...r.branches.keys.where((b) => b != r.head), ...r.remotes.keys];
  if (sources.isEmpty) return toast(context, 'Chưa có nhánh khác để merge.', error: true);
  var from = preset != null && sources.contains(preset) ? preset : sources.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setSt) {
        final ab = r.aheadBehind(r.resolve(from)!, r.headId);
        return AlertDialog(
          title: Text('Merge vào "${r.head}"'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'Lấy thay đổi từ'),
                items: [for (final s in sources) DropdownMenuItem(value: s, child: Text('${r.remotes.containsKey(s) ? '[nhận] ' : ''}$s'))],
                onChanged: (v) => setSt(() => from = v!),
              ),
              const SizedBox(height: 8),
              Text('"$from" có ${ab.ahead} commit mà "${r.head}" chưa có.', style: c.tt.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tiếp tục')),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final prep = r.prepareMerge(from);
  if (prep.kind == MergeKind.upToDate) return toast(context, '"${r.head}" đã có mọi thay đổi của "$from".');
  if (prep.kind == MergeKind.fastForward) {
    r.finishMerge(prep);
    app.afterSwitch();
    return toast(context, 'Đã cập nhật "${r.head}" tới "$from".');
  }
  if (!await ensureAuthor(context) || !context.mounted) return;
  final msg = TextEditingController(text: 'Merge "$from" vào "${r.head}"');
  final choices = List<dynamic>.filled(prep.conflicts.length, null);
  final manual = [for (final cf in prep.conflicts) TextEditingController(text: cf.ours is String && cf.theirs is String ? '${cf.ours}\n${cf.theirs}' : '')];
  String show(dynamic v) {
    if (v == null) return '(đã xoá / trống)';
    if (v is List) return '[${v.length} mục]';
    if (v is Map) {
      if (v['blocks'] != null) return 'Trang "${v['title']}" — ${(v['blocks'] as List).length} khối';
      if (v['problems'] != null) return 'Contest "${v['title']}" — ${(v['problems'] as List).length} bài';
      return '${blockName(v.cast<String, dynamic>())}\n\n${v['text'] ?? v['code'] ?? v['url'] ?? v['statement'] ?? ''}';
    }
    return '$v';
  }

  await showPanel<void>(
    context,
    title: prep.conflicts.isEmpty ? 'Merge không có xung đột' : '${prep.conflicts.length} xung đột cần giải quyết',
    width: 1000,
    builder: (c, setSt) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (prep.conflicts.isEmpty) ...[
        const Text('Các thay đổi sẽ được đưa vào:'),
        const SizedBox(height: 6),
        changesList(c, diffSnapshots((r.commits[prep.oursId]!['snapshot'] as Map).cast<String, dynamic>(), prep.snapshot)),
      ] else ...[
        Text('"${r.head}" và "$from" cùng sửa một chỗ. Chọn bản muốn giữ.', style: c.tt.bodySmall),
        for (var i = 0; i < prep.conflicts.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: warnColor), borderRadius: BorderRadius.circular(4)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Xung đột ${i + 1}: ${prep.conflicts[i].label}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final (val, label, v) in [('ours', 'Giữ bản của bạn (${r.head})', prep.conflicts[i].ours), ('theirs', 'Lấy bản "$from"', prep.conflicts[i].theirs)])
                  Expanded(
                    child: Card(
                      color: choices[i] == val ? c.cs.primaryContainer.withValues(alpha: .4) : null,
                      child: InkWell(
                        onTap: () => setSt(() => choices[i] = val),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [Padding(padding: const EdgeInsets.only(right: 6), child: Icon(choices[i] == val ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: c.cs.primary)), Text(label, style: const TextStyle(fontWeight: FontWeight.w600))]),
                            MonoBox(show(v), maxHeight: 180),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
              if (prep.conflicts[i].ours is String && prep.conflicts[i].theirs is String)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CheckboxListTile(
                    dense: true,
                    value: choices[i] is Map,
                    title: const Text('Tự gộp bằng tay'),
                    onChanged: (v) => setSt(() => choices[i] = v == true ? {'value': manual[i].text} : null),
                  ),
                  if (choices[i] is Map)
                    TextField(controller: manual[i], minLines: 3, maxLines: 10, style: TextStyle(fontFamily: monoFont, fontSize: 13), onChanged: (t) => choices[i] = {'value': t}),
                ]),
            ]),
          ),
      ],
      const SizedBox(height: 12),
      TextField(controller: msg, decoration: const InputDecoration(labelText: 'Mô tả merge commit')),
    ]),
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ merge')),
      FilledButton(
        onPressed: () {
          final missing = choices.indexWhere((x) => x == null);
          if (missing != -1) return toast(c, 'Chưa chọn cho xung đột ${missing + 1}.', error: true);
          final snapshot = prep.conflicts.isEmpty ? prep.snapshot! : applyResolutions(prep.snapshot!, prep.conflicts, choices);
          r.finishMerge(prep, snapshot: snapshot, author: app.authorOr, message: msg.text, from: from);
          app.afterSwitch();
          Navigator.pop(c);
          toast(context, 'Đã merge');
        },
        child: Text(prep.conflicts.isEmpty ? 'Merge' : 'Hoàn tất merge'),
      ),
    ],
  );
}

// ---------- Chia sẻ / nhập ----------
Json makeBundle(AppState app, List<String> branches) {
  final bundle = app.repo!.exportBundle(branchNames: branches, author: app.authorOr);
  final refs = Storage.assetRefs(bundle['commits'] as Object);
  if (refs.isNotEmpty) bundle['assets'] = Storage.I.packAssets(refs);
  return bundle;
}

Future<void> shareDialog(BuildContext context) async {
  if (!await ensureAuthor(context) || !context.mounted) return;
  final app = context.read<AppState>();
  final r = app.repo!;
  final picked = {...r.branches.keys};
  String? link;
  await showPanel<void>(
    context,
    title: 'Chia sẻ notebook',
    builder: (c, setSt) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Người nhận bấm "Nhập" để mở thành bản riêng, hoặc gộp vào notebook của họ như một nhánh rồi merge.'),
      if (r.isDirty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Thay đổi chưa commit sẽ không được chia sẻ.', style: TextStyle(color: warnColor))),
      const SizedBox(height: 10),
      const Text('Nhánh muốn chia sẻ:'),
      for (final b in r.branches.keys)
        CheckboxListTile(dense: true, value: picked.contains(b), title: Text(b), onChanged: (v) => setSt(() => v == true ? picked.add(b) : picked.remove(b))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        FilledButton.icon(
          icon: const Icon(Icons.save_alt),
          label: Text(Platform.isAndroid ? 'Gửi file' : 'Lưu file .dsanote.json'),
          onPressed: picked.isEmpty ? null : () => saveTextFile(context, '${slugify('${r.working['title']}')}.dsanote.json', jsonEncode(makeBundle(app, picked.toList()))),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.link),
          label: const Text('Tạo link'),
          onPressed: picked.isEmpty ? null : () => setSt(() => link = 'sotaydsa://share/${encodeShare(makeBundle(app, picked.toList()))}'),
        ),
      ]),
      if (link != null) ...[
        const SizedBox(height: 10),
        Text('Link (${(link!.length / 1024).toStringAsFixed(1)} KB) — người nhận dán vào mục Nhập:', style: c.tt.bodySmall),
        MonoBox(link!, maxHeight: 120),
        if (link!.length > 30000) const Text('Link khá dài (có ảnh/video?) — nên gửi file thay thế.', style: TextStyle(color: warnColor)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Sao chép link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link!));
              toast(c, 'Đã sao chép');
            },
          ),
        ),
      ],
    ]),
  );
}

Future<void> importDialog(BuildContext context, {void Function(Repo)? onOpen}) async {
  final paste = TextEditingController();
  String? text;
  await showPanel<void>(
    context,
    title: 'Nhập notebook',
    builder: (c, setSt) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('Chọn file .dsanote.json'),
        onPressed: () async {
          final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
          if (r == null || r.files.isEmpty) return;
          final f = r.files.first;
          text = f.bytes != null ? utf8.decode(f.bytes!) : await File(f.path!).readAsString();
          if (c.mounted) Navigator.pop(c);
        },
      ),
      const SizedBox(height: 12),
      TextField(controller: paste, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Hoặc dán link chia sẻ / mã vào đây')),
    ]),
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      FilledButton(
        onPressed: () {
          text = paste.text;
          Navigator.pop(c);
        },
        child: const Text('Tiếp tục'),
      ),
    ],
  );
  if (text == null || text!.trim().isEmpty || !context.mounted) return;
  await handleIncoming(context, text!, onOpen: onOpen);
}

Future<void> handleIncoming(BuildContext context, String text, {void Function(Repo)? onOpen}) async {
  final app = context.read<AppState>();
  Json bundle;
  try {
    final data = parseIncoming(text);
    if (data is Map && data['format'] == 'dsa-backup') {
      if (!await confirmBox(context, 'Khôi phục bản sao lưu?', 'Notebook chưa có sẽ được thêm vào. Notebook đã có giữ nguyên, các thay đổi trong bản sao lưu được thêm thành nhánh "sao-luu/…" để bạn merge nếu cần.', ok: 'Khôi phục')) return;
      final r = Storage.I.restoreAll(data);
      app.saveNow();
      if (app.repo != null) app.openRepo(Storage.I.getRepo(app.repo!.id) ?? app.repo!);
      app.changed();
      if (context.mounted) toast(context, 'Đã khôi phục: ${r.added} notebook mới, ${r.merged} notebook đã có được bổ sung.');
      return;
    }
    bundle = Repo.validateBundle(data);
  } catch (e) {
    return toast(context, '$e', error: true);
  }
  final repos = Storage.I.listRepos();
  final related = repos.where((x) => x.id == bundle['repoId'] || x.upstream == bundle['repoId'] || (bundle['commits'] as Map).keys.any(x.commits.containsKey)).toList();
  var target = related.isNotEmpty ? related.first.id : repos.isNotEmpty ? repos.first.id : null;
  final remoteName = TextEditingController(text: '${bundle['sharedBy'] ?? 'ban'}'.replaceAll(RegExp(r'\s+'), '-'));
  final choice = await showPanel<String>(
    context,
    title: 'Nhập "${bundle['title']}"',
    builder: (c, setSt) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Gửi bởi ${bundle['sharedBy'] ?? 'Ẩn danh'} · ${timeAgo((bundle['sharedAt'] ?? now()) as int)} · ${(bundle['branches'] as Map).length} nhánh · ${(bundle['commits'] as Map).length} commit'),
      const SizedBox(height: 10),
      const Card(child: ListTile(title: Text('Mở thành notebook riêng'), subtitle: Text('Tạo bản sao đầy đủ lịch sử để ghi chú tiếp hoặc làm bài.'))),
      if (repos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Gộp vào notebook có sẵn', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('Các nhánh của họ hiện dạng "tên/nhánh" để bạn xem rồi merge.${related.isNotEmpty ? ' Đã tìm thấy notebook có chung lịch sử.' : ''}', style: c.tt.bodySmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: target,
                decoration: const InputDecoration(labelText: 'Notebook'),
                items: [for (final x in repos) DropdownMenuItem(value: x.id, child: Text('${x.working['title']}'))],
                onChanged: (v) => target = v,
              ),
              const SizedBox(height: 8),
              TextField(controller: remoteName, decoration: const InputDecoration(labelText: 'Tên người gửi')),
            ]),
          ),
        ),
      ],
    ]),
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      if (repos.isNotEmpty) OutlinedButton(onPressed: () => Navigator.pop(c, 'fetch'), child: const Text('Gộp vào notebook')),
      FilledButton(onPressed: () => Navigator.pop(c, 'fork'), child: const Text('Mở thành notebook riêng')),
    ],
  );
  if (choice == null || !context.mounted) return;
  Storage.I.unpackAssets(bundle['assets'] as Map?);
  if (choice == 'fork') {
    final repo = Repo.fromBundle(bundle)..normalize();
    Storage.I.putRepo(repo);
    onOpen?.call(repo);
    toast(context, 'Đã mở notebook');
  } else {
    final repo = app.repo?.id == target ? app.repo! : Storage.I.getRepo(target!)!;
    final res = repo.fetchBundle(bundle, remoteName.text.trim().isEmpty ? 'ban' : remoteName.text.trim());
    repo.normalize();
    Storage.I.putRepo(repo);
    onOpen?.call(repo);
    toast(context, 'Đã nhận ${res.added} commit mới: ${res.refs.join(', ')}');
    if (!repo.isDirty && res.refs.isNotEmpty && context.mounted) {
      await mergeDialog(context, preset: res.refs.firstWhere((x) => x.endsWith('/${repo.head}'), orElse: () => res.refs.first));
    }
  }
}

// ---------- Cài đặt ----------
Future<void> settingsDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final name = TextEditingController(text: app.author);
  final flags = TextEditingController(text: app.setting('cppFlags', '-O2 -std=c++17'));
  final compiler = TextEditingController(text: app.setting('compiler', 'g132'));
  final gpp = TextEditingController(text: app.setting('gppPath', ''));
  var theme = app.setting('theme', 'system');
  var mode = app.setting('judgeMode', 'auto');
  String info = '';
  Future<void> detect(StateSetter setSt) async {
    app.setSetting('gppPath', gpp.text.trim());
    setSt(() => info = 'Đang tìm g++…');
    final r = await app.detectCompiler(force: true);
    final gdb = r == null ? null : await findGdb(r.path);
    setSt(() => info = r == null
        ? 'Không tìm thấy g++. Code sẽ chạy online. Cài MinGW-w64 / MSYS2 (Windows), Xcode Command Line Tools (macOS) hoặc g++ (Linux), hoặc chọn file g++.'
        : 'g++: ${r.version}\n${r.path}\ngdb: ${gdb?.version ?? 'không có (không gỡ lỗi từng dòng được)'}');
  }

  var started = false;
  await showPanel<void>(
    context,
    title: 'Cài đặt',
    builder: (c, setSt) {
      if (!started && app.canRunLocal) {
        started = true;
        detect(setSt);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Tên của bạn')),
        const SizedBox(height: 12),
        const Text('Giao diện'),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'system', label: Text('Theo hệ thống')), ButtonSegment(value: 'light', label: Text('Sáng')), ButtonSegment(value: 'dark', label: Text('Tối'))],
          selected: {theme},
          onSelectionChanged: (v) => setSt(() => theme = v.first),
        ),
        const Divider(height: 28),
        Text('Chạy & chấm code C++', style: c.tt.titleSmall),
        const SizedBox(height: 8),
        if (app.canRunLocal)
          DropdownButtonFormField<String>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Nơi chạy code'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('g++ trên máy (nếu có), không thì online')),
              DropdownMenuItem(value: 'online', child: Text('Luôn chạy online (Compiler Explorer)')),
            ],
            onChanged: (v) => mode = v ?? 'auto',
          ),
        const SizedBox(height: 8),
        TextField(controller: flags, decoration: const InputDecoration(labelText: 'Cờ biên dịch'), style: TextStyle(fontFamily: monoFont)),
        const SizedBox(height: 8),
        TextField(controller: compiler, decoration: const InputDecoration(labelText: 'Mã trình biên dịch online (VD: g132, clang1701)'), style: TextStyle(fontFamily: monoFont)),
        if (app.canRunLocal) ...[
          const Divider(height: 28),
          Text('Trình biên dịch trên máy', style: c.tt.titleSmall),
          const SizedBox(height: 6),
          SelectableText(info, style: c.tt.bodySmall),
          const SizedBox(height: 8),
          TextField(controller: gpp, decoration: const InputDecoration(labelText: 'Đường dẫn g++ (để trống để tự tìm)'), style: TextStyle(fontFamily: monoFont)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: () => detect(setSt), child: const Text('Tìm lại')),
            OutlinedButton(
              onPressed: () async {
                final r = await FilePicker.platform.pickFiles(dialogTitle: 'Chọn file g++');
                if (r?.files.single.path != null) {
                  gpp.text = r!.files.single.path!;
                  detect(setSt);
                }
              },
              child: const Text('Chọn file g++…'),
            ),
          ]),
        ],
        const Divider(height: 28),
        Text('Sao lưu dữ liệu', style: c.tt.titleSmall),
        const SizedBox(height: 6),
        Text('Lưu toàn bộ notebook (cả lịch sử, ảnh, video), bài nộp và file code vào một file. Khôi phục bằng Notebook → Nhập. '
            'Cập nhật app không xoá dữ liệu; app còn tự sao lưu trước mỗi lần cập nhật.', style: c.tt.bodySmall),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: const Text('Sao lưu tất cả…'),
            onPressed: () {
              app.saveNow();
              final d = DateTime.now();
              saveTextFile(c, 'sao-luu-so-tay-dsa-${d.year}-${d.month}-${d.day}.json', jsonEncode(Storage.I.exportAll()));
            },
          ),
        ),
        const SizedBox(height: 12),
        Text('Dữ liệu lưu tại: ${Storage.I.root.path}', style: c.tt.bodySmall),
      ]);
    },
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      FilledButton(
        onPressed: () {
          app.setSetting('author', name.text.trim());
          app.setSetting('theme', theme);
          app.setSetting('judgeMode', mode);
          app.setSetting('cppFlags', flags.text.trim());
          app.setSetting('compiler', compiler.text.trim().isEmpty ? 'g132' : compiler.text.trim());
          app.setSetting('gppPath', gpp.text.trim());
          Navigator.pop(c);
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}
