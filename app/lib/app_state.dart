// Trạng thái chung của ứng dụng: cài đặt, notebook đang mở, chế độ (Sổ tay / IDE), lưu tự động.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core/judge.dart';
import 'core/runner.dart';
import 'core/storage.dart';
import 'core/vcs.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _settings = Storage.I.readKv('settings', {});
  }

  late Json _settings;
  T setting<T>(String key, T dflt) => (_settings[key] ?? dflt) as T;
  void setSetting(String key, Object? value) {
    _settings[key] = value;
    Storage.I.writeKv('settings', _settings);
    notifyListeners();
  }

  String get author => setting('author', '');
  String get authorOr => author.isEmpty ? 'Ẩn danh' : author;

  ThemeMode get themeMode => switch (setting('theme', 'system')) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };

  // ---------- Chế độ ----------
  String get mode => setting('mode', 'notes');
  set mode(String m) => setSetting('mode', m);

  // ---------- Notebook ----------
  Repo? repo;
  String? pageId;
  Json? previewSnap;
  String? previewLabel, previewRef;
  final Set<String> editing = {};
  String? contestId;
  String scrollTarget = '';

  Json get snap => previewSnap ?? repo!.working;
  bool get readOnly => previewSnap != null;
  Json? get page => pagesOf(snap).where((p) => p['id'] == pageId).firstOrNull ?? pagesOf(snap).firstOrNull;

  /// Tăng mỗi khi nội dung thay đổi (để thanh trạng thái cập nhật mà không vẽ lại cả trang).
  final ValueNotifier<int> revision = ValueNotifier(0);
  Timer? _saveTimer;

  void openRepo(Repo r) {
    r.normalize();
    repo = r;
    previewSnap = null;
    contestId = null;
    editing.clear();
    pageId = pagesOf(r.working).firstOrNull?['id'];
    setSetting('lastRepo', r.id);
  }

  void closeRepo() {
    saveNow();
    repo = null;
    previewSnap = null;
    contestId = null;
    setSetting('lastRepo', null);
  }

  /// Gọi khi sửa nội dung nhỏ (gõ chữ): chỉ lưu + cập nhật trạng thái.
  void edited() {
    revision.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), saveNow);
  }

  /// Gọi khi đổi cấu trúc (thêm/xoá/di chuyển khối, đổi trang…): vẽ lại + lưu.
  void changed() {
    edited();
    notifyListeners();
  }

  void saveNow() {
    _saveTimer?.cancel();
    if (repo != null) Storage.I.putRepo(repo!);
  }

  void selectPage(String id, {String anchor = ''}) {
    pageId = id;
    contestId = null;
    scrollTarget = anchor;
    notifyListeners();
  }

  void preview(String ref, {String? label}) {
    final id = repo!.resolve(ref)!;
    final c = repo!.commits[id]!;
    previewSnap = (c['snapshot'] as Map).cast<String, dynamic>();
    previewRef = id;
    previewLabel = label ?? (repo!.remotes.containsKey(ref) ? 'nhánh $ref' : 'commit ${id.substring(0, 7)} — ${c['message']}');
    editing.clear();
    contestId = null;
    if (!pagesOf(previewSnap!).any((p) => p['id'] == pageId)) pageId = pagesOf(previewSnap!).firstOrNull?['id'];
    notifyListeners();
  }

  void endPreview() {
    previewSnap = null;
    notifyListeners();
  }

  void afterSwitch() {
    previewSnap = null;
    contestId = null;
    editing.clear();
    repo!.normalize();
    if (!pagesOf(repo!.working).any((p) => p['id'] == pageId)) pageId = pagesOf(repo!.working).firstOrNull?['id'];
    saveNow();
    revision.value++;
    notifyListeners();
  }

  // ---------- Biên dịch ----------
  CompilerInfo? _compiler;
  bool _detected = false;

  Future<CompilerInfo?> detectCompiler({bool force = false}) async {
    if (_detected && !force) return _compiler;
    _compiler = await findCompiler(setting('gppPath', ''));
    _detected = true;
    return _compiler;
  }

  bool get canRunLocal => !(Platform.isAndroid || Platform.isIOS);

  Future<Backend> backend() async {
    if (canRunLocal && setting('judgeMode', 'auto') != 'online') {
      final info = await detectCompiler();
      if (info != null) return LocalBackend(info.path, setting('cppFlags', '-O2 -std=c++17'));
    }
    return OnlineBackend(compiler: setting('compiler', 'g132'), flags: setting('cppFlags', '-O2 -std=c++17'));
  }
}
