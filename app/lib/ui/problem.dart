// Khối "Bài tập": làm bài + nộp + chấm (người học) và chế độ tác giả (đề, test, code chuẩn, sinh test).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../app_state.dart';
import '../core/judge.dart';
import '../core/storage.dart';
import '../core/templates.dart';
import '../core/vcs.dart';
import 'code_editor.dart';
import 'media.dart';
import 'theme.dart';
import 'widgets.dart';

// ---------- Bản nháp bài làm ----------
class Drafts {
  static Json? _d;
  static Timer? _t;
  static Json get _data => _d ??= Storage.I.readKv('drafts');
  static String? get(String key) => _data[key] as String?;
  static void set(String key, String v) {
    _data[key] = v;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 600), () => Storage.I.writeKv('drafts', _data));
  }
}

class VerdictText extends StatelessWidget {
  final String verdict;
  final int? test;
  const VerdictText(this.verdict, this.test, {super.key});
  @override
  Widget build(BuildContext context) {
    final ok = verdict == 'AC';
    final color = ok ? (context.isDark ? okColorDark : okColor) : verdict == 'NT' ? null : context.cs.error;
    return Text(verdictText(verdict, test), style: TextStyle(color: color, fontWeight: FontWeight.w700));
  }
}

Widget _io(BuildContext context, String label, String text) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant)),
      const SizedBox(height: 2),
      MonoBox(text.length > 4000 ? '${text.substring(0, 4000)}…' : text, maxHeight: 180),
    ]);

class ResultBox extends StatelessWidget {
  final JudgeResult r;
  final bool showData;
  final String where;
  const ResultBox(this.r, {super.key, this.showData = false, this.where = ''});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            VerdictText(r.verdict, r.test),
            const SizedBox(width: 10),
            if (r.verdict != 'CE' && r.verdict != 'NT') Text('${r.timeMs} ms', style: context.tt.bodySmall),
            if (r.verdict == 'AC' && r.tests > 0) Text('  ·  ${r.tests} test', style: context.tt.bodySmall),
            const Spacer(),
            Text(where, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
          ]),
          if (r.verdict == 'CE') ...[const SizedBox(height: 6), _io(context, 'Thông báo của trình biên dịch', r.message)],
          if (r.verdict == 'NT') const Text('Bài này chưa có test. Tác giả cần thêm test trong chế độ sửa.'),
          if (r.verdict != 'AC' && r.verdict != 'CE' && r.verdict != 'NT' && showData) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (l, t) in [('Input', r.input), ('Output đúng', r.expected), ('Output của bạn', r.got), if (r.stderr.isNotEmpty) ('stderr', r.stderr)])
                SizedBox(width: 260, child: _io(context, l, t)),
            ]),
          ],
        ]),
      );
}

class ProblemView extends StatefulWidget {
  final Json block;
  final String? contestId;
  final String? letter;
  final VoidCallback? onSubmitted;
  const ProblemView({super.key, required this.block, this.contestId, this.letter, this.onSubmitted});
  @override
  State<ProblemView> createState() => _ProblemViewState();
}

class _ProblemViewState extends State<ProblemView> {
  late final CodeLineEditingController editor;
  JudgeResult? result;
  bool showData = false;
  String where = '';
  String progress = '';
  bool busy = false;

  Json get b => widget.block;
  String get draftKey => '${context.read<AppState>().repo?.id}:${b['id']}';

  @override
  void initState() {
    super.initState();
    editor = CodeLineEditingController.fromText(cppTemplate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final d = Drafts.get(draftKey);
      if (d != null) editor.text = d;
      editor.addListener(() => Drafts.set(draftKey, editor.text));
    });
  }

  @override
  void dispose() {
    editor.dispose();
    super.dispose();
  }

  Future<void> _go(bool samplesOnly) async {
    final app = context.read<AppState>();
    final tests = ((b['tests'] ?? []) as List).cast<Map>().map((t) => t.cast<String, dynamic>()).where((t) => !samplesOnly || t['sample'] == true).toList();
    setState(() {
      busy = true;
      result = null;
      progress = 'Đang biên dịch…';
    });
    try {
      final be = await app.backend();
      final r = await judge(
        source: editor.text,
        tests: tests,
        timeLimit: ((b['timeLimit'] ?? 1000) as num).toInt(),
        checker: (b['checker'] ?? 'tokens') as String,
        backend: be,
        onProgress: (i, n) => mounted ? setState(() => progress = 'Đang chấm test $i/$n…') : null,
      );
      if (!samplesOnly && r.verdict != 'NT') {
        Storage.I.addSub({
          'id': newId(), 'repoId': app.repo?.id, 'contestId': widget.contestId, 'problemId': b['id'], 'user': app.authorOr,
          'time': now(), 'verdict': r.verdict, 'test': r.test, 'timeMs': r.timeMs, 'code': editor.text,
        });
        widget.onSubmitted?.call();
      }
      final failed = r.test != null ? r.test! - 1 : -1;
      setState(() {
        result = r;
        where = be.name;
        showData = samplesOnly || (failed >= 0 && failed < tests.length && tests[failed]['sample'] == true);
      });
    } catch (e) {
      if (mounted) toast(context, 'Không chấm được: $e', error: true);
    }
    if (mounted) setState(() {
      busy = false;
      progress = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final samples = ((b['tests'] ?? []) as List).cast<Map>().where((t) => t['sample'] == true).toList();
    final subs = Storage.I.subs
        .where((s) => s['repoId'] == app.repo?.id && s['problemId'] == b['id'] && s['user'] == app.authorOr && s['contestId'] == widget.contestId)
        .toList()
      ..sort((x, y) => (y['time'] as int).compareTo(x['time'] as int));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Text('${widget.letter != null ? '${widget.letter}. ' : ''}${b['title'] ?? 'Bài tập'}', style: context.tt.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
      Center(
        child: Text('Giới hạn thời gian: ${((b['timeLimit'] ?? 1000) as num) / 1000} giây  ·  Bộ nhớ: ${b['memoryLimit'] ?? 256} MB',
            style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
      ),
      const SizedBox(height: 10),
      MarkdownView((b['statement'] ?? '') as String),
      if (samples.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Ví dụ', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        for (final t in samples)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _sample(context, 'Input', '${t['input']}')),
              const SizedBox(width: 6),
              Expanded(child: _sample(context, 'Output', '${t['output']}')),
            ]),
          ),
      ],
      const Divider(height: 28),
      Text('Bài làm (C++)', style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Container(
        height: 300,
        decoration: BoxDecoration(border: Border.all(color: context.cs.outline), borderRadius: BorderRadius.circular(4)),
        child: CodeArea(controller: editor),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(onPressed: busy ? null : () => _go(true), icon: const Icon(Icons.play_arrow, size: 18), label: const Text('Chạy test mẫu')),
        FilledButton.icon(onPressed: busy ? null : () => _go(false), icon: const Icon(Icons.upload, size: 18), label: const Text('Nộp bài')),
        if (progress.isNotEmpty) Text(progress, style: context.tt.bodySmall),
      ]),
      if (result != null) ResultBox(result!, showData: showData, where: where),
      if (subs.isNotEmpty) ...[
        const SizedBox(height: 10),
        Table(
          columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(1), 3: IntrinsicColumnWidth()},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final s in subs.take(8))
              TableRow(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.cs.outlineVariant))), children: [
                Padding(padding: const EdgeInsets.all(4), child: Text(timeAgo(s['time'] as int), style: context.tt.bodySmall)),
                VerdictText(s['verdict'] as String, s['test'] as int?),
                Text(s['verdict'] == 'CE' ? '' : '${s['timeMs']} ms', style: context.tt.bodySmall),
                TextButton(onPressed: () => editor.text = (s['code'] ?? '') as String, child: const Text('Mở lại code')),
              ]),
          ],
        ),
      ],
    ]);
  }

  Widget _sample(BuildContext context, String label, String text) => Container(
        decoration: BoxDecoration(border: Border.all(color: context.cs.outline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: context.cs.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(children: [
              Text(label, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  toast(context, 'Đã sao chép');
                },
                child: Text('Sao chép', style: TextStyle(color: context.cs.primary, fontSize: 12)),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(8), child: SelectableText(text, style: TextStyle(fontFamily: monoFont, fontSize: 13))),
        ]),
      );
}

// ---------- Chế độ tác giả ----------
class ProblemEditor extends StatefulWidget {
  final Json block;
  const ProblemEditor({super.key, required this.block});
  @override
  State<ProblemEditor> createState() => _ProblemEditorState();
}

class _ProblemEditorState extends State<ProblemEditor> {
  int tab = 0;
  String status = '';
  JudgeResult? refResult;
  String refWhere = '';
  late final CodeLineEditingController refCtl, genCtl;

  Json get b => widget.block;
  List<Json> get tests {
    b['tests'] ??= <dynamic>[];
    return (b['tests'] as List).cast<Json>();
  }

  @override
  void initState() {
    super.initState();
    refCtl = CodeLineEditingController.fromText((b['reference'] ?? cppTemplate) as String);
    genCtl = CodeLineEditingController.fromText((b['generator'] ?? genTemplate) as String);
    refCtl.addListener(() => _set('reference', refCtl.text));
    genCtl.addListener(() => _set('generator', genCtl.text));
  }

  @override
  void dispose() {
    refCtl.dispose();
    genCtl.dispose();
    super.dispose();
  }

  void _set(String k, Object? v) {
    if (b[k] == v) return;
    b[k] = v;
    context.read<AppState>().edited();
  }

  Future<void> _busy(String label, Future<void> Function() fn) async {
    setState(() => status = label);
    try {
      await fn();
    } catch (e) {
      if (mounted) toast(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => status = '');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final nSample = tests.where((t) => t['sample'] == true).length;
    final tabs = ['Đề bài', 'Test (${tests.length})', 'Code chuẩn', 'Sinh test'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 4, children: [
        for (var i = 0; i < tabs.length; i++) ChoiceChip(label: Text(tabs[i]), selected: tab == i, onSelected: (_) => setState(() => tab = i)),
      ]),
      const SizedBox(height: 10),
      if (tab == 0) ...[
        TextFormField(initialValue: (b['title'] ?? '') as String, decoration: const InputDecoration(labelText: 'Tên bài'), onChanged: (v) => _set('title', v)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
            width: 180,
            child: TextFormField(
              initialValue: '${b['timeLimit'] ?? 1000}',
              decoration: const InputDecoration(labelText: 'Giới hạn thời gian (ms)'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _set('timeLimit', int.tryParse(v) ?? 1000),
            ),
          ),
          SizedBox(
            width: 160,
            child: TextFormField(
              initialValue: '${b['memoryLimit'] ?? 256}',
              decoration: const InputDecoration(labelText: 'Bộ nhớ (MB)'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _set('memoryLimit', int.tryParse(v) ?? 256),
            ),
          ),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              initialValue: (b['checker'] ?? 'tokens') as String,
              decoration: const InputDecoration(labelText: 'Cách so output'),
              items: [for (final (v, t) in checkers) DropdownMenuItem(value: v, child: Text(t))],
              onChanged: (v) => _set('checker', v),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: (b['statement'] ?? '') as String,
          decoration: const InputDecoration(labelText: 'Đề bài (Markdown)', alignLabelWithHint: true),
          minLines: 8,
          maxLines: 20,
          style: TextStyle(fontFamily: monoFont, fontSize: 13),
          onChanged: (v) => _set('statement', v),
        ),
      ],
      if (tab == 1) ...[
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${tests.length} test, $nSample test mẫu hiện trong đề. Test còn lại được giữ kín khi chấm.', style: context.tt.bodySmall),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm test'),
            onPressed: () {
              (b['tests'] as List).add({'input': '', 'output': '', 'sample': tests.length < 2});
              app.edited();
              setState(() {});
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Tạo output bằng code chuẩn'),
            onPressed: () => _busy('Đang chạy code chuẩn…', () async {
              if (tests.isEmpty) throw Exception('Chưa có test nào.');
              final be = await app.backend();
              final outs = await runAll(refCtl.text, tests.map((t) => '${t['input'] ?? ''}').toList(), be,
                  onProgress: (i, n) => mounted ? setState(() => status = 'Code chuẩn: $i/$n') : null);
              for (var i = 0; i < outs.length; i++) {
                tests[i]['output'] = outs[i];
              }
              app.edited();
              if (mounted) toast(context, 'Đã tạo output cho ${outs.length} test');
            }),
          ),
          if (tests.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (await confirmBox(context, 'Xoá hết test?', 'Xoá ${tests.length} test của bài này?', ok: 'Xoá', danger: true)) {
                  (b['tests'] as List).clear();
                  app.edited();
                  setState(() {});
                }
              },
              child: Text('Xoá hết', style: TextStyle(color: context.cs.error)),
            ),
        ]),
        if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(status, style: context.tt.bodySmall)),
        for (var i = 0; i < tests.length; i++) _testItem(i),
      ],
      if (tab == 2) ...[
        Text('Code chuẩn dùng để tạo output cho test. Khi xuất đề cho thí sinh, code chuẩn được bỏ đi.', style: context.tt.bodySmall),
        const SizedBox(height: 6),
        Container(height: 320, decoration: BoxDecoration(border: Border.all(color: context.cs.outline)), child: CodeArea(controller: refCtl)),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Chấm thử code chuẩn với các test'),
            onPressed: () => _busy('Đang chấm…', () async {
              final be = await app.backend();
              final r = await judge(
                source: refCtl.text,
                tests: tests,
                timeLimit: ((b['timeLimit'] ?? 1000) as num).toInt(),
                checker: (b['checker'] ?? 'tokens') as String,
                backend: be,
                onProgress: (i, n) => mounted ? setState(() => status = 'Test $i/$n') : null,
              );
              if (mounted) setState(() {
                refResult = r;
                refWhere = be.name;
              });
            }),
          ),
          const SizedBox(width: 8),
          Text(status, style: context.tt.bodySmall),
        ]),
        if (refResult != null) ResultBox(refResult!, showData: true, where: refWhere),
      ],
      if (tab == 3) ...[
        Text('Viết chương trình C++ in ra một bộ input ngẫu nhiên từ seed. App chạy generator với seed 1…N rồi chạy code chuẩn để có output. Test mới được thêm vào cuối danh sách.',
            style: context.tt.bodySmall),
        const SizedBox(height: 6),
        Container(height: 300, decoration: BoxDecoration(border: Border.all(color: context.cs.outline)), child: CodeArea(controller: genCtl)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Số test:'),
          SizedBox(
            width: 90,
            child: TextFormField(initialValue: '${b['genCount'] ?? 10}', keyboardType: TextInputType.number, onChanged: (v) => _set('genCount', int.tryParse(v) ?? 10)),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Sinh test'),
            onPressed: () => _busy('Đang sinh input…', () async {
              final n = ((b['genCount'] ?? 10) as num).toInt().clamp(1, 200);
              final be = await app.backend();
              final start = tests.length + 1;
              final seeds = List.generate(n, (i) => '${start + i}');
              final inputs = await runAll(genCtl.text, seeds, be, onProgress: (i, k) => mounted ? setState(() => status = 'Generator: $i/$k') : null);
              final outs = await runAll(refCtl.text, inputs, be, onProgress: (i, k) => mounted ? setState(() => status = 'Code chuẩn: $i/$k') : null);
              for (var i = 0; i < inputs.length; i++) {
                (b['tests'] as List).add({'input': inputs[i], 'output': outs[i], 'sample': false});
              }
              app.edited();
              if (mounted) {
                setState(() => tab = 1);
                toast(context, 'Đã sinh $n test');
              }
            }),
          ),
          Text(status, style: context.tt.bodySmall),
        ]),
      ],
    ]);
  }

  Widget _testItem(int i) {
    final t = tests[i];
    final app = context.read<AppState>();
    final big = '${t['input']}'.length + '${t['output']}'.length > 20000;
    Widget area(String field) => big
        ? MonoBox('${t[field]}'.length > 2000 ? '${'${t[field]}'.substring(0, 2000)}…' : '${t[field]}', maxHeight: 140)
        : TextFormField(
            key: ValueKey('${b['id']}-$i-$field-${tests.length}'),
            initialValue: '${t[field] ?? ''}',
            minLines: 2,
            maxLines: 8,
            style: TextStyle(fontFamily: monoFont, fontSize: 13),
            onChanged: (v) {
              t[field] = v;
              app.edited();
            },
          );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
      child: Column(children: [
        Row(children: [
          Text('Test ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Checkbox(value: t['sample'] == true, onChanged: (v) => setState(() {
                t['sample'] = v;
                app.edited();
              })),
          const Text('Test mẫu'),
          const Spacer(),
          IconButton(
            tooltip: 'Xoá test',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => setState(() {
              (b['tests'] as List).removeAt(i);
              app.edited();
            }),
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Input'), area('input')])),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Output'), area('output')])),
        ]),
      ]),
    );
  }
}
