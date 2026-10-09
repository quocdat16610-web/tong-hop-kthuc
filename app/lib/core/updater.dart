// Tự cập nhật từ GitHub:
//  - Ứng dụng: so commit của bản đang chạy với Release "ban-moi-nhat", tải bộ cài / APK mới.
//  - Nội dung: thư viện notebook (bài tập, ghi chú mẫu) do tác giả đưa lên repo (thư mục content/),
//    CI gom thành file noi-dung.json trên Release. App tải về, notebook đã có thì nhận commit mới
//    như một nhánh "github/…" và tự cập nhật nếu người dùng chưa sửa gì (không thì gợi ý merge).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'storage.dart';
import 'vcs.dart';

const githubRepo = 'quocdat16610-web/tong-hop-kthuc';
const releaseTag = 'ban-moi-nhat';

/// Commit của bản đang chạy (CI truyền vào bằng --dart-define=GIT_SHA=...). Rỗng khi chạy từ mã nguồn.
const buildSha = String.fromEnvironment('GIT_SHA');
const buildVersion = String.fromEnvironment('APP_VERSION', defaultValue: '3.1.3');

const defaultContentUrl = 'https://github.com/$githubRepo/releases/download/$releaseTag/noi-dung.json';

final _headers = {'User-Agent': 'SoTayDSA/$buildVersion', 'Accept': 'application/vnd.github+json'};

// ---------- Cập nhật ứng dụng ----------
class AppRelease {
  final String sha, name, body, htmlUrl;
  final DateTime? publishedAt;
  final Map<String, String> assets; // tên file → link tải
  AppRelease(this.sha, this.name, this.body, this.htmlUrl, this.publishedAt, this.assets);

  bool get isNewer => buildSha.isNotEmpty && sha.isNotEmpty && !sha.startsWith(buildSha) && !buildSha.startsWith(sha);

  String? assetMatching(RegExp re) => assets.entries.where((e) => re.hasMatch(e.key)).firstOrNull?.value;
  String? get installer => assetMatching(RegExp(r'^SoTayDSA-Setup-.*\.exe$'));
  String? get portableZip => assetMatching(RegExp(r'win-x64-portable\.zip$')) ?? assetMatching(RegExp(r'win-x64.*\.zip$'));

  /// Gói cập nhật nhẹ: chỉ phần app, không kèm g++/gdb (máy đã có sẵn từ lần cài trước).
  String? get appUpdateZip => assetMatching(RegExp(r'-app-update\.zip$'));

  /// APK đúng loại chip của máy (nhẹ hơn APK gộp).
  String? get apk {
    final abi = Abi.current();
    if (abi == Abi.androidArm) return assetMatching(RegExp(r'android-armv7\.apk$')) ?? assetMatching(RegExp(r'android\.apk$'));
    if (abi == Abi.androidX64) return assetMatching(RegExp(r'android-x86_64\.apk$')) ?? assetMatching(RegExp(r'android\.apk$'));
    return assetMatching(RegExp(r'android\.apk$')) ?? assetMatching(RegExp(r'\.apk$'));
  }

  /// Windows: gói cập nhật nhẹ nếu máy đã có g++ đi kèm, không thì bộ cài / bản portable đầy đủ.
  ({String url, bool zip})? get windowsUpdate {
    final hasCompiler = Directory(p.join(p.dirname(Platform.resolvedExecutable), 'mingw64', 'bin')).existsSync();
    if (hasCompiler && appUpdateZip != null) return (url: appUpdateZip!, zip: true);
    if (installedWithSetup && installer != null) return (url: installer!, zip: false);
    if (portableZip != null) return (url: portableZip!, zip: true);
    return null;
  }
}

Future<AppRelease> fetchRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse('https://api.github.com/repos/$githubRepo/releases/tags/$releaseTag'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw HttpException('GitHub trả lỗi ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    // Commit của bản build nằm trong ghi chú release ("Commit: <sha>"); bản cũ dùng target_commitish.
    final fromBody = RegExp(r'Commit:\s*([0-9a-f]{7,40})').firstMatch('${j['body'] ?? ''}')?.group(1);
    return AppRelease(
      fromBody ?? '${j['target_commitish'] ?? ''}',
      '${j['name'] ?? ''}',
      '${j['body'] ?? ''}',
      '${j['html_url'] ?? 'https://github.com/$githubRepo/releases'}',
      DateTime.tryParse('${j['published_at'] ?? ''}'),
      {for (final a in ((j['assets'] ?? const []) as List).cast<Map>()) '${a['name']}': '${a['browser_download_url']}'},
    );
  } finally {
    if (client == null) c.close();
  }
}

/// Tải file về thư mục tạm, báo tiến độ (0..1, hoặc -1 khi không biết kích thước).
/// File lớn được tải song song 4 luồng (HTTP Range) — nhanh hơn nhiều khi đường truyền quốc tế chậm.
Future<File> download(String url, String name, void Function(double) onProgress, {int parts = 4}) async {
  final dir = Directory(p.join(Directory.systemTemp.path, 'so-tay-dsa-update'))..createSync(recursive: true);
  final f = File(p.join(dir.path, name));
  final headers = {'User-Agent': 'SoTayDSA/$buildVersion'};
  final c = http.Client();
  try {
    // Hỏi kích thước + kiểm tra máy chủ có hỗ trợ tải từng đoạn không.
    final probe = await c.send(http.Request('GET', Uri.parse(url))..headers.addAll({...headers, 'Range': 'bytes=0-0'}));
    final range = probe.headers['content-range'];
    await probe.stream.drain<void>();
    final total = range == null ? 0 : int.tryParse(range.split('/').last) ?? 0;
    if (probe.statusCode == 206 && total > 4 * 1024 * 1024 && parts > 1) {
      final size = (total / parts).ceil();
      final got = List<int>.filled(parts, 0);
      final pieces = await Future.wait([
        for (var i = 0; i < parts; i++)
          () async {
            final from = i * size, to = ((i + 1) * size - 1).clamp(0, total - 1);
            final part = File('${f.path}.part$i');
            for (var attempt = 0;; attempt++) {
              try {
                final res = await c.send(http.Request('GET', Uri.parse(url))..headers.addAll({...headers, 'Range': 'bytes=$from-$to'}));
                if (res.statusCode != 206) throw HttpException('Máy chủ trả ${res.statusCode}');
                final sink = part.openWrite();
                got[i] = 0;
                await for (final chunk in res.stream) {
                  sink.add(chunk);
                  got[i] += chunk.length;
                  onProgress(got.fold<int>(0, (a, b) => a + b) / total);
                }
                await sink.close();
                if (part.lengthSync() != to - from + 1) throw const HttpException('Thiếu dữ liệu');
                return part;
              } catch (_) {
                if (attempt >= 2) rethrow;
              }
            }
          }(),
      ]);
      final out = f.openWrite();
      for (final x in pieces) {
        await out.addStream(x.openRead());
      }
      await out.close();
      for (final x in pieces) {
        x.deleteSync();
      }
      if (f.lengthSync() != total) throw const HttpException('File tải về bị thiếu');
      return f;
    }
    // Máy chủ không hỗ trợ Range: tải một luồng.
    final res = await c.send(http.Request('GET', Uri.parse(url))..headers.addAll(headers));
    if (res.statusCode != 200) throw HttpException('Tải thất bại (${res.statusCode})');
    final sink = f.openWrite();
    var got = 0;
    final len = res.contentLength ?? 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      onProgress(len > 0 ? got / len : -1);
    }
    await sink.close();
    return f;
  } finally {
    c.close();
  }
}

/// Bản Windows cài bằng bộ cài (có file gỡ cài đặt cạnh exe) hay bản portable giải nén.
bool get installedWithSetup {
  final dir = p.dirname(Platform.resolvedExecutable);
  return Directory(dir).listSync().any((e) => p.basename(e.path).toLowerCase().startsWith('unins'));
}

/// Windows: chạy bộ cài ở chế độ im lặng (tự mở lại app khi xong) rồi thoát app.
Future<void> runInstallerAndExit(File setup, {bool relaunch = true}) async {
  // /NORUN (tham số riêng của bộ cài) → không mở lại app khi cập nhật lúc người dùng đóng app.
  await Process.start(setup.path, ['/VERYSILENT', '/SP-', '/SUPPRESSMSGBOXES', '/NOCANCEL', '/CLOSEAPPLICATIONS', if (!relaunch) '/NORUN'], mode: ProcessStartMode.detached);
  exit(0);
}

/// Windows bản portable: giải nén bản mới đè lên thư mục app sau khi app thoát, rồi mở lại.
Future<void> replacePortableAndExit(File zip, {bool relaunch = true}) async {
  final appDir = p.dirname(Platform.resolvedExecutable);
  final tmp = p.join(p.dirname(zip.path), 'giai-nen');
  final script = File(p.join(p.dirname(zip.path), 'cap-nhat.cmd'));
  script.writeAsStringSync([
    '@echo off',
    'chcp 65001 >nul',
    ':wait',
    'tasklist /FI "PID eq $pid" | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)',
    'rmdir /s /q "$tmp" 2>nul',
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath \'${zip.path}\' -DestinationPath \'$tmp\' -Force"',
    'robocopy "$tmp" "$appDir" /E /NFL /NDL /NJH /NJS /NP >nul',
    if (relaunch) 'start "" "${p.join(appDir, p.basename(Platform.resolvedExecutable))}"',
  ].join('\r\n'));
  await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached);
  exit(0);
}

// ---------- Thư viện nội dung ----------
class LibraryItem {
  final String file, title, description;
  final Json bundle;
  LibraryItem(this.file, this.title, this.description, this.bundle);
  String get repoId => '${bundle['repoId']}';
  int get updatedAt => ((bundle['commits'] as Map).values.map((c) => ((c as Map)['time'] ?? 0) as int).fold<int>(0, (a, b) => a > b ? a : b));
}

Future<List<LibraryItem>> fetchLibrary(String url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(url), headers: {'User-Agent': 'SoTayDSA/$buildVersion'}).timeout(const Duration(seconds: 60));
    if (r.statusCode == 404) return [];
    if (r.statusCode != 200) throw HttpException('Không tải được thư viện (${r.statusCode})');
    return parseLibrary(jsonDecode(utf8.decode(r.bodyBytes)));
  } finally {
    if (client == null) c.close();
  }
}

List<LibraryItem> parseLibrary(dynamic data) {
  final list = data is Map ? (data['notebooks'] ?? const []) as List : (data is List ? data : const []);
  final out = <LibraryItem>[];
  for (final x in list.whereType<Map>()) {
    final b = x['bundle'] ?? x;
    try {
      final bundle = Repo.validateBundle(b);
      out.add(LibraryItem('${x['file'] ?? ''}', '${x['title'] ?? bundle['title'] ?? 'Notebook'}', '${x['description'] ?? ''}', bundle));
    } catch (_) {}
  }
  return out;
}

/// Notebook trên máy ứng với một mục trong thư viện (bản tải về trước đó).
Repo? localCopy(LibraryItem item, List<Repo> repos) => repos.where((r) => r.upstream == item.repoId || r.id == item.repoId).firstOrNull;

int newCommits(LibraryItem item, Repo local) => (item.bundle['commits'] as Map).keys.where((k) => !local.commits.containsKey(k)).length;

enum ContentResult { upToDate, updated, needsMerge }

/// Nhận commit mới từ thư viện. Tự cập nhật (fast-forward) nếu người dùng chưa sửa / chưa có commit riêng,
/// còn không thì giữ nhánh "github/<nhánh>" để người dùng merge.
({ContentResult result, String ref, int added}) applyContent(Repo local, LibraryItem item) {
  Storage.I.unpackAssets(item.bundle['assets'] as Map?);
  final f = local.fetchBundle(item.bundle, 'github');
  final ref = 'github/${local.head}';
  final theirs = local.remotes[ref] ?? (f.refs.isNotEmpty ? local.remotes[f.refs.first] : null);
  if (theirs == null || theirs == local.headId || local.isAncestor(theirs, local.headId)) {
    return (result: ContentResult.upToDate, ref: ref, added: f.added);
  }
  if (!local.isDirty && local.isAncestor(local.headId, theirs)) {
    local.branches[local.head] = theirs;
    local.working = deepClone(local.commits[theirs]!['snapshot']) as Json;
    return (result: ContentResult.updated, ref: ref, added: f.added);
  }
  return (result: ContentResult.needsMerge, ref: local.remotes.containsKey(ref) ? ref : f.refs.first, added: f.added);
}

/// Tải một notebook trong thư viện về máy lần đầu.
Repo installContent(LibraryItem item) {
  Storage.I.unpackAssets(item.bundle['assets'] as Map?);
  final r = Repo.fromBundle(item.bundle)..normalize();
  Storage.I.putRepo(r);
  return r;
}
