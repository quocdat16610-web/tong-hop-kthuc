// Biên dịch & chạy C++: g++ trên máy (Windows/Linux/macOS) hoặc Compiler Explorer online (Android).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'judge.dart';
import 'vcs.dart' show newId;

final bool isWin = Platform.isWindows;

class CompilerInfo {
  final String path, version;
  CompilerInfo(this.path, this.version);
}

/// Thư mục chứa app (để tìm g++ đi kèm: <thư mục app>/mingw64/bin/g++.exe).
String get appDir => p.dirname(Platform.resolvedExecutable);

List<String> compilerCandidates(String? custom) {
  final list = <String>[];
  if (custom != null && custom.isNotEmpty) list.add(custom);
  list.add(p.join(appDir, 'mingw64', 'bin', isWin ? 'g++.exe' : 'g++'));
  list.add(isWin ? 'g++.exe' : 'g++');
  if (isWin) {
    final bases = [Platform.environment['ProgramFiles'], Platform.environment['ProgramFiles(x86)'], r'C:\'].whereType<String>();
    const rel = [r'mingw64\bin', r'MinGW\bin', r'msys64\ucrt64\bin', r'msys64\mingw64\bin', r'Dev-Cpp\MinGW64\bin', r'Embarcadero\Dev-Cpp\TDM-GCC-64\bin', r'CodeBlocks\MinGW\bin', r'TDM-GCC-64\bin'];
    for (final b in bases) {
      for (final r in rel) {
        list.add(p.join(b, r, 'g++.exe'));
      }
    }
  } else if (Platform.isMacOS) {
    list.addAll(['/opt/homebrew/bin/g++', '/usr/local/bin/g++', '/usr/bin/clang++']);
  }
  return list.toSet().toList();
}

Future<String?> _version(String exe) async {
  try {
    final r = await Process.run(exe, ['--version']).timeout(const Duration(seconds: 8));
    if (r.exitCode != 0) return null;
    return (r.stdout as String).split('\n').first.trim();
  } catch (_) {
    return null;
  }
}

Future<CompilerInfo?> findCompiler(String? custom) async {
  if (Platform.isAndroid || Platform.isIOS) return null;
  for (final c in compilerCandidates(custom)) {
    if (p.isAbsolute(c) && !File(c).existsSync()) continue;
    final v = await _version(c);
    if (v != null) return CompilerInfo(c, v);
  }
  return null;
}

/// Python: bản đi kèm app (Windows: <thư mục app>/python/python.exe), hoặc python3 / python trên máy.
List<String> pythonCandidates(String? custom) => [
      if (custom != null && custom.isNotEmpty) custom,
      p.join(appDir, 'python', isWin ? 'python.exe' : 'bin/python3'),
      if (!isWin) 'python3',
      isWin ? 'python.exe' : 'python',
      if (isWin)
        for (final v in ['313', '312', '311', '310']) ...[
          if (Platform.environment['LOCALAPPDATA'] != null) p.join(Platform.environment['LOCALAPPDATA']!, 'Programs', 'Python', 'Python$v', 'python.exe'),
          if (Platform.environment['ProgramFiles'] != null) p.join(Platform.environment['ProgramFiles']!, 'Python$v', 'python.exe'),
        ],
    ];

Future<CompilerInfo?> findPython(String? custom) async {
  if (Platform.isAndroid || Platform.isIOS) return null;
  for (final c in pythonCandidates(custom)) {
    if (p.isAbsolute(c) && !File(c).existsSync()) continue;
    final v = await _version(c);
    // Bỏ qua "python" giả của Microsoft Store (in ra lời nhắc cài đặt thay vì phiên bản).
    if (v != null && v.startsWith('Python 3')) return CompilerInfo(c, v);
  }
  return null;
}

Future<CompilerInfo?> findGdb(String? gppPath) async {
  if (Platform.isAndroid || Platform.isIOS) return null;
  final cands = <String>[];
  if (gppPath != null && p.isAbsolute(gppPath)) cands.add(p.join(p.dirname(gppPath), isWin ? 'gdb.exe' : 'gdb'));
  cands.add(isWin ? 'gdb.exe' : 'gdb');
  for (final c in cands) {
    if (p.isAbsolute(c) && !File(c).existsSync()) continue;
    final v = await _version(c);
    if (v != null) return CompilerInfo(c, v);
  }
  return null;
}

List<String> splitFlags(String s) =>
    RegExp(r'"[^"]*"|\S+').allMatches(s).map((m) => m.group(0)!.replaceAll(RegExp(r'^"|"$'), '')).toList();

class Program {
  final String dir, exe, src, gppDir;
  final List<String> args;
  final bool python;
  Program(this.dir, this.exe, this.src, this.gppDir, {this.args = const [], this.python = false});
}

/// Chấm / chạy bằng g++ trên máy.
class LocalBackend implements Backend {
  final String gpp;
  final String flags;
  final String? python;
  LocalBackend(this.gpp, this.flags, {this.python});

  static final Map<String, Program> programs = {};
  static Directory get work => Directory(p.join(Directory.systemTemp.path, 'so-tay-dsa-judge'));

  @override
  String get name => 'g++ trên máy';
  @override
  bool get local => true;
  @override
  int get parallel => 2;

  Map<String, String> _env(String gppDir) {
    final env = Map<String, String>.from(Platform.environment);
    final key = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    env[key] = '$gppDir${isWin ? ';' : ':'}${env[key] ?? ''}';
    return env;
  }

  // Header chèn vào bản build của IDE: tắt bộ đệm stdout để output hiện ngay.
  static String unbufHeader() {
    final f = File(p.join(work.path, 'dsa_unbuffered.h'));
    if (!f.existsSync()) {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('#include <cstdio>\nstatic void __attribute__((constructor)) dsa_unbuffered_stdout() { std::setvbuf(stdout, nullptr, _IONBF, 0); }\n');
    }
    return f.path;
  }

  @override
  Future<CompileResult> compile(String source, {String? includeDir, bool debug = false, bool unbuffered = false, String lang = 'cpp'}) async {
    if (lang == 'py') return _compilePython(source, includeDir);
    final id = newId();
    final dir = Directory(p.join(work.path, id))..createSync(recursive: true);
    final src = p.join(dir.path, 'main.cpp');
    final exe = p.join(dir.path, isWin ? 'main.exe' : 'main');
    File(src).writeAsStringSync(source);
    var base = splitFlags(flags.isEmpty ? '-O2 -std=c++17' : flags);
    if (debug) base = [...base.where((f) => !f.startsWith('-O')), '-g', '-O0'];
    final args = [...base, src, '-o', exe];
    if (includeDir != null && Directory(includeDir).existsSync()) args.addAll(['-I', includeDir]);
    if (unbuffered || debug) args.addAll(['-include', unbufHeader()]);
    // Windows: ngăn xếp lớn như Codeforces và liên kết tĩnh (không cần DLL của MinGW).
    if (isWin) args.addAll(['-Wl,--stack,268435456', '-static']);
    try {
      final r = await Process.run(gpp, args, workingDirectory: dir.path, environment: _env(p.dirname(gpp)))
          .timeout(const Duration(seconds: 60));
      final err = (r.stderr as String).split(src).join('main.cpp');
      if (r.exitCode != 0 || !File(exe).existsSync()) {
        dir.deleteSync(recursive: true);
        return CompileResult.fail(err.isEmpty ? 'Biên dịch thất bại' : err);
      }
      programs[id] = Program(dir.path, exe, src, p.dirname(gpp));
      return CompileResult.ok(id, err);
    } on TimeoutException {
      return CompileResult.fail('Biên dịch quá 60 giây.');
    } catch (e) {
      return CompileResult.fail('Không chạy được trình biên dịch: $e');
    }
  }

  /// Python không cần biên dịch: chỉ kiểm tra cú pháp (lỗi cú pháp → "Compilation error" như Codeforces).
  Future<CompileResult> _compilePython(String source, String? includeDir) async {
    final py = python;
    if (py == null) return CompileResult.fail('Không tìm thấy Python trên máy. Cài Python 3 (python.org) hoặc chọn đường dẫn trong Cài đặt.');
    final id = newId();
    final dir = Directory(p.join(work.path, id))..createSync(recursive: true);
    final src = p.join(dir.path, 'main.py');
    File(src).writeAsStringSync(source);
    // Cho phép import file .py cạnh file đang mở (giống -I của C++).
    if (includeDir != null && Directory(includeDir).existsSync()) {
      for (final f in Directory(includeDir).listSync().whereType<File>().where((f) => f.path.endsWith('.py'))) {
        final dst = p.join(dir.path, p.basename(f.path));
        if (!File(dst).existsSync()) f.copySync(dst);
      }
    }
    try {
      final r = await Process.run(py, ['-c', 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read(), "main.py")', src], workingDirectory: dir.path, environment: _pyEnv())
          .timeout(const Duration(seconds: 30));
      if (r.exitCode != 0) {
        dir.deleteSync(recursive: true);
        return CompileResult.fail(_pyError('${r.stderr}'));
      }
    } on TimeoutException {
      return CompileResult.fail('Kiểm tra cú pháp Python quá lâu.');
    } catch (e) {
      return CompileResult.fail('Không chạy được Python: $e');
    }
    programs[id] = Program(dir.path, py, src, p.dirname(py), args: ['-u', 'main.py'], python: true);
    return CompileResult.ok(id);
  }

  static Map<String, String> _pyEnv() => {...Platform.environment, 'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1', 'PYTHONDONTWRITEBYTECODE': '1'};

  /// Gọn thông báo lỗi Python: bỏ dòng traceback nội bộ của trình kiểm tra.
  static String _pyError(String err) {
    final lines = const LineSplitter().convert(err);
    final i = lines.indexWhere((l) => l.contains('File "main.py"'));
    return (i >= 0 ? lines.sublist(i) : lines).join('\n').trim();
  }

  Future<Process> spawn(String id) {
    final prog = programs[id];
    if (prog == null) throw StateError('Chương trình chưa được biên dịch');
    if (prog.python) return Process.start(prog.exe, prog.args, workingDirectory: prog.dir, environment: _pyEnv());
    return Process.start(prog.exe, prog.args, workingDirectory: prog.dir, environment: _env(prog.gppDir));
  }

  @override
  Future<RunResult> run(String id, String input, int timeLimitMs) async {
    final Process proc;
    try {
      proc = await spawn(id);
    } catch (e) {
      return RunResult(stderr: '$e', exitCode: -1);
    }
    final sw = Stopwatch()..start();
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    var size = 0;
    var tooBig = false;
    var timedOut = false;
    final killer = Timer(Duration(milliseconds: timeLimitMs + 500), () {
      timedOut = true;
      proc.kill(ProcessSignal.sigkill);
    });
    final o = proc.stdout.listen((d) {
      size += d.length;
      if (size > 64 * 1024 * 1024) {
        tooBig = true;
        proc.kill(ProcessSignal.sigkill);
      } else {
        out.add(d);
      }
    }).asFuture<void>();
    final e = proc.stderr.listen((d) {
      if (err.length < 20000) err.add(d);
    }).asFuture<void>();
    try {
      proc.stdin.add(utf8.encode(input));
      await proc.stdin.close();
    } catch (_) {/* chương trình thoát trước khi đọc hết input */}
    final code = await proc.exitCode;
    sw.stop();
    killer.cancel();
    await Future.wait([o, e]).catchError((_) => <void>[]);
    return RunResult(
      stdout: utf8.decode(out.takeBytes(), allowMalformed: true),
      stderr: utf8.decode(err.takeBytes(), allowMalformed: true) + (tooBig ? '\nOutput quá lớn (> 64 MB).' : ''),
      exitCode: code,
      timeMs: sw.elapsedMilliseconds,
      timedOut: timedOut || sw.elapsedMilliseconds > timeLimitMs,
    );
  }

  @override
  void dispose(String id) {
    final prog = programs.remove(id);
    if (prog == null) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        Directory(prog.dir).deleteSync(recursive: true);
      } catch (_) {}
    });
  }

  static void cleanupAll() {
    try {
      if (work.existsSync()) work.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Chạy online bằng Compiler Explorer (godbolt.org) — dùng trên Android hoặc khi máy không có g++.
class OnlineBackend implements Backend {
  final String compiler, flags;
  OnlineBackend({this.compiler = 'g132', this.flags = '-O2 -std=c++17'});
  static final Map<String, String> _sources = {};
  static final Map<String, String> _langs = {};
  static String? _pyCompiler;

  /// Chọn trình thông dịch Python mới nhất có hỗ trợ chạy trên Compiler Explorer.
  static Future<String> pythonCompiler() async {
    if (_pyCompiler != null) return _pyCompiler!;
    try {
      final r = await http.get(Uri.parse('https://godbolt.org/api/compilers/python?fields=id,name,supportsExecute'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
      final list = (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map>().where((c) => c['supportsExecute'] == true).map((c) => '${c['id']}').toList()..sort();
      final best = list.where((x) => RegExp(r'^python3\d+$').hasMatch(x)).toList()
        ..sort((a, b) => int.parse(a.substring(7)).compareTo(int.parse(b.substring(7))));
      _pyCompiler = best.isNotEmpty ? best.last : (list.isNotEmpty ? list.last : 'python312');
    } catch (_) {
      _pyCompiler = 'python312';
    }
    return _pyCompiler!;
  }

  @override
  String get name => 'Compiler Explorer (online)';
  @override
  bool get local => false;
  @override
  int get parallel => 3;

  @override
  Future<CompileResult> compile(String source, {String? includeDir, bool debug = false, bool unbuffered = false, String lang = 'cpp'}) async {
    final id = newId();
    _sources[id] = source;
    _langs[id] = lang;
    return CompileResult.ok(id);
  }

  @override
  Future<RunResult> run(String id, String input, int timeLimitMs) async {
    final py = _langs[id] == 'py';
    final comp = py ? await pythonCompiler() : compiler;
    final res = await http
        .post(Uri.parse('https://godbolt.org/api/compiler/${Uri.encodeComponent(comp)}/compile'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'source': _sources[id] ?? '',
              'options': {
                'userArguments': py ? '' : flags,
                'executeParameters': {'args': [], 'stdin': input},
                'compilerOptions': {'executorRequest': true},
                'filters': {'execute': true},
                'tools': [],
                'libraries': [],
              },
              'lang': py ? 'python' : 'c++',
              'allowStoreCodeDebug': false,
            }))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw Exception('Máy chủ biên dịch trả lỗi ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final exec = (data['execResult'] ?? data) as Map;
    final build = (exec['buildResult'] ?? data['buildResult'] ?? {}) as Map;
    String text(dynamic arr) => ((arr ?? []) as List).map((x) => (x as Map)['text']).join('\n');
    if (build['code'] != null && build['code'] != 0) {
      final e = text(build['stderr']);
      return RunResult(compileError: e.isEmpty ? 'Biên dịch thất bại' : e);
    }
    final timeMs = int.tryParse('${exec['execTime'] ?? 0}') ?? 0;
    return RunResult(
      stdout: text(exec['stdout']),
      stderr: text(exec['stderr']),
      exitCode: (exec['code'] ?? 0) as int,
      timeMs: timeMs,
      timedOut: exec['timedOut'] == true || timeMs > timeLimitMs,
      warnings: text(build['stderr']),
    );
  }

  @override
  void dispose(String id) {
    _sources.remove(id);
    _langs.remove(id);
  }
}
