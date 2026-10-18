// IDE kiểu Code::Blocks / Thonny: nhiều tab, Build/Run, console tương tác, báo lỗi theo dòng, gỡ lỗi từng dòng bằng gdb.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../app_state.dart';
import '../core/gdb.dart';
import '../core/judge.dart';
import '../core/runner.dart';
import '../core/storage.dart';
import '../core/templates.dart';
import '../core/vcs.dart';
import 'blocks.dart' show newBlock;
import 'code_editor.dart';
import 'extras.dart' show pickSnippet;
import 'theme.dart';
import 'widgets.dart';

class IdeTab {
  String name;
  String? path; // file trên ổ đĩa (desktop)
  String? fileId; // file lưu trong app
  final CodeLineEditingController ctl;
  String saved;
  final ValueNotifier<EditorMarks> marks = ValueNotifier(const EditorMarks());
  final FocusNode focus = FocusNode();
  IdeTab({required this.name, this.path, this.fileId, required String code, String? savedText}) : ctl = CodeLineEditingController.fromText(code), saved = savedText ?? code;
  bool get dirty => ctl.text != saved;
  String get lang => name.endsWith('.js') ? 'js' : name.endsWith('.py') ? 'py' : 'cpp';
  void dispose() {
    ctl.dispose();
    marks.dispose();
    focus.dispose();
  }
}

class BuildMsg {
  final String file, kind, text;
  final int line, col;
  BuildMsg(this.file, this.line, this.col, this.kind, this.text);
}

final _msgRe = RegExp(r'^(.*?):(\d+):(\d+): (fatal error|error|warning|note): (.*)$');
final _pyRe = RegExp(r'^\s*File "(.*?)", line (\d+)');

List<BuildMsg> parseBuildLog(String log) {
  final lines = const LineSplitter().convert(log);
  final out = <BuildMsg>[
    for (final l in lines)
      if (_msgRe.firstMatch(l) case final m?) BuildMsg(p.basename(m[1]!), int.parse(m[2]!), int.parse(m[3]!), m[4]!.replaceFirst('fatal ', ''), m[5]!),
  ];
  // Lỗi Python: dòng 'File "main.py", line N' (lấy dòng cuối cùng của traceback) + câu báo lỗi ở cuối.
  final last = lines.lastWhere((l) => RegExp(r'^\w*(Error|Exception)\b').hasMatch(l.trim()), orElse: () => '');
  for (var i = lines.length - 1; i >= 0; i--) {
    final m = _pyRe.firstMatch(lines[i]);
    if (m != null) {
      out.add(BuildMsg(p.basename(m[1]!.replaceAll('\\', '/')), int.parse(m[2]!), 1, 'error', last.isEmpty ? 'Lỗi Python' : last.trim()));
      break;
    }
  }
  return out;
}

/// Trạng thái IDE (giữ lại khi chuyển qua lại giữa Sổ tay và IDE).
class IdeModel extends ChangeNotifier {
  final List<IdeTab> tabs = [];
  int active = 0;
  String? folder;
  String console = '';
  String buildLog = '';
  List<BuildMsg> msgs = [];
  final input = TextEditingController();
  int bottomTab = 0; // 0 console, 1 input, 2 build log, 3 biến
  String status = 'Sẵn sàng';
  bool busy = false;
  Process? proc;
  String? runningId;
  Backend? runningBackend;
  DebugSession? dbg;
  DebugStopped? stopped;
  final consoleScroll = ScrollController();
  final stdinFocus = FocusNode();
  Timer? _saveTimer;

  IdeTab? get tab => tabs.isEmpty ? null : tabs[active.clamp(0, tabs.length - 1)];

  IdeModel() {
    final s = Storage.I.readKv('ide', {});
    folder = s['folder'] as String?;
    input.text = (s['input'] ?? '') as String;
    for (final t in ((s['tabs'] ?? []) as List).cast<Map>()) {
      final path = t['path'] as String?;
      var code = (t['code'] ?? '') as String;
      var saved = (t['saved'] ?? code) as String;
      if (path != null && File(path).existsSync() && code == saved) code = saved = File(path).readAsStringSync();
      _add(IdeTab(name: t['name'] as String, path: path, fileId: t['fileId'] as String?, code: code, savedText: saved));
    }
    active = ((s['active'] ?? 0) as int).clamp(0, tabs.isEmpty ? 0 : tabs.length - 1);
    if (tabs.isEmpty) newFile();
  }

  void _add(IdeTab t) {
    tabs.add(t);
    t.ctl.addListener(() {
      if (t.marks.value.errors.isNotEmpty && !busy) t.marks.value = t.marks.value.copyWith(errors: {});
      _persist();
    });
  }

  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), saveSession);
    notifyListeners();
  }

  void saveSession() {
    _saveTimer?.cancel();
    Storage.I.writeKv('ide', {
      'folder': folder,
      'active': active,
      'input': input.text,
      'tabs': [
        for (final t in tabs) {'name': t.name, 'path': t.path, 'fileId': t.fileId, 'code': t.ctl.text, 'saved': t.saved},
      ],
    });
  }

  void select(int i) {
    active = i;
    _persist();
  }

  void newFile([String? name, String code = ideNewCode, String ext = 'cpp']) {
    var n = name ?? 'main.$ext';
    if (name == null) {
      var k = 1;
      while (tabs.any((t) => t.name == n)) {
        n = 'main${++k}.$ext';
      }
    }
    _add(IdeTab(name: n, code: code, savedText: ''));
    active = tabs.length - 1;
    _persist();
  }

  void openCode(String name, String code) {
    final n = name.contains('.') ? name : '${slugify(name).isEmpty ? 'code' : slugify(name)}.cpp';
    newFile(n, code);
  }

  void openPath(String path) {
    final i = tabs.indexWhere((t) => t.path == path);
    if (i != -1) return select(i);
    final text = File(path).readAsStringSync();
    _add(IdeTab(name: p.basename(path), path: path, code: text));
    active = tabs.length - 1;
    _persist();
  }

  void openStored(Json f) {
    final i = tabs.indexWhere((t) => t.fileId == f['id']);
    if (i != -1) return select(i);
    _add(IdeTab(name: f['name'] as String, fileId: f['id'] as String, code: f['code'] as String));
    active = tabs.length - 1;
    _persist();
  }

  void close(int i) {
    final t = tabs.removeAt(i);
    t.dispose();
    if (tabs.isEmpty) newFile();
    active = active.clamp(0, tabs.length - 1);
    if (active > i) active--;
    active = active.clamp(0, tabs.length - 1);
    _persist();
  }

  /// Lưu: desktop ghi file; Android (hoặc file chưa có đường dẫn trên điện thoại) lưu trong app.
  Future<bool> save(IdeTab t, {bool saveAs = false}) async {
    if (t.path == null || saveAs) {
      if (Platform.isAndroid || Platform.isIOS) {
        t.fileId ??= newId();
        Storage.I.putFile({'id': t.fileId, 'name': t.name, 'code': t.ctl.text});
        t.saved = t.ctl.text;
        _persist();
        return true;
      }
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Lưu file', fileName: t.name, initialDirectory: folder, type: FileType.custom, allowedExtensions: ['cpp', 'py', 'h', 'hpp', 'c', 'txt']);
      if (path == null) return false;
      t.path = path;
      t.name = p.basename(path);
    }
    await File(t.path!).writeAsString(t.ctl.text);
    t.saved = t.ctl.text;
    _persist();
    return true;
  }

  void log(String s) {
    console += s;
    if (console.length > 300000) console = console.substring(console.length - 250000);
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (consoleScroll.hasClients) consoleScroll.jumpTo(consoleScroll.position.maxScrollExtent);
    });
  }

  void setStatus(String s) {
    status = s;
    notifyListeners();
  }

  // ---------- Build / Run ----------
  Future<(Backend, String)?> build(AppState app, {bool debug = false}) async {
    final t = tab;
    if (t == null || busy) return null;
    stopAll();
    busy = true;
    for (final x in tabs) {
      x.marks.value = x.marks.value.copyWith(errors: {}, clearCurrent: true);
    }
    setStatus('Đang biên dịch ${t.name}…');
    final sw = Stopwatch()..start();
    try {
      final Backend be;
      if (debug) {
        final info = await app.detectCompiler();
        if (info == null) throw Exception('Cần g++ trên máy để gỡ lỗi. Xem Cài đặt.');
        be = LocalBackend(info.path, app.setting('cppFlags', '-O2 -std=c++17'));
      } else {
        be = await app.backend(lang: t.lang == 'py' ? 'py' : 'cpp');
      }
      final dir = t.path != null ? p.dirname(t.path!) : folder;
      final r = await be.compile(t.ctl.text, includeDir: dir, debug: debug, unbuffered: true, lang: t.lang == 'py' ? 'py' : 'cpp');
      final text = r.ok ? r.warnings : r.error;
      buildLog =
          '-------------- Build: ${t.name} (${be.name}) --------------\n${text.trim().isEmpty ? '' : '${text.trimRight()}\n'}'
          '${r.ok ? 'Build xong: 0 lỗi' : 'Build thất bại'} (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} giây)\n';
      _applyMsgs(text);
      if (!r.ok) {
        bottomTab = 2;
        setStatus('Lỗi biên dịch');
        return null;
      }
      setStatus('Build xong');
      return (be, r.id);
    } catch (e) {
      buildLog = '$e\n';
      bottomTab = 2;
      setStatus('Không biên dịch được');
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _applyMsgs(String text) {
    msgs = parseBuildLog(text);
    final t = tab!;
    final errs = {
      for (final m in msgs)
        if (m.kind == 'error' && (m.file == 'main.cpp' || m.file == 'main.py')) m.line - 1,
    };
    t.marks.value = t.marks.value.copyWith(errors: errs);
  }

  void goTo(int line, [int col = 1]) {
    final t = tab;
    if (t == null) return;
    final idx = (line - 1).clamp(0, t.ctl.codeLines.length - 1);
    final off = (col - 1).clamp(0, t.ctl.codeLines[idx].text.length);
    t.ctl.selection = CodeLineSelection.collapsed(index: idx, offset: off);
    t.ctl.makeCursorCenterIfInvisible();
    t.focus.requestFocus();
  }

  Future<void> run(AppState app) async {
    final b = await build(app);
    if (b == null) return;
    final (be, id) = b;
    final name = tab!.name;
    console = '';
    bottomTab = 0;
    if (be is LocalBackend) {
      final sw = Stopwatch()..start();
      try {
        final pr = await be.spawn(id);
        proc = pr;
        runningId = id;
        runningBackend = be;
        setStatus('Đang chạy $name — gõ dữ liệu vào ô bên dưới console');
        WidgetsBinding.instance.addPostFrameCallback((_) => stdinFocus.requestFocus());
        final dec1 = const Utf8Decoder(allowMalformed: true);
        final dec2 = const Utf8Decoder(allowMalformed: true);
        final o = pr.stdout.transform(dec1).listen(log).asFuture<void>();
        final e = pr.stderr.transform(dec2).listen(log).asFuture<void>();
        final code = await pr.exitCode;
        await Future.wait([o, e]).catchError((_) => <void>[]);
        if (proc == pr) {
          // Python lỗi khi chạy: đánh dấu dòng gây lỗi trong traceback để bấm vào là nhảy tới.
          if (code != 0 && tab?.lang == 'py') {
            final ms = parseBuildLog(console).where((m) => m.file == 'main.py').toList();
            if (ms.isNotEmpty) {
              msgs = ms;
              tab!.marks.value = tab!.marks.value.copyWith(errors: {ms.last.line - 1});
            }
          }
          log('\n\n[Chương trình kết thúc · mã thoát $code · ${sw.elapsedMilliseconds} ms]\n');
          setStatus(code == 0 ? 'Chạy xong' : 'Chương trình lỗi (mã thoát $code)');
          proc = null;
        }
      } catch (e) {
        log('Không chạy được: $e\n');
      } finally {
        be.dispose(id);
        if (runningId == id) runningId = null;
        notifyListeners();
      }
    } else {
      setStatus('Đang chạy online…');
      busy = true;
      notifyListeners();
      try {
        final r = await be.run(id, input.text, 10000);
        if (r.compileError != null) {
          buildLog = r.compileError!;
          _applyMsgs(r.compileError!);
          bottomTab = 2;
          setStatus('Lỗi biên dịch');
        } else {
          if (input.text.isNotEmpty) log('[Input lấy từ tab "Input"]\n');
          log(r.stdout);
          if (r.stderr.isNotEmpty) log('\n[stderr]\n${r.stderr}');
          log('\n\n[${r.timedOut ? 'Quá thời gian' : 'Kết thúc · mã thoát ${r.exitCode} · ${r.timeMs} ms'}]\n');
          setStatus('Chạy xong (online)');
        }
      } catch (e) {
        log('Không chạy được: $e\nCần Internet để biên dịch online.\n');
        setStatus('Lỗi mạng');
      } finally {
        busy = false;
        be.dispose(id);
        notifyListeners();
      }
    }
  }

  void sendInput(String line) {
    final pr = proc;
    if (pr == null) return;
    log('$line\n');
    try {
      pr.stdin.writeln(line);
    } catch (_) {}
  }

  void stopAll() {
    if (proc != null) {
      proc!.kill(ProcessSignal.sigkill);
      proc = null;
      log('\n[Đã dừng]\n');
      setStatus('Đã dừng');
    }
    dbg?.stop();
  }

  // ---------- Gỡ lỗi ----------
  Future<void> debug(AppState app) async {
    if (dbg != null) return dbgControl('continue');
    if (tab?.lang == 'py') {
      buildLog = 'Gỡ lỗi từng dòng hiện hỗ trợ C++ (gdb). Với Python, hãy dùng print() để xem giá trị biến, hoặc bấm F9 để chạy.\n';
      bottomTab = 2;
      notifyListeners();
      return;
    }
    final info = await app.detectCompiler();
    final gdb = info == null ? null : await findGdb(info.path);
    if (gdb == null) {
      buildLog = 'Không tìm thấy gdb. Bản Windows có kèm sẵn gdb; trên Linux cài gói gdb, macOS dùng lldb chưa hỗ trợ.\n';
      bottomTab = 2;
      notifyListeners();
      return;
    }
    final t = tab!;
    final b = await build(app, debug: true);
    if (b == null) return;
    console = '';
    bottomTab = 0;
    stopped = null;
    final session = DebugSession(gdb: gdb.path, progId: b.$2, input: input.text, initialBreakpoints: [for (final l in t.marks.value.breakpoints) l + 1], onEvent: (ev) => _onDebug(t, ev));
    dbg = session;
    setStatus('Đang gỡ lỗi — F7 dòng tiếp, Shift+F7 vào hàm, Ctrl+F7 ra khỏi hàm, F8 chạy tiếp, Shift+F8 dừng');
    log(input.text.isEmpty ? '[Gỡ lỗi: chương trình đọc input từ tab "Input" (đang trống)]\n' : '[Gỡ lỗi: input lấy từ tab "Input"]\n');
    try {
      await session.start();
    } catch (e) {
      log('Không khởi động được gdb: $e\n');
      session.stop();
    }
  }

  String _shown = '';
  void _onDebug(IdeTab t, DebugEvent ev) {
    switch (ev) {
      case DebugRunning():
        setStatus('Đang chạy…');
      case DebugStopped():
        stopped = ev;
        t.marks.value = t.marks.value.copyWith(current: ev.line != null ? ev.line! - 1 : null, clearCurrent: ev.line == null);
        if (ev.output.length > _shown.length && ev.output.startsWith(_shown)) log(ev.output.substring(_shown.length));
        _shown = ev.output;
        if (ev.line != null && tab == t) goTo(ev.line!);
        if (ev.signal != null) {
          log('\n[Chương trình dừng vì tín hiệu ${ev.signal}]\n');
          setStatus('Lỗi khi chạy: ${ev.signal} tại dòng ${ev.line ?? '?'}');
        } else {
          setStatus('Dừng tại dòng ${ev.line ?? '?'} trong ${ev.func}()');
        }
      case DebugExited():
        if (ev.output.length > _shown.length && ev.output.startsWith(_shown)) log(ev.output.substring(_shown.length));
        log('\n\n[Chương trình kết thúc · mã thoát ${ev.code}]\n');
      case DebugEnded():
        if (ev.error != null) log('\n${ev.error}\n');
        dbg = null;
        stopped = null;
        _shown = '';
        t.marks.value = t.marks.value.copyWith(clearCurrent: true);
        setStatus('Kết thúc gỡ lỗi');
      case DebugLog():
        log('[gdb] ${ev.text}\n');
    }
    notifyListeners();
  }

  void dbgControl(String action) {
    if (dbg == null) return;
    dbg!.control(action);
  }

  void toggleBreakpoint(int line) {
    final t = tab;
    if (t == null) return;
    final bps = {...t.marks.value.breakpoints};
    if (!bps.remove(line)) {
      bps.add(line);
      dbg?.addBreakpoint(line + 1);
    } else {
      dbg?.removeBreakpoint(line + 1);
    }
    t.marks.value = t.marks.value.copyWith(breakpoints: bps);
  }

  void fontZoom(AppState app, double d) => app.setSetting('ideFont', (app.setting<num>('ideFont', 15) + d).clamp(10, 30).toDouble());
}

// ---------- Giao diện ----------
class IdeView extends StatefulWidget {
  const IdeView({super.key});
  @override
  State<IdeView> createState() => _IdeViewState();
}

class _IdeViewState extends State<IdeView> {
  bool explorer = true;
  final stdinLine = TextEditingController();

  IdeModel get ide => context.read<IdeModel>();
  AppState get app => context.read<AppState>();

  Future<void> _open() async {
    final r = await FilePicker.platform.pickFiles(dialogTitle: 'Mở file', type: FileType.any, withData: Platform.isAndroid);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.path != null && !Platform.isAndroid) {
      ide.openPath(f.path!);
    } else {
      final text = f.bytes != null ? utf8.decode(f.bytes!, allowMalformed: true) : await File(f.path!).readAsString();
      ide.openCode(f.name, text);
    }
  }

  Future<void> _openFolder() async {
    final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Mở thư mục');
    if (d == null) return;
    ide.folder = d;
    ide.saveSession();
    setState(() => explorer = true);
  }

  Future<void> _close(int i) async {
    final t = ide.tabs[i];
    if (t.dirty) {
      final c = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Lưu "${t.name}"?'),
          content: const Text('File có thay đổi chưa lưu.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
            TextButton(onPressed: () => Navigator.pop(c, 'no'), child: const Text('Không lưu')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Lưu')),
          ],
        ),
      );
      if (c == null) return;
      if (c == 'save' && !await ide.save(t)) return;
    }
    ide.close(i);
  }

  Future<void> _toNotebook() async {
    final t = ide.tab;
    if (t == null) return;
    if (app.repo == null || app.readOnly) return toast(context, 'Hãy mở một notebook (không ở chế độ xem) trước.', error: true);
    final page = app.page;
    if (page == null) return toast(context, 'Notebook chưa có trang nào.', error: true);
    final b = newBlock('code');
    b['title'] = t.name;
    b['code'] = t.ctl.text;
    b['stdin'] = ide.input.text;
    (page['blocks'] as List).add(b);
    app.changed();
    toast(context, 'Đã thêm khối code vào trang "${page['title']}"');
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.f9): () => ide.run(app),
    const SingleActivator(LogicalKeyboardKey.f9, control: true): () => ide.build(app),
    const SingleActivator(LogicalKeyboardKey.f10, control: true): () => ide.run(app),
    const SingleActivator(LogicalKeyboardKey.f8): () => ide.debug(app),
    const SingleActivator(LogicalKeyboardKey.f8, shift: true): ide.stopAll,
    const SingleActivator(LogicalKeyboardKey.f7): () => ide.dbgControl('next'),
    const SingleActivator(LogicalKeyboardKey.f7, shift: true): () => ide.dbgControl('step'),
    const SingleActivator(LogicalKeyboardKey.f7, control: true): () => ide.dbgControl('finish'),
    const SingleActivator(LogicalKeyboardKey.f5): () {
      final t = ide.tab;
      if (t != null) ide.toggleBreakpoint(t.ctl.selection.extentIndex);
    },
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
      if (ide.tab != null) ide.save(ide.tab!);
    },
    const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () {
      if (ide.tab != null) ide.save(ide.tab!, saveAs: true);
    },
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => ide.newFile(),
    const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
    const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _close(ide.active),
    const SingleActivator(LogicalKeyboardKey.equal, control: true): () => ide.fontZoom(app, 1),
    const SingleActivator(LogicalKeyboardKey.minus, control: true): () => ide.fontZoom(app, -1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true): () => ide.select((ide.active + 1) % ide.tabs.length),
  };

  @override
  void dispose() {
    stdinLine.dispose();
    super.dispose();
  }

  Widget _btn(IconData icon, String tip, VoidCallback? f, {Color? color}) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    icon: Icon(icon, color: f == null ? null : color),
    onPressed: f,
  );

  Widget _toolbar(IdeModel m) {
    final dbg = m.dbg != null;
    final local = app.canRunLocal;
    const green = Color(0xFF2DA44E);
    final sep = Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.cs.outlineVariant);
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      color: context.cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (context.compact)
              _btn(Icons.folder_outlined, 'Các file', () => _filesSheet(m))
            else
              _btn(explorer ? Icons.vertical_split : Icons.vertical_split_outlined, 'Ẩn/hiện danh sách file', () => setState(() => explorer = !explorer)),
            _btn(Icons.note_add_outlined, 'File C++ mới (Ctrl+N)', () => m.newFile()),
            _btn(Icons.data_object, 'File Python mới', () => m.newFile(null, pyIdeNewCode, 'py')),
            _btn(Icons.file_open_outlined, 'Mở file (Ctrl+O)', _open),
            _btn(Icons.save_outlined, 'Lưu (Ctrl+S)', m.tab == null ? null : () => m.save(m.tab!)),
            sep,
            _btn(Icons.build_outlined, 'Build (Ctrl+F9)', m.busy ? null : () => m.build(app), color: warnColor),
            _btn(Icons.play_arrow, 'Build & Run (F9)', m.busy ? null : () => m.run(app), color: green),
            _btn(Icons.stop, 'Dừng (Shift+F8)', m.proc != null || dbg ? m.stopAll : null, color: context.cs.error),
            if (local) ...[
              sep,
              _btn(Icons.bug_report_outlined, dbg ? 'Chạy tiếp (F8)' : 'Gỡ lỗi (F8)', m.busy ? null : () => m.debug(app), color: const Color(0xFFD97706)),
              _btn(Icons.redo, 'Dòng tiếp (F7)', dbg ? () => m.dbgControl('next') : null),
              _btn(Icons.login, 'Vào hàm (Shift+F7)', dbg ? () => m.dbgControl('step') : null),
              _btn(Icons.logout, 'Ra khỏi hàm (Ctrl+F7)', dbg ? () => m.dbgControl('finish') : null),
              _btn(Icons.radio_button_checked, 'Đặt/bỏ điểm dừng (F5)', m.tab == null ? null : () => m.toggleBreakpoint(m.tab!.ctl.selection.extentIndex), color: const Color(0xFFE5534B)),
            ],
            sep,
            _btn(Icons.zoom_out, 'Chữ nhỏ (Ctrl+-)', () => m.fontZoom(app, -1)),
            _btn(Icons.zoom_in, 'Chữ to (Ctrl+=)', () => m.fontZoom(app, 1)),
            sep,
            TextButton.icon(
              onPressed: m.tab == null
                  ? null
                  : () async {
                      final code = await pickSnippet(context, lang: m.tab!.lang == 'py' ? 'py' : 'cpp');
                      if (code != null) m.tab!.ctl.replaceSelection(code);
                    },
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: const Text('Code mẫu'),
            ),
            TextButton.icon(onPressed: _toNotebook, icon: const Icon(Icons.post_add, size: 18), label: const Text('Đưa vào sổ tay')),
          ],
        ),
      ),
    );
  }

  Widget _tabBar(IdeModel m) => Container(
    height: 36,
    decoration: BoxDecoration(
      color: context.cs.surfaceContainer,
      border: Border(bottom: BorderSide(color: context.cs.outlineVariant)),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < m.tabs.length; i++)
          GestureDetector(
            onTertiaryTapUp: (_) => _close(i),
            child: InkWell(
              onTap: () => m.select(i),
              child: Container(
                padding: const EdgeInsets.only(left: 12, right: 2),
                decoration: BoxDecoration(
                  color: i == m.active ? context.cs.surface : null,
                  border: Border(
                    top: BorderSide(color: i == m.active ? context.cs.primary : Colors.transparent, width: 2),
                    right: BorderSide(color: context.cs.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(m.tabs[i].path != null ? Icons.description_outlined : Icons.insert_drive_file_outlined, size: 15, color: context.cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    ListenableBuilder(
                      listenable: m.tabs[i].ctl,
                      builder: (_, _) => Text('${m.tabs[i].dirty ? '● ' : ''}${m.tabs[i].name}', style: TextStyle(fontSize: 13, fontWeight: i == m.active ? FontWeight.w600 : null)),
                    ),
                    IconButton(visualDensity: VisualDensity.compact, iconSize: 15, tooltip: 'Đóng (Ctrl+W)', onPressed: () => _close(i), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
            ),
          ),
        IconButton(tooltip: 'Tab mới', iconSize: 18, onPressed: () => m.newFile(), icon: const Icon(Icons.add)),
      ],
    ),
  );

  List<Widget> _fileEntries(IdeModel m, {VoidCallback? after}) {
    final out = <Widget>[];
    if (m.folder != null && !Platform.isAndroid) {
      out.add(
        ListTile(
          dense: true,
          leading: const Icon(Icons.folder_open, size: 18),
          title: Text(p.basename(m.folder!), style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: IconButton(iconSize: 16, tooltip: 'Đóng thư mục', icon: const Icon(Icons.close), onPressed: () => setState(() => m.folder = null)),
        ),
      );
      try {
        final files =
            Directory(m.folder!)
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => RegExp(r'\.(cpp|cc|c|h|hpp|py|txt|in|out|inp)$', caseSensitive: false).hasMatch(f.path) && !f.path.contains('${p.separator}.'))
                .take(300)
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          out.add(
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 28, right: 8),
              title: Text(p.relative(f.path, from: m.folder!), style: const TextStyle(fontSize: 13)),
              selected: m.tab?.path == f.path,
              onTap: () {
                m.openPath(f.path);
                after?.call();
              },
            ),
          );
        }
      } catch (e) {
        out.add(Padding(padding: const EdgeInsets.all(8), child: Text('$e')));
      }
    }
    final stored = Storage.I.listFiles();
    out.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Text('Lưu trong app', style: context.tt.labelMedium),
      ),
    );
    if (stored.isEmpty)
      out.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Chưa có', style: TextStyle(fontSize: 12)),
        ),
      );
    for (final f in stored) {
      out.add(
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text('${f['name']}', style: const TextStyle(fontSize: 13)),
          subtitle: Text(timeAgo(f['updatedAt'] as int), style: const TextStyle(fontSize: 11)),
          selected: m.tab?.fileId == f['id'],
          onTap: () {
            m.openStored(f);
            after?.call();
          },
          trailing: IconButton(
            iconSize: 16,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirmBox(context, 'Xoá file?', 'Xoá "${f['name']}" khỏi app?', ok: 'Xoá', danger: true)) return;
              Storage.I.removeFile(f['id'] as String);
              setState(() {});
            },
          ),
        ),
      );
    }
    return out;
  }

  void _filesSheet(IdeModel m) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.note_add_outlined),
          title: const Text('File mới'),
          onTap: () {
            Navigator.pop(c);
            m.newFile();
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Mở file từ máy'),
          onTap: () {
            Navigator.pop(c);
            _open();
          },
        ),
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Xuất file đang mở'),
          onTap: () {
            Navigator.pop(c);
            if (m.tab != null) saveTextFile(context, m.tab!.name, m.tab!.ctl.text);
          },
        ),
        const Divider(),
        ..._fileEntries(m, after: () => Navigator.pop(c)),
      ],
    ),
  );

  Widget _explorer(IdeModel m) => Container(
    width: 230,
    decoration: BoxDecoration(
      color: context.cs.surfaceContainerLow,
      border: Border(right: BorderSide(color: context.cs.outlineVariant)),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Expanded(child: Text('FILE', style: context.tt.labelMedium?.copyWith(letterSpacing: 1))),
              IconButton(iconSize: 18, tooltip: 'Mở thư mục…', onPressed: _openFolder, icon: const Icon(Icons.create_new_folder_outlined)),
            ],
          ),
        ),
        Expanded(child: ListView(children: _fileEntries(m))),
      ],
    ),
  );

  Widget _varsPanel(IdeModel m) {
    final s = m.stopped;
    if (m.dbg == null) {
      return const Padding(padding: EdgeInsets.all(12), child: Text('Bấm F8 (Gỡ lỗi) để chạy từng dòng và xem giá trị biến. Bấm vào lề trái của dòng để đặt điểm dừng.'));
    }
    if (s == null) return const Padding(padding: EdgeInsets.all(12), child: Text('Đang chạy…'));
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('Biến', style: context.tt.labelLarge),
        const SizedBox(height: 4),
        if (s.locals.isEmpty) const Text('(không có biến cục bộ)', style: TextStyle(fontSize: 12)),
        Table(
          columnWidths: const {0: IntrinsicColumnWidth()},
          children: [
            for (final v in s.locals)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    child: Text(
                      v.name,
                      style: TextStyle(fontFamily: monoFont, fontSize: 13, fontWeight: FontWeight.w600, color: v.arg ? context.cs.tertiary : null),
                    ),
                  ),
                  SelectableText(v.value, style: TextStyle(fontFamily: monoFont, fontSize: 13)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Ngăn xếp lời gọi', style: context.tt.labelLarge),
        for (final f in s.frames)
          InkWell(
            onTap: f.line == null ? null : () => m.goTo(f.line!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${f.func}()  dòng ${f.line ?? '?'}', style: TextStyle(fontFamily: monoFont, fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _bottom(IdeModel m) {
    final tabs = ['Console', 'Input', 'Build log${m.msgs.where((x) => x.kind == 'error').isNotEmpty ? ' (${m.msgs.where((x) => x.kind == 'error').length})' : ''}', if (context.compact) 'Biến'];
    final idx = m.bottomTab.clamp(0, tabs.length - 1);
    final mono = TextStyle(fontFamily: monoFont, fontSize: 13);
    Widget body = switch (idx) {
      0 => Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: context.isDark ? const Color(0xFF16171A) : const Color(0xFFFAFAFA),
              child: SingleChildScrollView(
                controller: m.consoleScroll,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  m.console.isEmpty ? (app.canRunLocal ? 'Bấm F9 để build & chạy. Chương trình đọc dữ liệu từ ô nhập bên dưới.' : 'Bấm ▶ để chạy online. Dữ liệu vào lấy từ tab "Input".') : m.console,
                  style: mono,
                ),
              ),
            ),
          ),
          if (m.proc != null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: TextField(
                controller: stdinLine,
                focusNode: m.stdinFocus,
                autofocus: true,
                style: mono,
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.keyboard_return, size: 16), hintText: 'Nhập dữ liệu cho chương trình rồi Enter'),
                onSubmitted: (t) {
                  m.sendInput(t);
                  stdinLine.clear();
                  m.stdinFocus.requestFocus();
                },
              ),
            ),
        ],
      ),
      1 => Padding(
        padding: const EdgeInsets.all(6),
        child: TextField(
          controller: m.input,
          expands: true,
          maxLines: null,
          style: mono,
          textAlignVertical: TextAlignVertical.top,
          onChanged: (_) => m.saveSession(),
          decoration: InputDecoration(hintText: app.canRunLocal ? 'Dữ liệu vào dùng khi gỡ lỗi (F8)' : 'Dữ liệu vào (stdin) khi chạy online'),
        ),
      ),
      2 => ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final x in m.msgs)
            InkWell(
              onTap: () => m.goTo(x.line, x.col),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      x.kind == 'error'
                          ? Icons.error
                          : x.kind == 'warning'
                          ? Icons.warning_amber
                          : Icons.info_outline,
                      size: 16,
                      color: x.kind == 'error'
                          ? context.cs.error
                          : x.kind == 'warning'
                          ? warnColor
                          : null,
                    ),
                    const SizedBox(width: 6),
                    SizedBox(width: 110, child: Text('${x.file}:${x.line}', style: mono)),
                    Expanded(child: Text(x.text, style: mono)),
                  ],
                ),
              ),
            ),
          if (m.msgs.isNotEmpty) const Divider(),
          SelectableText(m.buildLog.isEmpty ? 'Chưa build.' : m.buildLog, style: mono),
        ],
      ),
      _ => _varsPanel(m),
    };
    return Column(
      children: [
        Container(
          height: 32,
          color: context.cs.surfaceContainer,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                InkWell(
                  onTap: () => setState(() => m.bottomTab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == idx ? context.cs.primary : Colors.transparent, width: 2)),
                    ),
                    child: Text(tabs[i], style: TextStyle(fontSize: 13, fontWeight: i == idx ? FontWeight.w600 : null)),
                  ),
                ),
              const Spacer(),
              if (idx == 0) IconButton(iconSize: 16, tooltip: 'Xoá console', onPressed: () => setState(() => m.console = ''), icon: const Icon(Icons.clear_all)),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  double bottomH = 230;
  final scope = FocusNode(debugLabel: 'ide');

  @override
  Widget build(BuildContext context) {
    final m = context.watch<IdeModel>();
    final appState = context.watch<AppState>();
    final t = m.tab;
    final compact = context.compact;
    final editor = t == null
        ? const SizedBox()
        : CodeArea(
            key: ObjectKey(t),
            controller: t.ctl,
            lang: t.lang,
            marks: t.marks,
            focusNode: t.focus,
            autofocus: true,
            fontSize: appState.setting<num>('ideFont', compact ? 13 : 15).toDouble(),
            onGutterTap: m.toggleBreakpoint,
          );
    final h = MediaQuery.sizeOf(context).height;
    final bh = compact ? h * .36 : bottomH.clamp(100.0, h - 220);
    // Vừa chuyển sang IDE: đưa con trỏ vào trình soạn để phím tắt (F9, F8…) dùng được ngay.
    if (appState.mode == 'ide' && !scope.hasFocus && t != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !scope.hasFocus) t.focus.requestFocus();
      });
    }
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        focusNode: scope,
        skipTraversal: true,
        child: Column(
          children: [
            _toolbar(m),
            Expanded(
              child: Row(
                children: [
                  if (explorer && !compact) _explorer(m),
                  Expanded(
                    child: Column(
                      children: [
                        _tabBar(m),
                        Expanded(child: editor),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: GestureDetector(
                            onVerticalDragUpdate: (d) => setState(() => bottomH = (bottomH - d.delta.dy).clamp(100.0, h - 220)),
                            child: Container(height: 5, color: context.cs.outlineVariant.withValues(alpha: .6)),
                          ),
                        ),
                        SizedBox(height: bh, child: _bottom(m)),
                      ],
                    ),
                  ),
                  if (!compact && m.dbg != null)
                    Container(
                      width: 280,
                      decoration: BoxDecoration(
                        color: context.cs.surfaceContainerLow,
                        border: Border(left: BorderSide(color: context.cs.outlineVariant)),
                      ),
                      child: _varsPanel(m),
                    ),
                ],
              ),
            ),
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: m.dbg != null ? const Color(0xFFD97706) : context.cs.surfaceContainerHigh,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: m.dbg != null ? Colors.white : null),
                    ),
                  ),
                  if (t != null)
                    ListenableBuilder(
                      listenable: t.ctl,
                      builder: (_, _) => Text(
                        'Dòng ${t.ctl.selection.extentIndex + 1}, cột ${t.ctl.selection.extentOffset + 1}   ${t.path ?? (t.fileId != null ? 'trong app' : 'chưa lưu')}',
                        style: TextStyle(fontSize: 12, color: m.dbg != null ? Colors.white : null),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
