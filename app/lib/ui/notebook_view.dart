// Màn hình Sổ tay: mục lục bên trái + trang (phần tiêu đề, các khối, chèn khối).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/templates.dart';
import '../core/vcs.dart';
import 'blocks.dart';
import 'contest.dart';
import 'media.dart';
import 'theme.dart';
import 'widgets.dart';

final Map<String, GlobalKey> anchorKeys = {};
GlobalKey anchorFor(String id) => anchorKeys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

void scrollToAnchor(String id) {
  final ctx = anchorKeys[id]?.currentContext;
  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.05);
}

class TocEntry {
  final int level;
  final String text, anchor;
  final bool problem;
  TocEntry(this.level, this.text, this.anchor, {this.problem = false});
}

List<TocEntry> tocEntries(Json page) {
  final out = <TocEntry>[];
  for (final b in blocksOf(page)) {
    final id = b['id'] as String;
    if (b['type'] == 'heading' && '${b['text'] ?? ''}'.trim().isNotEmpty) {
      out.add(TocEntry(((b['level'] ?? 1) as num).toInt(), '${b['text']}', id));
    } else if (b['type'] == 'markdown') {
      for (final h in markdownHeadings(b['text'] as String?)) {
        out.add(TocEntry(h.level, h.text, id));
      }
    } else if (b['type'] == 'problem') {
      out.add(TocEntry(2, '${b['title'] ?? 'Bài tập'}', id, problem: true));
    }
  }
  return out;
}

void addPage(AppState app) {
  final pages = app.repo!.working['pages'] as List;
  final cur = app.page;
  final p = deepClone({
    'id': newId(12),
    'title': 'Trang mới',
    'chapter': cur?['chapter'] ?? '',
    'blocks': [
      {'id': newId(12), 'type': 'heading', 'level': 1, 'text': ''},
    ],
  }) as Json;
  pages.insert(cur == null ? pages.length : pages.indexOf(cur) + 1, p);
  app.pageId = p['id'];
  app.contestId = null;
  app.changed();
}

class TocPanel extends StatefulWidget {
  final VoidCallback? onNavigate;
  const TocPanel({super.key, this.onNavigate});
  @override
  State<TocPanel> createState() => _TocPanelState();
}

class _TocPanelState extends State<TocPanel> {
  int tab = 0;
  String q = '';

  void _go(AppState app, String pageId, [String anchor = '']) {
    final same = pageId == app.page?['id'] && app.contestId == null;
    if (same && anchor.isNotEmpty) {
      scrollToAnchor(anchor);
    } else {
      app.selectPage(pageId, anchor: anchor);
    }
    widget.onNavigate?.call();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.snap;
    final query = q.trim().toLowerCase();
    final pages = pagesOf(s).where((p) => query.isEmpty || '${p['title']} ${p['chapter']} ${blocksOf(p).map((b) => '${b['text'] ?? ''} ${b['title'] ?? ''} ${b['statement'] ?? ''}').join(' ')}'.toLowerCase().contains(query)).toList();
    final items = <Widget>[];
    if (tab == 0) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s['title'] ?? 'Notebook'}', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          if ('${s['description'] ?? ''}'.isNotEmpty) Text('${s['description']}', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        ]),
      ));
      String? chapter;
      for (final p in pages) {
        final ch = '${p['chapter'] ?? ''}';
        if (ch != chapter) {
          chapter = ch;
          if (ch.isNotEmpty) items.add(SectionLabel(ch));
        }
        final active = p['id'] == app.page?['id'] && app.contestId == null;
        items.add(ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          selected: active,
          leading: const Icon(Icons.description_outlined, size: 18),
          minLeadingWidth: 18,
          title: Text('${p['title'] ?? '(không tên)'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => _go(app, p['id'] as String),
        ));
        for (final e in tocEntries(p)) {
          items.add(InkWell(
            onTap: () => _go(app, p['id'] as String, e.anchor),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.0 + (e.level - 1) * 14, 5, 8, 5),
              child: Row(children: [
                if (e.problem) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.assignment_outlined, size: 14, color: context.cs.onSurfaceVariant)),
                Expanded(child: Text(e.text, style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ));
        }
      }
      if (pages.isEmpty) items.add(Padding(padding: const EdgeInsets.all(12), child: Text(query.isEmpty ? 'Chưa có trang nào.' : 'Không có kết quả.')));
    } else if (tab == 1) {
      for (final p in pages) {
        for (final b in blocksOf(p).where((b) => b['type'] == 'video')) {
          final v = parseVideo(b['url'] as String?);
          items.add(ListTile(
            dense: true,
            leading: Icon(v?.kind == 'youtube' ? Icons.smart_display : Icons.movie_outlined),
            title: Text('${(b['title'] ?? '').toString().isNotEmpty ? b['title'] : (v?.kind == 'asset' ? 'Video trên máy' : b['url'] ?? '(chưa có video)')}', maxLines: 2),
            subtitle: Text('${p['title']}'),
            onTap: () => _go(app, p['id'] as String, b['id'] as String),
          ));
        }
      }
      if (items.isEmpty) items.add(const Padding(padding: EdgeInsets.all(12), child: Text('Chưa có video. Thêm khối Video vào trang để tổng hợp ở đây.')));
    } else {
      for (final p in pages) {
        for (final b in blocksOf(p).where((b) => b['type'] == 'problem')) {
          items.add(ListTile(
            dense: true,
            leading: const Icon(Icons.assignment_outlined),
            title: Text('${b['title'] ?? 'Bài tập'}'),
            subtitle: Text('${(b['tests'] as List? ?? []).length} test · ${p['title']}'),
            onTap: () => _go(app, p['id'] as String, b['id'] as String),
          ));
        }
      }
      items.add(Padding(padding: const EdgeInsets.all(8), child: OutlinedButton.icon(icon: const Icon(Icons.emoji_events_outlined, size: 18), label: const Text('Contest…'), onPressed: () => showContestsDialog(context))));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [ButtonSegment(value: 0, label: Text('Mục lục')), ButtonSegment(value: 1, label: Text('Video')), ButtonSegment(value: 2, label: Text('Bài tập'))],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(decoration: const InputDecoration(hintText: 'Tìm trong notebook…', prefixIcon: Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => q = v)),
      ),
      Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 8), children: items)),
      if (tab == 0 && !app.readOnly) ...[
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Trang mới'), onPressed: () => addPage(app))),
        ),
      ],
    ]);
  }
}

class NotebookView extends StatefulWidget {
  const NotebookView({super.key});
  @override
  State<NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<NotebookView> {
  final scroll = ScrollController();
  String? lastPage;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _add(AppState app, Json page, int index, String kind) async {
    final b = newBlock(kind);
    (page['blocks'] as List).insert(index, b);
    if (kind != 'heading' && kind != 'code') app.editing.add(b['id'] as String);
    app.changed();
    if (kind == 'image') {
      final ref = await pickAsset(context, FileType.image);
      if (ref != null) {
        b['src'] = ref;
        app.editing.remove(b['id']);
        app.changed();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToAnchor(b['id'] as String));
  }

  Widget _inserter(AppState app, Json page, int index, {bool bar = false}) {
    final menu = PopupMenuButton<String>(
      tooltip: 'Chèn khối',
      onSelected: (k) => _add(app, page, index, k),
      itemBuilder: (_) => [for (final (k, label, icon) in blockTypes) PopupMenuItem(value: k, child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)]))],
      child: bar
          ? null
          : Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.add_circle_outline, size: 16, color: context.cs.outline)),
    );
    if (bar) {
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Thêm khối:', style: context.tt.bodySmall),
          for (final (k, label, icon) in blockTypes) TextButton.icon(onPressed: () => _add(app, page, index, k), icon: Icon(icon, size: 16), label: Text(label)),
        ]),
      );
    }
    return SizedBox(height: 18, child: Align(alignment: Alignment.centerLeft, child: menu));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.contestId != null) return const ContestView();
    final page = app.page;
    if (app.scrollTarget.isNotEmpty) {
      final target = app.scrollTarget;
      app.scrollTarget = '';
      WidgetsBinding.instance.addPostFrameCallback((_) => scrollToAnchor(target));
    }
    if (page?['id'] != lastPage) {
      lastPage = page?['id'];
      if (scroll.hasClients) scroll.jumpTo(0);
    }
    final ro = app.readOnly;
    final content = <Widget>[];
    if (ro) {
      content.add(Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: context.cs.primaryContainer.withValues(alpha: .4), border: Border.all(color: context.cs.primary), borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          const Icon(Icons.visibility_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text('Đang xem ${app.previewLabel} — chỉ đọc')),
          FilledButton(onPressed: app.endPreview, child: Text('Về nhánh ${app.repo!.head}')),
        ]),
      ));
    }
    if (page == null) {
      content.add(Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          const Text('Notebook chưa có trang nào.'),
          const SizedBox(height: 12),
          if (!ro) FilledButton.icon(onPressed: () => addPage(app), icon: const Icon(Icons.add), label: const Text('Tạo trang')),
        ]),
      ));
    } else {
      final pages = app.repo!.working['pages'] as List;
      content.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${app.snap['title'] ?? 'Notebook'}${'${page['chapter'] ?? ''}'.isNotEmpty ? ' / ${page['chapter']}' : ''}',
            style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        TextFormField(
          key: ValueKey('title-${page['id']}'),
          initialValue: '${page['title'] ?? ''}',
          readOnly: ro,
          style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          decoration: const InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, hintText: 'Tiêu đề trang', contentPadding: EdgeInsets.symmetric(vertical: 4)),
          onChanged: (v) {
            page['title'] = v;
            app.edited();
          },
          onTapOutside: (_) => app.changed(),
        ),
        Row(children: [
          Text('Chương  ', style: context.tt.bodySmall),
          SizedBox(
            width: 200,
            child: TextFormField(
              key: ValueKey('chapter-${page['id']}'),
              initialValue: '${page['chapter'] ?? ''}',
              readOnly: ro,
              decoration: const InputDecoration(hintText: 'VD: Sắp xếp'),
              onChanged: (v) {
                page['chapter'] = v;
                app.edited();
              },
              onTapOutside: (_) => app.changed(),
            ),
          ),
          const Spacer(),
          if (!ro) ...[
            IconButton(tooltip: 'Đưa trang lên', icon: const Icon(Icons.arrow_upward, size: 18), onPressed: () => _movePage(app, pages, page, -1)),
            IconButton(tooltip: 'Đưa trang xuống', icon: const Icon(Icons.arrow_downward, size: 18), onPressed: () => _movePage(app, pages, page, 1)),
            IconButton(
              tooltip: 'Xoá trang',
              icon: Icon(Icons.delete_outline, size: 18, color: context.cs.error),
              onPressed: () async {
                if (!await confirmBox(context, 'Xoá trang?', 'Xoá trang "${page['title']}"? Có thể khôi phục từ lịch sử nếu đã commit.', ok: 'Xoá', danger: true)) return;
                final i = pages.indexOf(page);
                pages.removeAt(i);
                app.pageId = pages.isEmpty ? null : (pages[(i - 1).clamp(0, pages.length - 1)] as Map)['id'] as String;
                app.changed();
              },
            ),
          ],
        ]),
        const Divider(height: 24),
      ]));
      final blocks = blocksOf(page);
      for (var i = 0; i < blocks.length; i++) {
        if (!ro) content.add(_inserter(app, page, i));
        content.add(BlockFrame(key: ValueKey(blocks[i]['id']), page: page, block: blocks[i], anchorKey: anchorFor(blocks[i]['id'] as String)));
      }
      if (!ro) content.add(_inserter(app, page, blocks.length, bar: true));
    }
    return Scrollbar(
      controller: scroll,
      child: SingleChildScrollView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(context.compact ? 12 : 40, 20, context.compact ? 8 : 32, 120),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content))),
      ),
    );
  }

  void _movePage(AppState app, List pages, Json page, int d) {
    final i = pages.indexOf(page);
    final j = i + d;
    if (j < 0 || j >= pages.length) return;
    pages[i] = pages[j];
    pages[j] = page;
    app.changed();
  }
}

/// Notebook mẫu: tạo từ mẫu hướng dẫn.
Json guideNotebook() => guideSnapshot();
