// Contest: tạo kỳ thi từ các bài tập, làm bài có giờ, bảng xếp hạng ICPC, xuất đề / nhập kết quả.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/judge.dart';
import '../core/storage.dart';
import '../core/vcs.dart';
import 'problem.dart';
import 'theme.dart';
import 'widgets.dart';

List<({Json page, Json block})> allProblems(Json snap) => [
      for (final p in pagesOf(snap))
        for (final b in blocksOf(p).where((b) => b['type'] == 'problem')) (page: p, block: b),
    ];

Json? findProblem(Json snap, String id) => allProblems(snap).where((x) => x.block['id'] == id).firstOrNull?.block;

Future<void> showContestsDialog(BuildContext context) {
  final app = context.read<AppState>();
  return showPanel<void>(
    context,
    title: 'Contest',
    width: 900,
    builder: (c, setSt) {
      final snap = app.snap;
      snap['contests'] ??= <dynamic>[];
      final contests = contestsOf(snap);
      final problems = allProblems(snap);
      final ro = app.readOnly;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (contests.isEmpty) const Text('Chưa có contest nào.'),
        for (final ct in contests)
          Card(
            child: ListTile(
              title: Text('${ct['title']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${(ct['problems'] as List).where((id) => findProblem(snap, id as String) != null).length} bài · ${ct['durationMin']} phút'),
              trailing: Wrap(spacing: 4, children: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    app.contestId = ct['id'] as String;
                    app.mode = 'notes';
                    app.changed();
                  },
                  child: const Text('Vào thi'),
                ),
                if (!ro) IconButton(tooltip: 'Sửa', icon: const Icon(Icons.edit_outlined), onPressed: () => _contestForm(c, app, ct).then((_) => setSt(() {}))),
                IconButton(tooltip: 'Xuất đề cho thí sinh (không kèm code chuẩn)', icon: const Icon(Icons.download_outlined), onPressed: () => _exportForStudents(c, app, ct)),
                if (!ro)
                  IconButton(
                    tooltip: 'Xoá',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await confirmBox(c, 'Xoá contest?', 'Xoá contest "${ct['title']}"? (Bài tập vẫn còn trong trang.)', ok: 'Xoá', danger: true)) return;
                      (snap['contests'] as List).remove(ct);
                      app.changed();
                      setSt(() {});
                    },
                  ),
              ]),
            ),
          ),
        if (!ro) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Tạo contest mới'), onPressed: () => _contestForm(c, app, null).then((_) => setSt(() {}))),
            if (problems.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.emoji_events_outlined),
                label: Text('Tạo nhanh từ tất cả ${problems.length} bài'),
                onPressed: () {
                  (snap['contests'] as List).add({'id': newId(12), 'title': '${snap['title'] ?? 'Contest'} — luyện tập', 'durationMin': 120, 'problems': problems.map((p) => p.block['id']).toList()});
                  app.changed();
                  setSt(() {});
                },
              ),
          ]),
          if (problems.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Notebook chưa có khối "Bài tập". Thêm bài tập vào trang trước rồi tạo contest.')),
        ],
      ]);
    },
  );
}

Future<void> _contestForm(BuildContext context, AppState app, Json? ct) async {
  final problems = allProblems(app.snap);
  final title = TextEditingController(text: ct?['title'] ?? 'Contest mới');
  final dur = TextEditingController(text: '${ct?['durationMin'] ?? 120}');
  final picked = <String>{...((ct?['problems'] ?? problems.map((p) => p.block['id'])) as Iterable).cast<String>()};
  await showPanel<void>(
    context,
    title: ct == null ? 'Tạo contest' : 'Sửa contest',
    builder: (c, setSt) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Tên contest')),
      const SizedBox(height: 8),
      TextField(controller: dur, decoration: const InputDecoration(labelText: 'Thời gian làm bài (phút)'), keyboardType: TextInputType.number),
      const SizedBox(height: 12),
      const Text('Các bài (đánh chữ A, B, C… theo thứ tự trong notebook):'),
      for (final p in problems)
        CheckboxListTile(
          dense: true,
          value: picked.contains(p.block['id']),
          onChanged: (v) => setSt(() => v == true ? picked.add(p.block['id'] as String) : picked.remove(p.block['id'])),
          title: Text('${p.block['title'] ?? 'Bài tập'}'),
          subtitle: Text('Trang "${p.page['title']}"'),
        ),
    ]),
    actions: (c) => [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
      FilledButton(
        onPressed: () {
          final ids = problems.map((p) => p.block['id'] as String).where(picked.contains).toList();
          if (ids.isEmpty) return toast(c, 'Chọn ít nhất một bài.', error: true);
          final data = {'title': title.text.trim().isEmpty ? 'Contest' : title.text.trim(), 'durationMin': (int.tryParse(dur.text) ?? 120).clamp(5, 10000), 'problems': ids};
          if (ct != null) {
            ct.addAll(data);
          } else {
            (app.snap['contests'] as List).add({'id': newId(12), ...data});
          }
          app.changed();
          Navigator.pop(c);
        },
        child: Text(ct == null ? 'Tạo' : 'Lưu'),
      ),
    ],
  );
}

Future<void> _exportForStudents(BuildContext context, AppState app, Json ct) async {
  final blocks = (ct['problems'] as List).map((id) => findProblem(app.snap, id as String)).whereType<Json>().map((b) => {...deepClone(b) as Json, 'reference': '', 'generator': ''}).toList();
  final snapshot = {
    'title': ct['title'],
    'description': 'Đề thi gồm ${blocks.length} bài, làm trong ${ct['durationMin']} phút.',
    'contests': [deepClone(ct)],
    'pages': [
      {
        'id': newId(12),
        'title': ct['title'],
        'chapter': 'Contest',
        'blocks': [
          {'id': newId(12), 'type': 'heading', 'level': 1, 'text': ct['title']},
          {'id': newId(12), 'type': 'markdown', 'text': 'Mở **Contest** → **Vào thi** → **Bắt đầu làm bài**. Thời gian: ${ct['durationMin']} phút.\n\nLàm xong bấm **Xuất kết quả** để gửi lại cho người ra đề.'},
          ...blocks,
        ],
      },
    ],
  };
  final bundle = Repo.bundleFromSnapshot(snapshot, author: app.authorOr);
  final refs = Storage.assetRefs(snapshot);
  if (refs.isNotEmpty) bundle['assets'] = Storage.I.packAssets(refs);
  await saveTextFile(context, 'de-thi-${slugify('${ct['title']}')}.dsanote.json', jsonEncode(bundle));
}

String _fmtDur(int ms) {
  final s = (ms / 1000).floor().clamp(0, 1 << 31);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

class ContestView extends StatefulWidget {
  const ContestView({super.key});
  @override
  State<ContestView> createState() => _ContestViewState();
}

class _ContestViewState extends State<ContestView> {
  int tab = 0, idx = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ct = contestsOf(app.snap).where((c) => c['id'] == app.contestId).firstOrNull;
    if (ct == null) return const Center(child: Text('Không tìm thấy contest.'));
    final probs = (ct['problems'] as List).map((id) => findProblem(app.snap, id as String)).whereType<Json>().toList();
    final user = app.authorOr;
    final runId = '${ct['id']}|$user';
    final run = Storage.I.getRun(runId);
    final dur = ((ct['durationMin'] ?? 120) as num).toInt() * 60000;
    final subs = run == null
        ? <Json>[]
        : (Storage.I.subs.where((s) => s['repoId'] == app.repo?.id && s['contestId'] == ct['id'] && s['user'] == user).toList()
          ..sort((a, b) => (b['time'] as int).compareTo(a['time'] as int)));
    final left = run == null ? dur : (run['startedAt'] as int) + dur - now();
    final ended = run != null && left <= 0;

    Widget body;
    if (tab == 0) {
      if (run == null) {
        body = Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${ct['title']}', style: context.tt.headlineSmall),
              const SizedBox(height: 8),
              Text('${probs.length} bài · ${ct['durationMin']} phút · thí sinh: $user'),
              const SizedBox(height: 8),
              const Text('Đồng hồ bắt đầu chạy khi bạn bấm nút bên dưới. Xếp hạng theo luật ICPC: số bài giải được, sau đó tổng thời gian + 20 phút cho mỗi lần nộp sai.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Bắt đầu làm bài'),
                onPressed: () {
                  Storage.I.putRun({'id': runId, 'contestId': ct['id'], 'repoId': app.repo?.id, 'user': user, 'startedAt': now(), 'imported': false});
                  setState(() {});
                },
              ),
            ]),
          ),
        );
      } else {
        String status(Json p) {
          final s = subs.where((x) => x['problemId'] == p['id']);
          return s.any((x) => x['verdict'] == 'AC') ? 'ok' : s.isNotEmpty ? 'bad' : '';
        }

        final nav = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < probs.length; i++)
            ListTile(
              dense: true,
              selected: i == idx,
              leading: Text(problemLetter(i), style: const TextStyle(fontWeight: FontWeight.w800)),
              minLeadingWidth: 16,
              title: Text('${probs[i]['title'] ?? 'Bài tập'}'),
              trailing: switch (status(probs[i])) {
                'ok' => Icon(Icons.check, color: context.isDark ? okColorDark : okColor),
                'bad' => Icon(Icons.close, color: context.cs.error),
                _ => null,
              },
              onTap: () => setState(() => idx = i),
            ),
        ]);
        final p = probs.isEmpty ? null : probs[idx.clamp(0, probs.length - 1)];
        final main = p == null
            ? const Text('Contest chưa có bài.')
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
                child: ProblemView(key: ValueKey('c${p['id']}'), block: p, contestId: ct['id'] as String, letter: problemLetter(probs.indexOf(p)), onSubmitted: () => setState(() {})),
              );
        body = context.compact
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nav, const SizedBox(height: 12), main])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 230, child: Card(child: nav)),
                const SizedBox(width: 14),
                Expanded(child: main),
              ]);
      }
    } else if (tab == 1) {
      body = subs.isEmpty
          ? const Text('Chưa có bài nộp.')
          : Table(
              columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth(1), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2), 4: FlexColumnWidth(1)},
              children: [
                TableRow(children: [for (final h in ['#', 'Thời điểm', 'Bài', 'Kết quả', 'Thời gian chạy']) Padding(padding: const EdgeInsets.all(6), child: Text(h, style: const TextStyle(fontWeight: FontWeight.w600)))]),
                for (var i = 0; i < subs.length; i++)
                  TableRow(decoration: BoxDecoration(border: Border(top: BorderSide(color: context.cs.outlineVariant))), children: [
                    Padding(padding: const EdgeInsets.all(6), child: Text('${subs.length - i}')),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text((subs[i]['time'] as int) <= (run!['startedAt'] as int) + dur ? _fmtDur((subs[i]['time'] as int) - (run['startedAt'] as int)) : 'ngoài giờ'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(() {
                        final k = (ct['problems'] as List).indexOf(subs[i]['problemId']);
                        return k < 0 ? '?' : '${problemLetter(k)}. ${findProblem(app.snap, subs[i]['problemId'] as String)?['title'] ?? ''}';
                      }()),
                    ),
                    Padding(padding: const EdgeInsets.all(6), child: VerdictText(subs[i]['verdict'] as String, subs[i]['test'] as int?)),
                    Padding(padding: const EdgeInsets.all(6), child: Text(subs[i]['verdict'] == 'CE' ? '' : '${subs[i]['timeMs']} ms')),
                  ]),
              ],
            );
    } else {
      final imported = Storage.I.runs.where((r) => r['contestId'] == ct['id'] && r['imported'] == true && !(run != null && r['user'] == user)).toList();
      final participants = [if (run != null) {'user': user, 'startedAt': run['startedAt'], 'subs': subs}, ...imported];
      if (participants.isEmpty) {
        body = const Text('Chưa có ai tham gia. Thí sinh làm bài xong bấm "Xuất kết quả" và gửi file cho bạn; bạn bấm "Nhập kết quả" để xếp hạng.');
      } else {
        final rows = standings(ct, participants);
        final ok = context.isDark ? okColorDark : okColor;
        body = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Hạng')),
              const DataColumn(label: Text('Thí sinh')),
              const DataColumn(label: Text('Giải')),
              const DataColumn(label: Text('Penalty')),
              for (var i = 0; i < (ct['problems'] as List).length; i++) DataColumn(label: Text(problemLetter(i))),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text('${r.rank}')),
                  DataCell(Text(r.user, style: TextStyle(fontWeight: r.user == user ? FontWeight.w700 : null))),
                  DataCell(Text('${r.solved}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${r.penalty}')),
                  for (final pid in (ct['problems'] as List).cast<String>())
                    DataCell(() {
                      final cell = r.cells[pid]!;
                      if (cell.solved) {
                        return Text('${cell.tries > 0 ? '+${cell.tries}' : '+'}\n${_fmtDur(cell.minutes * 60000).substring(0, 5)}', style: TextStyle(color: ok, fontWeight: FontWeight.w700));
                      }
                      return Text(cell.tries > 0 ? '−${cell.tries}' : '', style: TextStyle(color: context.cs.error));
                    }()),
                ]),
            ],
          ),
        );
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Thoát'),
                onPressed: () {
                  app.contestId = null;
                  app.changed();
                },
              ),
              Text('${ct['title']}', style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: ended ? context.cs.error : context.cs.outline), borderRadius: BorderRadius.circular(4)),
                child: Text(run == null ? '${ct['durationMin']} phút' : ended ? 'Đã kết thúc' : 'Còn lại ${_fmtDur(left)}',
                    style: TextStyle(fontFamily: monoFont, color: ended ? context.cs.error : null)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Xuất kết quả'),
                onPressed: run == null
                    ? null
                    : () => saveTextFile(
                          context,
                          'ket-qua-${slugify(user)}.json',
                          jsonEncode({
                            'format': 'dsa-contest-result', 'version': 1, 'contestId': ct['id'], 'contestTitle': ct['title'], 'user': user, 'startedAt': run['startedAt'],
                            'subs': subs.map((s) => {'problemId': s['problemId'], 'time': s['time'], 'verdict': s['verdict'], 'test': s['test'], 'timeMs': s['timeMs']}).toList(),
                          }),
                        ),
              ),
              OutlinedButton.icon(icon: const Icon(Icons.upload_outlined, size: 18), label: const Text('Nhập kết quả'), onPressed: () => _importResults(ct)),
            ]),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [const ButtonSegment(value: 0, label: Text('Đề bài')), ButtonSegment(value: 1, label: Text('Bài nộp (${subs.length})')), const ButtonSegment(value: 2, label: Text('Bảng xếp hạng'))],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            ),
            const SizedBox(height: 14),
            body,
          ]),
        ),
      ),
    );
  }

  Future<void> _importResults(Json ct) async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any, withData: true);
    if (r == null) return;
    var n = 0;
    for (final f in r.files) {
      try {
        final text = f.bytes != null ? utf8.decode(f.bytes!) : await File(f.path!).readAsString();
        final d = jsonDecode(text) as Map;
        if (d['format'] != 'dsa-contest-result') throw Exception('${f.name}: không phải file kết quả');
        if (d['contestId'] != ct['id']) throw Exception('${f.name}: kết quả của contest khác ("${d['contestTitle']}")');
        Storage.I.putRun({'id': '${ct['id']}|${d['user']}|imported', 'contestId': ct['id'], 'user': '${d['user']}', 'startedAt': d['startedAt'], 'subs': d['subs'], 'imported': true});
        n++;
      } catch (e) {
        if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
      }
    }
    if (n > 0 && mounted) {
      toast(context, 'Đã nhập $n kết quả');
      setState(() => tab = 2);
    }
  }
}
