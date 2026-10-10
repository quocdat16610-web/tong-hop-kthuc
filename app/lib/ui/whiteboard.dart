// Bảng trắng vô hạn: vẽ tay, đường thẳng, mũi tên, hình chữ nhật, hình tròn, chữ, tẩy, hoàn tác.
// Kéo bằng công cụ bàn tay / chuột phải / chuột giữa / hai ngón để di chuyển, cuộn hoặc chụm ngón để phóng to.
// Nét vẽ lưu dạng vector trong notebook (nên có lịch sử, commit, merge, chia sẻ như nội dung khác).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/vcs.dart' show Json;
import 'theme.dart';
import 'widgets.dart';

const boardWidth = 1000.0; // khối trong trang mặc định hiện vùng rộng 1000 đơn vị (như bản cũ)
const minZoom = 0.05, maxZoom = 8.0;

const boardColors = [Color(0xFF1F2328), Color(0xFFCF222E), Color(0xFF0969DA), Color(0xFF1A7F37), Color(0xFFBF8700), Color(0xFF8250DF), Color(0xFFE16F24), Color(0xFF6E7781)];

enum Tool { hand, pen, highlighter, line, arrow, rect, ellipse, text, eraser }

const _toolInfo = {
  Tool.hand: (Icons.pan_tool_outlined, 'Di chuyển bảng (hoặc kéo bằng chuột phải / chuột giữa / hai ngón)'),
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
  final double zoom;
  final Offset origin; // toạ độ trên bảng ở góc trên-trái khung nhìn
  _BoardPainter(this.strokes, this.live, this.bg, this.zoom, this.origin);

  static List<Offset> pts(Map s) {
    final p = (s['p'] as List).cast<num>();
    return [for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i].toDouble(), p[i + 1].toDouble())];
  }

  /// Khung bao gần đúng của một nét (để bỏ qua nét ngoài khung nhìn và tính "vừa khung").
  static Rect strokeBounds(Map s) {
    final p = pts(s);
    if (p.isEmpty) return Rect.zero;
    if (s['t'] == 'text') {
      final w = ((s['w'] ?? 3) as num).toDouble();
      final lines = '${s['text'] ?? ''}'.split('\n');
      final fs = 10 + w * 4;
      return Rect.fromLTWH(p.first.dx, p.first.dy, lines.map((l) => l.length).fold(1, math.max) * fs * .62, lines.length * fs * 1.3);
    }
    var r = Rect.fromPoints(p.first, p.first);
    for (final q in p) {
      r = r.expandToInclude(Rect.fromPoints(q, q));
    }
    final w = ((s['w'] ?? 3) as num).toDouble() * (s['t'] == 'highlighter' ? 4 : 1);
    return r.inflate(w / 2 + (s['t'] == 'arrow' ? 10 + w * 3 : 0));
  }

  static Rect? allBounds(List strokes) {
    Rect? r;
    for (final s in strokes) {
      if (s is! Map) continue;
      final b = strokeBounds(s);
      r = r == null ? b : r.expandToInclude(b);
    }
    return r;
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
          text: TextSpan(
            text: '${s['text'] ?? ''}',
            style: TextStyle(color: color, fontSize: 10 + w * 4, fontWeight: FontWeight.w500),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, p.first);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(zoom);
    canvas.translate(-origin.dx, -origin.dy);
    final view = Rect.fromLTWH(origin.dx, origin.dy, size.width / zoom, size.height / zoom);
    if (bg != 'plain') {
      // Lưới vô hạn: chỉ vẽ phần đang nhìn thấy; thu nhỏ nhiều thì giãn ô lưới cho đỡ rối.
      var step = 40.0;
      while (step * zoom < 12) {
        step *= 5;
      }
      final g = Paint()
        ..color = const Color(0xFFDDE1E6)
        ..strokeWidth = 1 / zoom;
      final x0 = (view.left / step).floorToDouble() * step, y0 = (view.top / step).floorToDouble() * step;
      if (bg == 'grid') {
        for (var x = x0; x <= view.right; x += step) {
          canvas.drawLine(Offset(x, view.top), Offset(x, view.bottom), g);
        }
        for (var y = y0; y <= view.bottom; y += step) {
          canvas.drawLine(Offset(view.left, y), Offset(view.right, y), g);
        }
      } else if (bg == 'dots') {
        final pts = <Offset>[
          for (var x = x0; x <= view.right; x += step)
            for (var y = y0; y <= view.bottom; y += step) Offset(x, y),
        ];
        canvas.drawPoints(
          ui.PointMode.points,
          pts,
          g
            ..strokeWidth = 2.8 / zoom
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (final s in strokes) {
      if (s is Map && view.overlaps(strokeBounds(s).inflate(20))) _draw(canvas, s);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.draw_outlined, size: 16, color: context.cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                (block['title'] ?? '').toString().isEmpty ? 'Bảng trắng' : '${block['title']}',
                style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(onPressed: () => openBoardFullscreen(context, block, ro), icon: const Icon(Icons.fullscreen, size: 18), label: Text(ro ? 'Phóng to' : 'Vẽ toàn màn hình')),
          ],
        ),
        const SizedBox(height: 6),
        // Trên điện thoại vẽ ở chế độ toàn màn hình (để vuốt trang không bị nhầm thành nét vẽ).
        Whiteboard(block: block, ro: ro || touch, onTapReadOnly: touch && !ro ? () => openBoardFullscreen(context, block, ro) : null),
      ],
    );
  }
}

Future<void> openBoardFullscreen(BuildContext context, Json block, bool ro) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (c) => Scaffold(
        appBar: AppBar(title: Text((block['title'] ?? '').toString().isEmpty ? 'Bảng trắng' : '${block['title']}')),
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Whiteboard(block: block, ro: ro, fill: true),
        ),
      ),
    ),
  );
}

class Whiteboard extends StatefulWidget {
  final Json block;
  final bool ro;
  final bool fill; // bảng chiếm hết chỗ còn lại (tab Bảng trắng, toàn màn hình); cuộn chuột = di chuyển bảng
  final VoidCallback? onTapReadOnly;
  final VoidCallback? onChanged; // mặc định: lưu notebook đang mở
  const Whiteboard({super.key, required this.block, required this.ro, this.fill = false, this.onTapReadOnly, this.onChanged});
  @override
  State<Whiteboard> createState() => _WhiteboardState();
}

class _WhiteboardState extends State<Whiteboard> {
  Tool tool = Tool.pen;
  Color color = boardColors.first;
  double width = 3;
  Map? live;
  final List redo = [];

  // Khung nhìn: zoom = số pixel trên màn hình cho 1 đơn vị bảng; origin = điểm trên bảng ở góc trên-trái.
  double? _zoom;
  Offset origin = Offset.zero;
  bool _userView = false; // người dùng đã tự di chuyển / phóng to (khối trong trang thôi tự co theo bề rộng)
  Size _size = Size.zero;
  final Map<int, Offset> _touches = {};
  ({Offset focal, double dist, double zoom, Offset origin})? _pinch;
  bool _panning = false;
  Offset? _panLast;
  double get zoom => _zoom ?? 1;

  Json get b => widget.block;

  void _save() {
    if (!mounted) return;
    if (widget.onChanged != null) return widget.onChanged!();
    context.read<AppState>().edited();
  }

  Offset _toBoard(Offset local) => origin + local / zoom;
  static double _r(double v) => (v * 10).roundToDouble() / 10;

  /// Khung nhìn ban đầu: khối trong trang hiện vùng rộng 1000 đơn vị từ gốc (giống bản cũ);
  /// tab Bảng trắng nhớ khung nhìn lần trước.
  void _initView(Size size) {
    final v = b['view'];
    if (widget.fill && v is Map && v['z'] is num) {
      _zoom = (v['z'] as num).toDouble().clamp(minZoom, maxZoom);
      origin = Offset(((v['x'] ?? 0) as num).toDouble(), ((v['y'] ?? 0) as num).toDouble());
      _userView = true;
    } else if (widget.fill) {
      _zoom = 1;
      final r = _BoardPainter.allBounds(_strokes(b));
      if (r != null && !Rect.fromLTWH(0, 0, size.width, size.height).contains(r.bottomRight)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
      }
    } else {
      _zoom = size.width / boardWidth;
    }
  }

  void _setView(double z, Offset o) {
    setState(() {
      _zoom = z.clamp(minZoom, maxZoom);
      origin = o;
      _userView = true;
    });
    // Tab Bảng trắng: nhớ khung nhìn (không ghi vào notebook để khỏi tạo thay đổi chỉ vì kéo bảng).
    if (widget.fill && widget.onChanged != null) {
      b['view'] = {'x': _r(origin.dx), 'y': _r(origin.dy), 'z': (zoom * 1000).roundToDouble() / 1000};
      widget.onChanged!();
    }
  }

  /// Phóng to / thu nhỏ quanh một điểm trên màn hình (điểm đó đứng yên).
  void _zoomAt(Offset screen, double factor) {
    final z = (zoom * factor).clamp(minZoom, maxZoom);
    final board = _toBoard(screen);
    _setView(z, board - screen / z);
  }

  void _panBy(Offset screenDelta) => _setView(zoom, origin - screenDelta / zoom);

  /// Thu / phóng để thấy toàn bộ nét vẽ.
  void _fitAll() {
    if (!mounted || _size.isEmpty) return;
    final r = _BoardPainter.allBounds(_strokes(b));
    if (r == null) return _setView(widget.fill ? 1 : _size.width / boardWidth, Offset.zero);
    final box = r.inflate(30);
    final z = math.min(_size.width / box.width, _size.height / box.height).clamp(minZoom, 2.0);
    _setView(z, box.center - Offset(_size.width, _size.height) / (2 * z));
  }

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
      'p': <dynamic>[_r(p.dx), _r(p.dy)],
    };
    if (tool != Tool.pen && tool != Tool.highlighter) (live!['p'] as List).addAll([_r(p.dx), _r(p.dy)]);
    setState(() {});
  }

  void _move(Offset p) {
    if (tool == Tool.eraser) return _erase(p);
    final s = live;
    if (s == null) return;
    final list = s['p'] as List;
    if (tool == Tool.pen || tool == Tool.highlighter) {
      final last = Offset((list[list.length - 2] as num).toDouble(), (list[list.length - 1] as num).toDouble());
      if ((p - last).distance * zoom < 2) return;
      list.addAll([_r(p.dx), _r(p.dy)]);
    } else {
      list[2] = _r(p.dx);
      list[3] = _r(p.dy);
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
    final r = (8 + width * 2) / math.max(zoom, .3);
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
      if (s['t'] == 'text') return _BoardPainter.strokeBounds(s).inflate(r / 2).contains(p);
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
    _strokes(b).add({
      't': 'text',
      'c': color.toARGB32(),
      'w': width,
      'p': [_r(p.dx), _r(p.dy)],
      'text': t,
    });
    redo.clear();
    setState(() {});
    _save();
  }

  /// Lưu toàn bộ nét vẽ thành ảnh PNG (độ nét gấp đôi, tối đa 8000 px mỗi chiều).
  Future<void> _exportPng() async {
    final box = (_BoardPainter.allBounds(_strokes(b)) ?? const Rect.fromLTWH(0, 0, boardWidth, 560)).inflate(30);
    final z = math.min(2.0, 8000 / math.max(box.width, box.height));
    final size = Size((box.width * z).ceilToDouble(), (box.height * z).ceilToDouble());
    final rec = ui.PictureRecorder();
    _BoardPainter(_strokes(b), null, (b['bg'] ?? 'grid') as String, z, box.topLeft).paint(Canvas(rec), size);
    final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;
    final name = (b['title'] ?? '').toString().trim().isEmpty ? 'bang-trang' : '${b['title']}'.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-');
    await saveBytesFile(context, '$name.png', data.buffer.asUint8List());
  }

  Offset get _center => Offset(_size.width, _size.height) / 2;

  List<Widget> _viewButtons() => [
    IconButton(tooltip: 'Thu nhỏ (Ctrl + cuộn chuột)', visualDensity: VisualDensity.compact, icon: const Icon(Icons.zoom_out, size: 20), onPressed: () => _zoomAt(_center, 1 / 1.25)),
    Tooltip(
      message: 'Về 100%',
      child: InkWell(
        onTap: () => _zoomAt(_center, 1 / zoom),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('${(zoom * 100).round()}%', style: context.tt.labelMedium),
        ),
      ),
    ),
    IconButton(tooltip: 'Phóng to (Ctrl + cuộn chuột)', visualDensity: VisualDensity.compact, icon: const Icon(Icons.zoom_in, size: 20), onPressed: () => _zoomAt(_center, 1.25)),
    IconButton(tooltip: 'Vừa khung: xem toàn bộ hình vẽ', visualDensity: VisualDensity.compact, icon: const Icon(Icons.fit_screen_outlined, size: 20), onPressed: _fitAll),
  ];

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
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
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
            for (final (v, n) in [(2.0, 'Mảnh'), (3.0, 'Vừa'), (6.0, 'Đậm'), (10.0, 'Rất đậm')])
              PopupMenuItem(
                value: v,
                child: Row(
                  children: [
                    Container(width: 30, height: v, color: Colors.black87),
                    const SizedBox(width: 10),
                    Text(n),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 22, height: width.clamp(1, 10), color: context.cs.onSurface),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
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
        Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.cs.outlineVariant),
        ..._viewButtons(),
        if (!widget.fill)
          IconButton(
            tooltip: 'Khung bảng cao hơn',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.expand, size: 20),
            onPressed: () {
              setState(() => b['height'] = (_height(b) + 200).clamp(200, 4000));
              _save();
            },
          ),
        IconButton(tooltip: 'Lưu thành ảnh PNG', visualDensity: VisualDensity.compact, icon: const Icon(Icons.image_outlined, size: 20), onPressed: _exportPng),
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
      ],
    );
  }

  // ---------- Thao tác chuột / cảm ứng ----------
  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        // Ngón thứ hai: bỏ nét đang vẽ dở, chuyển sang kéo / chụm để phóng to.
        live = null;
        final ps = _touches.values.toList();
        _pinch = (focal: (ps[0] + ps[1]) / 2, dist: math.max((ps[0] - ps[1]).distance, 1), zoom: zoom, origin: origin);
        setState(() {});
        return;
      }
      if (_touches.length > 2 || _pinch != null) return;
    }
    final pan = tool == Tool.hand || (e.kind == PointerDeviceKind.mouse && (e.buttons & (kSecondaryMouseButton | kMiddleMouseButton)) != 0);
    if (pan || widget.ro) {
      _panning = true;
      _panLast = e.localPosition;
      setState(() {});
      return;
    }
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    final p = _toBoard(e.localPosition);
    if (tool == Tool.text) {
      _text(p);
    } else {
      _start(p);
    }
  }

  void _moveEv(PointerMoveEvent e) {
    if (_touches.containsKey(e.pointer)) _touches[e.pointer] = e.localPosition;
    final pinch = _pinch;
    if (pinch != null) {
      if (_touches.length < 2) return;
      final ps = _touches.values.take(2).toList();
      final focal = (ps[0] + ps[1]) / 2;
      final z = (pinch.zoom * (ps[0] - ps[1]).distance / pinch.dist).clamp(minZoom, maxZoom);
      final board = pinch.origin + pinch.focal / pinch.zoom; // điểm trên bảng dưới tâm hai ngón lúc bắt đầu
      _setView(z, board - focal / z);
      return;
    }
    if (_panning) {
      _panBy(e.localPosition - _panLast!);
      _panLast = e.localPosition;
      return;
    }
    _move(_toBoard(e.localPosition));
  }

  void _up(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_pinch != null) {
      if (_touches.isEmpty) setState(() => _pinch = null);
      return;
    }
    if (_panning) {
      setState(() => _panning = false);
      return;
    }
    _end();
  }

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
      // Trong trang sổ tay, cuộn chuột thường để cuộn trang; Ctrl + cuộn mới phóng to.
      if (!ctrl && !widget.fill) return;
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScrollEvent;
        if (ctrl) {
          _zoomAt(s.localPosition, math.pow(1.0015, -s.scrollDelta.dy).toDouble());
        } else {
          final shift = HardwareKeyboard.instance.isShiftPressed;
          _panBy(-(shift ? Offset(s.scrollDelta.dy, s.scrollDelta.dx) : s.scrollDelta));
        }
      });
    } else if (e is PointerScaleEvent) {
      _zoomAt(e.localPosition, e.scale);
    }
  }

  double _pzScale = 1;
  void _panZoomStart(PointerPanZoomStartEvent e) => _pzScale = 1;
  void _panZoomUpdate(PointerPanZoomUpdateEvent e) {
    // Bàn di chuột (touchpad): hai ngón kéo = di chuyển, chụm = phóng to.
    if (e.scale != _pzScale) {
      _zoomAt(e.localPosition, e.scale / _pzScale);
      _pzScale = e.scale;
    }
    if (widget.fill && e.panDelta != Offset.zero) _panBy(e.panDelta);
  }

  @override
  Widget build(BuildContext context) {
    final bg = (b['bg'] ?? 'grid') as String;
    final touchRo = widget.ro && widget.onTapReadOnly != null; // điện thoại trong trang: chạm để mở toàn màn hình
    Widget board(double w, double h) {
      final size = Size(w, h);
      if (_zoom == null) {
        _initView(size);
      } else if (!widget.fill && !_userView && w != _size.width) {
        _zoom = w / boardWidth; // khối trong trang co giãn theo bề rộng như trước
      }
      _size = size;
      final canvas = SizedBox(
        width: w,
        height: h,
        child: CustomPaint(painter: _BoardPainter(_strokes(b), live, bg, zoom, origin)),
      );
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.cs.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: touchRo
            ? GestureDetector(onTap: widget.onTapReadOnly, child: canvas)
            : MouseRegion(
                cursor: _panning
                    ? SystemMouseCursors.grabbing
                    : tool == Tool.hand || widget.ro
                    ? SystemMouseCursors.grab
                    : tool == Tool.text
                    ? SystemMouseCursors.text
                    : SystemMouseCursors.precise,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _moveEv,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  onPointerSignal: _signal,
                  onPointerPanZoomStart: _panZoomStart,
                  onPointerPanZoomUpdate: _panZoomUpdate,
                  // Chặn menu chuột phải của hệ thống khi kéo bảng bằng chuột phải.
                  child: GestureDetector(onSecondaryTapDown: (_) {}, child: canvas),
                ),
              ),
      );
    }

    final toolbar = widget.ro ? (touchRo ? null : Wrap(children: _viewButtons())) : _toolbar();
    if (widget.fill) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (toolbar != null) ...[toolbar, const SizedBox(height: 4)],
          Expanded(child: LayoutBuilder(builder: (context, box) => board(box.maxWidth, box.maxHeight))),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Khối trong trang: khung cao theo "height" (đơn vị bảng ở mức 100% bề rộng 1000).
        final h = _height(b) * w / boardWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (toolbar != null) ...[toolbar, const SizedBox(height: 4)],
            board(w, h),
            if (touchRo)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Chạm vào bảng để vẽ', style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
              ),
          ],
        );
      },
    );
  }
}
