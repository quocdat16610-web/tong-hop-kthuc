// Giao diện tự cập nhật: kiểm tra bản mới của ứng dụng và thư viện nội dung trên GitHub.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/updater.dart';
import '../core/vcs.dart';
import 'theme.dart';
import 'vcs_dialogs.dart' show mergeDialog;
import 'widgets.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navKey = GlobalKey<NavigatorState>();

void _notify(String msg, {SnackBarAction? action}) {
  messengerKey.currentState?.showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 6)));
}

class UpdateService extends ChangeNotifier {
  final AppState app;
  UpdateService(this.app);

  AppRelease? release;
  String? releaseError;
  bool checkingApp = false;

  List<LibraryItem> library = [];
  String? libraryError;
  bool checkingContent = false;
  DateTime? lastContentCheck;

  /// Notebook có thay đổi từ GitHub nhưng người dùng đã sửa → cần merge (id notebook → nhánh github/…).
  final Map<String, String> pendingMerge = {};

  Timer? _timer;

  bool get updateAvailable => release?.isNewer ?? false;
  String get contentUrl => app.setting<String>('contentUrl', '').trim().isEmpty ? defaultContentUrl : app.setting<String>('contentUrl', '').trim();

  void start() {
    if (Platform.environment['SOTAY_NO_UPDATE'] != null) return;
    Future.delayed(const Duration(seconds: 4), () {
      if (app.setting('autoUpdate', true)) checkApp(silent: true);
      if (app.setting('autoContent', true)) checkContent(silent: true);
    });
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (app.setting('autoUpdate', true)) checkApp(silent: true);
      if (app.setting('autoContent', true)) checkContent(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> checkApp({bool silent = false}) async {
    if (checkingApp) return;
    checkingApp = true;
    notifyListeners();
    try {
      final wasNew = updateAvailable;
      release = await fetchRelease();
      releaseError = null;
      if (silent && updateAvailable && !wasNew) {
        _notify('Có bản mới của Sổ tay DSA C++.', action: SnackBarAction(label: 'Cập nhật', onPressed: () => showUpdateDialog()));
      }
    } catch (e) {
      releaseError = '$e';
    } finally {
      checkingApp = false;
      notifyListeners();
    }
  }

  /// Tải thư viện và tự nhận nội dung mới cho các notebook đã tải về.
  Future<void> checkContent({bool silent = false}) async {
    if (checkingContent) return;
    checkingContent = true;
    notifyListeners();
    try {
      library = await fetchLibrary(contentUrl);
      libraryError = null;
      lastContentCheck = DateTime.now();
      final repos = Storage.I.listRepos();
      final updated = <String>[];
      for (final item in library) {
        var local = localCopy(item, repos);
        if (local == null) continue;
        final isOpen = app.repo?.id == local.id;
        if (isOpen) {
          app.saveNow();
          local = app.repo!;
        }
        if (newCommits(item, local) == 0 && !pendingMerge.containsKey(local.id)) continue;
        final r = applyContent(local, item);
        local.normalize();
        Storage.I.putRepo(local);
        switch (r.result) {
          case ContentResult.updated:
            pendingMerge.remove(local.id);
            updated.add('${local.working['title']}');
            if (isOpen) app.afterSwitch();
          case ContentResult.needsMerge:
            pendingMerge[local.id] = r.ref;
            if (isOpen) app.changed();
          case ContentResult.upToDate:
            pendingMerge.remove(local.id);
        }
      }
      if (updated.isNotEmpty) _notify('Đã cập nhật nội dung mới từ GitHub: ${updated.join(', ')}');
      if (pendingMerge.isNotEmpty && silent) {
        _notify('Có nội dung mới từ GitHub cho notebook bạn đã sửa — mở Thư viện để gộp (merge).',
            action: SnackBarAction(label: 'Thư viện', onPressed: () => showLibraryDialog()));
      }
    } catch (e) {
      libraryError = '$e';
    } finally {
      checkingContent = false;
      notifyListeners();
    }
  }
}

BuildContext? get _ctx => navKey.currentContext;

Future<void> showUpdateDialog([BuildContext? context]) async {
  final ctx = context ?? _ctx;
  if (ctx == null) return;
  final svc = ctx.read<UpdateService>();
  if (svc.release == null) await svc.checkApp();
  if (!ctx.mounted) return;
  double? progress;
  String? status;
  await showPanel<void>(
    ctx,
    title: 'Cập nhật ứng dụng',
    width: 560,
    builder: (c, setSt) {
      final r = svc.release;
      return ListenableBuilder(
        listenable: svc,
        builder: (c, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Bản đang dùng: $buildVersion${buildSha.isEmpty ? ' (chạy từ mã nguồn)' : ' · commit ${buildSha.substring(0, buildSha.length.clamp(0, 7))}'}'),
          const SizedBox(height: 6),
          if (svc.checkingApp) const LinearProgressIndicator(),
          if (svc.releaseError != null) Text('Không kiểm tra được: ${svc.releaseError}', style: TextStyle(color: c.cs.error)),
          if (r != null) ...[
            Text('Bản mới nhất trên GitHub: commit ${r.sha.substring(0, r.sha.length.clamp(0, 7))}${r.publishedAt != null ? ' · ${fullTime(r.publishedAt!.millisecondsSinceEpoch)}' : ''}'),
            const SizedBox(height: 10),
            if (buildSha.isEmpty)
              const Text('Bản chạy từ mã nguồn không tự cập nhật. Dùng git pull để lấy mã mới.')
            else if (!r.isNewer)
              Text('Bạn đang dùng bản mới nhất.', style: TextStyle(color: c.isDark ? okColorDark : okColor, fontWeight: FontWeight.w600))
            else
              Text('Có bản mới!', style: TextStyle(color: c.cs.primary, fontWeight: FontWeight.w700)),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress! < 0 ? null : progress),
            if (status != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(status!, style: c.tt.bodySmall)),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: svc.app.setting('autoUpdate', true),
            title: const Text('Tự kiểm tra bản mới khi mở app'),
            onChanged: (v) => setSt(() => svc.app.setSetting('autoUpdate', v)),
          ),
        ]),
      );
    },
    actions: (c) => [
      TextButton(onPressed: () => launchUrl(Uri.parse(svc.release?.htmlUrl ?? 'https://github.com/$githubRepo/releases'), mode: LaunchMode.externalApplication), child: const Text('Trang tải về')),
      OutlinedButton(onPressed: () => svc.checkApp(), child: const Text('Kiểm tra lại')),
      StatefulBuilder(
        builder: (c2, setSt) => FilledButton(
          onPressed: !(svc.release?.isNewer ?? false) || progress != null
              ? null
              : () async {
                  final r = svc.release!;
                  try {
                    if (Platform.isAndroid) {
                      final url = r.apk;
                      if (url == null) throw Exception('Chưa có file APK trên Release.');
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      if (c.mounted) toast(c, 'Đang tải APK bằng trình duyệt — mở file vừa tải để cài bản mới.');
                      return;
                    }
                    if (!Platform.isWindows) {
                      await launchUrl(Uri.parse(r.htmlUrl), mode: LaunchMode.externalApplication);
                      return;
                    }
                    final setup = installedWithSetup;
                    final url = setup ? r.installer : r.portableZip;
                    if (url == null) throw Exception('Chưa có file cập nhật trên Release.');
                    void tick(double x) {
                      progress = x;
                      status = x < 0 ? 'Đang tải…' : 'Đang tải ${(x * 100).toStringAsFixed(0)}%';
                      (c as Element).markNeedsBuild();
                      setSt(() {});
                    }

                    tick(0);
                    final f = await download(url, Uri.parse(url).pathSegments.last, tick);
                    status = 'Đang cài đặt, app sẽ tự mở lại…';
                    setSt(() {});
                    svc.app.saveNow();
                    await Future<void>.delayed(const Duration(milliseconds: 400));
                    if (setup) {
                      await runInstallerAndExit(f);
                    } else {
                      await replacePortableAndExit(f);
                    }
                  } catch (e) {
                    progress = null;
                    setSt(() {});
                    if (c.mounted) toast(c, 'Không cập nhật được: $e', error: true);
                  }
                },
          child: Text(Platform.isAndroid ? 'Tải APK mới' : 'Cập nhật ngay'),
        ),
      ),
    ],
  );
}

Future<void> showLibraryDialog([BuildContext? context, void Function(Repo)? onOpen]) async {
  final ctx = context ?? _ctx;
  if (ctx == null) return;
  final svc = ctx.read<UpdateService>();
  final app = ctx.read<AppState>();
  if (svc.library.isEmpty && !svc.checkingContent) unawaited(svc.checkContent());
  final url = TextEditingController(text: app.setting<String>('contentUrl', ''));
  void open(Repo r) {
    if (onOpen != null) {
      onOpen(r);
    } else {
      app.openRepo(r);
      app.mode = 'notes';
    }
  }

  await showPanel<void>(
    ctx,
    title: 'Thư viện bài tập & ghi chú (GitHub)',
    width: 860,
    builder: (c, setSt) => ListenableBuilder(
      listenable: svc,
      builder: (c, _) {
        final repos = Storage.I.listRepos();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Notebook do tác giả đăng trên GitHub. Tải về một lần, sau đó app tự nhận nội dung mới (bài tập, ghi chú, video) mỗi khi tác giả cập nhật. '
              'Nếu bạn đã ghi chú thêm, nội dung mới được gộp (merge) vào mà không mất ghi chú của bạn.'),
          const SizedBox(height: 10),
          if (svc.checkingContent) const LinearProgressIndicator(),
          if (svc.libraryError != null) Text('Không tải được thư viện: ${svc.libraryError}', style: TextStyle(color: c.cs.error)),
          if (!svc.checkingContent && svc.libraryError == null && svc.library.isEmpty) const Text('Thư viện chưa có notebook nào.'),
          for (final item in svc.library)
            () {
              final local = localCopy(item, repos);
              final n = local == null ? 0 : newCommits(item, local);
              final pending = local != null && svc.pendingMerge.containsKey(local.id);
              return Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: Icon(local == null ? Icons.cloud_download_outlined : Icons.book_outlined, color: c.cs.primary),
                  title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    if (item.description.isNotEmpty) item.description,
                    'Cập nhật ${timeAgo(item.updatedAt)} · ${(item.bundle['commits'] as Map).length} commit',
                    if (local != null) pending ? 'Có nội dung mới — cần gộp với ghi chú của bạn' : n > 0 ? '$n commit mới' : 'Đã có bản mới nhất',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: Wrap(spacing: 6, children: [
                    if (local == null)
                      FilledButton(
                        onPressed: () {
                          final r = installContent(item);
                          Navigator.pop(c);
                          open(r);
                          toast(ctx, 'Đã tải "${item.title}"');
                        },
                        child: const Text('Tải về'),
                      )
                    else ...[
                      if (pending)
                        FilledButton(
                          onPressed: () async {
                            Navigator.pop(c);
                            final r = Storage.I.getRepo(local.id) ?? local;
                            open(r);
                            await Future<void>.delayed(const Duration(milliseconds: 100));
                            if (ctx.mounted) await mergeDialog(ctx, preset: svc.pendingMerge[local.id]);
                            svc.pendingMerge.remove(local.id);
                          },
                          child: const Text('Gộp nội dung mới'),
                        ),
                      OutlinedButton(
                        onPressed: () {
                          Navigator.pop(c);
                          open(Storage.I.getRepo(local.id) ?? local);
                        },
                        child: const Text('Mở'),
                      ),
                    ],
                  ]),
                ),
              );
            }(),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: app.setting('autoContent', true),
            title: const Text('Tự nhận nội dung mới (kiểm tra mỗi 30 phút)'),
            onChanged: (v) => setSt(() => app.setSetting('autoContent', v)),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Nguồn thư viện'),
            children: [
              TextField(controller: url, decoration: InputDecoration(labelText: 'Link file thư viện (để trống = mặc định)', hintText: defaultContentUrl), style: TextStyle(fontFamily: monoFont, fontSize: 12)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    app.setSetting('contentUrl', url.text.trim());
                    svc.checkContent();
                  },
                  child: const Text('Lưu & tải lại'),
                ),
              ),
            ],
          ),
        ]);
      },
    ),
    actions: (c) => [
      OutlinedButton.icon(onPressed: () => svc.checkContent(), icon: const Icon(Icons.refresh, size: 18), label: const Text('Kiểm tra ngay')),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Đóng')),
    ],
  );
}

/// Thanh báo có bản mới (hiện ở đầu cửa sổ).
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final svc = context.watch<UpdateService>();
    if (!svc.updateAvailable || svc.app.setting('dismissedSha', '') == svc.release?.sha) return const SizedBox();
    return Material(
      color: context.cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Icon(Icons.system_update_alt, size: 18, color: context.cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text('Có bản mới của Sổ tay DSA C++.', style: TextStyle(color: context.cs.onPrimaryContainer))),
          TextButton(onPressed: () => svc.app.setSetting('dismissedSha', svc.release?.sha), child: const Text('Để sau')),
          FilledButton(onPressed: () => showUpdateDialog(context), child: const Text('Cập nhật')),
        ]),
      ),
    );
  }
}
