// Trình phát mô phỏng: tua tới/lui từng bước, vẽ mảng / lưới / đồ thị / stack bằng CustomPainter.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/sim.dart';

const _stateColors = {
  'compare': Color(0xFFF59E0B), 'swap': Color(0xFFEF4444), 'set': Color(0xFFA855F7), 'active': Color(0xFF3B82F6),
  'current': Color(0xFFEF4444), 'done': Color(0xFF22C55E), 'sorted': Color(0xFF22C55E), 'found': Color(0xFF16A34A),
  'visited': Color(0xFF8B5CF6), 'path': Color(0xFFF97316), 'start': Color(0xFF10B981), 'end': Color(0xFFE11D48),
  'frontier': Color(0xFF06B6D4), 'dim': Color(0xFF94A3B8),
};

Color? stateColor(dynamic st, bool dark) {
  if (st == null) return null;
  final s = '$st';
  if (s == 'wall') return dark ? const Color(0xFF64748B) : const Color(0xFF334155);
  if (_stateColors.containsKey(s)) return _stateColors[s];
  if (s.startsWith('#') && (s.length == 7 || s.length == 4)) {
    final hex = s.length == 4 ? s.substring(1).split('').map((c) => '$c$c').join() : s.substring(1);
    return Color(int.parse('FF$hex', radix: 16));
  }
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) % 360;
  }
  return HSLColor.fromAHSL(1, h.toDouble(), .65, .5).toColor();
}

class SimPlayer extends StatefulWidget {
  final String code, input;
  final int runKey; // đổi giá trị để chạy lại
  const SimPlayer({super.key, required this.code, required this.input, this.runKey = 0});
  @override
  State<SimPlayer> createState() => _SimPlayerState();
}

class _SimPlayerState extends State<SimPlayer> {
  SimResult? result;
  bool running = false;
  int cur = 0;
  Timer? timer;
  double speed = 1;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant SimPlayer old) {
    super.didUpdateWidget(old);
    if (old.runKey != widget.runKey) _run();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    _stop();
    setState(() => running = true);
    final r = await runSimulation(widget.code, widget.input);
    if (!mounted) return;
    setState(() {
      result = r;
      cur = 0;
      running = false;
    });
  }

  void _stop() {
    timer?.cancel();
    timer = null;
    if (mounted) setState(() {});
  }

  void _play() {
    final n = result?.frames.length ?? 0;
    if (timer != null) return _stop();
    if (cur >= n - 1) cur = 0;
    timer = Timer.periodic(Duration(milliseconds: (700 / speed).round()), (_) {
      if (cur >= n - 1) return _stop();
      setState(() => cur++);
    });
    setState(() {});
  }

  void _go(int i) {
    final n = result?.frames.length ?? 0;
    setState(() => cur = i.clamp(0, math.max(0, n - 1)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frames = result?.frames ?? [];
    final f = frames.isEmpty ? null : frames[cur];
    final n = frames.length;
    final logs = result == null || f == null ? <String>[] : result!.logs.take(((f['logN'] ?? 0) as num).toInt()).toList();
    final vars = ((f?['vars'] ?? {}) as Map).entries.toList();
    return Container(
      decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(tooltip: 'Về đầu', icon: const Icon(Icons.first_page), onPressed: n == 0 ? null : () { _stop(); _go(0); }),
          IconButton(tooltip: 'Lùi', icon: const Icon(Icons.chevron_left), onPressed: n == 0 ? null : () { _stop(); _go(cur - 1); }),
          IconButton(tooltip: 'Chạy / dừng', icon: Icon(timer != null ? Icons.pause : Icons.play_arrow), onPressed: n == 0 ? null : _play),
          IconButton(tooltip: 'Tới', icon: const Icon(Icons.chevron_right), onPressed: n == 0 ? null : () { _stop(); _go(cur + 1); }),
          IconButton(tooltip: 'Về cuối', icon: const Icon(Icons.last_page), onPressed: n == 0 ? null : () { _stop(); _go(n - 1); }),
          Expanded(
            child: Slider(
              value: n == 0 ? 0 : cur.toDouble(),
              max: math.max(0, n - 1).toDouble(),
              onChanged: n <= 1 ? null : (v) { _stop(); _go(v.round()); },
            ),
          ),
          DropdownButton<double>(
            value: speed,
            underline: const SizedBox(),
            items: const [0.5, 1.0, 2.0, 4.0, 10.0].map((s) => DropdownMenuItem(value: s, child: Text('${s == s.roundToDouble() ? s.toInt() : s}x'))).toList(),
            onChanged: (s) => setState(() {
              speed = s ?? 1;
              if (timer != null) { _stop(); _play(); }
            }),
          ),
          const SizedBox(width: 8),
          Text(n == 0 ? '' : 'Bước ${cur + 1}/$n', style: theme.textTheme.bodySmall),
        ]),
        if (running) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        if (result?.error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Lỗi: ${result!.error}', style: TextStyle(color: theme.colorScheme.error))),
        if (f != null) ...[
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('${f['note'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final s in (f['s'] as List).cast<Map>()) _StructView(s.cast<String, dynamic>()),
          if (vars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in vars)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(border: Border.all(color: theme.dividerColor), borderRadius: BorderRadius.circular(4)),
                    child: Text('${e.key} = ${e.value}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
              ]),
            ),
          if (logs.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(6),
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              color: theme.colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(reverse: true, child: Text(logs.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ),
        ],
      ]),
    );
  }
}

class _StructView extends StatelessWidget {
  final Map<String, dynamic> s;
  const _StructView(this.s);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final kind = s['kind'];
    final title = '${s['name']}${kind == 'list' ? (s['mode'] == 'stack' ? ' (stack)' : ' (queue)') : ''}';
    late final Size size;
    late final CustomPainter painter;
    switch (kind) {
      case 'array':
        final n = (s['v'] as List).length;
        final w = (680 / math.max(1, n)).clamp(24.0, 52.0);
        final ptrs = (s['ptr'] as Map).values.fold<Map<dynamic, int>>({}, (m, i) => m..[i] = (m[i] ?? 0) + 1);
        final maxPtr = ptrs.values.fold(0, math.max);
        size = Size(n * w + 2, (s['bars'] == true ? 140 : w) + 18 + maxPtr * 15 + 6);
        painter = _ArrayPainter(s, w, theme, dark);
      case 'grid':
        final rows = (s['v'] as List).length;
        final cols = rows == 0 ? 0 : ((s['v'] as List)[0] as List).length;
        final cs = (680 / math.max(1, cols)).clamp(10.0, 36.0);
        size = Size(cols * cs + 2, rows * cs + 2);
        painter = _GridPainter(s, cs, theme, dark);
      case 'graph':
        final depth = (s['depth'] ?? -1) as num;
        size = Size(680, depth >= 0 ? math.max(120, (depth + 1) * 80).toDouble() : 340);
        painter = _GraphPainter(s, theme, dark);
      default:
        final n = (s['v'] as List).length;
        size = Size(math.max(120, n * 46 + 60).toDouble(), 68);
        painter = _ListPainter(s, theme, dark);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: CustomPaint(size: size, painter: painter)),
        ),
      ]),
    );
  }
}

abstract class _BasePainter extends CustomPainter {
  final ThemeData theme;
  final bool dark;
  _BasePainter(this.theme, this.dark);
  Color get fg => theme.colorScheme.onSurface;
  Color get muted => theme.colorScheme.onSurfaceVariant;
  Color get box => dark ? const Color(0xFF24262B) : const Color(0xFFF1F5F9);
  Color get line => dark ? const Color(0xFF3B3F46) : const Color(0xFFCBD5E1);
  Color get accent => theme.colorScheme.primary;

  void text(Canvas c, String t, Offset center, {double size = 14, Color? color, FontWeight weight = FontWeight.w600, bool alignLeft = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontSize: size, color: color ?? fg, fontWeight: weight, fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, alignLeft ? Offset(center.dx, center.dy - tp.height / 2) : center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

String _fmt(dynamic v) => v == null ? '' : '$v';

class _ArrayPainter extends _BasePainter {
  final Map<String, dynamic> s;
  final double w;
  _ArrayPainter(this.s, this.w, super.theme, super.dark);

  @override
  void paint(Canvas c, Size size) {
    final v = s['v'] as List;
    final hl = s['hl'] as Map, st = s['st'] as Map, ptr = s['ptr'] as Map;
    final bars = s['bars'] == true;
    final barH = bars ? 140.0 : 0.0;
    final boxH = bars ? 0.0 : w;
    final nums = v.map((x) => num.tryParse('$x')).whereType<num>();
    final maxV = math.max(1, nums.fold<num>(0, (m, x) => math.max(m, x.abs())));
    final ptrAt = <String, List<String>>{};
    ptr.forEach((k, i) => (ptrAt['$i'] ??= []).add('$k'));
    for (var i = 0; i < v.length; i++) {
      final x = i * w + 1;
      final col = stateColor(hl['$i'], dark) ?? stateColor(st['$i'], dark);
      if (bars) {
        final hh = math.max(4.0, ((num.tryParse('${v[i]}') ?? 0).abs() / maxV) * (barH - 18));
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, barH - hh, w - 4, hh), const Radius.circular(3)), Paint()..color = col ?? const Color(0xFF94A3B8));
        text(c, _fmt(v[i]), Offset(x + w / 2, barH - hh - 8), size: 11);
      } else {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 1, w - 2, w - 2), const Radius.circular(5));
        c.drawRRect(r, Paint()..color = col ?? box);
        c.drawRRect(r, Paint()..color = col ?? line..style = PaintingStyle.stroke..strokeWidth = 1.5);
        text(c, _fmt(v[i]), Offset(x + w / 2 - 1, w / 2), size: math.min(16, w / math.max(1.6, _fmt(v[i]).length * 0.62)), color: col != null ? Colors.white : fg);
      }
      text(c, '$i', Offset(x + w / 2, barH + boxH + 9), size: 11, color: muted, weight: FontWeight.w400);
      final ps = ptrAt['$i'] ?? [];
      for (var k = 0; k < ps.length; k++) {
        text(c, '↑${ps[k]}', Offset(x + w / 2, barH + boxH + 26 + k * 15), size: 12, color: accent);
      }
    }
  }
}

class _GridPainter extends _BasePainter {
  final Map<String, dynamic> s;
  final double cs;
  _GridPainter(this.s, this.cs, super.theme, super.dark);

  @override
  void paint(Canvas c, Size size) {
    final v = s['v'] as List;
    final hl = s['hl'] as Map, st = s['st'] as Map;
    for (var r = 0; r < v.length; r++) {
      final row = v[r] as List;
      for (var col = 0; col < row.length; col++) {
        final key = '$r,$col';
        final fill = stateColor(hl[key], dark) ?? stateColor(st[key], dark);
        final rect = Rect.fromLTWH(col * cs + 1, r * cs + 1, cs, cs);
        c.drawRect(rect, Paint()..color = fill ?? box);
        c.drawRect(rect, Paint()..color = line..style = PaintingStyle.stroke);
        final val = _fmt(row[col]);
        if (s['showValues'] != false && val.isNotEmpty && cs >= 18) {
          text(c, val, rect.center, size: 11, color: fill != null ? Colors.white : fg);
        }
      }
    }
  }
}

class _GraphPainter extends _BasePainter {
  final Map<String, dynamic> s;
  _GraphPainter(this.s, super.theme, super.dark);

  @override
  void paint(Canvas c, Size size) {
    const pad = 32.0;
    final pos = <String, Offset>{};
    for (final n in (s['nodes'] as List).cast<Map>()) {
      pos['${n['id']}'] = Offset(pad + ((n['x'] ?? .5) as num) * (size.width - 2 * pad), pad + 8 + ((n['y'] ?? .5) as num) * (size.height - 2 * pad - 8));
    }
    for (final e in (s['edges'] as List).cast<Map>()) {
      final a = pos['${e['u']}'], b = pos['${e['v']}'];
      if (a == null || b == null) continue;
      final d = b - a;
      final len = math.max(1.0, d.distance);
      final u = d / len;
      final col = stateColor(e['st'], dark);
      final p1 = a + u * 18, p2 = b - u * 18;
      c.drawLine(p1, p2, Paint()..color = col ?? line..strokeWidth = col != null ? 3 : 2);
      if (s['directed'] == true) {
        final left = Offset(-u.dy, u.dx);
        final path = Path()
          ..moveTo(p2.dx, p2.dy)
          ..lineTo((p2 - u * 9 + left * 4.5).dx, (p2 - u * 9 + left * 4.5).dy)
          ..lineTo((p2 - u * 9 - left * 4.5).dx, (p2 - u * 9 - left * 4.5).dy)
          ..close();
        c.drawPath(path, Paint()..color = col ?? muted);
      }
      final w = _fmt(e['w']);
      if (w.isNotEmpty) text(c, w, (a + b) / 2 + Offset(-u.dy, u.dx) * 10, size: 12, color: muted, weight: FontWeight.w400);
    }
    for (final n in (s['nodes'] as List).cast<Map>()) {
      final p = pos['${n['id']}']!;
      final col = stateColor(n['hl'], dark) ?? stateColor(n['st'], dark);
      c.drawCircle(p, 18, Paint()..color = col ?? box);
      c.drawCircle(p, 18, Paint()..color = col ?? line..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final label = _fmt(n['label']);
      text(c, label, p, size: label.length > 3 ? 11 : 14, color: col != null ? Colors.white : fg);
      final sub = _fmt(n['sub']);
      if (sub.isNotEmpty) text(c, sub, p - const Offset(0, 25), size: 11, color: accent);
    }
  }
}

class _ListPainter extends _BasePainter {
  final Map<String, dynamic> s;
  _ListPainter(this.s, super.theme, super.dark);

  @override
  void paint(Canvas c, Size size) {
    const w = 46.0;
    final v = s['v'] as List;
    final hl = s['hl'] as Map;
    if (v.isEmpty) text(c, '(rỗng)', const Offset(4, w / 2), size: 12, color: muted, weight: FontWeight.w400, alignLeft: true);
    for (var i = 0; i < v.length; i++) {
      final x = i * w + 1;
      final col = stateColor(hl['$i'], dark);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, 1, w - 2, w - 2), const Radius.circular(5));
      c.drawRRect(r, Paint()..color = col ?? box);
      c.drawRRect(r, Paint()..color = col ?? line..style = PaintingStyle.stroke..strokeWidth = 1.5);
      text(c, _fmt(v[i]), Offset(x + w / 2 - 1, w / 2), size: 15, color: col != null ? Colors.white : fg);
    }
    if (v.isNotEmpty) {
      if (s['mode'] == 'stack') {
        text(c, '↑ đỉnh', Offset((v.length - 1) * w + w / 2, w + 12), size: 12, color: accent);
      } else {
        text(c, '↑ đầu', const Offset(w / 2, w + 12), size: 12, color: accent);
        if (v.length > 1) text(c, '↑ cuối', Offset((v.length - 1) * w + w / 2, w + 12), size: 12, color: accent);
      }
    }
  }
}
