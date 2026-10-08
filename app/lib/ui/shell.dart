// Khung ứng dụng: thanh menu (desktop) / thanh dưới (Android), danh sách notebook, Sổ tay ⇄ IDE, thanh trạng thái.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/templates.dart';
import '../core/vcs.dart';
import 'blocks.dart' as blocks;
import 'contest.dart';
import 'board_tab.dart';
import 'ide.dart';
import 'notebook_view.dart';
import 'theme.dart';
import 'update_ui.dart';
import 'vcs_dialogs.dart';
import 'widgets.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  void initState() {
    super.initState();
    blocks.openInIde = (name, code) {
      context.read<IdeModel>().openCode(name, code);
      context.read<AppState>().mode = 'ide';
    };
  }

  AppState get app => context.read<AppState>();

  void _open(Repo r) {
    app.openRepo(r);
    app.mode = 'notes';
  }

  Future<void> _newNotebook() async {
    final name = await promptBox(context, 'Notebook mới', 'Tên notebook', value: 'Ghi chú DSA', ok: 'Tạo');
    if (name == null || name.isEmpty) return;
    final r = Repo.create(title: name, author: app.authorOr);
    Storage.I.putRepo(r);
    _open(r);
  }

  void _openGuide() {
    final r = Repo.create(title: 'Hướng dẫn sử dụng', author: 'Sổ tay DSA', snapshot: guideSnapshot());
    Storage.I.putRepo(r);
    _open(r);
  }

  void _toggleTheme() => app.setSetting('theme', context.isDark ? 'light' : 'dark');

  Future<void> _commit() async {
    if (app.repo == null) return;
    await commitDialog(context);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (app.mode == 'notes') _commit();
        },
        const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () => app.mode = 'notes',
        const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () => app.mode = 'ide',
        const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () => app.mode = 'board',
      };

  // ---------- Menu desktop ----------
  Widget _menuBar(AppState a) {
    final has = a.repo != null;
    MenuItemButton item(String t, VoidCallback? f, {MenuSerializableShortcut? sc, IconData? icon}) =>
        MenuItemButton(onPressed: f, shortcut: sc, leadingIcon: icon == null ? null : Icon(icon, size: 18), child: Text(t));
    return MenuBar(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.cs.surfaceContainerLow),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
      children: [
        SubmenuButton(menuChildren: [
          item('Danh sách notebook', has ? () => a.closeRepo() : null, icon: Icons.library_books_outlined),
          item('Notebook mới…', _newNotebook, icon: Icons.add),
          item('Mở sổ hướng dẫn', _openGuide, icon: Icons.menu_book_outlined),
          const Divider(),
          item('Nhập (file / link)…', () => importDialog(context, onOpen: _open), icon: Icons.download_outlined),
          item('Thư viện bài tập (GitHub)…', () => showLibraryDialog(context, _open), icon: Icons.cloud_sync_outlined),
          item('Chia sẻ…', has ? () => shareDialog(context) : null, icon: Icons.share_outlined),
          const Divider(),
          item('Cài đặt…', () => settingsDialog(context), icon: Icons.settings_outlined),
          item('Kiểm tra cập nhật…', () => showUpdateDialog(context), icon: Icons.system_update_alt),
          item('Thoát', () => SystemNavigator.pop(), icon: Icons.exit_to_app),
        ], child: const Text('Notebook')),
        SubmenuButton(menuChildren: [
          item('Commit…', has ? _commit : null, sc: const SingleActivator(LogicalKeyboardKey.keyS, control: true), icon: Icons.check),
          item('Lịch sử', has ? () => historyDialog(context) : null, icon: Icons.history),
          const Divider(),
          item('Nhánh…', has ? () => branchesDialog(context) : null, icon: Icons.call_split),
          item('Nhánh mới…', has ? () => newBranchDialog(context) : null, icon: Icons.add),
          item('Merge…', has ? () => mergeDialog(context) : null, icon: Icons.merge),
        ], child: const Text('Phiên bản')),
        SubmenuButton(menuChildren: [
          item('Trang mới', has && !a.readOnly ? () => addPage(a) : null, icon: Icons.note_add_outlined),
          item('Contest…', has ? () => showContestsDialog(context) : null, icon: Icons.emoji_events_outlined),
        ], child: const Text('Trang')),
        SubmenuButton(menuChildren: [
          item('Sổ tay', () => a.mode = 'notes', sc: const SingleActivator(LogicalKeyboardKey.digit1, alt: true), icon: Icons.menu_book_outlined),
          item('IDE C++', () => a.mode = 'ide', sc: const SingleActivator(LogicalKeyboardKey.digit2, alt: true), icon: Icons.code),
          item('Bảng trắng', () => a.mode = 'board', sc: const SingleActivator(LogicalKeyboardKey.digit3, alt: true), icon: Icons.draw_outlined),
          const Divider(),
          item('Giao diện sáng', () => a.setSetting('theme', 'light'), icon: Icons.light_mode_outlined),
          item('Giao diện tối', () => a.setSetting('theme', 'dark'), icon: Icons.dark_mode_outlined),
          item('Theo hệ thống', () => a.setSetting('theme', 'system'), icon: Icons.brightness_auto_outlined),
        ], child: const Text('Xem')),
      ],
    );
  }

  Widget _rail(AppState a) => Container(
        width: 52,
        decoration: BoxDecoration(color: context.cs.surfaceContainer, border: Border(right: BorderSide(color: context.cs.outlineVariant))),
        child: Column(children: [
          for (final (m, icon, tip) in [('notes', Icons.menu_book_outlined, 'Sổ tay (Alt+1)'), ('ide', Icons.code, 'IDE C++ (Alt+2)'), ('board', Icons.draw_outlined, 'Bảng trắng (Alt+3)')])
            Tooltip(
              message: tip,
              child: InkWell(
                onTap: () => a.mode = m,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: a.mode == m ? context.cs.primary : Colors.transparent, width: 3))),
                  child: Icon(icon, color: a.mode == m ? context.cs.primary : context.cs.onSurfaceVariant),
                ),
              ),
            ),
          const Spacer(),
          IconButton(tooltip: 'Đổi sáng / tối', onPressed: _toggleTheme, icon: Icon(context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
          IconButton(tooltip: 'Cài đặt', onPressed: () => settingsDialog(context), icon: const Icon(Icons.settings_outlined)),
          const SizedBox(height: 6),
        ]),
      );

  Widget _branchButton(AppState a) {
    final r = a.repo!;
    return PopupMenuButton<String>(
      tooltip: 'Chuyển nhánh',
      onSelected: (v) {
        if (v == '+') return newBranchDialog(context).ignore();
        if (v == '*') return branchesDialog(context).ignore();
        switchBranch(context, v);
      },
      itemBuilder: (_) => [
        for (final b in r.branches.keys) CheckedPopupMenuItem(value: b, checked: b == r.head, child: Text(b)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '+', child: Text('Nhánh mới…')),
        const PopupMenuItem(value: '*', child: Text('Quản lý nhánh…')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.call_split, size: 14), const SizedBox(width: 4), Text(r.head, style: const TextStyle(fontSize: 12))]),
      ),
    );
  }

  Widget _statusBar(AppState a) => Container(
        height: 26,
        decoration: BoxDecoration(color: context.cs.surfaceContainerHigh, border: Border(top: BorderSide(color: context.cs.outlineVariant))),
        child: Row(children: [
          if (a.repo != null) ...[
            _branchButton(a),
            ValueListenableBuilder<int>(
              valueListenable: a.revision,
              builder: (_, _, _) {
                if (a.readOnly) return Text('Đang xem: ${a.previewLabel}', style: const TextStyle(fontSize: 12, color: warnColor));
                final n = diffSnapshots(a.repo!.headSnapshot, a.repo!.working).length;
                return InkWell(
                  onTap: n == 0 ? null : _commit,
                  child: Text(n == 0 ? '✓ Đã commit' : '● $n thay đổi chưa commit — Ctrl+S để commit', style: TextStyle(fontSize: 12, color: n == 0 ? null : warnColor)),
                );
              },
            ),
          ],
          const Spacer(),
          Text('${a.repo?.working['title'] ?? ''}  ', style: const TextStyle(fontSize: 12)),
        ]),
      );

  // ---------- Danh sách notebook ----------
  Widget _home() {
    final repos = Storage.I.listRepos();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Sổ tay DSA C++', style: context.tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Ghi chú video bài giảng, code C++, mô phỏng và bài tập tự chấm — có nhánh và lịch sử như Git.', style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _newNotebook, icon: const Icon(Icons.add), label: const Text('Notebook mới')),
              OutlinedButton.icon(onPressed: () => showLibraryDialog(context, _open), icon: const Icon(Icons.cloud_sync_outlined), label: const Text('Thư viện bài tập (GitHub)')),
              OutlinedButton.icon(onPressed: () => importDialog(context, onOpen: _open), icon: const Icon(Icons.download_outlined), label: const Text('Nhập file / link')),
              OutlinedButton.icon(onPressed: _openGuide, icon: const Icon(Icons.menu_book_outlined), label: const Text('Sổ hướng dẫn')),
              OutlinedButton.icon(onPressed: () => app.mode = 'ide', icon: const Icon(Icons.code), label: const Text('Mở IDE C++')),
            ]),
            const SizedBox(height: 24),
            Text('Notebook của bạn', style: context.tt.titleMedium),
            const SizedBox(height: 8),
            if (repos.isEmpty) const Text('Chưa có notebook nào. Tạo mới hoặc mở sổ hướng dẫn để xem cách dùng.'),
            for (final r in repos)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(Icons.book_outlined),
                  title: Text('${r.working['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${pagesOf(r.working).length} trang · ${r.branches.length} nhánh · ${r.commits.length} commit · sửa ${timeAgo(r.updatedAt)}'),
                  onTap: () => _open(r),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'rename') {
                        final n = await promptBox(context, 'Đổi tên notebook', 'Tên', value: '${r.working['title']}');
                        if (n == null || n.isEmpty) return;
                        r.working['title'] = n;
                        Storage.I.putRepo(r);
                      } else if (v == 'dup') {
                        final c = Repo.fromJson(deepClone(r.toJson()) as Json)
                          ..id = newId()
                          ..upstream = r.id;
                        c.working['title'] = '${r.working['title']} (bản sao)';
                        Storage.I.putRepo(c);
                      } else if (v == 'del') {
                        if (!mounted || !await confirmBox(context, 'Xoá notebook?', 'Xoá "${r.working['title']}" cùng toàn bộ lịch sử? Không hoàn tác được.', ok: 'Xoá', danger: true)) return;
                        Storage.I.removeRepo(r.id);
                      }
                      setState(() {});
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                      PopupMenuItem(value: 'dup', child: Text('Nhân bản')),
                      PopupMenuItem(value: 'del', child: Text('Xoá')),
                    ],
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }

  Widget _notesDesktop(AppState a) => a.repo == null
      ? _home()
      : Row(children: [
          Container(
            width: 290,
            decoration: BoxDecoration(color: context.cs.surfaceContainerLow, border: Border(right: BorderSide(color: context.cs.outlineVariant))),
            child: const TocPanel(),
          ),
          const Expanded(child: NotebookView()),
        ]);

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    final compact = context.compact;
    final ide = a.mode == 'ide';
    final tab = switch (a.mode) { 'ide' => 1, 'board' => 2, _ => 0 };

    if (!compact) {
      return CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(children: [
              Row(children: [Expanded(child: _menuBar(a))]),
              const UpdateBanner(),
              Divider(height: 1, color: context.cs.outlineVariant),
              Expanded(
                child: Row(children: [
                  _rail(a),
                  Expanded(child: IndexedStack(index: tab, children: [_notesDesktop(a), const IdeView(), const BoardTab()])),
                ]),
              ),
              if (tab == 0) _statusBar(a),
            ]),
          ),
        ),
      );
    }

    // ---------- Điện thoại ----------
    final has = a.repo != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(ide ? 'IDE C++' : tab == 2 ? 'Bảng trắng' : has ? '${a.repo!.working['title']}' : 'Sổ tay DSA C++', overflow: TextOverflow.ellipsis),
        actions: [
          if (tab == 0 && has) ...[
            ValueListenableBuilder<int>(
              valueListenable: a.revision,
              builder: (_, _, _) {
                final n = a.readOnly ? 0 : diffSnapshots(a.repo!.headSnapshot, a.repo!.working).length;
                return IconButton(tooltip: 'Commit', onPressed: n == 0 ? null : _commit, icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.check)));
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'history' => historyDialog(context),
                'branches' => branchesDialog(context),
                'merge' => mergeDialog(context),
                'share' => shareDialog(context),
                'import' => importDialog(context, onOpen: _open),
                'contest' => showContestsDialog(context),
                'list' => Future(a.closeRepo),
                'library' => showLibraryDialog(context, _open),
                'update' => showUpdateDialog(context),
                _ => settingsDialog(context),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'branches', child: Text('Nhánh: ${a.repo!.head}')),
                const PopupMenuItem(value: 'history', child: Text('Lịch sử')),
                const PopupMenuItem(value: 'merge', child: Text('Merge')),
                const PopupMenuItem(value: 'contest', child: Text('Contest')),
                const PopupMenuItem(value: 'share', child: Text('Chia sẻ')),
                const PopupMenuItem(value: 'import', child: Text('Nhập')),
                const PopupMenuItem(value: 'list', child: Text('Danh sách notebook')),
                const PopupMenuItem(value: 'library', child: Text('Thư viện bài tập (GitHub)')),
                const PopupMenuItem(value: 'update', child: Text('Kiểm tra cập nhật')),
                const PopupMenuItem(value: 'settings', child: Text('Cài đặt')),
              ],
            ),
          ] else ...[
            IconButton(tooltip: 'Kiểm tra cập nhật', onPressed: () => showUpdateDialog(context), icon: const Icon(Icons.system_update_alt)),
            IconButton(tooltip: 'Cài đặt', onPressed: () => settingsDialog(context), icon: const Icon(Icons.settings_outlined)),
          ],
          IconButton(tooltip: 'Sáng / tối', onPressed: _toggleTheme, icon: Icon(context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
        ],
      ),
      drawer: tab == 0 && has ? Drawer(child: SafeArea(child: Builder(builder: (c) => TocPanel(onNavigate: () => Navigator.pop(c))))) : null,
      body: Column(children: [
        const UpdateBanner(),
        Expanded(child: IndexedStack(index: tab, children: [has ? const NotebookView() : _home(), const IdeView(), const BoardTab()])),
      ]),
      bottomNavigationBar: NavigationBar(
        height: 60,
        selectedIndex: tab,
        onDestinationSelected: (i) => a.mode = const ['notes', 'ide', 'board'][i],
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Sổ tay'),
          NavigationDestination(icon: Icon(Icons.code), label: 'IDE C++'),
          NavigationDestination(icon: Icon(Icons.draw_outlined), label: 'Bảng trắng'),
        ],
      ),
    );
  }
}
