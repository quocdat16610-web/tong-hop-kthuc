// Tính năng thêm: thư viện code mẫu, tìm nhanh mọi notebook (Ctrl+K), tiến độ luyện tập.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/snippets.dart';
import '../core/storage.dart';
import '../core/vcs.dart';
import 'contest.dart' show allProblems;
import 'theme.dart';
import 'widgets.dart';

// ---------- Thư viện code mẫu ----------
Future<String?> pickSnippet(BuildContext context) {
  var q = '';
  Snippet? sel = snippets.first;
  return showPanel<String>(
    context,
    title: 'Thư viện code mẫu C++',
    width: 1000,
    builder: (c, setSt) {
      final list = snippets.where((s) => q.isEmpty || '${s.group} ${s.name} ${s.note}'.toLowerCase().contains(q.toLowerCase())).toList();
      if (!list.contains(sel)) sel = list.firstOrNull;
      final groups = <String>{for (final s in list) s.group};
      final listView = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm: dijkstra, dsu, lis…'), onChanged: (v) => setSt(() => q = v)),
        const SizedBox(height: 8),
        for (final g in groups) ...[
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(g, style: c.tt.labelLarge?.copyWith(color: c.cs.primary))),
          for (final s in list.where((s) => s.group == g))
            ListTile(
              dense: true,
              selected: sel == s,
              title: Text(s.name),
              subtitle: Text(s.note, style: const TextStyle(fontSize: 12)),
              onTap: () => setSt(() => sel = s),
              onLongPress: () => Navigator.pop(c, s.code),
            ),
        ],
      ]);
      final preview = sel == null ? const SizedBox() : MonoBox(sel!.code, maxHeight: 520);
      return c.compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [listView, const Divider(height: 20), preview])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 4, child: listView), const SizedBox(width: 14), Expanded(flex: 6, child: preview)]);
    },
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      FilledButton.icon(onPressed: () => Navigator.pop(c, sel?.code), icon: const Icon(Icons.input, size: 18), label: const Text('Chèn vào code')),
    ],
  );
}

// ---------- Tìm nhanh (Ctrl+K) ----------
class _Hit {
  final Repo repo;
  final Json page;
  final String? blockId;
  final String kind, text;
  _Hit(this.repo, this.page, this.blockId, this.kind, this.text);
}

const _kindName = {
  'page': 'Trang',
  'heading': 'Tiêu đề',
  'markdown': 'Ghi chú',
  'code': 'Code',
  'problem': 'Bài tập',
  'video': 'Video',
  'sim': 'Mô phỏng',
  'board': 'Bảng trắng',
  'image': 'Ảnh',
};

const _accents = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _plain = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt để tìm "noi bot" ra "nổi bọt".
String fold(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _accents.indexOf(ch);
    b.write(i >= 0 ? _plain[i] : ch);
  }
  return b.toString();
}

List<_Hit> _search(List<Repo> repos, String q) {
  final query = fold(q.trim());
  if (query.isEmpty) return [];
  final out = <_Hit>[];
  for (final r in repos) {
    for (final p in pagesOf(r.working)) {
      if (fold('${p['title']} ${p['chapter'] ?? ''}').contains(query)) out.add(_Hit(r, p, null, 'page', '${p['title']}'));
      for (final b in blocksOf(p)) {
        final fields = [b['text'], b['title'], b['caption'], b['statement'], b['code'], b['url'], b['timestamps']].whereType<String>().join('\n');
        final i = fold(fields).indexOf(query);
        if (i < 0) continue;
        final start = (i - 40).clamp(0, fields.length);
        final end = (i + query.length + 60).clamp(0, fields.length);
        out.add(_Hit(r, p, b['id'] as String?, '${b['type']}', '${start > 0 ? '…' : ''}${fields.substring(start, end).replaceAll('\n', ' ')}${end < fields.length ? '…' : ''}'));
      }
      if (out.length > 200) return out;
    }
  }
  return out;
}

Future<void> showQuickSearch(BuildContext context) async {
  final app = context.read<AppState>();
  app.saveNow();
  final repos = Storage.I.listRepos();
  var q = '';
  final hit = await showPanel<_Hit>(
    context,
    title: 'Tìm trong mọi notebook',
    width: 860,
    builder: (c, setSt) {
      final hits = _search(repos, q);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Gõ từ khoá: quick sort, dijkstra, tên bài…'),
          onChanged: (v) => setSt(() => q = v),
          onSubmitted: (_) {
            if (hits.isNotEmpty) Navigator.pop(c, hits.first);
          },
        ),
        const SizedBox(height: 8),
        if (q.trim().isNotEmpty && hits.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Không tìm thấy.')),
        for (final h in hits.take(80))
          ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.cs.secondaryContainer, borderRadius: BorderRadius.circular(4)),
              child: Text(_kindName[h.kind] ?? h.kind, style: const TextStyle(fontSize: 11)),
            ),
            title: Text(h.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${h.repo.working['title']} › ${h.page['title']}', style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(c, h),
          ),
      ]);
    },
  );
  if (hit == null || !context.mounted) return;
  if (app.repo?.id != hit.repo.id) app.openRepo(Storage.I.getRepo(hit.repo.id) ?? hit.repo);
  app.mode = 'notes';
  app.selectPage(hit.page['id'] as String, anchor: hit.blockId ?? '');
}

// ---------- Tiến độ luyện tập ----------
Future<void> showProgress(BuildContext context) async {
  final app = context.read<AppState>();
  app.saveNow();
  final repos = Storage.I.listRepos();
  final subs = Storage.I.subs;
  final byProblem = <String, List<Json>>{};
  for (final s in subs) {
    (byProblem['${s['problemId']}'] ??= []).add(s);
  }
  final rows = <({Repo repo, Json page, Json block, String status, int tries})>[];
  for (final r in repos) {
    for (final x in allProblems(r.working)) {
      final list = byProblem['${x.block['id']}'] ?? const [];
      final status = list.any((s) => s['verdict'] == 'AC') ? 'AC' : list.isEmpty ? 'new' : 'tried';
      rows.add((repo: r, page: x.page, block: x.block, status: status, tries: list.length));
    }
  }
  final ac = rows.where((r) => r.status == 'AC').length;
  final tried = rows.where((r) => r.status == 'tried').length;
  var filter = 'all';
  final pick = await showPanel<({Repo repo, Json page, Json block, String status, int tries})>(
    context,
    title: 'Tiến độ luyện tập',
    width: 820,
    builder: (c, setSt) {
      final ok = c.isDark ? okColorDark : okColor;
      final shown = rows.where((r) => filter == 'all' || r.status == filter).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Đã giải $ac / ${rows.length} bài · đang làm $tried · chưa làm ${rows.length - ac - tried}', style: c.tt.titleMedium),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: rows.isEmpty ? 0 : ac / rows.length, minHeight: 10, color: ok, backgroundColor: c.cs.surfaceContainerHighest),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('Tất cả')),
            ButtonSegment(value: 'AC', label: Text('Đã giải')),
            ButtonSegment(value: 'tried', label: Text('Đang làm')),
            ButtonSegment(value: 'new', label: Text('Chưa làm')),
          ],
          selected: {filter},
          onSelectionChanged: (v) => setSt(() => filter = v.first),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Chưa có bài tập nào. Thêm khối Bài tập vào notebook hoặc tải từ Thư viện bài tập (GitHub).')),
        for (final r in shown)
          ListTile(
            dense: true,
            leading: Icon(
              r.status == 'AC' ? Icons.check_circle : r.status == 'tried' ? Icons.pending_outlined : Icons.radio_button_unchecked,
              color: r.status == 'AC' ? ok : r.status == 'tried' ? warnColor : c.cs.onSurfaceVariant,
            ),
            title: Text('${r.block['title'] ?? 'Bài tập'}'),
            subtitle: Text('${r.repo.working['title']} › ${r.page['title']}${r.tries > 0 ? ' · ${r.tries} lần nộp' : ''}', style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.pop(c, r),
          ),
      ]);
    },
  );
  if (pick == null || !context.mounted) return;
  if (app.repo?.id != pick.repo.id) app.openRepo(Storage.I.getRepo(pick.repo.id) ?? pick.repo);
  app.mode = 'notes';
  app.selectPage(pick.page['id'] as String, anchor: '${pick.block['id']}');
}
