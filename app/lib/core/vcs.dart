// "Git mini" cho notebook: commit, nhánh, lịch sử, diff, merge 3 chiều, chia sẻ (fork/fetch).
// Dữ liệu là JSON thuần (Map/List) để giữ tương thích với file .dsanote.json.
//
//   Snapshot = { title, description, pages: [ { id, title, chapter, blocks: [ {id, type, ...} ] } ], contests: [] }
//   Commit   = { id, parents: [id], message, author, time, snapshot }
//   Repo     = { id, commits: {id: Commit}, branches: {name: id}, remotes: {"ai/nhánh": id}, head, working }
import 'dart:convert';
import 'dart:math';

typedef Json = Map<String, dynamic>;

final _rng = Random.secure();
String newId([int len = 16]) => List.generate(len, (_) => _rng.nextInt(16).toRadixString(16)).join();

dynamic deepClone(dynamic x) => x == null ? null : jsonDecode(jsonEncode(x));
bool same(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);
int now() => DateTime.now().millisecondsSinceEpoch;

Json emptySnapshot([String title = 'Notebook mới']) =>
    {'title': title, 'description': '', 'pages': <dynamic>[], 'contests': <dynamic>[]};

List<Json> pagesOf(Json s) => (s['pages'] as List? ?? []).cast<Json>();
List<Json> blocksOf(Json p) => (p['blocks'] as List? ?? []).cast<Json>();
List<Json> contestsOf(Json s) => (s['contests'] as List? ?? []).cast<Json>();

class VcsError implements Exception {
  final String message;
  VcsError(this.message);
  @override
  String toString() => message;
}

class Repo {
  String id;
  Map<String, Json> commits;
  Map<String, String> branches;
  Map<String, String> remotes;
  String head;
  Json working;
  String? upstream;
  int updatedAt;

  Repo({
    required this.id,
    required this.commits,
    required this.branches,
    required this.remotes,
    required this.head,
    required this.working,
    this.upstream,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? now();

  factory Repo.create({String title = 'Notebook mới', String author = 'Ẩn danh', Json? snapshot}) {
    final snap = snapshot != null ? deepClone(snapshot) as Json : emptySnapshot(title);
    final first = {
      'id': newId(),
      'parents': <String>[],
      'message': 'Khởi tạo notebook',
      'author': author,
      'time': now(),
      'snapshot': deepClone(snap),
    };
    return Repo(
      id: newId(),
      commits: {first['id'] as String: first},
      branches: {'main': first['id'] as String},
      remotes: {},
      head: 'main',
      working: snap,
    );
  }

  factory Repo.fromJson(Json j) => Repo(
        id: j['id'],
        commits: (j['commits'] as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>())),
        branches: (j['branches'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        remotes: ((j['remotes'] ?? {}) as Map).map((k, v) => MapEntry(k as String, v as String)),
        head: j['head'],
        working: (j['working'] as Map).cast<String, dynamic>(),
        upstream: j['upstream'],
        updatedAt: j['updatedAt'],
      );

  Json toJson() => {
        'id': id,
        'commits': commits,
        'branches': branches,
        'remotes': remotes,
        'head': head,
        'working': working,
        if (upstream != null) 'upstream': upstream,
        'updatedAt': updatedAt,
      };

  // ---------- refs ----------
  String? resolve(String? ref) {
    if (ref == null) return null;
    if (branches.containsKey(ref)) return branches[ref];
    if (remotes.containsKey(ref)) return remotes[ref];
    if (commits.containsKey(ref)) return ref;
    final hits = commits.keys.where((id) => id.startsWith(ref)).toList();
    return hits.length == 1 ? hits.first : null;
  }

  String get headId => branches[head]!;
  Json get headSnapshot => (commits[headId]!['snapshot'] as Map).cast<String, dynamic>();
  bool get isDirty => !same(working, headSnapshot);

  static bool validBranchName(String name) =>
      RegExp(r'^[\p{L}\p{N}._-]+(/[\p{L}\p{N}._-]+)*$', unicode: true).hasMatch(name) && !name.contains('..');

  Json commit({required String message, required String author}) {
    if (!isDirty) throw VcsError('Không có thay đổi nào để commit.');
    final c = {
      'id': newId(),
      'parents': [headId],
      'message': message.trim().isEmpty ? 'Cập nhật ghi chú' : message.trim(),
      'author': author.isEmpty ? 'Ẩn danh' : author,
      'time': now(),
      'snapshot': deepClone(working),
    };
    commits[c['id'] as String] = c;
    branches[head] = c['id'] as String;
    return c;
  }

  String createBranch(String name, [String? fromRef]) {
    if (!validBranchName(name)) throw VcsError('Tên nhánh không hợp lệ (chỉ chữ, số, . _ - /).');
    if (branches.containsKey(name)) throw VcsError('Nhánh "$name" đã tồn tại.');
    final id = resolve(fromRef ?? head);
    if (id == null) throw VcsError('Không tìm thấy commit gốc cho nhánh.');
    branches[name] = id;
    return id;
  }

  void checkout(String name, {bool force = false}) {
    if (!branches.containsKey(name)) throw VcsError('Không có nhánh "$name".');
    if (!force && isDirty) throw VcsError('Còn thay đổi chưa commit.');
    head = name;
    working = deepClone(headSnapshot) as Json;
  }

  void deleteBranch(String name) {
    if (name == head) throw VcsError('Không thể xoá nhánh đang đứng.');
    if (!branches.containsKey(name)) throw VcsError('Không có nhánh "$name".');
    branches.remove(name);
  }

  void renameBranch(String from, String to) {
    if (!branches.containsKey(from)) throw VcsError('Không có nhánh "$from".');
    if (!validBranchName(to)) throw VcsError('Tên nhánh không hợp lệ.');
    if (branches.containsKey(to)) throw VcsError('Nhánh "$to" đã tồn tại.');
    branches[to] = branches.remove(from)!;
    if (head == from) head = to;
  }

  // ---------- lịch sử ----------
  Set<String> ancestors(String id) {
    final seen = <String>{};
    final stack = [id];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (seen.contains(cur) || !commits.containsKey(cur)) continue;
      seen.add(cur);
      stack.addAll((commits[cur]!['parents'] as List).cast<String>());
    }
    return seen;
  }

  bool isAncestor(String a, String b) => ancestors(b).contains(a);

  String? mergeBase(String a, String b) {
    final aa = ancestors(a);
    final common = ancestors(b).where(aa.contains).toList();
    if (common.isEmpty) return null;
    final best = common.where((c) => !common.any((o) => o != c && ancestors(o).contains(c))).toList()
      ..sort((x, y) => (commits[y]!['time'] as int).compareTo(commits[x]!['time'] as int));
    return best.first;
  }

  // Sắp xếp topo (con trước cha), commit mới hơn trước.
  List<Json> log([List<String>? refs]) {
    final starts = refs ?? [...branches.values, ...remotes.values];
    final reach = <String>{};
    for (final s in starts) {
      reach.addAll(ancestors(s));
    }
    final childCount = {for (final id in reach) id: 0};
    for (final id in reach) {
      for (final p in (commits[id]!['parents'] as List).cast<String>()) {
        if (reach.contains(p)) childCount[p] = childCount[p]! + 1;
      }
    }
    final ready = reach.where((id) => childCount[id] == 0).toList();
    final out = <Json>[];
    while (ready.isNotEmpty) {
      ready.sort((x, y) => (commits[x]!['time'] as int).compareTo(commits[y]!['time'] as int));
      final id = ready.removeLast();
      out.add(commits[id]!);
      for (final p in (commits[id]!['parents'] as List).cast<String>()) {
        if (reach.contains(p)) {
          childCount[p] = childCount[p]! - 1;
          if (childCount[p] == 0) ready.add(p);
        }
      }
    }
    return out;
  }

  ({int ahead, int behind}) aheadBehind(String a, String b) {
    final aa = ancestors(a);
    final bb = ancestors(b);
    return (ahead: aa.where((x) => !bb.contains(x)).length, behind: bb.where((x) => !aa.contains(x)).length);
  }

  // ---------- merge ----------
  MergePrep prepareMerge(String from) {
    if (isDirty) throw VcsError('Hãy commit hoặc bỏ thay đổi trước khi merge.');
    final theirsId = resolve(from);
    if (theirsId == null) throw VcsError('Không tìm thấy "$from".');
    final oursId = headId;
    if (theirsId == oursId || isAncestor(theirsId, oursId)) return MergePrep.upToDate();
    if (isAncestor(oursId, theirsId)) return MergePrep.fastForward(theirsId);
    final baseId = mergeBase(oursId, theirsId);
    final r = merge3(
      baseId != null ? (commits[baseId]!['snapshot'] as Map).cast<String, dynamic>() : null,
      (commits[oursId]!['snapshot'] as Map).cast<String, dynamic>(),
      (commits[theirsId]!['snapshot'] as Map).cast<String, dynamic>(),
    );
    return MergePrep.merge(oursId, theirsId, baseId, r.snapshot, r.conflicts);
  }

  Json finishMerge(MergePrep prep, {Json? snapshot, String? author, String? message, String? from}) {
    if (prep.kind == MergeKind.fastForward) {
      branches[head] = prep.theirsId!;
      working = deepClone(commits[prep.theirsId]!['snapshot']) as Json;
      return commits[prep.theirsId]!;
    }
    final c = {
      'id': newId(),
      'parents': [prep.oursId, prep.theirsId],
      'message': message ?? 'Merge "$from" vào "$head"',
      'author': author ?? 'Ẩn danh',
      'time': now(),
      'snapshot': deepClone(snapshot),
    };
    commits[c['id'] as String] = c;
    branches[head] = c['id'] as String;
    working = deepClone(snapshot) as Json;
    return c;
  }

  // ---------- chia sẻ ----------
  Json exportBundle({List<String>? branchNames, String? author}) {
    final names = branchNames ?? branches.keys.toList();
    final refs = {for (final n in names) n: branches[n]};
    final keep = <String>{};
    for (final id in refs.values) {
      keep.addAll(ancestors(id!));
    }
    return {
      'format': 'dsa-notebook',
      'version': 1,
      'repoId': id,
      'title': working['title'],
      'sharedBy': author ?? 'Ẩn danh',
      'sharedAt': now(),
      'head': names.contains(head) ? head : names.first,
      'branches': refs,
      'commits': {for (final id in keep) id: commits[id]},
    };
  }

  static Json bundleFromSnapshot(Json snapshot, {String? title, String? author}) {
    final c = {'id': newId(), 'parents': <String>[], 'message': 'Đề thi', 'author': author ?? 'Ẩn danh', 'time': now(), 'snapshot': deepClone(snapshot)};
    return {
      'format': 'dsa-notebook', 'version': 1, 'repoId': newId(), 'title': title ?? snapshot['title'],
      'sharedBy': author ?? 'Ẩn danh', 'sharedAt': now(), 'head': 'main', 'branches': {'main': c['id']}, 'commits': {c['id']: c},
    };
  }

  static Json validateBundle(dynamic b) {
    if (b is! Map || b['format'] != 'dsa-notebook' || b['commits'] is! Map || b['branches'] is! Map) {
      throw VcsError('File không phải notebook DSA hợp lệ.');
    }
    for (final c in (b['commits'] as Map).values) {
      if (c is! Map || c['id'] is! String || c['parents'] is! List || c['snapshot'] is! Map || (c['snapshot'] as Map)['pages'] is! List) {
        throw VcsError('Dữ liệu commit bị hỏng.');
      }
    }
    for (final id in (b['branches'] as Map).values) {
      if (!(b['commits'] as Map).containsKey(id)) throw VcsError('Nhánh trỏ tới commit không tồn tại.');
    }
    return (b).cast<String, dynamic>();
  }

  factory Repo.fromBundle(Json b) {
    validateBundle(b);
    final branches = (b['branches'] as Map).map((k, v) => MapEntry(k as String, v as String));
    final head = branches.containsKey(b['head']) ? b['head'] as String : branches.keys.first;
    final commits = (deepClone(b['commits']) as Map).map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));
    return Repo(
      id: newId(),
      commits: commits,
      branches: branches,
      remotes: {},
      head: head,
      working: deepClone(commits[branches[head]]!['snapshot']) as Json,
      upstream: b['repoId'],
    );
  }

  // Giống `git fetch`: thêm commit, tạo nhánh "tên-người/nhánh".
  ({int added, List<String> refs}) fetchBundle(Json b, String remoteName) {
    validateBundle(b);
    var added = 0;
    (b['commits'] as Map).forEach((id, c) {
      if (!commits.containsKey(id)) {
        commits[id as String] = (deepClone(c) as Map).cast<String, dynamic>();
        added++;
      }
    });
    final prefix = remoteName.replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '-');
    final refs = <String>[];
    (b['branches'] as Map).forEach((n, id) {
      remotes['$prefix/$n'] = id as String;
      refs.add('$prefix/$n');
    });
    return (added: added, refs: refs);
  }

  // Bổ sung trường cho dữ liệu cũ.
  void normalize() {
    void fix(Json s) {
      s['contests'] ??= <dynamic>[];
      for (final p in pagesOf(s)) {
        for (final b in blocksOf(p)) {
          if (b['type'] == 'sim' && b['mode'] == null) b['mode'] = 'code';
        }
      }
    }

    for (final c in commits.values) {
      fix((c['snapshot'] as Map).cast<String, dynamic>());
    }
    fix(working);
  }
}

enum MergeKind { upToDate, fastForward, merge }

class MergePrep {
  final MergeKind kind;
  final String? oursId, theirsId, baseId;
  final Json? snapshot;
  final List<Conflict> conflicts;
  MergePrep._(this.kind, {this.oursId, this.theirsId, this.baseId, this.snapshot, this.conflicts = const []});
  factory MergePrep.upToDate() => MergePrep._(MergeKind.upToDate);
  factory MergePrep.fastForward(String theirs) => MergePrep._(MergeKind.fastForward, theirsId: theirs);
  factory MergePrep.merge(String o, String t, String? b, Json s, List<Conflict> c) =>
      MergePrep._(MergeKind.merge, oursId: o, theirsId: t, baseId: b, snapshot: s, conflicts: c);
}

class Conflict {
  final String type; // field | page-delete | block-delete | contest
  final Map<String, String?> target; // pageId, blockId, field, contestId
  final String label;
  final dynamic base, ours, theirs;
  final int theirsIndex;
  Conflict(this.type, this.target, this.label, this.base, this.ours, this.theirs, [this.theirsIndex = 0]);
}

// ---------- diff ----------
class LineOp {
  final String op; // ' ', '+', '-'
  final String text;
  LineOp(this.op, this.text);
}

List<LineOp> diffLines(String? a, String? b) {
  final x = (a ?? '').split('\n');
  final y = (b ?? '').split('\n');
  final n = x.length, m = y.length;
  if (n * m > 4000000) return [...x.map((t) => LineOp('-', t)), ...y.map((t) => LineOp('+', t))];
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1]);
    }
  }
  final out = <LineOp>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      out.add(LineOp(' ', x[i]));
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add(LineOp('-', x[i++]));
    } else {
      out.add(LineOp('+', y[j++]));
    }
  }
  while (i < n) {
    out.add(LineOp('-', x[i++]));
  }
  while (j < m) {
    out.add(LineOp('+', y[j++]));
  }
  return out;
}

Map<String, Json> _byId(List? arr) => {for (final x in (arr ?? []).cast<Map>()) x['id'] as String: x.cast<String, dynamic>()};

class Change {
  final String kind; // meta, reorder-pages, page-added, page-removed, page-changed, contest-*
  final Json? before, after;
  final String? field;
  final List<String> fields;
  final List<BlockChange> blocks;
  Change(this.kind, {this.before, this.after, this.field, this.fields = const [], this.blocks = const []});
}

class BlockChange {
  final String kind; // block-added, block-removed, block-changed, reorder-blocks
  final Json? before, after;
  BlockChange(this.kind, {this.before, this.after});
}

List<Change> diffSnapshots(Json? a, Json? b) {
  a ??= emptySnapshot('');
  b ??= emptySnapshot('');
  final changes = <Change>[];
  for (final f in ['title', 'description']) {
    if (!same(a[f], b[f])) changes.add(Change('meta', field: f, before: {'v': a[f]}, after: {'v': b[f]}));
  }
  final pa = _byId(a['pages']), pb = _byId(b['pages']);
  final ordA = pagesOf(a).where((p) => pb.containsKey(p['id'])).map((p) => p['id']).toList();
  final ordB = pagesOf(b).where((p) => pa.containsKey(p['id'])).map((p) => p['id']).toList();
  if (!same(ordA, ordB)) changes.add(Change('reorder-pages'));
  final ca = _byId(a['contests']), cb = _byId(b['contests']);
  for (final c in contestsOf(b)) {
    if (!ca.containsKey(c['id'])) {
      changes.add(Change('contest-added', after: c));
    } else if (!same(ca[c['id']], c)) {
      changes.add(Change('contest-changed', before: ca[c['id']], after: c));
    }
  }
  for (final c in contestsOf(a)) {
    if (!cb.containsKey(c['id'])) changes.add(Change('contest-removed', before: c));
  }
  for (final p in pagesOf(b)) {
    if (!pa.containsKey(p['id'])) changes.add(Change('page-added', after: p));
  }
  for (final p in pagesOf(a)) {
    if (!pb.containsKey(p['id'])) changes.add(Change('page-removed', before: p));
  }
  for (final p in pagesOf(a)) {
    final q = pb[p['id']];
    if (q == null || same(p, q)) continue;
    final fields = ['title', 'chapter'].where((f) => !same(p[f], q[f])).toList();
    final ba = _byId(p['blocks']), bb = _byId(q['blocks']);
    final blocks = <BlockChange>[];
    for (final blk in blocksOf(q)) {
      if (!ba.containsKey(blk['id'])) blocks.add(BlockChange('block-added', after: blk));
    }
    for (final blk in blocksOf(p)) {
      if (!bb.containsKey(blk['id'])) blocks.add(BlockChange('block-removed', before: blk));
    }
    for (final blk in blocksOf(p)) {
      final o = bb[blk['id']];
      if (o != null && !same(blk, o)) blocks.add(BlockChange('block-changed', before: blk, after: o));
    }
    final oa = blocksOf(p).where((x) => bb.containsKey(x['id'])).map((x) => x['id']).toList();
    final ob = blocksOf(q).where((x) => ba.containsKey(x['id'])).map((x) => x['id']).toList();
    if (!same(oa, ob)) blocks.add(BlockChange('reorder-blocks'));
    changes.add(Change('page-changed', before: p, after: q, fields: fields, blocks: blocks));
  }
  return changes;
}

String blockName(Json? b) {
  if (b == null) return '';
  const map = {'markdown': 'văn bản', 'heading': 'tiêu đề', 'image': 'ảnh', 'video': 'video', 'code': 'code C++', 'sim': 'mô phỏng', 'problem': 'bài tập', 'board': 'bảng trắng'};
  String t = (b['title'] ?? b['caption'] ?? '') as String;
  if (t.isEmpty) {
    final text = (b['text'] ?? '') as String;
    final first = text.split('\n').first;
    t = first.length > 40 ? first.substring(0, 40) : first;
  }
  return '${map[b['type']] ?? b['type']}${t.isNotEmpty ? ' "$t"' : ''}';
}

// Gộp thứ tự: giữ thứ tự của ours, chèn phần tử chỉ có ở theirs ngay sau phần tử đứng trước nó.
List<String> mergeOrder(List<String> base, List<String> ours, List<String> theirs) {
  final result = [...ours];
  for (var i = 0; i < theirs.length; i++) {
    final id = theirs[i];
    if (result.contains(id)) continue;
    var pos = 0;
    for (var k = i - 1; k >= 0; k--) {
      final at = result.indexOf(theirs[k]);
      if (at != -1) {
        pos = at + 1;
        break;
      }
    }
    result.insert(pos, id);
  }
  for (final id in base) {
    if (!result.contains(id)) result.add(id);
  }
  return result;
}

({Json snapshot, List<Conflict> conflicts}) merge3(Json? base, Json ours, Json theirs) {
  base ??= emptySnapshot('');
  final conflicts = <Conflict>[];
  dynamic pick(dynamic b, dynamic o, dynamic t, void Function() onConflict) {
    if (same(o, t)) return deepClone(o);
    if (same(o, b)) return deepClone(t);
    if (same(t, b)) return deepClone(o);
    onConflict();
    return deepClone(o);
  }

  final result = <String, dynamic>{'pages': <dynamic>[]};
  for (final f in ['title', 'description']) {
    result[f] = pick(base[f], ours[f], theirs[f], () {
      conflicts.add(Conflict('field', {'field': f}, 'Thông tin notebook › ${f == 'title' ? 'tiêu đề' : 'mô tả'}', base![f], ours[f], theirs[f]));
    });
  }
  final pb = _byId(base['pages']), po = _byId(ours['pages']), pt = _byId(theirs['pages']);
  List<String> ids(Json s, String k) => (s[k] as List? ?? []).map((x) => (x as Map)['id'] as String).toList();

  Json mergeBlock(Json b, Json o, Json t, String pageId, String label) {
    final out = <String, dynamic>{};
    final keys = {...b.keys, ...o.keys, ...t.keys};
    for (final k in keys) {
      final v = pick(b[k], o[k], t[k], () {
        conflicts.add(Conflict('field', {'pageId': pageId, 'blockId': o['id'], 'field': k}, '$label › $k', b[k], o[k], t[k]));
      });
      if (v != null) out[k] = v;
    }
    return out;
  }

  Json mergePage(Json b, Json o, Json t, String name) {
    final page = <String, dynamic>{'id': o['id']};
    for (final f in ['title', 'chapter']) {
      page[f] = pick(b[f], o[f], t[f], () {
        conflicts.add(Conflict('field', {'pageId': o['id'], 'field': f}, 'Trang "$name" › ${f == 'title' ? 'tiêu đề' : 'chương'}', b[f], o[f], t[f]));
      });
    }
    final bb = _byId(b['blocks']), bo = _byId(o['blocks']), bt = _byId(t['blocks']);
    final blocks = <dynamic>[];
    for (final bid in mergeOrder(ids(b, 'blocks'), ids(o, 'blocks'), ids(t, 'blocks'))) {
      final B = bb[bid], O = bo[bid], T = bt[bid];
      final label = 'Trang "$name" › khối ${blockName(O ?? T ?? B)}';
      if (B == null) {
        if (O != null && T != null && !same(O, T)) {
          blocks.add(mergeBlock({'id': bid, 'type': O['type']}, O, T, o['id'], label));
        } else {
          blocks.add(deepClone(O ?? T));
        }
        continue;
      }
      if (O == null && T == null) continue;
      if (O == null || T == null) {
        final alive = O ?? T;
        if (same(alive, B)) continue;
        conflicts.add(Conflict('block-delete', {'pageId': o['id'], 'blockId': bid}, '$label bị ${O != null ? 'họ' : 'bạn'} xoá nhưng bên kia có sửa', B, O, T,
            blocksOf(t).indexWhere((x) => x['id'] == bid)));
        if (O != null) blocks.add(deepClone(O));
        continue;
      }
      blocks.add(mergeBlock(B, O, T, o['id'], label));
    }
    page['blocks'] = blocks;
    return page;
  }

  for (final pid in mergeOrder(ids(base, 'pages'), ids(ours, 'pages'), ids(theirs, 'pages'))) {
    final b = pb[pid], o = po[pid], t = pt[pid];
    final name = ((o ?? t ?? b)!['title'] ?? '(trang không tên)') as String;
    if (b == null) {
      if (o != null && t != null && !same(o, t)) {
        (result['pages'] as List).add(mergePage({'id': pid, 'title': o['title'], 'chapter': o['chapter'], 'blocks': []}, o, t, name));
      } else {
        (result['pages'] as List).add(deepClone(o ?? t));
      }
      continue;
    }
    if (o == null && t == null) continue;
    if (o == null || t == null) {
      final alive = o ?? t;
      if (same(alive, b)) continue;
      conflicts.add(Conflict('page-delete', {'pageId': pid}, 'Trang "$name" bị ${o != null ? 'họ' : 'bạn'} xoá nhưng bên kia có sửa', b, o, t,
          pagesOf(theirs).indexWhere((p) => p['id'] == pid)));
      if (o != null) (result['pages'] as List).add(deepClone(o));
      continue;
    }
    (result['pages'] as List).add(mergePage(b, o, t, name));
  }

  final cbm = _byId(base['contests']), com = _byId(ours['contests']), ctm = _byId(theirs['contests']);
  final contests = <dynamic>[];
  for (final cid in mergeOrder(ids(base, 'contests'), ids(ours, 'contests'), ids(theirs, 'contests'))) {
    final B = cbm[cid], O = com[cid], T = ctm[cid];
    final name = ((O ?? T ?? B)!['title'] ?? 'contest') as String;
    final v = pick(B, O, T, () {
      conflicts.add(Conflict('contest', {'contestId': cid}, 'Contest "$name"', B, O, T, contestsOf(theirs).indexWhere((c) => c['id'] == cid)));
    });
    if (v != null) contests.add(v);
  }
  result['contests'] = contests;
  return (snapshot: result, conflicts: conflicts);
}

// choice: 'ours' | 'theirs' | {'value': ...}
Json applyResolutions(Json snapshot, List<Conflict> conflicts, List<dynamic> choices) {
  final snap = deepClone(snapshot) as Json;
  for (var i = 0; i < conflicts.length; i++) {
    final c = conflicts[i];
    final ch = choices[i];
    if (ch == null) throw VcsError('Chưa giải quyết xung đột: ${c.label}');
    final value = ch == 'ours' ? c.ours : ch == 'theirs' ? c.theirs : (ch as Map)['value'];
    final pageId = c.target['pageId'], blockId = c.target['blockId'], field = c.target['field'];
    void place(List list, String id) {
      final idx = list.indexWhere((x) => (x as Map)['id'] == id);
      if (value == null) {
        if (idx != -1) list.removeAt(idx);
      } else if (idx == -1) {
        list.insert(min(c.theirsIndex < 0 ? list.length : c.theirsIndex, list.length), deepClone(value));
      } else {
        list[idx] = deepClone(value);
      }
    }

    if (c.type == 'field') {
      Map? obj = snap;
      if (pageId != null) obj = pagesOf(snap).cast<Map?>().firstWhere((p) => p!['id'] == pageId, orElse: () => null);
      if (obj != null && blockId != null) obj = (obj['blocks'] as List).cast<Map?>().firstWhere((x) => x!['id'] == blockId, orElse: () => null);
      if (obj == null) continue;
      if (value == null) {
        obj.remove(field);
      } else {
        obj[field] = deepClone(value);
      }
    } else if (c.type == 'page-delete') {
      place(snap['pages'] as List, pageId!);
    } else if (c.type == 'block-delete') {
      final page = pagesOf(snap).cast<Json?>().firstWhere((p) => p!['id'] == pageId, orElse: () => null);
      if (page != null) place(page['blocks'] as List, blockId!);
    } else if (c.type == 'contest') {
      snap['contests'] ??= <dynamic>[];
      place(snap['contests'] as List, c.target['contestId']!);
    }
  }
  return snap;
}

// Làn vẽ đồ thị lịch sử (giống `git log --graph`).
class GraphRow {
  final Json commit;
  final int col;
  final List<String?> before, after;
  GraphRow(this.commit, this.col, this.before, this.after);
}

List<GraphRow> graphLayout(List<Json> commits) {
  var lanes = <String?>[];
  return commits.map((c) {
    final before = [...lanes];
    var col = before.indexOf(c['id']);
    if (col == -1) {
      col = before.indexOf(null);
      if (col == -1) col = before.length;
    }
    final after = [...before];
    final parents = (c['parents'] as List).cast<String>();
    if (col >= after.length) after.add(null);
    after[col] = parents.isNotEmpty ? parents.first : null;
    for (var k = 0; k < after.length; k++) {
      if (k != col && after[k] == c['id']) after[k] = null;
    }
    for (final p in parents.skip(1)) {
      if (!after.contains(p)) {
        final free = after.indexOf(null);
        if (free == -1) {
          after.add(p);
        } else {
          after[free] = p;
        }
      }
    }
    while (after.isNotEmpty && after.last == null) {
      after.removeLast();
    }
    lanes = after;
    return GraphRow(c, col, before, after);
  }).toList();
}
