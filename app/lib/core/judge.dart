// Chấm bài kiểu Codeforces và bảng xếp hạng kiểu ICPC.
import 'dart:async';
import 'dart:math';

import 'vcs.dart';

class CompileResult {
  final bool ok;
  final String id;
  final String error;
  final String warnings;
  CompileResult.ok(this.id, [this.warnings = '']) : ok = true, error = '';
  CompileResult.fail(this.error) : ok = false, id = '', warnings = '';
}

class RunResult {
  final String stdout, stderr;
  final int exitCode;
  final int timeMs;
  final bool timedOut;
  final String? compileError; // backend online: lỗi biên dịch chỉ biết khi chạy
  final String warnings;
  RunResult({this.stdout = '', this.stderr = '', this.exitCode = 0, this.timeMs = 0, this.timedOut = false, this.compileError, this.warnings = ''});
}

abstract class Backend {
  String get name;
  bool get local;
  int get parallel;
  Future<CompileResult> compile(String source, {String? includeDir, bool debug = false, bool unbuffered = false});
  Future<RunResult> run(String id, String input, int timeLimitMs);
  void dispose(String id);
}

const verdictNames = {
  'AC': 'Accepted',
  'WA': 'Wrong answer',
  'TLE': 'Time limit exceeded',
  'RE': 'Runtime error',
  'CE': 'Compilation error',
  'NT': 'Chưa có test',
};

String verdictText(String verdict, [int? test]) {
  final base = verdictNames[verdict] ?? verdict;
  return test != null && verdict != 'AC' && verdict != 'CE' ? '$base on test $test' : base;
}

List<String> _tokens(String s) => s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();

bool checkOutput(String checker, String expected, String got) {
  if (checker == 'exact') {
    String norm(String s) => s.replaceAll('\r\n', '\n').split('\n').map((l) => l.trimRight()).join('\n').replaceAll(RegExp(r'\n+$'), '');
    return norm(expected) == norm(got);
  }
  final a = _tokens(expected), b = _tokens(got);
  if (a.length != b.length) return false;
  if (checker.startsWith('float')) {
    final eps = double.tryParse(checker.split(':').length > 1 ? checker.split(':')[1] : '') ?? 1e-6;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == b[i]) continue;
      final p = double.tryParse(a[i]), q = double.tryParse(b[i]);
      if (p == null || q == null) return false;
      if ((p - q).abs() > eps * max(1, p.abs())) return false;
    }
    return true;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class JudgeResult {
  final String verdict;
  final int? test;
  final int timeMs;
  final int tests;
  final String message, input, expected, got, stderr;
  JudgeResult(this.verdict, {this.test, this.timeMs = 0, this.tests = 0, this.message = '', this.input = '', this.expected = '', this.got = '', this.stderr = ''});
  String get text => verdictText(verdict, test);
}

// Chạy song song tối đa `limit` việc; dừng lấy việc mới khi fn trả true.
Future<void> _pool<T>(List<T> items, int limit, Future<bool> Function(T, int) fn) async {
  var next = 0;
  var stopped = false;
  Future<void> worker() async {
    while (!stopped && next < items.length) {
      final i = next++;
      if (await fn(items[i], i)) stopped = true;
    }
  }

  await Future.wait(List.generate(min(limit, items.length), (_) => worker()));
}

Future<JudgeResult> judge({
  required String source,
  required List<Json> tests,
  int timeLimit = 1000,
  String checker = 'tokens',
  required Backend backend,
  void Function(int done, int total)? onProgress,
}) async {
  if (tests.isEmpty) return JudgeResult('NT');
  final comp = await backend.compile(source);
  if (!comp.ok) return JudgeResult('CE', message: comp.error);
  final results = List<({String verdict, RunResult r})?>.filled(tests.length, null);
  var firstBad = 1 << 30;
  var done = 0;
  try {
    await _pool(tests, backend.parallel, (t, i) async {
      if (i > firstBad) return true;
      final r = await backend.run(comp.id, (t['input'] ?? '') as String, timeLimit);
      done++;
      onProgress?.call(done, tests.length);
      var v = 'AC';
      if (r.compileError != null) {
        v = 'CE';
      } else if (r.timedOut || r.timeMs > timeLimit) {
        v = 'TLE';
      } else if (r.exitCode != 0) {
        v = 'RE';
      } else if (!checkOutput(checker, (t['output'] ?? '') as String, r.stdout)) {
        v = 'WA';
      }
      results[i] = (verdict: v, r: r);
      if (v != 'AC') {
        firstBad = min(firstBad, i);
        return true;
      }
      return false;
    });
  } finally {
    backend.dispose(comp.id);
  }
  final maxTime = results.whereType<({String verdict, RunResult r})>().fold<int>(0, (m, x) => max(m, x.r.timeMs));
  if (firstBad == 1 << 30) return JudgeResult('AC', timeMs: maxTime, tests: tests.length);
  final bad = results[firstBad]!;
  if (bad.verdict == 'CE') return JudgeResult('CE', message: bad.r.compileError ?? '');
  final t = tests[firstBad];
  return JudgeResult(bad.verdict,
      test: firstBad + 1, timeMs: bad.r.timeMs, input: t['input'] ?? '', expected: t['output'] ?? '', got: bad.r.stdout, stderr: bad.r.stderr);
}

// Chạy chương trình với nhiều input (sinh test bằng generator / tạo output bằng code chuẩn).
Future<List<String>> runAll(String source, List<String> inputs, Backend backend, {int timeLimit = 5000, void Function(int, int)? onProgress}) async {
  final comp = await backend.compile(source);
  if (!comp.ok) throw Exception('Lỗi biên dịch:\n${comp.error}');
  final out = List<String>.filled(inputs.length, '');
  var done = 0;
  try {
    await _pool(inputs, backend.parallel, (input, i) async {
      final r = await backend.run(comp.id, input, timeLimit);
      if (r.compileError != null) throw Exception('Lỗi biên dịch:\n${r.compileError}');
      if (r.timedOut) throw Exception('Chạy quá $timeLimit ms ở test ${i + 1}');
      if (r.exitCode != 0) throw Exception('Lỗi khi chạy test ${i + 1} (mã thoát ${r.exitCode})\n${r.stderr}');
      out[i] = r.stdout;
      onProgress?.call(++done, inputs.length);
      return false;
    });
  } finally {
    backend.dispose(comp.id);
  }
  return out;
}

// ---------- Bảng xếp hạng ICPC ----------
class StandingCell {
  final bool solved;
  final int tries;
  final int minutes;
  StandingCell(this.solved, this.tries, [this.minutes = 0]);
}

class StandingRow {
  final String user;
  final int solved, penalty, last;
  final Map<String, StandingCell> cells;
  int rank = 0;
  StandingRow(this.user, this.solved, this.penalty, this.last, this.cells);
}

// participants: [{user, startedAt, subs: [{problemId, time, verdict}]}]
List<StandingRow> standings(Json contest, List<Json> participants) {
  final dur = ((contest['durationMin'] ?? 120) as num).toInt() * 60000;
  final problems = (contest['problems'] as List).cast<String>();
  final rows = participants.map((p) {
    final started = (p['startedAt'] as num).toInt();
    final cells = <String, StandingCell>{};
    var solved = 0, penalty = 0, last = 0;
    for (final pid in problems) {
      final subs = (p['subs'] as List? ?? [])
          .cast<Map>()
          .where((s) => s['problemId'] == pid && s['time'] >= started && s['time'] <= started + dur && s['verdict'] != 'CE')
          .toList()
        ..sort((a, b) => (a['time'] as num).compareTo(b['time'] as num));
      final ac = subs.indexWhere((s) => s['verdict'] == 'AC');
      if (ac == -1) {
        cells[pid] = StandingCell(false, subs.length);
      } else {
        final minutes = ((subs[ac]['time'] as num).toInt() - started) ~/ 60000;
        cells[pid] = StandingCell(true, ac, minutes);
        solved++;
        penalty += minutes + 20 * ac;
        last = max(last, (subs[ac]['time'] as num).toInt());
      }
    }
    return StandingRow(p['user'] as String, solved, penalty, last, cells);
  }).toList();
  rows.sort((a, b) {
    if (a.solved != b.solved) return b.solved - a.solved;
    if (a.penalty != b.penalty) return a.penalty - b.penalty;
    if (a.last != b.last) return a.last - b.last;
    return a.user.compareTo(b.user);
  });
  for (var i = 0; i < rows.length; i++) {
    rows[i].rank = i > 0 && rows[i - 1].solved == rows[i].solved && rows[i - 1].penalty == rows[i].penalty ? rows[i - 1].rank : i + 1;
  }
  return rows;
}

String problemLetter(int i) => i < 26 ? String.fromCharCode(65 + i) : 'P${i + 1}';
