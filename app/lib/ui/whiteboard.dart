// Bảng trắng: vẽ tay, đường thẳng, mũi tên, hình chữ nhật, hình tròn, chữ, tẩy, hoàn tác.
// Nét vẽ lưu dạng vector trong notebook (nên có lịch sử, commit, merge, chia sẻ như nội dung khác).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/vcs.dart' show Json;
import 'theme.dart';
import 'widgets.dart';

const boardWidth = 1000.0; // toạ độ logic; bảng co giãn theo chiều rộng màn hình

const boardColors = [
  Color(0xFF1F2328),
  Color(0xFFCF222E),
  Color(0xFF0969DA),
  Color(0xFF1A7F37),
  Color(0xFFBF8700),
  Color(0xFF8250DF),
  Color(0xFFE16F24),
  Color(0xFF6E7781),
];

enum Tool { pen, highlighter, line, arrow, rect, ellipse, text, eraser }

const _toolInfo = {
  Tool.pen: (Icons.edit, 'Bút'),
  Tool.highlighter: (Icons.brush, 'Bút dạ (tô mờ)'),
  Tool.line: (Icons.horizontal_rule, 'Đường thẳng'),
  Tool.arrow: (Icons.north_east, 'Mũi tên'),
  Tool.rect: (Icons.crop_square, 'Hình chữ nhật'),
  Tool.ellipse: (Icons.circle_outlined, 'Hình tròn / elip'),
  Tool.text: (Icons.text_fields, 'Chữ'),
  Tool.eraser: (Icons.auto_fix_normal, 'Tẩy'),
};

List _strokes(Json b) => (b['strokes'] ??= <dynamic>[]) as List;
double _height(Json b) => ((b['height'] ?? 560) as num).toDouble();

class _BoardPainter extends CustomPainter {
  final List strokes;
  final Map? live;
  final String bg;
  final double scale, h;
  _BoardPainter(this.strokes, this.live, this.bg, this.scale, this.h);

  static List<Offset> pts(Map s) {
    final p = (s['p'] as List).cast<num>();
    return [for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i].toDouble(), p[i + 1].toDouble())];
  }

  void _draw(Canvas c, Map s) {
    final t = s['t'] as String;
    final color = Color((s['c'] ?? 0xFF1F2328) as int);
    final w = ((s['w'] ?? 3) as num).toDouble();
    final paint = Paint()
      ..color = t == 'highlighter' ? color.withValues(alpha: .35) : color
      ..strokeWidth = t == 'highlighter' ? w * 4 : w
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = pts(s);
    if (p.isEmpty) return;
    switch (t) {
      case 'pen' || 'highlighter':
        if (p.length == 1) {
          c.drawCircle(p.first, paint.strokeWidth / 2, Paint()..color = paint.color);
          return;
        }
        final path = Path()..moveTo(p.first.dx, p.first.dy);
        for (var i = 1; i < p.length - 1; i++) {
          final mid = (p[i] + p[i + 1]) / 2;
          path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
        }
        path.lineTo(p.last.dx, p.last.dy);
        c.drawPath(path, paint);
      case 'line' || 'arrow':
        if (p.length < 2) return;
        c.drawLine(p[0], p[1], paint);
        if (t == 'arrow') {
          final d = p[1] - p[0];
          if (d.distance < 1) return;
          final ang = math.atan2(d.dy, d.dx);
          final len = 10 + w * 3;
          for (final a in [ang + 2.6, ang - 2.6]) {
            c.drawLine(p[1], p[1] + Offset(math.cos(a), math.sin(a)) * len, paint);
          }
        }
      case 'rect':
        if (p.length < 2) return;
        c.drawRect(Rect.fromPoints(p[0], p[1]), paint);
      case 'ellipse':
        if (p.length < 2) return;
        c.drawOval(Rect.fromPoints(p[0], p[1]), paint);
      case 'text':
        final tp = TextPainter(
          text: TextSpan(text: '${s['text'] ?? ''}', style: TextStyle(color: color, fontSize: 10 + w * 4, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: boardWidth - p.first.dx);
        tp.paint(c, p.first);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    canvas.clipRect(Rect.fromLTWH(0, 0, boardWidth, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, boardWidth, h), Paint()..color = const Color(0xFFFFFFFF));
    if (bg != 'plain') {
      final g = Paint()
        ..color = const Color(0xFFDDE1E6)
        ..strokeWidth = 1;
      for (var x = 40.0; x < boardWidth; x += 40) {
        for (var y = 40.0; y < h; y += 40) {
          if (bg == 'dots') canvas.drawCircle(Offset(x, y), 1.4, g);
        }
        if (bg == 'grid') canvas.drawLine(Offset(x, 0), Offset(x, h), g);
      }
      if (bg == 'grid') {
        for (var y = 40.0; y < h; y += 40) {
          canvas.drawLine(Offset(0, y), Offset(boardWidth, y), g);
        }
      }
    }
    for (final s in strokes) {
      if (s is Map) _draw(canvas, s);
    }
    if (live != null) _draw(canvas, live!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

/// Khối bảng trắng trong trang.
class WhiteboardBlock extends StatelessWidget {
  final Json block;
  final bool ro;
  const WhiteboardBlock({super.key, required this.block, required this.ro});

  @override
  Widget build(BuildContext context) {
    final touch = Platform.isAndroid || Platform.isIOS;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.draw_outlined, size: 16, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text((block['title'] ?? '').toString().isEmpty ? 'Bảng trắng' : '${block['title']}', style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
        TextButton.icon(
          onPressed: () => openBoardFullscreen(context, block, ro),
          icon: const Icon(Icons.fullscreen, size: 18),
          label: Text(ro ? 'Phóng to' : 'Vẽ toàn màn hình'),
        ),
      ]),
      const SizedBox(height: 6),
      // Trên điện thoại vẽ ở chế độ toàn màn hình (để vuốt trang không bị nhầm thành nét vẽ).
      Whiteboard(block: block, ro: ro || touch, onTapReadOnly: touch && !ro ? () => openBoardFullscreen(context, block, ro) : null),
    ]);
  }
}

Future<void> openBoardFullscreen(BuildContext context, Json block, bool ro) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (c) => Scaffold(
      appBar: AppBar(title: Text((block['title'] ?? '').toString().isEmpty ? 'Bảng trắng' : '${block['title']}')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(8), physics: const NeverScrollableScrollPhysics(), child: Whiteboard(block: block, ro: ro, fit: true)),
    ),
  ));
}

class Whiteboard extends StatefulWidget {
  final Json block;
  final bool ro;
  final bool fit; // co bảng cho vừa màn hình (chế độ toàn màn hình)
  final VoidCallback? onTapReadOnly;
  final VoidCallback? onChanged; // mặc định: lưu notebook đang mở
  const Whiteboard({super.key, required this.block, required this.ro, this.fit = false, this.onTapReadOnly, this.onChanged});
  @override
  State<Whiteboard> createState() => _WhiteboardState();
}

class _WhiteboardState extends State<Whiteboard> {
  Tool tool = Tool.pen;
  Color color = boardColors.first;
  double width = 3;
  Map? live;
  final List redo = [];

  Json get b => widget.block;

  void _save() {
    if (!mounted) return;
    if (widget.onChanged != null) return widget.onChanged!();
    context.read<AppState>().edited();
  }

  Offset _toBoard(Offset local, double scale) => local / scale;

  void _start(Offset p) {
    if (tool == Tool.eraser) {
      _erase(p);
      return;
    }
    if (tool == Tool.text) return;
    live = {
      't': tool.name,
      'c': color.toARGB32(),
      'w': width,
      'p': <dynamic>[p.dx.roundToDouble(), p.dy.roundToDouble()],
    };
    if (tool != Tool.pen && tool != Tool.highlighter) (live!['p'] as List).addAll([p.dx.roundToDouble(), p.dy.roundToDouble()]);
    setState(() {});
  }

  void _move(Offset p) {
    if (tool == Tool.eraser) return _erase(p);
    final s = live;
    if (s == null) return;
    final list = s['p'] as List;
    if (tool == Tool.pen || tool == Tool.highlighter) {
      final last = Offset((list[list.length - 2] as num).toDouble(), (list[list.length - 1] as num).toDouble());
      if ((p - last).distance < 2) return;
      list.addAll([p.dx.roundToDouble(), p.dy.roundToDouble()]);
    } else {
      list[2] = p.dx.roundToDouble();
      list[3] = p.dy.roundToDouble();
    }
    setState(() {});
  }

  void _end() {
    final s = live;
    if (s == null) return;
    live = null;
    _strokes(b).add(s);
    redo.clear();
    setState(() {});
    _save();
  }

  void _erase(Offset p) {
    final list = _strokes(b);
    final r = 8 + width * 2;
    final before = list.length;
    list.removeWhere((s) {
      if (s is! Map) return false;
      final pts = _BoardPainter.pts(s);
      if (s['t'] == 'rect' || s['t'] == 'ellipse' || s['t'] == 'line' || s['t'] == 'arrow') {
        if (pts.length < 2) return false;
        final rect = Rect.fromPoints(pts[0], pts[1]).inflate(r);
        if (!rect.contains(p)) return false;
        if (s['t'] == 'line' || s['t'] == 'arrow') return _distToSegment(p, pts[0], pts[1]) < r;
        return true;
      }
      if (s['t'] == 'text') return pts.isNotEmpty && (Rect.fromLTWH(pts.first.dx, pts.first.dy, 12.0 * '${s['text']}'.length + 20, 40)).contains(p);
      for (var i = 0; i < pts.length; i++) {
        if ((pts[i] - p).distance < r) return true;
        if (i > 0 && _distToSegment(p, pts[i - 1], pts[i]) < r) return true;
      }
      return false;
    });
    if (list.length != before) {
      setState(() {});
      _save();
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Future<void> _text(Offset p) async {
    final t = await promptBox(context, 'Thêm chữ', 'Nội dung', ok: 'Thêm');
    if (t == null || t.trim().isEmpty) return;
    _strokes(b).add({'t': 'text', 'c': color.toARGB32(), 'w': width, 'p': [p.dx.roundToDouble(), p.dy.roundToDouble()], 'text': t});
    redo.clear();
    setState(() {});
    _save();
  }

  Widget _toolbar() {
    final sel = context.cs.primaryContainer;
    Widget toolBtn(Tool t) => IconButton(
          tooltip: _toolInfo[t]!.$2,
          visualDensity: VisualDensity.compact,
          isSelected: tool == t,
          style: IconButton.styleFrom(backgroundColor: tool == t ? sel : null),
          icon: Icon(_toolInfo[t]!.$1, size: 20),
          onPressed: () => setState(() => tool = t),
        );
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: [
      for (final t in Tool.values) toolBtn(t),
      Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.cs.outlineVariant),
      for (final c in boardColors)
        InkWell(
          onTap: () => setState(() {
            color = c;
            if (tool == Tool.eraser) tool = Tool.pen;
          }),
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: color == c ? context.cs.primary : Colors.white, width: color == c ? 3 : 1.5),
            ),
          ),
        ),
      Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.cs.outlineVariant),
      PopupMenuButton<double>(
        tooltip: 'Độ dày nét',
        initialValue: width,
        onSelected: (v) => setState(() => width = v),
        itemBuilder: (_) => [
          for (final (v, n) in [(2.0, 'Mảnh'), (3.0, 'Vừa'), (6.0, 'Đậm'), (10.0, 'Rất đậm')]) PopupMenuItem(value: v, child: Row(children: [Container(width: 30, height: v, color: Colors.black87), const SizedBox(width: 10), Text(n)])),
        ],
        child: Padding(padding: const EdgeInsets.all(6), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 22, height: width.clamp(1, 10), color: context.cs.onSurface), const Icon(Icons.arrow_drop_down, size: 18)])),
      ),
      PopupMenuButton<String>(
        tooltip: 'Nền bảng',
        onSelected: (v) {
          setState(() => b['bg'] = v);
          _save();
        },
        itemBuilder: (_) => const [PopupMenuItem(value: 'plain', child: Text('Nền trơn')), PopupMenuItem(value: 'grid', child: Text('Kẻ ô')), PopupMenuItem(value: 'dots', child: Text('Chấm'))],
        icon: const Icon(Icons.grid_on, size: 20),
      ),
      IconButton(
        tooltip: 'Hoàn tác',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.undo, size: 20),
        onPressed: _strokes(b).isEmpty
            ? null
            : () {
                setState(() => redo.add(_strokes(b).removeLast()));
                _save();
              },
      ),
      IconButton(
        tooltip: 'Làm lại',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.redo, size: 20),
        onPressed: redo.isEmpty
            ? null
            : () {
                setState(() => _strokes(b).add(redo.removeLast()));
                _save();
              },
      ),
      IconButton(
        tooltip: 'Bảng cao hơn',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.expand, size: 20),
        onPressed: () {
          setState(() => b['height'] = (_height(b) + 200).clamp(200, 4000));
          _save();
        },
      ),
      IconButton(
        tooltip: 'Xoá hết',
        visualDensity: VisualDensity.compact,
        icon: Icon(Icons.delete_sweep_outlined, size: 20, color: context.cs.error),
        onPressed: _strokes(b).isEmpty
            ? null
            : () async {
                if (!await confirmBox(context, 'Xoá hết bảng?', 'Mọi nét vẽ trên bảng sẽ bị xoá (vẫn khôi phục được từ lịch sử commit).', ok: 'Xoá hết', danger: true)) return;
                setState(() {
                  redo
                    ..clear()
                    ..addAll(_strokes(b).reversed);
                  _strokes(b).clear();
                });
                _save();
              },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final h = _height(b);
    final bg = (b['bg'] ?? 'grid') as String;
    return LayoutBuilder(builder: (context, box) {
      var w = box.maxWidth;
      if (widget.fit) {
        // Toàn màn hình: vừa cả chiều rộng lẫn chiều cao còn lại.
        final avail = MediaQuery.sizeOf(context).height - 200;
        w = math.min(w, avail / h * boardWidth);
      }
      final scale = w / boardWidth;
      final canvas = SizedBox(
        width: w,
        height: h * scale,
        child: CustomPaint(painter: _BoardPainter(_strokes(b), live, bg, scale, h)),
      );
      final framed = Container(
        decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: widget.ro
            ? GestureDetector(onTap: widget.onTapReadOnly, child: canvas)
            : MouseRegion(
                cursor: tool == Tool.text ? SystemMouseCursors.text : SystemMouseCursors.precise,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (e.buttons != 1 && e.kind == PointerDeviceKind.mouse) return;
                    final p = _toBoard(e.localPosition, scale);
                    if (tool == Tool.text) {
                      _text(p);
                    } else {
                      _start(p);
                    }
                  },
                  onPointerMove: (e) => _move(_toBoard(e.localPosition, scale)),
                  onPointerUp: (_) => _end(),
                  onPointerCancel: (_) => _end(),
                  child: canvas,
                ),
              ),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!widget.ro) ...[_toolbar(), const SizedBox(height: 4)],
        Center(child: framed),
        if (widget.ro && widget.onTapReadOnly != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Chạm vào bảng để vẽ', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant))),
      ]);
    });
  }
}
