// Lưu dữ liệu ra file JSON trong thư mục dữ liệu của app (không dùng trình duyệt / IndexedDB).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vcs.dart';

class Storage {
  Storage._(this.root);
  final Directory root;
  static Storage? _i;
  static Storage get I => _i!;

  static Future<Storage> init({Directory? override}) async {
    final base = override ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'so_tay_dsa'));
    base.createSync(recursive: true);
    for (final d in ['repos', 'assets', 'files']) {
      Directory(p.join(base.path, d)).createSync(recursive: true);
    }
    return _i = Storage._(base);
  }

  File _f(String name) => File(p.join(root.path, name));

  Json _readJson(File f, Json dflt) {
    try {
      if (!f.existsSync()) return dflt;
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {
      return dflt;
    }
  }

  void _writeJson(File f, Object data) {
    final tmp = File('${f.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(data));
    tmp.renameSync(f.path); // ghi an toàn: không hỏng file khi mất điện giữa chừng
  }

  // ---------- Notebook ----------
  List<Repo> listRepos() {
    final out = <Repo>[];
    for (final f in Directory(p.join(root.path, 'repos')).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        out.add(Repo.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>()));
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Repo? getRepo(String id) {
    final f = _f('repos/$id.json');
    if (!f.existsSync()) return null;
    return Repo.fromJson(_readJson(f, {}));
  }

  void putRepo(Repo r) {
    r.updatedAt = now();
    _writeJson(_f('repos/${r.id}.json'), r.toJson());
  }

  void removeRepo(String id) {
    final f = _f('repos/$id.json');
    if (f.existsSync()) f.deleteSync();
  }

  // ---------- Ảnh / video (tham chiếu "asset:<hash>") ----------
  Json get _assetIndex => _readJson(_f('assets/index.json'), {});

  String addAsset(Uint8List bytes, {String type = 'application/octet-stream', String name = ''}) {
    final hash = crypto.sha256.convert(bytes).toString();
    final f = _f('assets/$hash');
    if (!f.existsSync()) f.writeAsBytesSync(bytes);
    final idx = _assetIndex;
    idx[hash] = {'type': type, 'name': name, 'size': bytes.length};
    _writeJson(_f('assets/index.json'), idx);
    return 'asset:$hash';
  }

  File? assetFile(String ref) {
    final hash = ref.replaceFirst('asset:', '');
    if (!RegExp(r'^[0-9a-f]{16,64}$').hasMatch(hash)) return null;
    final f = _f('assets/$hash');
    return f.existsSync() ? f : null;
  }

  String assetType(String ref) => ((_assetIndex[ref.replaceFirst('asset:', '')] ?? {})['type'] ?? '') as String;

  static final _assetRe = RegExp(r'asset:([0-9a-f]{16,64})');
  static List<String> assetRefs(Object data) => _assetRe.allMatches(jsonEncode(data)).map((m) => m.group(1)!).toSet().toList();

  Json packAssets(List<String> hashes) {
    final idx = _assetIndex;
    final out = <String, dynamic>{};
    for (final h in hashes) {
      final f = _f('assets/$h');
      if (!f.existsSync()) continue;
      final meta = (idx[h] ?? {}) as Map;
      out[h] = {'type': meta['type'] ?? 'application/octet-stream', 'name': meta['name'] ?? '', 'data': base64Encode(f.readAsBytesSync())};
    }
    return out;
  }

  void unpackAssets(Map? map) {
    if (map == null) return;
    map.forEach((hash, a) {
      if (hash is! String || !RegExp(r'^[0-9a-f]{16,64}$').hasMatch(hash) || a is! Map) return;
      final f = _f('assets/$hash');
      if (!f.existsSync()) f.writeAsBytesSync(base64Decode(a['data'] as String));
      final idx = _assetIndex;
      idx[hash] = {'type': a['type'] ?? '', 'name': a['name'] ?? ''};
      _writeJson(_f('assets/index.json'), idx);
    });
  }

  // ---------- Bài nộp & lượt thi ----------
  List<Json> get subs => (_readJson(_f('subs.json'), {'items': []})['items'] as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  void addSub(Json s) => _writeJson(_f('subs.json'), {'items': [...subs, s]});

  List<Json> get runs => (_readJson(_f('runs.json'), {'items': []})['items'] as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  Json? getRun(String id) => runs.where((r) => r['id'] == id).firstOrNull;
  void putRun(Json r) => _writeJson(_f('runs.json'), {'items': [...runs.where((x) => x['id'] != r['id']), r]});

  // ---------- Cài đặt & dữ liệu khác ----------
  Json readKv(String name, [Json? dflt]) => _readJson(_f('$name.json'), dflt ?? {});
  void writeKv(String name, Json data) => _writeJson(_f('$name.json'), data);

  // File C++ lưu trong app (Android / chưa lưu ra ổ đĩa).
  List<Json> listFiles() {
    final out = <Json>[];
    for (final f in Directory(p.join(root.path, 'files')).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        out.add((jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    out.sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    return out;
  }

  void putFile(Json f) => _writeJson(_f('files/${f['id']}.json'), {...f, 'updatedAt': now()});
  void removeFile(String id) {
    final f = _f('files/$id.json');
    if (f.existsSync()) f.deleteSync();
  }
}

// ---------- Sao lưu toàn bộ dữ liệu ----------
extension Backup on Storage {
  /// Toàn bộ notebook (kèm lịch sử, ảnh/video), bài nộp, file code trong app.
  Json exportAll() {
    final repos = listRepos();
    return {
      'format': 'dsa-backup',
      'version': 1,
      'createdAt': now(),
      'repos': [for (final r in repos) r.toJson()],
      'assets': packAssets(Storage.assetRefs([for (final r in repos) r.toJson()])),
      'subs': subs,
      'runs': runs,
      'files': listFiles(),
    };
  }

  /// Khôi phục bản sao lưu mà không ghi đè dữ liệu đang có:
  /// notebook đã có thì nhận các nhánh của bản sao lưu dưới tên "sao-luu/…" để merge khi cần.
  ({int added, int merged}) restoreAll(Map data) {
    unpackAssets(data['assets'] as Map?);
    var added = 0, merged = 0;
    for (final x in ((data['repos'] ?? const []) as List).whereType<Map>()) {
      final r = Repo.fromJson(x.cast<String, dynamic>());
      final cur = getRepo(r.id);
      if (cur == null) {
        putRepo(r);
        added++;
      } else {
        r.commits.forEach((id, c) => cur.commits.putIfAbsent(id, () => c));
        r.branches.forEach((n, id) {
          if (cur.branches[n] != id) cur.remotes['sao-luu/$n'] = id;
        });
        putRepo(cur);
        merged++;
      }
    }
    final known = {for (final s in subs) jsonEncode(s)};
    for (final s in ((data['subs'] ?? const []) as List).whereType<Map>()) {
      if (!known.contains(jsonEncode(s))) addSub(s.cast<String, dynamic>());
    }
    for (final f in ((data['files'] ?? const []) as List).whereType<Map>()) {
      if (!File(p.join(root.path, 'files', '${f['id']}.json')).existsSync()) putFile(f.cast<String, dynamic>());
    }
    return (added: added, merged: merged);
  }

  /// Sao lưu tự động (trước khi cập nhật app), giữ 5 bản gần nhất.
  File autoBackup(String reason) {
    final dir = Directory(p.join(root.path, 'backups'))..createSync(recursive: true);
    final f = File(p.join(dir.path, 'sao-luu-$reason-${now()}.json'))..writeAsStringSync(jsonEncode(exportAll()));
    final old = dir.listSync().whereType<File>().toList()..sort((a, b) => b.path.compareTo(a.path));
    for (final x in old.skip(5)) {
      try {
        x.deleteSync();
      } catch (_) {}
    }
    return f;
  }
}

// ---------- Mã chia sẻ (tương thích với bản cũ: 'z' + base64url(deflate-raw)) ----------
String encodeShare(Object obj) {
  final bytes = utf8.encode(jsonEncode(obj));
  final z = ZLibCodec(raw: true, level: 9).encode(bytes);
  return 'z${base64Url.encode(z).replaceAll('=', '')}';
}

dynamic decodeShare(String code) {
  final kind = code[0];
  var s = code.substring(1).replaceAll('+', '-').replaceAll('/', '_');
  while (s.length % 4 != 0) {
    s += '=';
  }
  var bytes = base64Url.decode(s);
  if (kind == 'z') {
    bytes = Uint8List.fromList(ZLibCodec(raw: true).decode(bytes));
  } else if (kind != 'j') {
    throw VcsError('Mã chia sẻ không hợp lệ.');
  }
  return jsonDecode(utf8.decode(bytes));
}

dynamic parseIncoming(String text) {
  text = text.trim();
  final m = RegExp(r'(?:#share=|sotaydsa://share/)([\w-]+)').firstMatch(text);
  if (m != null) return decodeShare(m.group(1)!);
  if (RegExp(r'^[zj][\w-]+$').hasMatch(text)) return decodeShare(text);
  try {
    return jsonDecode(text);
  } catch (_) {
    throw VcsError('Không đọc được dữ liệu. Kiểm tra lại file/link.');
  }
}

String slugify(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  final r = b.toString().replaceAll(RegExp(r'[^a-z0-9-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return r.isEmpty ? 'file' : r;
}
