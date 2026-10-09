// Lập trình kéo thả kiểu Scratch cho mô phỏng: danh mục khối, sinh code JavaScript (thư viện viz),
// và chuyển khối Blockly của bản HTML cũ sang định dạng mới.
//
// Chương trình: {v: 2, vars: [tên], main: [khối], funcs: [{name, params: [tên], body: [khối]}]}
// Khối: {op, a: {tên ô: chuỗi (giá trị gõ tay / lựa chọn) | khối giá trị}, do: [khối], else: [khối]}
import 'dart:convert';

import 'package:flutter/painting.dart' show Color;

import 'vcs.dart' show Json;

enum Shape { stmt, cblock, ifelse, reporter, boolean, cap }

enum SlotKind { num, text, any, bool, list, varName, dropdown, ident, code, func, label }

class Slot {
  final SlotKind kind;
  final String dflt;
  final List<(String, String)> options; // (nhãn, giá trị)
  const Slot(this.kind, [this.dflt = '', this.options = const []]);
}

class Category {
  final String id, name;
  final Color color;
  const Category(this.id, this.name, this.color);
}

const categories = [
  Category('event', 'Hiển thị', Color(0xFF9966FF)),
  Category('input', 'Dữ liệu vào', Color(0xFF4C97FF)),
  Category('control', 'Điều khiển', Color(0xFFFFAB19)),
  Category('math', 'Toán', Color(0xFF59C059)),
  Category('text', 'Chữ', Color(0xFF5CB1D6)),
  Category('var', 'Biến', Color(0xFFFF8C1A)),
  Category('list', 'Danh sách', Color(0xFFFF661A)),
  Category('array', 'Mảng (vẽ)', Color(0xFFE6A100)),
  Category('ds', 'Stack / Queue', Color(0xFFCF63CF)),
  Category('grid', 'Lưới', Color(0xFF0FBD8C)),
  Category('graph', 'Đồ thị / Cây', Color(0xFFFF6680)),
  Category('func', 'Hàm', Color(0xFFE0457B)),
];

Category categoryOf(String id) => categories.firstWhere((c) => c.id == id);

const colorOpts = [
  ('xanh dương (đang xét)', 'active'),
  ('vàng (so sánh)', 'compare'),
  ('đỏ (đổi chỗ)', 'swap'),
  ('xanh lá (xong)', 'done'),
  ('tím (đã thăm)', 'visited'),
  ('cam (đường đi)', 'path'),
  ('xám (bỏ qua)', 'dim'),
  ('tường', 'wall'),
  ('điểm đầu', 'start'),
  ('điểm cuối', 'end'),
  ('bỏ màu', 'none'),
];

class BlockSpec {
  final String op, cat, label;
  final Shape shape;
  final Map<String, Slot> slots;
  final String Function(Gen g, Json n) gen;
  final String? tip;
  const BlockSpec(this.op, this.cat, this.shape, this.label, this.slots, this.gen, {this.tip});
  bool get isValue => shape == Shape.reporter || shape == Shape.boolean;
  bool get hasBody => shape == Shape.cblock || shape == Shape.ifelse;
}

// ---------- Sinh code ----------
String jsName(String prefix, String name) {
  final b = StringBuffer(prefix);
  for (final r in name.runes) {
    final ch = String.fromCharCode(r);
    b.write(RegExp(r'[A-Za-z0-9]').hasMatch(ch) ? ch : '_${r.toRadixString(36)}');
  }
  return b.toString();
}

String jsStr(String s) => jsonEncode(s);

class Gen {
  final Json prog;
  int _tmp = 0;
  Gen(this.prog);

  String tmp() => '__t${++_tmp}';
  String v(String name) => jsName('v_', name);
  String fn(String name) => jsName('f_', name);

  String f(Json n, String slot) {
    final x = (n['a'] as Map?)?[slot];
    if (x is String) return x;
    return specs[n['op']]?.slots[slot]?.dflt ?? '';
  }

  /// Biểu thức cho ô giá trị.
  String e(Json n, String slot) {
    final spec = specs[n['op']];
    final s = spec?.slots[slot];
    final x = (n['a'] as Map?)?[slot];
    if (x is Map) return '(${expr(x.cast<String, dynamic>())})';
    final lit = x is String ? x : (s?.dflt ?? '');
    switch (s?.kind) {
      case SlotKind.num:
        final d = num.tryParse(lit.trim());
        return d == null ? (lit.trim().isEmpty ? '0' : 'Number(${jsStr(lit)})') : (d < 0 ? '($d)' : '$d');
      case SlotKind.text:
        return jsStr(lit);
      case SlotKind.bool:
        return 'false';
      case SlotKind.list:
        return lit.trim().isEmpty ? '[]' : '(${jsStr(lit)}.match(/-?\\d+(\\.\\d+)?/g) || []).map(Number)';
      default:
        final d = num.tryParse(lit.trim());
        return d != null && lit.trim().isNotEmpty ? (d < 0 ? '($d)' : '$d') : jsStr(lit);
    }
  }

  String col(Json n) {
    final c = f(n, 'COLOR');
    return c == 'none' || c.isEmpty ? 'null' : jsStr(c);
  }

  String expr(Json n) {
    final spec = specs[n['op']];
    if (spec == null) return '0';
    return spec.gen(this, n);
  }

  String stmts(List? list, [String indent = '  ']) {
    final b = StringBuffer();
    for (final x in list ?? const []) {
      if (x is! Map) continue;
      final n = x.cast<String, dynamic>();
      final spec = specs[n['op']];
      if (spec == null || spec.isValue) continue;
      final code = spec.gen(this, n);
      for (final line in const LineSplitter().convert(code)) {
        b.writeln('$indent$line');
      }
    }
    return b.toString();
  }

  String body(Json n, [String key = 'do']) => stmts(n[key] as List?);

  String program() {
    final vars = <String>{...((prog['vars'] ?? const []) as List).cast<String>()};
    final b = StringBuffer();
    b.writeln('// Code sinh tự động từ các khối kéo thả');
    b.writeln("const __show = (n, x) => { if (['number', 'string', 'boolean'].includes(typeof x)) viz.var(n, x); };");
    b.writeln('const __list = (x) => (Array.isArray(x) ? x : x && typeof x.values === "function" ? x.values() : typeof x === "string" ? x.split("") : []);');
    if (vars.isNotEmpty) b.writeln('let ${vars.map((x) => '${v(x)} = 0').join(', ')};');
    for (final fx in ((prog['funcs'] ?? const []) as List).cast<Map>()) {
      final params = ((fx['params'] ?? const []) as List).cast<String>();
      b.writeln('function ${fn('${fx['name']}')}(${params.map(v).join(', ')}) {');
      b.write(stmts(fx['body'] as List?));
      b.writeln('}');
    }
    b.write(stmts(prog['main'] as List?, ''));
    return b.toString();
  }
}

String generateJs(Json prog) => Gen(prog).program();

// ---------- Danh mục khối ----------
const _n0 = Slot(SlotKind.num, '0');
const _n1 = Slot(SlotKind.num, '1');
const _any0 = Slot(SlotKind.any, '0');
const _anyT = Slot(SlotKind.any, '');
const _bool = Slot(SlotKind.bool);
const _list = Slot(SlotKind.list);
const _var = Slot(SlotKind.varName, 'a');
const _color = Slot(SlotKind.dropdown, 'done', colorOpts);

String _sv(Gen g, Json n, String expr) => '${g.v(g.f(n, 'VAR'))}$expr';
String _name(Gen g, Json n) => jsStr(g.f(n, 'VAR'));

final Map<String, BlockSpec> specs = {
  for (final s in <BlockSpec>[
    // ----- Hiển thị -----
    BlockSpec('step', 'event', Shape.stmt, 'chụp bước, ghi chú {X}', {'X': const Slot(SlotKind.any, 'ghi chú')}, (g, n) => 'viz.step(String(${g.e(n, 'X')}));',
        tip: 'Tạo một bước trong trình phát mô phỏng'),
    BlockSpec('show_var', 'event', Shape.stmt, 'hiện {NAME} = {X}', {'NAME': const Slot(SlotKind.ident, 'i'), 'X': _any0}, (g, n) => 'viz.var(${jsStr(g.f(n, 'NAME'))}, ${g.e(n, 'X')});'),
    BlockSpec('hide_var', 'event', Shape.stmt, 'ẩn {NAME}', {'NAME': const Slot(SlotKind.ident, 'i')}, (g, n) => 'viz.var(${jsStr(g.f(n, 'NAME'))});'),
    BlockSpec('log', 'event', Shape.stmt, 'in ra {X}', {'X': const Slot(SlotKind.any, 'xin chào')}, (g, n) => 'viz.log(${g.e(n, 'X')});'),
    BlockSpec('auto', 'event', Shape.stmt, 'tự chụp bước sau mỗi thao tác: {ON}', {'ON': const Slot(SlotKind.dropdown, 'true', [('bật', 'true'), ('tắt', 'false')])},
        (g, n) => 'viz.auto(${g.f(n, 'ON') == 'true'});'),
    BlockSpec('comment', 'event', Shape.stmt, '// {TEXT}', {'TEXT': const Slot(SlotKind.ident, 'ghi chú')}, (g, n) => '// ${g.f(n, 'TEXT').replaceAll('\n', ' ')}'),
    BlockSpec('js', 'event', Shape.stmt, 'chạy code JS {CODE}', {'CODE': const Slot(SlotKind.code, 'viz.log(1);')}, (g, n) => g.f(n, 'CODE')),
    BlockSpec('js_expr', 'event', Shape.reporter, 'JS {CODE}', {'CODE': const Slot(SlotKind.code, '1 + 1')}, (g, n) => '(${g.f(n, 'CODE')})'),

    // ----- Dữ liệu vào -----
    BlockSpec('read_numbers', 'input', Shape.reporter, 'các số trong dữ liệu vào', {}, (g, n) => 'readNumbers()'),
    BlockSpec('input_k', 'input', Shape.reporter, 'số thứ {K} trong dữ liệu vào', {'K': _n0}, (g, n) => 'readNumbers()[${g.e(n, 'K')}]', tip: 'Đánh số từ 0'),
    BlockSpec('input_lines', 'input', Shape.reporter, 'các dòng của dữ liệu vào', {}, (g, n) => "INPUT.split('\\n').map((l) => l.replace(/\\r\$/, '')).filter((l) => l.trim() !== '')"),
    BlockSpec('input_text', 'input', Shape.reporter, 'dữ liệu vào (chữ)', {}, (g, n) => 'INPUT'),
    BlockSpec('input_count', 'input', Shape.reporter, 'có bao nhiêu số trong dữ liệu vào', {}, (g, n) => 'readNumbers().length'),

    // ----- Điều khiển -----
    BlockSpec('repeat', 'control', Shape.cblock, 'lặp lại {N} lần', {'N': const Slot(SlotKind.num, '10')}, (g, n) {
      final t = g.tmp();
      return 'for (let $t = 0; $t < ${g.e(n, 'N')}; $t++) {\n${g.body(n)}}';
    }),
    BlockSpec('for', 'control', Shape.cblock, 'với {VAR} chạy từ {FROM} đến {TO} bước {BY}', {'VAR': const Slot(SlotKind.varName, 'i'), 'FROM': _n0, 'TO': const Slot(SlotKind.num, '9'), 'BY': _n1},
        (g, n) {
      final s = g.tmp(), e = g.tmp(), x = g.v(g.f(n, 'VAR'));
      return '{\n  const $s = ${g.e(n, 'BY')}, $e = ${g.e(n, 'TO')};\n  for ($x = ${g.e(n, 'FROM')}; $s >= 0 ? $x <= $e : $x >= $e; $x += $s) {\n    __show(${_name(g, n)}, $x);\n${g.stmts(n['do'] as List?, '    ')}  }\n}';
    }, tip: 'Giống for (int i = từ; i <= đến; i += bước) trong C++'),
    BlockSpec('while', 'control', Shape.cblock, 'lặp khi {COND}', {'COND': _bool}, (g, n) => 'while (${g.e(n, 'COND')}) {\n${g.body(n)}}'),
    BlockSpec('until', 'control', Shape.cblock, 'lặp cho đến khi {COND}', {'COND': _bool}, (g, n) => 'while (!${g.e(n, 'COND')}) {\n${g.body(n)}}'),
    BlockSpec('for_lt', 'control', Shape.cblock, 'for (int {VAR} = {FROM}; {VAR2} < {TO}; {VAR3}++)', {
      'VAR': const Slot(SlotKind.varName, 'i'),
      'FROM': _n0,
      'VAR2': const Slot(SlotKind.label),
      'TO': const Slot(SlotKind.num, '10'),
      'VAR3': const Slot(SlotKind.label),
    }, (g, n) {
      final e = g.tmp(), x = g.v(g.f(n, 'VAR'));
      return '{\n  const $e = ${g.e(n, 'TO')};\n  for ($x = ${g.e(n, 'FROM')}; $x < $e; $x++) {\n    __show(${_name(g, n)}, $x);\n${g.stmts(n['do'] as List?, '    ')}  }\n}';
    }, tip: 'Vòng for kiểu C++: chạy từ FROM đến TO − 1'),
    BlockSpec('foreach', 'control', Shape.cblock, 'for (auto {VAR} : danh sách {LIST})', {'VAR': const Slot(SlotKind.varName, 'x'), 'LIST': _list}, (g, n) {
      final x = g.v(g.f(n, 'VAR'));
      return 'for ($x of __list(${g.e(n, 'LIST')})) {\n  __show(${_name(g, n)}, $x);\n${g.body(n)}}';
    }, tip: 'Duyệt từng phần tử của danh sách (dữ liệu vào, danh sách, đỉnh kề…)'),
    BlockSpec('foreach_text', 'control', Shape.cblock, 'for (char {VAR} : chuỗi {T})', {'VAR': const Slot(SlotKind.varName, 'c'), 'T': const Slot(SlotKind.text, 'abc')}, (g, n) {
      final x = g.v(g.f(n, 'VAR'));
      return 'for ($x of String(${g.e(n, 'T')})) {\n  __show(${_name(g, n)}, $x);\n${g.body(n)}}';
    }, tip: 'Duyệt từng ký tự của chuỗi, như for (char c : s) trong C++'),
    BlockSpec('foreach_array', 'control', Shape.cblock, 'for (auto {VAR} : mảng {ARR})', {'VAR': const Slot(SlotKind.varName, 'x'), 'ARR': const Slot(SlotKind.varName, 'a')}, (g, n) {
      final x = g.v(g.f(n, 'VAR')), arr = g.v(g.f(n, 'ARR')), k = g.tmp(), name = jsStr(g.f(n, 'VAR'));
      return 'for (let $k = 0; $k < $arr.length; $k++) {\n  $x = $arr.get($k);\n  $arr.pointer($name, $k);\n  __show($name, $x);\n  viz.step($name + " = " + $x);\n${g.body(n)}}\n$arr.pointer($name, null);';
    }, tip: 'Duyệt từng phần tử của mảng (vẽ), có mũi tên chỉ phần tử đang xét'),
    BlockSpec('if', 'control', Shape.cblock, 'nếu {COND} thì', {'COND': _bool}, (g, n) => 'if (${g.e(n, 'COND')}) {\n${g.body(n)}}'),
    BlockSpec('ifelse', 'control', Shape.ifelse, 'nếu {COND} thì', {'COND': _bool}, (g, n) => 'if (${g.e(n, 'COND')}) {\n${g.body(n)}} else {\n${g.body(n, 'else')}}'),
    BlockSpec('break', 'control', Shape.cap, 'thoát vòng lặp', {}, (g, n) => 'break;'),
    BlockSpec('continue', 'control', Shape.cap, 'sang lượt lặp tiếp', {}, (g, n) => 'continue;'),
    BlockSpec('stop', 'control', Shape.cap, 'dừng chương trình', {}, (g, n) => 'throw "__stop";'),

    // ----- Toán -----
    BlockSpec('arith', 'math', Shape.reporter, '{A} {OP} {B}', {
      'A': _any0,
      'OP': const Slot(SlotKind.dropdown, '+', [('+', '+'), ('−', '-'), ('×', '*'), ('÷', '/'), ('mũ', '**')]),
      'B': _any0,
    }, (g, n) => '${g.e(n, 'A')} ${g.f(n, 'OP')} ${g.e(n, 'B')}'),
    BlockSpec('mod', 'math', Shape.reporter, 'phần dư của {A} chia {B}', {'A': const Slot(SlotKind.num, '10'), 'B': const Slot(SlotKind.num, '3')}, (g, n) => '${g.e(n, 'A')} % ${g.e(n, 'B')}'),
    BlockSpec('idiv', 'math', Shape.reporter, 'thương nguyên {A} / {B}', {'A': const Slot(SlotKind.num, '10'), 'B': const Slot(SlotKind.num, '3')}, (g, n) => 'Math.trunc(${g.e(n, 'A')} / ${g.e(n, 'B')})'),
    BlockSpec('compare', 'math', Shape.boolean, '{A} {OP} {B}', {
      'A': _any0,
      'OP': const Slot(SlotKind.dropdown, '<', [('=', '=='), ('≠', '!='), ('<', '<'), ('≤', '<='), ('>', '>'), ('≥', '>=')]),
      'B': _any0,
    }, (g, n) => '${g.e(n, 'A')} ${g.f(n, 'OP')} ${g.e(n, 'B')}'),
    BlockSpec('and', 'math', Shape.boolean, '{A} {OP} {B}', {'A': _bool, 'OP': const Slot(SlotKind.dropdown, '&&', [('và', '&&'), ('hoặc', '||')]), 'B': _bool},
        (g, n) => '${g.e(n, 'A')} ${g.f(n, 'OP')} ${g.e(n, 'B')}'),
    BlockSpec('not', 'math', Shape.boolean, 'không phải {A}', {'A': _bool}, (g, n) => '!${g.e(n, 'A')}'),
    BlockSpec('bool', 'math', Shape.boolean, '{V}', {'V': const Slot(SlotKind.dropdown, 'true', [('đúng', 'true'), ('sai', 'false')])}, (g, n) => g.f(n, 'V')),
    BlockSpec('parity', 'math', Shape.boolean, '{X} là số {P}', {'X': _n0, 'P': const Slot(SlotKind.dropdown, 'even', [('chẵn', 'even'), ('lẻ', 'odd')])},
        (g, n) => g.f(n, 'P') == 'even' ? '${g.e(n, 'X')} % 2 === 0' : 'Math.abs(${g.e(n, 'X')} % 2) === 1'),
    BlockSpec('random', 'math', Shape.reporter, 'số ngẫu nhiên từ {A} đến {B}', {'A': _n1, 'B': const Slot(SlotKind.num, '10')}, (g, n) {
      return 'Math.floor(Math.random() * (${g.e(n, 'B')} - ${g.e(n, 'A')} + 1)) + ${g.e(n, 'A')}';
    }),
    BlockSpec('mathfn', 'math', Shape.reporter, '{F} của {X}', {
      'F': const Slot(SlotKind.dropdown, 'abs', [('trị tuyệt đối', 'abs'), ('căn bậc hai', 'sqrt'), ('làm tròn xuống', 'floor'), ('làm tròn lên', 'ceil'), ('làm tròn', 'round'), ('log2', 'log2'), ('log10', 'log10')]),
      'X': _n0,
    }, (g, n) => 'Math.${g.f(n, 'F')}(${g.e(n, 'X')})'),
    BlockSpec('minmax', 'math', Shape.reporter, '{F} của {A} và {B}', {'F': const Slot(SlotKind.dropdown, 'min', [('nhỏ nhất', 'min'), ('lớn nhất', 'max')]), 'A': _n0, 'B': _n0},
        (g, n) => 'Math.${g.f(n, 'F')}(${g.e(n, 'A')}, ${g.e(n, 'B')})'),
    BlockSpec('infinity', 'math', Shape.reporter, '{S}vô cực', {'S': const Slot(SlotKind.dropdown, '', [('+', ''), ('−', '-')])}, (g, n) => '${g.f(n, 'S')}Infinity'),

    // ----- Chữ -----
    BlockSpec('join', 'text', Shape.reporter, 'nối {A} với {B}', {'A': const Slot(SlotKind.text, 'xin '), 'B': const Slot(SlotKind.text, 'chào')}, (g, n) => 'String(${g.e(n, 'A')}) + String(${g.e(n, 'B')})'),
    BlockSpec('text_len', 'text', Shape.reporter, 'độ dài chữ {X}', {'X': const Slot(SlotKind.text, 'abc')}, (g, n) => 'String(${g.e(n, 'X')}).length'),
    BlockSpec('char_at', 'text', Shape.reporter, 'ký tự thứ {I} của {X}', {'I': _n0, 'X': const Slot(SlotKind.text, 'abc')}, (g, n) => 'String(${g.e(n, 'X')})[${g.e(n, 'I')}]'),
    BlockSpec('text_has', 'text', Shape.boolean, '{X} có chứa {Y}', {'X': const Slot(SlotKind.text, 'abc'), 'Y': const Slot(SlotKind.text, 'b')}, (g, n) => 'String(${g.e(n, 'X')}).includes(String(${g.e(n, 'Y')}))'),
    BlockSpec('text_index', 'text', Shape.reporter, 'vị trí của {Y} trong {X}', {'Y': const Slot(SlotKind.text, 'b'), 'X': const Slot(SlotKind.text, 'abc')},
        (g, n) => 'String(${g.e(n, 'X')}).indexOf(String(${g.e(n, 'Y')}))', tip: '-1 nếu không có'),
    BlockSpec('to_number', 'text', Shape.reporter, 'đổi {X} thành số', {'X': const Slot(SlotKind.text, '42')}, (g, n) => 'Number(${g.e(n, 'X')})'),
    BlockSpec('text_lit', 'text', Shape.reporter, '"{T}"', {'T': const Slot(SlotKind.ident, 'chữ')}, (g, n) => jsStr(g.f(n, 'T'))),

    // ----- Biến -----
    BlockSpec('var_get', 'var', Shape.reporter, '{VAR}', {'VAR': _var}, (g, n) => g.v(g.f(n, 'VAR'))),
    BlockSpec('var_set', 'var', Shape.stmt, 'đặt {VAR} thành {X}', {'VAR': _var, 'X': _any0}, (g, n) => '${g.v(g.f(n, 'VAR'))} = ${g.e(n, 'X')};\n__show(${_name(g, n)}, ${g.v(g.f(n, 'VAR'))});'),
    BlockSpec('var_change', 'var', Shape.stmt, 'tăng {VAR} thêm {X}', {'VAR': _var, 'X': _n1}, (g, n) => '${g.v(g.f(n, 'VAR'))} += ${g.e(n, 'X')};\n__show(${_name(g, n)}, ${g.v(g.f(n, 'VAR'))});'),

    // ----- Danh sách (mảng JS, không vẽ) -----
    BlockSpec('list_new', 'list', Shape.reporter, 'danh sách rỗng', {}, (g, n) => '[]'),
    BlockSpec('list_of', 'list', Shape.reporter, 'danh sách các số {T}', {'T': const Slot(SlotKind.text, '1 2 3')}, (g, n) => '(String(${g.e(n, 'T')}).match(/-?\\d+(\\.\\d+)?/g) || []).map(Number)'),
    BlockSpec('list_fill', 'list', Shape.reporter, 'danh sách {N} phần tử bằng {X}', {'N': const Slot(SlotKind.num, '5'), 'X': _any0}, (g, n) => 'Array.from({ length: ${g.e(n, 'N')} }, () => ${g.e(n, 'X')})'),
    BlockSpec('list_len', 'list', Shape.reporter, 'độ dài {L}', {'L': _list}, (g, n) => '__list(${g.e(n, 'L')}).length'),
    BlockSpec('list_get', 'list', Shape.reporter, 'phần tử {I} của {L}', {'I': _n0, 'L': _list}, (g, n) => '__list(${g.e(n, 'L')})[${g.e(n, 'I')}]', tip: 'Đánh số từ 0 như C++'),
    BlockSpec('list_set', 'list', Shape.stmt, 'gán {VAR} [ {I} ] = {X}', {'VAR': _var, 'I': _n0, 'X': _any0}, (g, n) => '${g.v(g.f(n, 'VAR'))}[${g.e(n, 'I')}] = ${g.e(n, 'X')};'),
    BlockSpec('list_push', 'list', Shape.stmt, 'thêm {X} vào cuối {VAR}', {'VAR': _var, 'X': _any0}, (g, n) => '${g.v(g.f(n, 'VAR'))}.push(${g.e(n, 'X')});'),
    BlockSpec('list_insert', 'list', Shape.stmt, 'chèn {X} vào {VAR} tại {I}', {'VAR': _var, 'X': _any0, 'I': _n0}, (g, n) => '${g.v(g.f(n, 'VAR'))}.splice(${g.e(n, 'I')}, 0, ${g.e(n, 'X')});'),
    BlockSpec('list_remove', 'list', Shape.stmt, 'xoá phần tử {I} của {VAR}', {'VAR': _var, 'I': _n0}, (g, n) => '${g.v(g.f(n, 'VAR'))}.splice(${g.e(n, 'I')}, 1);'),
    BlockSpec('list_pop', 'list', Shape.reporter, 'lấy ra phần tử cuối của {VAR}', {'VAR': _var}, (g, n) => '${g.v(g.f(n, 'VAR'))}.pop()'),
    BlockSpec('list_has', 'list', Shape.boolean, '{L} có chứa {X}', {'L': _list, 'X': _any0}, (g, n) => '__list(${g.e(n, 'L')}).includes(${g.e(n, 'X')})'),
    BlockSpec('list_index', 'list', Shape.reporter, 'vị trí của {X} trong {L}', {'X': _any0, 'L': _list}, (g, n) => '__list(${g.e(n, 'L')}).indexOf(${g.e(n, 'X')})', tip: '-1 nếu không có'),
    BlockSpec('list_sorted', 'list', Shape.reporter, '{L} sắp xếp {DIR}', {'L': _list, 'DIR': const Slot(SlotKind.dropdown, 'asc', [('tăng dần', 'asc'), ('giảm dần', 'desc')])},
        (g, n) => '[...__list(${g.e(n, 'L')})].sort((x, y) => ${g.f(n, 'DIR') == 'asc' ? '(x > y) - (x < y)' : '(y > x) - (y < x)'})'),
    BlockSpec('list_agg', 'list', Shape.reporter, '{F} của {L}', {'F': const Slot(SlotKind.dropdown, 'sum', [('tổng', 'sum'), ('nhỏ nhất', 'min'), ('lớn nhất', 'max')]), 'L': _list},
        (g, n) => switch (g.f(n, 'F')) {
              'min' => 'Math.min(...__list(${g.e(n, 'L')}))',
              'max' => 'Math.max(...__list(${g.e(n, 'L')}))',
              _ => '__list(${g.e(n, 'L')}).reduce((s, x) => s + Number(x), 0)',
            }),
    BlockSpec('list_slice', 'list', Shape.reporter, 'đoạn {L} từ {A} đến {B}', {'L': _list, 'A': _n0, 'B': _n1}, (g, n) => '__list(${g.e(n, 'L')}).slice(${g.e(n, 'A')}, ${g.e(n, 'B')} + 1)'),
    BlockSpec('list_text', 'list', Shape.reporter, 'nối {L} thành chữ', {'L': _list}, (g, n) => "__list(${g.e(n, 'L')}).join(' ')"),
    BlockSpec('list_empty', 'list', Shape.boolean, '{L} rỗng', {'L': _list}, (g, n) => '__list(${g.e(n, 'L')}).length === 0'),

    // ----- Mảng (vẽ thành ô / cột) -----
    BlockSpec('array_create', 'array', Shape.stmt, 'tạo mảng {VAR} từ {LIST} vẽ dạng {STYLE}', {
      'VAR': _var,
      'LIST': _list,
      'STYLE': const Slot(SlotKind.dropdown, 'box', [('ô', 'box'), ('cột', 'bars')]),
    }, (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.array(__list(${g.e(n, 'LIST')}), { name: ${_name(g, n)}, bars: ${g.f(n, 'STYLE') == 'bars'} });'),
    BlockSpec('array_fill', 'array', Shape.stmt, 'tạo mảng {VAR} gồm {N} phần tử bằng {X}', {'VAR': _var, 'N': const Slot(SlotKind.num, '5'), 'X': _any0},
        (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.array(Array.from({ length: ${g.e(n, 'N')} }, () => ${g.e(n, 'X')}), { name: ${_name(g, n)} });'),
    BlockSpec('array_get', 'array', Shape.reporter, '{VAR} [ {I} ]', {'VAR': _var, 'I': _n0}, (g, n) => _sv(g, n, '.get(${g.e(n, 'I')})')),
    BlockSpec('array_len', 'array', Shape.reporter, 'độ dài {VAR}', {'VAR': _var}, (g, n) => _sv(g, n, '.length')),
    BlockSpec('array_set', 'array', Shape.stmt, 'gán {VAR} [ {I} ] = {X}', {'VAR': _var, 'I': _n0, 'X': _any0}, (g, n) => _sv(g, n, '.set(${g.e(n, 'I')}, ${g.e(n, 'X')});')),
    BlockSpec('array_swap', 'array', Shape.stmt, 'đổi chỗ {VAR} [ {I} ] và [ {J} ]', {'VAR': _var, 'I': _n0, 'J': _n1}, (g, n) => _sv(g, n, '.swap(${g.e(n, 'I')}, ${g.e(n, 'J')});')),
    BlockSpec('array_compare', 'array', Shape.boolean, 'so sánh {VAR} [ {I} ] {OP} [ {J} ]', {
      'VAR': _var,
      'I': _n0,
      'OP': const Slot(SlotKind.dropdown, '>', [('>', '>'), ('<', '<'), ('=', '==='), ('≥', '>='), ('≤', '<=')]),
      'J': _n1,
    }, (g, n) => '${_sv(g, n, '.compare(${g.e(n, 'I')}, ${g.e(n, 'J')})')} ${g.f(n, 'OP')} 0', tip: 'So sánh hai phần tử và tô màu vàng'),
    BlockSpec('array_mark', 'array', Shape.stmt, 'tô màu {VAR} [ {I} ] màu {COLOR}', {'VAR': _var, 'I': _n0, 'COLOR': _color}, (g, n) => _sv(g, n, '.mark(${g.e(n, 'I')}, ${g.col(n)});')),
    BlockSpec('array_mark_range', 'array', Shape.stmt, 'tô màu {VAR} từ [ {L} ] đến [ {R} ] màu {COLOR}', {'VAR': _var, 'L': _n0, 'R': _n1, 'COLOR': _color},
        (g, n) => _sv(g, n, '.markRange(${g.e(n, 'L')}, ${g.e(n, 'R')}, ${g.col(n)});')),
    BlockSpec('array_highlight', 'array', Shape.stmt, 'nháy {VAR} [ {I} ] màu {COLOR}', {'VAR': _var, 'I': _n0, 'COLOR': const Slot(SlotKind.dropdown, 'active', colorOpts)},
        (g, n) => _sv(g, n, '.highlight(${g.e(n, 'I')}, ${g.col(n)});'), tip: 'Tô màu chỉ trong một bước'),
    BlockSpec('array_pointer', 'array', Shape.stmt, 'đặt mũi tên {NAME} của {VAR} tại {I}', {'NAME': const Slot(SlotKind.ident, 'i'), 'VAR': _var, 'I': _n0},
        (g, n) => _sv(g, n, '.pointer(${jsStr(g.f(n, 'NAME'))}, ${g.e(n, 'I')});')),
    BlockSpec('array_unpointer', 'array', Shape.stmt, 'bỏ mũi tên {NAME} của {VAR}', {'NAME': const Slot(SlotKind.ident, 'i'), 'VAR': _var}, (g, n) => _sv(g, n, '.pointer(${jsStr(g.f(n, 'NAME'))}, null);')),
    BlockSpec('array_push', 'array', Shape.stmt, 'thêm {X} vào cuối {VAR}', {'VAR': _var, 'X': _any0}, (g, n) => _sv(g, n, '.push(${g.e(n, 'X')});')),
    BlockSpec('array_pop', 'array', Shape.reporter, 'lấy ra phần tử cuối của {VAR}', {'VAR': _var}, (g, n) => _sv(g, n, '.pop()')),
    BlockSpec('array_insert', 'array', Shape.stmt, 'chèn {X} vào {VAR} tại {I}', {'VAR': _var, 'X': _any0, 'I': _n0}, (g, n) => _sv(g, n, '.insert(${g.e(n, 'I')}, ${g.e(n, 'X')});')),
    BlockSpec('array_remove', 'array', Shape.stmt, 'xoá {VAR} [ {I} ]', {'VAR': _var, 'I': _n0}, (g, n) => _sv(g, n, '.removeAt(${g.e(n, 'I')});')),
    BlockSpec('array_values', 'array', Shape.reporter, 'các giá trị của {VAR}', {'VAR': _var}, (g, n) => _sv(g, n, '.values()')),

    // ----- Stack / Queue -----
    BlockSpec('ds_create', 'ds', Shape.stmt, 'tạo {VAR} là {KIND} rỗng', {
      'VAR': const Slot(SlotKind.varName, 'st'),
      'KIND': const Slot(SlotKind.dropdown, 'stack', [('stack (ngăn xếp)', 'stack'), ('queue (hàng đợi)', 'queue')]),
    }, (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.${g.f(n, 'KIND')}([], { name: ${_name(g, n)} });'),
    BlockSpec('ds_push', 'ds', Shape.stmt, 'đưa {X} vào {VAR}', {'VAR': const Slot(SlotKind.varName, 'st'), 'X': _any0}, (g, n) => _sv(g, n, '.push(${g.e(n, 'X')});')),
    BlockSpec('ds_pop', 'ds', Shape.reporter, 'lấy ra từ {VAR}', {'VAR': const Slot(SlotKind.varName, 'st')}, (g, n) => _sv(g, n, '.pop()'), tip: 'Stack: lấy ở đỉnh. Queue: lấy ở đầu.'),
    BlockSpec('ds_pop_stmt', 'ds', Shape.stmt, 'bỏ một phần tử khỏi {VAR}', {'VAR': const Slot(SlotKind.varName, 'st')}, (g, n) => _sv(g, n, '.pop();')),
    BlockSpec('ds_peek', 'ds', Shape.reporter, '{WHICH} của {VAR}', {'VAR': const Slot(SlotKind.varName, 'st'), 'WHICH': const Slot(SlotKind.dropdown, 'top', [('đỉnh', 'top'), ('đầu', 'front')])},
        (g, n) => _sv(g, n, '.${g.f(n, 'WHICH')}()')),
    BlockSpec('ds_empty', 'ds', Shape.boolean, '{VAR} rỗng', {'VAR': const Slot(SlotKind.varName, 'st')}, (g, n) => _sv(g, n, '.empty()')),
    BlockSpec('ds_size', 'ds', Shape.reporter, 'kích thước {VAR}', {'VAR': const Slot(SlotKind.varName, 'st')}, (g, n) => _sv(g, n, '.size()')),

    // ----- Lưới -----
    BlockSpec('grid_from_lines', 'grid', Shape.stmt, 'tạo lưới {VAR} từ các dòng {LINES}', {'VAR': const Slot(SlotKind.varName, 'g'), 'LINES': _list},
        (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.grid(__list(${g.e(n, 'LINES')}).map((r) => String(r).split("")), { name: ${_name(g, n)} });', tip: 'Mỗi ký tự là một ô'),
    BlockSpec('grid_create', 'grid', Shape.stmt, 'tạo lưới {VAR} có {R} hàng {C} cột', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': const Slot(SlotKind.num, '5'), 'C': const Slot(SlotKind.num, '5')},
        (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.grid(${g.e(n, 'R')}, ${g.e(n, 'C')}, "", { name: ${_name(g, n)} });'),
    BlockSpec('grid_get', 'grid', Shape.reporter, 'ô {VAR} [ {R} ][ {C} ]', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0}, (g, n) => _sv(g, n, '.get(${g.e(n, 'R')}, ${g.e(n, 'C')})')),
    BlockSpec('grid_set', 'grid', Shape.stmt, 'gán ô {VAR} [ {R} ][ {C} ] = {X}', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0, 'X': _anyT},
        (g, n) => _sv(g, n, '.set(${g.e(n, 'R')}, ${g.e(n, 'C')}, ${g.e(n, 'X')});')),
    BlockSpec('grid_mark', 'grid', Shape.stmt, 'tô màu ô {VAR} [ {R} ][ {C} ] màu {COLOR}', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0, 'COLOR': const Slot(SlotKind.dropdown, 'visited', colorOpts)},
        (g, n) => _sv(g, n, '.mark(${g.e(n, 'R')}, ${g.e(n, 'C')}, ${g.col(n)});')),
    BlockSpec('grid_highlight', 'grid', Shape.stmt, 'nháy ô {VAR} [ {R} ][ {C} ]', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0},
        (g, n) => _sv(g, n, '.highlight(${g.e(n, 'R')}, ${g.e(n, 'C')});')),
    BlockSpec('grid_is', 'grid', Shape.boolean, 'ô {VAR} [ {R} ][ {C} ] có màu {COLOR}', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0, 'COLOR': const Slot(SlotKind.dropdown, 'wall', colorOpts)},
        (g, n) => '${_sv(g, n, '.state(${g.e(n, 'R')}, ${g.e(n, 'C')})')} === ${g.col(n)}'),
    BlockSpec('grid_inside', 'grid', Shape.boolean, 'ô [ {R} ][ {C} ] nằm trong {VAR}', {'VAR': const Slot(SlotKind.varName, 'g'), 'R': _n0, 'C': _n0},
        (g, n) => _sv(g, n, '.inside(${g.e(n, 'R')}, ${g.e(n, 'C')})')),
    BlockSpec('grid_size', 'grid', Shape.reporter, 'số {DIM} của {VAR}', {'VAR': const Slot(SlotKind.varName, 'g'), 'DIM': const Slot(SlotKind.dropdown, 'rows', [('hàng', 'rows'), ('cột', 'cols')])},
        (g, n) => _sv(g, n, '.${g.f(n, 'DIM')}')),

    // ----- Đồ thị / Cây -----
    BlockSpec('graph_create', 'graph', Shape.stmt, 'tạo đồ thị {VAR} từ các số {LIST} mỗi cạnh {K} số, {DIR}', {
      'VAR': const Slot(SlotKind.varName, 'G'),
      'LIST': _list,
      'K': const Slot(SlotKind.dropdown, '2', [('2', '2'), ('3 (có trọng số)', '3')]),
      'DIR': const Slot(SlotKind.dropdown, 'false', [('vô hướng', 'false'), ('có hướng', 'true')]),
    }, (g, n) {
      final l = g.tmp(), k = g.f(n, 'K');
      return '{\n  const $l = __list(${g.e(n, 'LIST')}), e = [];\n  for (let i = 0; i + $k <= $l.length; i += $k) e.push($l.slice(i, i + $k));\n  ${g.v(g.f(n, 'VAR'))} = viz.graph({ edges: e, directed: ${g.f(n, 'DIR')}, name: ${_name(g, n)} });\n}';
    }, tip: 'VD dữ liệu "1 2 2 3" → cạnh 1-2 và 2-3'),
    BlockSpec('graph_empty', 'graph', Shape.stmt, 'tạo đồ thị {VAR} rỗng, {DIR}', {
      'VAR': const Slot(SlotKind.varName, 'G'),
      'DIR': const Slot(SlotKind.dropdown, 'false', [('vô hướng', 'false'), ('có hướng', 'true')]),
    }, (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.graph({ directed: ${g.f(n, 'DIR')}, name: ${_name(g, n)} });'),
    BlockSpec('tree_create', 'graph', Shape.stmt, 'tạo cây {VAR} rỗng', {'VAR': const Slot(SlotKind.varName, 'T')}, (g, n) => '${g.v(g.f(n, 'VAR'))} = viz.tree({ name: ${_name(g, n)} });'),
    BlockSpec('graph_add_node', 'graph', Shape.stmt, 'thêm đỉnh {N} vào {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'N': _n1}, (g, n) => _sv(g, n, '.addNode(${g.e(n, 'N')});')),
    BlockSpec('graph_add_edge', 'graph', Shape.stmt, 'thêm cạnh {U} → {W} trọng số {C} vào {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'U': _n1, 'W': const Slot(SlotKind.num, '2'), 'C': _anyT},
        (g, n) => _sv(g, n, '.addEdge(${g.e(n, 'U')}, ${g.e(n, 'W')}, ${g.f(n, 'C').isEmpty && (n['a'] as Map?)?['C'] is! Map ? 'undefined' : g.e(n, 'C')});')),
    BlockSpec('graph_remove_edge', 'graph', Shape.stmt, 'xoá cạnh {U} — {W} của {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'U': _n1, 'W': const Slot(SlotKind.num, '2')},
        (g, n) => _sv(g, n, '.removeEdge(${g.e(n, 'U')}, ${g.e(n, 'W')});')),
    BlockSpec('graph_visit', 'graph', Shape.stmt, 'tô màu đỉnh {N} của {VAR} màu {COLOR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'N': _n0, 'COLOR': const Slot(SlotKind.dropdown, 'visited', colorOpts)},
        (g, n) => _sv(g, n, '.visit(${g.e(n, 'N')}, ${g.col(n)});')),
    BlockSpec('graph_highlight', 'graph', Shape.stmt, 'nháy đỉnh {N} của {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'N': _n0}, (g, n) => _sv(g, n, '.highlight(${g.e(n, 'N')});')),
    BlockSpec('graph_edge', 'graph', Shape.stmt, 'tô màu cạnh {U} — {W} của {VAR} màu {COLOR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'U': _n0, 'W': _n1, 'COLOR': const Slot(SlotKind.dropdown, 'path', colorOpts)},
        (g, n) => _sv(g, n, '.edge(${g.e(n, 'U')}, ${g.e(n, 'W')}, ${g.col(n)});')),
    BlockSpec('graph_label', 'graph', Shape.stmt, 'ghi {X} dưới đỉnh {N} của {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'N': _n0, 'X': _anyT},
        (g, n) => _sv(g, n, '.label(${g.e(n, 'N')}, ${g.e(n, 'X')});')),
    BlockSpec('graph_neighbors', 'graph', Shape.reporter, 'các đỉnh kề {N} trong {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'N': _n0}, (g, n) => _sv(g, n, '.neighbors(${g.e(n, 'N')})')),
    BlockSpec('graph_weight', 'graph', Shape.reporter, 'trọng số cạnh {U} — {W} trong {VAR}', {'VAR': const Slot(SlotKind.varName, 'G'), 'U': _n0, 'W': _n1},
        (g, n) => _sv(g, n, '.weight(${g.e(n, 'U')}, ${g.e(n, 'W')})')),
    BlockSpec('graph_nodes', 'graph', Shape.reporter, 'các đỉnh của {VAR}', {'VAR': const Slot(SlotKind.varName, 'G')}, (g, n) => '[...${g.v(g.f(n, 'VAR'))}.nodes.values()].map((x) => x.id)'),

    // ----- Hàm -----
    BlockSpec('call', 'func', Shape.stmt, 'gọi {FN}', {'FN': const Slot(SlotKind.func)}, (g, n) => '${_call(g, n)};'),
    BlockSpec('call_value', 'func', Shape.reporter, 'kết quả {FN}', {'FN': const Slot(SlotKind.func)}, _call),
    BlockSpec('return', 'func', Shape.cap, 'trả về {X}', {'X': _anyT}, (g, n) => 'return ${g.e(n, 'X')};'),
    BlockSpec('return_void', 'func', Shape.cap, 'kết thúc hàm', {}, (g, n) => 'return;'),
  ])
    s.op: s,
};

String _call(Gen g, Json n) {
  final name = g.f(n, 'FN');
  final fx = ((g.prog['funcs'] ?? const []) as List).cast<Map>().where((x) => x['name'] == name).firstOrNull;
  final params = ((fx?['params'] ?? const []) as List).cast<String>();
  final args = [for (var i = 0; i < params.length; i++) callArg(g, n, i)];
  return '${g.fn(name)}(${args.join(', ')})';
}

String callArg(Gen g, Json n, int i) {
  final x = (n['a'] as Map?)?['P$i'];
  if (x is Map) return '(${g.expr(x.cast<String, dynamic>())})';
  final lit = x is String ? x : '0';
  final d = num.tryParse(lit.trim());
  return d != null && lit.trim().isNotEmpty ? '$d' : jsStr(lit);
}

/// Thứ tự hiện trong bảng khối.
List<BlockSpec> paletteOf(String cat) => specs.values.where((s) => s.cat == cat && s.op != 'var_get').toList();

Json newNode(String op, {Map<String, dynamic>? a}) {
  final s = specs[op]!;
  final args = <String, dynamic>{};
  s.slots.forEach((k, slot) {
    if (slot.kind != SlotKind.bool && slot.kind != SlotKind.func && slot.kind != SlotKind.label) args[k] = slot.dflt;
  });
  if (a != null) args.addAll(a);
  return {
    'op': op,
    'a': args,
    if (s.hasBody) 'do': <dynamic>[],
    if (s.shape == Shape.ifelse) 'else': <dynamic>[],
  };
}

Json emptyProgram() => {'v': 2, 'vars': <dynamic>['a', 'i', 'j'], 'main': <dynamic>[], 'funcs': <dynamic>[]};

/// Biến được dùng trong chương trình nhưng chưa khai báo → thêm vào danh sách biến.
void collectVars(Json prog) {
  final vars = ((prog['vars'] ??= <dynamic>[]) as List);
  void walk(dynamic x) {
    if (x is List) {
      x.forEach(walk);
    } else if (x is Map) {
      final s = specs[x['op']];
      final a = x['a'];
      if (s != null && a is Map) {
        s.slots.forEach((k, slot) {
          if (slot.kind == SlotKind.varName && a[k] is String && (a[k] as String).isNotEmpty && !vars.contains(a[k])) vars.add(a[k]);
        });
        a.values.forEach(walk);
      }
      walk(x['do']);
      walk(x['else']);
    }
  }

  walk(prog['main']);
  for (final f in ((prog['funcs'] ?? const []) as List).cast<Map>()) {
    walk(f['body']);
  }
}

// ---------- Chuyển khối Blockly (bản HTML cũ) ----------
Json fromBlockly(Map data) {
  final idName = <String, String>{};
  for (final v in ((data['variables'] ?? const []) as List).cast<Map>()) {
    idName['${v['id']}'] = '${v['name']}';
  }
  final prog = emptyProgram()..['vars'] = <dynamic>[...idName.values];
  final tops = (((data['blocks'] as Map?)?['blocks']) ?? const []) as List;

  String field(Map b, String name) {
    final f = (b['fields'] as Map?)?[name];
    if (f is Map) return idName['${f['id']}'] ?? '${f['name'] ?? f['id'] ?? ''}';
    return f == null ? '' : '$f';
  }

  Map? input(Map b, String name) {
    final i = (b['inputs'] as Map?)?[name];
    if (i is! Map) return null;
    return (i['block'] ?? i['shadow']) as Map?;
  }

  late dynamic Function(Map? b) val;
  late List<dynamic> Function(Map? b) chain;

  dynamic value(Map b, String name) => val(input(b, name));

  Json node(String op, Map<String, dynamic> a, {List? doList, List? elseList}) {
    final n = newNode(op);
    (n['a'] as Map).addAll(a);
    if (doList != null) n['do'] = doList;
    if (elseList != null) n['else'] = elseList;
    return n;
  }

  Json? stmt(Map b) {
    final t = b['type'] as String? ?? '';
    final colorF = {'COLOR': field(b, 'COLOR')};
    switch (t) {
      case 'variables_set':
        return node('var_set', {'VAR': field(b, 'VAR'), 'X': value(b, 'VALUE')});
      case 'math_change':
        return node('var_change', {'VAR': field(b, 'VAR'), 'X': value(b, 'DELTA')});
      case 'controls_for':
        return node('for', {'VAR': field(b, 'VAR'), 'FROM': value(b, 'FROM'), 'TO': value(b, 'TO'), 'BY': value(b, 'BY')}, doList: chain(input(b, 'DO')));
      case 'controls_repeat_ext':
      case 'controls_repeat':
        return node('repeat', {'N': t == 'controls_repeat' ? field(b, 'TIMES') : value(b, 'TIMES')}, doList: chain(input(b, 'DO')));
      case 'controls_whileUntil':
        return node(field(b, 'MODE') == 'UNTIL' ? 'until' : 'while', {'COND': value(b, 'BOOL')}, doList: chain(input(b, 'DO')));
      case 'controls_forEach':
        return node('foreach', {'VAR': field(b, 'VAR'), 'LIST': value(b, 'LIST')}, doList: chain(input(b, 'DO')));
      case 'controls_flow_statements':
        return node(field(b, 'FLOW') == 'CONTINUE' ? 'continue' : 'break', {});
      case 'controls_if':
        final ex = (b['extraState'] as Map?) ?? const {};
        final elseIf = (ex['elseIfCount'] ?? 0) as int;
        final hasElse = ex['hasElse'] == true;
        List? tail = hasElse ? chain(input(b, 'ELSE')) : null;
        for (var i = elseIf; i >= 1; i--) {
          final inner = node(tail == null ? 'if' : 'ifelse', {'COND': value(b, 'IF$i')}, doList: chain(input(b, 'DO$i')), elseList: tail);
          tail = [inner];
        }
        return node(tail == null ? 'if' : 'ifelse', {'COND': value(b, 'IF0')}, doList: chain(input(b, 'DO0')), elseList: tail);
      case 'lists_setIndex':
        final list = input(b, 'LIST');
        final varName = list != null && list['type'] == 'variables_get' ? field(list, 'VAR') : 'a';
        final where = field(b, 'WHERE');
        final at = where == 'FIRST' ? '0' : value(b, 'AT');
        if (field(b, 'MODE') == 'INSERT') {
          return where == 'LAST' ? node('list_push', {'VAR': varName, 'X': value(b, 'TO')}) : node('list_insert', {'VAR': varName, 'I': at, 'X': value(b, 'TO')});
        }
        return node('list_set', {'VAR': varName, 'I': at, 'X': value(b, 'TO')});
      case 'lists_getIndex':
        final list = input(b, 'VALUE');
        final varName = list != null && list['type'] == 'variables_get' ? field(list, 'VAR') : 'a';
        return field(b, 'WHERE') == 'LAST' ? node('js', {'CODE': '${jsName('v_', varName)}.pop();'}) : node('list_remove', {'VAR': varName, 'I': field(b, 'WHERE') == 'FIRST' ? '0' : value(b, 'AT')});
      case 'procedures_ifreturn':
        return node('if', {'COND': value(b, 'CONDITION')}, doList: [node('return', {'X': value(b, 'VALUE')})]);
      case 'procedures_callnoreturn':
        final ex = (b['extraState'] as Map?) ?? const {};
        final params = ((ex['params'] ?? const []) as List);
        return node('call', {'FN': '${ex['name'] ?? ''}', for (var i = 0; i < params.length; i++) 'P$i': value(b, 'ARG$i')});
      case 'dsa_array_create':
        return node('array_create', {'VAR': field(b, 'VAR'), 'LIST': value(b, 'LIST'), 'STYLE': field(b, 'STYLE')});
      case 'dsa_array_set':
        return node('array_set', {'VAR': field(b, 'VAR'), 'I': value(b, 'I'), 'X': value(b, 'X')});
      case 'dsa_array_swap':
        return node('array_swap', {'VAR': field(b, 'VAR'), 'I': value(b, 'I'), 'J': value(b, 'J')});
      case 'dsa_array_mark':
        return node('array_mark', {'VAR': field(b, 'VAR'), 'I': value(b, 'I'), ...colorF});
      case 'dsa_array_pointer':
        return node('array_pointer', {'NAME': field(b, 'NAME'), 'VAR': field(b, 'VAR'), 'I': value(b, 'I')});
      case 'dsa_array_push':
        return node('array_push', {'VAR': field(b, 'VAR'), 'X': value(b, 'X')});
      case 'dsa_ds_create':
        return node('ds_create', {'VAR': field(b, 'VAR'), 'KIND': field(b, 'KIND')});
      case 'dsa_ds_push':
        return node('ds_push', {'VAR': field(b, 'VAR'), 'X': value(b, 'X')});
      case 'dsa_ds_pop_stmt':
        return node('ds_pop_stmt', {'VAR': field(b, 'VAR')});
      case 'dsa_grid_from_lines':
        return node('grid_from_lines', {'VAR': field(b, 'VAR'), 'LINES': value(b, 'LINES')});
      case 'dsa_grid_create':
        return node('grid_create', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C')});
      case 'dsa_grid_set':
        return node('grid_set', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C'), 'X': value(b, 'X')});
      case 'dsa_grid_mark':
        return node('grid_mark', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C'), ...colorF});
      case 'dsa_graph_create':
        return node('graph_create', {'VAR': field(b, 'VAR'), 'LIST': value(b, 'LIST'), 'K': field(b, 'K'), 'DIR': field(b, 'DIRECTED') == 'TRUE' || field(b, 'DIRECTED') == 'true' ? 'true' : 'false'});
      case 'dsa_tree_create':
        return node('tree_create', {'VAR': field(b, 'VAR')});
      case 'dsa_graph_add_node':
        return node('graph_add_node', {'VAR': field(b, 'VAR'), 'N': value(b, 'N')});
      case 'dsa_graph_add_edge':
        return node('graph_add_edge', {'VAR': field(b, 'VAR'), 'U': value(b, 'U'), 'W': value(b, 'W')});
      case 'dsa_graph_visit':
        return node('graph_visit', {'VAR': field(b, 'VAR'), 'N': value(b, 'N'), ...colorF});
      case 'dsa_graph_edge':
        return node('graph_edge', {'VAR': field(b, 'VAR'), 'U': value(b, 'U'), 'W': value(b, 'W'), ...colorF});
      case 'dsa_graph_label':
        return node('graph_label', {'VAR': field(b, 'VAR'), 'N': value(b, 'N'), 'X': value(b, 'X')});
      case 'dsa_step':
        return node('step', {'X': value(b, 'X')});
      case 'dsa_var':
        return node('show_var', {'NAME': field(b, 'NAME'), 'X': value(b, 'X')});
      case 'dsa_log':
      case 'text_print':
        return node('log', {'X': value(b, t == 'text_print' ? 'TEXT' : 'X')});
      case 'dsa_auto':
        return node('auto', {'ON': field(b, 'ON') == 'TRUE' ? 'true' : 'false'});
    }
    // Khối giá trị đặt rời làm câu lệnh: bỏ qua.
    return null;
  }

  val = (Map? b) {
    if (b == null) return null;
    final t = b['type'] as String? ?? '';
    Json v(String op, Map<String, dynamic> a) => node(op, a);
    switch (t) {
      case 'math_number':
        return field(b, 'NUM');
      case 'text':
        return field(b, 'TEXT');
      case 'logic_boolean':
        return v('bool', {'V': field(b, 'BOOL') == 'TRUE' ? 'true' : 'false'});
      case 'variables_get':
        return v('var_get', {'VAR': field(b, 'VAR')});
      case 'math_arithmetic':
        return v('arith', {'A': value(b, 'A'), 'OP': const {'ADD': '+', 'MINUS': '-', 'MULTIPLY': '*', 'DIVIDE': '/', 'POWER': '**'}[field(b, 'OP')] ?? '+', 'B': value(b, 'B')});
      case 'math_modulo':
        return v('mod', {'A': value(b, 'DIVIDEND'), 'B': value(b, 'DIVISOR')});
      case 'logic_compare':
        return v('compare', {'A': value(b, 'A'), 'OP': const {'EQ': '==', 'NEQ': '!=', 'LT': '<', 'LTE': '<=', 'GT': '>', 'GTE': '>='}[field(b, 'OP')] ?? '==', 'B': value(b, 'B')});
      case 'logic_operation':
        return v('and', {'A': value(b, 'A'), 'OP': field(b, 'OP') == 'OR' ? '||' : '&&', 'B': value(b, 'B')});
      case 'logic_negate':
        return v('not', {'A': value(b, 'BOOL')});
      case 'math_single':
      case 'math_round':
        final op = field(b, 'OP');
        if (op == 'NEG') return v('arith', {'A': '0', 'OP': '-', 'B': value(b, 'NUM')});
        return v('mathfn', {'F': const {'ROOT': 'sqrt', 'ABS': 'abs', 'ROUND': 'round', 'ROUNDUP': 'ceil', 'ROUNDDOWN': 'floor', 'LOG10': 'log10'}[op] ?? 'abs', 'X': value(b, 'NUM')});
      case 'math_random_int':
        return v('random', {'A': value(b, 'FROM'), 'B': value(b, 'TO')});
      case 'math_number_property':
        final p = field(b, 'PROPERTY');
        return p == 'ODD' ? v('parity', {'X': value(b, 'NUMBER_TO_CHECK'), 'P': 'odd'}) : v('parity', {'X': value(b, 'NUMBER_TO_CHECK'), 'P': 'even'});
      case 'math_on_list':
        final op = field(b, 'OP');
        return v('list_agg', {'F': op == 'MIN' ? 'min' : op == 'MAX' ? 'max' : 'sum', 'L': value(b, 'LIST')});
      case 'math_constant':
        return field(b, 'CONSTANT') == 'INFINITY' ? v('infinity', {'S': ''}) : v('js_expr', {'CODE': 'Math.PI'});
      case 'text_join':
        final count = ((b['extraState'] as Map?)?['itemCount'] ?? 2) as int;
        dynamic acc = '';
        for (var i = 0; i < count; i++) {
          final x = value(b, 'ADD$i');
          acc = i == 0 ? (x ?? '') : v('join', {'A': acc, 'B': x ?? ''});
        }
        return acc;
      case 'text_length':
        return v('text_len', {'X': value(b, 'VALUE')});
      case 'text_charAt':
        return v('char_at', {'I': value(b, 'AT') ?? '0', 'X': value(b, 'VALUE')});
      case 'lists_create_empty':
        return v('list_new', {});
      case 'lists_create_with':
        final count = ((b['extraState'] as Map?)?['itemCount'] ?? 0) as int;
        final items = [for (var i = 0; i < count; i++) value(b, 'ADD$i')];
        if (items.every((x) => x is String)) return v('list_of', {'T': items.join(' ')});
        return v('js_expr', {'CODE': '[${items.map((x) => x is String ? (num.tryParse(x) != null ? x : jsStr(x)) : 'null').join(', ')}]'});
      case 'lists_repeat':
        return v('list_fill', {'N': value(b, 'NUM'), 'X': value(b, 'ITEM')});
      case 'lists_length':
        return v('list_len', {'L': value(b, 'VALUE')});
      case 'lists_isEmpty':
        return v('list_empty', {'L': value(b, 'VALUE')});
      case 'lists_indexOf':
        return v('list_index', {'X': value(b, 'FIND'), 'L': value(b, 'VALUE')});
      case 'lists_sort':
        return v('list_sorted', {'L': value(b, 'LIST'), 'DIR': field(b, 'DIRECTION') == '-1' ? 'desc' : 'asc'});
      case 'lists_getIndex':
        final where = field(b, 'WHERE');
        final list = input(b, 'VALUE');
        if (field(b, 'MODE') == 'GET_REMOVE' && where == 'LAST' && list != null && list['type'] == 'variables_get') return v('list_pop', {'VAR': field(list, 'VAR')});
        final at = where == 'FIRST' ? '0' : where == 'LAST' ? null : value(b, 'AT');
        if (at == null) return v('list_get', {'I': v('arith', {'A': v('list_len', {'L': value(b, 'VALUE')}), 'OP': '-', 'B': '1'}), 'L': value(b, 'VALUE')});
        return v('list_get', {'I': at, 'L': value(b, 'VALUE')});
      case 'procedures_callreturn':
        final ex = (b['extraState'] as Map?) ?? const {};
        final params = ((ex['params'] ?? const []) as List);
        return v('call_value', {'FN': '${ex['name'] ?? ''}', for (var i = 0; i < params.length; i++) 'P$i': value(b, 'ARG$i')});
      case 'dsa_read_numbers':
        return v('read_numbers', {});
      case 'dsa_input_text':
        return v('input_text', {});
      case 'dsa_input_lines':
        return v('input_lines', {});
      case 'dsa_array_get':
        return v('array_get', {'VAR': field(b, 'VAR'), 'I': value(b, 'I')});
      case 'dsa_array_length':
        return v('array_len', {'VAR': field(b, 'VAR')});
      case 'dsa_array_compare':
        return v('array_compare', {'VAR': field(b, 'VAR'), 'I': value(b, 'I'), 'OP': const {'GT': '>', 'LT': '<', 'EQ': '==='}[field(b, 'OP')] ?? '>', 'J': value(b, 'J')});
      case 'dsa_ds_pop':
        return v('ds_pop', {'VAR': field(b, 'VAR')});
      case 'dsa_ds_peek':
        return v('ds_peek', {'VAR': field(b, 'VAR'), 'WHICH': field(b, 'WHICH')});
      case 'dsa_ds_empty':
        return v('ds_empty', {'VAR': field(b, 'VAR')});
      case 'dsa_ds_size':
        return v('ds_size', {'VAR': field(b, 'VAR')});
      case 'dsa_grid_get':
        return v('grid_get', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C')});
      case 'dsa_grid_is':
        return v('grid_is', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C'), 'COLOR': field(b, 'COLOR')});
      case 'dsa_grid_inside':
        return v('grid_inside', {'VAR': field(b, 'VAR'), 'R': value(b, 'R'), 'C': value(b, 'C')});
      case 'dsa_grid_size':
        return v('grid_size', {'VAR': field(b, 'VAR'), 'DIM': field(b, 'DIM')});
      case 'dsa_graph_neighbors':
        return v('graph_neighbors', {'VAR': field(b, 'VAR'), 'N': value(b, 'N')});
      case 'dsa_graph_weight':
        return v('graph_weight', {'VAR': field(b, 'VAR'), 'U': value(b, 'U'), 'W': value(b, 'W')});
    }
    return null;
  };

  chain = (Map? b) {
    final out = <dynamic>[];
    var cur = b;
    while (cur != null) {
      final s = stmt(cur);
      if (s != null) out.add(s);
      cur = (cur['next'] as Map?)?['block'] as Map?;
    }
    return out;
  };

  // Khối đầu tiên (không phải định nghĩa hàm) và các khối rời được nối thành chương trình chính theo vị trí từ trên xuống.
  final sorted = tops.cast<Map>().toList()..sort((a, b) => ((a['y'] ?? 0) as num).compareTo((b['y'] ?? 0) as num));
  for (final t in sorted) {
    final type = t['type'] as String? ?? '';
    if (type == 'procedures_defnoreturn' || type == 'procedures_defreturn') {
      final ex = (t['extraState'] as Map?) ?? const {};
      final params = [for (final p in ((ex['params'] ?? const []) as List).cast<Map>()) '${p['name']}'];
      final body = chain(input(t, 'STACK'));
      final ret = value(t, 'RETURN');
      if (type == 'procedures_defreturn' && ret != null) body.add(node('return', {'X': ret}));
      (prog['funcs'] as List).add({'name': field(t, 'NAME'), 'params': params, 'body': body});
    } else {
      (prog['main'] as List).addAll(chain(t));
    }
  }
  _dropNulls(prog);
  collectVars(prog);
  return prog;
}

// Ô giá trị trống (null) → bỏ để dùng giá trị mặc định.
void _dropNulls(dynamic x) {
  if (x is List) {
    x.forEach(_dropNulls);
  } else if (x is Map) {
    final a = x['a'];
    if (a is Map) {
      a.removeWhere((k, v) => v == null);
      a.values.forEach(_dropNulls);
    }
    for (final k in ['main', 'funcs', 'body', 'do', 'else']) {
      if (x[k] != null) _dropNulls(x[k]);
    }
  }
}
