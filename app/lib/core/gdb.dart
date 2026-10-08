// Gỡ lỗi từng dòng bằng gdb ở chế độ máy (GDB/MI) — giống Code::Blocks.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runner.dart';

// ---------- Đọc dòng GDB/MI ----------
class MiRecord {
  final int? token;
  final String kind; // ^ * = + ~ @ & hoặc 'text'
  final String cls;
  final Map<String, dynamic> data;
  final String text;
  MiRecord(this.token, this.kind, {this.cls = '', this.data = const {}, this.text = ''});
}

(String, int) _cstring(String s, int i) {
  final out = StringBuffer();
  i++;
  while (i < s.length && s[i] != '"') {
    if (s[i] == r'\' && i + 1 < s.length) {
      final c = s[i + 1];
      if (c == 'n') {
        out.write('\n');
      } else if (c == 't') {
        out.write('\t');
      } else if (c == 'r') {
        out.write('\r');
      } else if (RegExp(r'[0-7]').hasMatch(c)) {
        final m = RegExp(r'^[0-7]{1,3}').firstMatch(s.substring(i + 1))!;
        out.writeCharCode(int.parse(m.group(0)!, radix: 8));
        i += m.group(0)!.length - 1;
      } else {
        out.write(c);
      }
      i += 2;
    } else {
      out.write(s[i++]);
    }
  }
  return (out.toString(), i + 1);
}

(dynamic, int) _value(String s, int i) {
  if (s[i] == '"') return _cstring(s, i);
  if (s[i] == '{') {
    final obj = <String, dynamic>{};
    i++;
    if (s[i] == '}') return (obj, i + 1);
    while (true) {
      final (k, v, j) = _result(s, i);
      obj[k] = v;
      i = j;
      if (s[i] == ',') {
        i++;
      } else {
        return (obj, i + 1);
      }
    }
  }
  if (s[i] == '[') {
    final arr = <dynamic>[];
    i++;
    if (s[i] == ']') return (arr, i + 1);
    while (true) {
      if (s[i] == '"' || s[i] == '{' || s[i] == '[') {
        final (v, j) = _value(s, i);
        arr.add(v);
        i = j;
      } else {
        final (_, v, j) = _result(s, i);
        arr.add(v);
        i = j;
      }
      if (s[i] == ',') {
        i++;
      } else {
        return (arr, i + 1);
      }
    }
  }
  throw FormatException('MI: ký tự lạ ở vị trí $i');
}

(String, dynamic, int) _result(String s, int i) {
  final eq = s.indexOf('=', i);
  final (v, j) = _value(s, eq + 1);
  return (s.substring(i, eq), v, j);
}

MiRecord? parseMiLine(String line) {
  line = line.replaceAll(RegExp(r'\r$'), '');
  if (line.isEmpty || line.startsWith('(gdb)')) return null;
  final m = RegExp(r'^(\d*)([\^*=+~@&])(.*)$').firstMatch(line);
  if (m == null) return MiRecord(null, 'text', text: line);
  final token = m.group(1)!.isEmpty ? null : int.parse(m.group(1)!);
  final kind = m.group(2)!;
  final rest = m.group(3)!;
  if (kind == '~' || kind == '@' || kind == '&') {
    try {
      return MiRecord(token, kind, text: _cstring(rest, 0).$1);
    } catch (_) {
      return MiRecord(token, kind, text: rest);
    }
  }
  final comma = rest.indexOf(',');
  final cls = comma == -1 ? rest : rest.substring(0, comma);
  final data = <String, dynamic>{};
  if (comma != -1) {
    var i = comma + 1;
    while (i < rest.length) {
      final (k, v, j) = _result(rest, i);
      data[k] = v;
      i = j;
      if (i < rest.length && rest[i] == ',') {
        i++;
      } else {
        break;
      }
    }
  }
  return MiRecord(token, kind, cls: cls, data: data);
}

// ---------- Phiên gỡ lỗi ----------
class DebugVar {
  final String name, value;
  final bool arg;
  DebugVar(this.name, this.value, this.arg);
}

class DebugFrame {
  final String func;
  final int? line;
  final int level;
  final bool user;
  DebugFrame(this.func, this.line, this.level, this.user);
}

sealed class DebugEvent {}

class DebugRunning extends DebugEvent {}

class DebugStopped extends DebugEvent {
  final String reason;
  final String? signal;
  final int? line;
  final String func;
  final List<DebugFrame> frames;
  final List<DebugVar> locals;
  final String output;
  DebugStopped(this.reason, this.signal, this.line, this.func, this.frames, this.locals, this.output);
}

class DebugExited extends DebugEvent {
  final int code;
  final String output;
  DebugExited(this.code, this.output);
}

class DebugEnded extends DebugEvent {
  final String? error;
  DebugEnded([this.error]);
}

class DebugLog extends DebugEvent {
  final String text;
  DebugLog(this.text);
}

class DebugSession {
  final String gdb;
  final String progId;
  final String input;
  final List<int> initialBreakpoints;
  final void Function(DebugEvent) onEvent;
  late final Program prog;
  Process? _proc;
  int _token = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, String> _bps = {}; // dòng -> số hiệu breakpoint
  String? _lastCmd;
  bool done = false;

  DebugSession({required this.gdb, required this.progId, required this.input, required this.initialBreakpoints, required this.onEvent}) {
    final pr = LocalBackend.programs[progId];
    if (pr == null) throw StateError('Chương trình chưa được biên dịch');
    prog = pr;
  }

  Future<void> start() async {
    File(p.join(prog.dir, 'input.txt')).writeAsStringSync(input);
    File(p.join(prog.dir, 'output.txt')).writeAsStringSync('');
    final env = Map<String, String>.from(Platform.environment);
    final key = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    env[key] = '${prog.gppDir}${isWin ? ';' : ':'}${env[key] ?? ''}';
    final proc = await Process.start(gdb, ['--interpreter=mi2', '--quiet', '--nx', prog.exe], workingDirectory: prog.dir, environment: env);
    _proc = proc;
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    proc.stderr.drain<void>();
    proc.exitCode.then((_) => _finish());
    await _cmd('-gdb-set confirm off');
    await _cmd('-gdb-set print pretty off');
    if (isWin) await _cmd('-gdb-set new-console off').catchError((_) => <String, dynamic>{});
    for (final l in initialBreakpoints) {
      await addBreakpoint(l);
    }
    if (initialBreakpoints.isEmpty) await _cmd('-break-insert -t main'); // dừng ở đầu main như Thonny
    await _cmd('-exec-arguments < input.txt > output.txt');
    _lastCmd = 'run';
    await _cmd('-exec-run');
  }

  Future<Map<String, dynamic>> _cmd(String text) {
    if (done || _proc == null) return Future.error(StateError('Phiên gỡ lỗi đã kết thúc'));
    final t = _token++;
    final c = Completer<Map<String, dynamic>>();
    _pending[t] = c;
    _proc!.stdin.writeln('$t$text');
    return c.future;
  }

  void _onLine(String line) {
    MiRecord? rec;
    try {
      rec = parseMiLine(line);
    } catch (_) {
      rec = null;
    }
    if (rec == null) return;
    if (rec.kind == '^' && rec.token != null && _pending.containsKey(rec.token)) {
      final c = _pending.remove(rec.token)!;
      if (rec.cls == 'error') {
        c.completeError(Exception(rec.data['msg'] ?? 'gdb error'));
      } else {
        c.complete(rec.data);
      }
    } else if (rec.kind == '*' && rec.cls == 'running') {
      onEvent(DebugRunning());
    } else if (rec.kind == '*' && rec.cls == 'stopped') {
      _onStopped(rec.data).catchError((e) => onEvent(DebugLog('$e')));
    }
  }

  String _output() {
    try {
      final f = File(p.join(prog.dir, 'output.txt'));
      final bytes = f.readAsBytesSync();
      final start = bytes.length > 256 * 1024 ? bytes.length - 256 * 1024 : 0;
      return utf8.decode(bytes.sublist(start), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  bool _isUser(Map? f) => f != null && f['file'] != null && p.basename((f['file'] as String).replaceAll(r'\', '/')) == 'main.cpp';

  Future<void> _onStopped(Map<String, dynamic> data) async {
    final reason = (data['reason'] ?? '') as String;
    if (reason.startsWith('exited')) {
      final code = reason == 'exited-normally' ? 0 : int.tryParse('${data['exit-code'] ?? '1'}', radix: 8) ?? 1;
      onEvent(DebugExited(code, _output()));
      stop();
      return;
    }
    // Bước vào thư viện chuẩn (vd. cout) thì tự đi ra lại code của người dùng.
    if (!_isUser(data['frame'] as Map?) && (_lastCmd == 'step' || _lastCmd == 'next') && reason == 'end-stepping-range') {
      _lastCmd = 'finish';
      await _cmd('-exec-finish').catchError((_) => _cmd('-exec-next'));
      return;
    }
    final stack = ((await _cmd('-stack-list-frames').catchError((_) => <String, dynamic>{}))['stack'] ?? []) as List;
    final frames = stack.cast<Map>().map((f) => DebugFrame((f['func'] ?? '?') as String, int.tryParse('${f['line']}'), int.parse('${f['level']}'), _isUser(f))).toList();
    final top = frames.where((f) => f.user).firstOrNull;
    var locals = <DebugVar>[];
    if (top != null) {
      if (top.level > 0) await _cmd('-stack-select-frame ${top.level}').catchError((_) => <String, dynamic>{});
      final v = await _cmd('-stack-list-variables --all-values').catchError((_) => <String, dynamic>{});
      locals = ((v['variables'] ?? []) as List).cast<Map>().map((x) => DebugVar(x['name'] as String, (x['value'] ?? '…') as String, x['arg'] != null)).toList();
    }
    onEvent(DebugStopped(
      reason,
      data['signal-name'] != null ? '${data['signal-name']} (${data['signal-meaning'] ?? ''})' : null,
      top?.line,
      top?.func ?? ((data['frame'] as Map?)?['func'] ?? '?') as String,
      frames.where((f) => f.user).toList(),
      locals,
      _output(),
    ));
  }

  Future<void> addBreakpoint(int line) async {
    if (_bps.containsKey(line) || done) return;
    try {
      final r = await _cmd('-break-insert --source main.cpp --line $line');
      final b = r['bkpt'] as Map?;
      if (b != null) _bps[line] = '${b['number']}';
    } catch (_) {}
  }

  Future<void> removeBreakpoint(int line) async {
    final n = _bps.remove(line);
    if (n == null || done) return;
    await _cmd('-break-delete $n').catchError((_) => <String, dynamic>{});
  }

  Future<void> control(String action) async {
    const map = {'continue': '-exec-continue', 'next': '-exec-next', 'step': '-exec-step', 'finish': '-exec-finish'};
    final c = map[action];
    if (c == null || done) return;
    _lastCmd = action;
    await _cmd(c).catchError((e) {
      onEvent(DebugLog('$e'));
      return <String, dynamic>{};
    });
  }

  void stop() {
    if (done) return;
    try {
      _proc?.stdin.writeln('-gdb-exit');
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 500), () => _proc?.kill(ProcessSignal.sigkill));
  }

  void _finish([String? error]) {
    if (done) return;
    done = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('gdb đã thoát'));
    }
    _pending.clear();
    onEvent(DebugEnded(error));
    LocalBackend.programs.remove(progId);
  }
}
