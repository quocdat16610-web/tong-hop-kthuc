// Bảng trắng vô hạn: vẽ tay, đường thẳng, mũi tên, hình chữ nhật, hình tròn, chữ, ảnh, tẩy, hoàn tác.
// Kéo bằng công cụ bàn tay / chuột phải / chuột giữa / hai ngón để di chuyển, cuộn hoặc chụm ngón để phóng to.
// Bút có "tự nắn hình": vẽ tay đường thẳng / hình tròn / chữ nhật / tam giác méo sẽ được thay bằng hình chuẩn ngay khi nhấc bút.
// Viết tay chữ số (0–9, nhiều chữ số) thì sau khi ngừng viết một chút được thay bằng chữ in cùng cỡ, cùng chỗ.
// Nét vẽ lưu dạng vector trong notebook (nên có lịch sử, commit, merge, chia sẻ như nội dung khác).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/digits.dart';
import '../core/shapes.dart';
import '../core/storage.dart';
import '../core/vcs.dart' show Json;
import 'drop.dart';
import 'theme.dart';
import 'widgets.dart';

const boardWidth = 1000.0; // khối trong trang mặc định hiện vùng rộng 1000 đơn vị (như bản cũ)
const minZoom = 0.05, maxZoom = 8.0;

const boardColors = [Color(0xFF1F2328), Color(0xFFCF222E), Color(0xFF0969DA), Color(0xFF1A7F37), Color(0xFFBF8700), Color(0xFF8250DF), Color(0xFFE16F24), Color(0xFF6E7781)];

enum Tool { hand, select, pen, highlighter, line, arrow, rect, ellipse, text, eraser }

const _toolInfo = {
  Tool.hand: (Icons.pan_tool_outlined, 'Di chuyển bảng (hoặc kéo bằng chuột phải / chuột giữa / hai ngón)'),
  Tool.select: (Icons.near_me_outlined, 'Chọn: kéo để di chuyển, kéo góc để đổi cỡ, Delete để xoá'),
  Tool.pen: (Icons.edit, 'Bút (tự nắn đường thẳng / hình tròn / chữ nhật / tam giác nếu bật)'),
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

/// Ảnh trên bảng: giải mã một lần (thu nhỏ còn tối đa 2048 px), dùng chung cho mọi bảng.
class BoardImages {
  static final _cache = <String, ui.Image>{};
  static final _futures = <String, Future<ui.Image?>>{};

  /// Tăng mỗi khi có ảnh giải mã xong để bảng vẽ lại.
  static final tick = ValueNotifier(0);

  static ui.Image? get(String src) {
    final img = _cache[src];
    if (img == null) load(src);
    return img;
  }

  static Future<ui.Image?> load(String src) => _futures[src] ??= _decode(src).then((img) {
    if (img != null) {
      _cache[src] = img;
      tick.value++;
    }
    return img;
  });

  static Future<ui.Image?> _decode(String src) async {
    try {
      final f = Storage.I.assetFile(src);
      if (f == null) return null;
      final desc = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(await f.readAsBytes()));
      const maxSide = 2048;
      final wide = desc.width >= desc.height;
      final big = math.max(desc.width, desc.height) > maxSide;
      final codec = await desc.instantiateCodec(targetWidth: big && wide ? maxSide : null, targetHeight: big && !wide ? maxSide : null);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }
}

/// Dữ liệu hình học tính sẵn cho một nét đã vẽ xong (nét không bị sửa tại chỗ — di chuyển thì thay bằng map mới).
class _Geo {
  final List<Offset> pts;
  final Rect bounds;
  Path? path;
  _Geo(this.pts, this.bounds);
}

final _geoCache = Expando<_Geo>();

// Số lần đổi của mỗi danh sách nét (dùng chung giữa khối trong trang và bản toàn màn hình của cùng một bảng).
final _listRev = Expando<int>();
int _revOf(List l) => _listRev[l] ?? 0;
void _bump(List l) => _listRev[l] = _revOf(l) + 1;

List<Offset> _pts(Map s) {
  final p = (s['p'] as List).cast<num>();
  return [for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i].toDouble(), p[i + 1].toDouble())];
}

double _w(Map s) => ((s['w'] ?? 3) as num).toDouble();

/// Cỡ chữ: theo độ dày nét, hoặc lưu sẵn ("fs") với chữ số nhận dạng từ nét viết tay.
double _fs(Map s) => (s['fs'] as num?)?.toDouble() ?? 10 + _w(s) * 4;

_Geo _makeGeo(Map s) {
  final p = _pts(s);
  if (p.isEmpty) return _Geo(p, Rect.zero);
  final w = _w(s);
  if (s['t'] == 'text') {
    final lines = '${s['text'] ?? ''}'.split('\n');
    final fs = _fs(s);
    return _Geo(p, Rect.fromLTWH(p.first.dx, p.first.dy, lines.map((l) => l.length).fold(1, math.max) * fs * .62, lines.length * fs * 1.3));
  }
  var l = p.first.dx, t = p.first.dy, r = l, btm = t;
  for (final q in p) {
    l = math.min(l, q.dx);
    r = math.max(r, q.dx);
    t = math.min(t, q.dy);
    btm = math.max(btm, q.dy);
  }
  final rect = Rect.fromLTRB(l, t, r, btm);
  if (s['t'] == 'image') return _Geo(p, rect);
  return _Geo(p, rect.inflate(w * (s['t'] == 'highlighter' ? 4 : 1) / 2 + (s['t'] == 'arrow' ? 10 + w * 3 : 0)));
}

_Geo _geo(Map s) => _geoCache[s] ??= _makeGeo(s);

Rect? _allBounds(List strokes) {
  Rect? r;
  for (final s in strokes) {
    if (s is! Map) continue;
    final b = _geo(s).bounds;
    r = r == null ? b : r.expandToInclude(b);
  }
  return r;
}

double _distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Điểm p có chạm nét s không (sai số tol, đơn vị bảng). `solid`: chạm bên trong hình / ảnh / chữ cũng tính.
bool _hits(Map s, Offset p, double tol, {bool solid = true}) {
  final g = _geo(s);
  if (g.pts.isEmpty || !g.bounds.inflate(tol).contains(p)) return false;
  final t = s['t'];
  final r = tol + _w(s) / 2;
  if (t == 'image' || t == 'text') return true;
  if (t == 'rect' || t == 'ellipse') {
    if (solid) return true;
    final box = Rect.fromPoints(g.pts[0], g.pts[1]);
    return !box.deflate(r).contains(p);
  }
  final pts = g.pts;
  if (pts.length == 1) return (pts.first - p).distance < r;
  for (var i = 1; i < pts.length; i++) {
    if (_distToSegment(p, pts[i - 1], pts[i]) < r) return true;
  }
  return t == 'poly' && _distToSegment(p, pts.last, pts.first) < r;
}

void _drawStroke(Canvas c, Map s, _Geo g) {
  final t = s['t'] as String;
  final color = Color((s['c'] ?? 0xFF1F2328) as int);
  final w = _w(s);
  final p = g.pts;
  if (p.isEmpty) return;
  final paint = Paint()
    ..color = t == 'highlighter' ? color.withValues(alpha: .35) : color
    ..strokeWidth = t == 'highlighter' ? w * 4 : w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  switch (t) {
    case 'pen' || 'highlighter':
      if (p.length == 1) {
        c.drawCircle(p.first, paint.strokeWidth / 2, Paint()..color = paint.color);
        return;
      }
      c.drawPath(
        g.path ??= () {
          final path = Path()..moveTo(p.first.dx, p.first.dy);
          for (var i = 1; i < p.length - 1; i++) {
            final mid = (p[i] + p[i + 1]) / 2;
            path.quadraticBezierTo(p[i].dx, p[i].dy, mid.dx, mid.dy);
          }
          return path..lineTo(p.last.dx, p.last.dy);
        }(),
        paint,
      );
    case 'poly':
      c.drawPath(g.path ??= (Path()..addPolygon(p, true)), paint);
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
    case 'image':
      if (p.length < 2) return;
      final dst = Rect.fromPoints(p[0], p[1]);
      final img = BoardImages.get('${s['src'] ?? ''}');
      if (img == null) {
        c.drawRect(dst, Paint()..color = const Color(0x14000000));
        return;
      }
      c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
    case 'text':
      final tp = TextPainter(
        text: TextSpan(
          text: '${s['text'] ?? ''}',
          style: TextStyle(color: color, fontSize: _fs(s), fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, p.first);
  }
}

/// Lớp dưới: nền + các nét đã vẽ xong. Chỉ vẽ lại khi nét / khung nhìn đổi (không vẽ lại theo từng điểm của nét đang vẽ).
class _BoardPainter extends CustomPainter {
  final List strokes;
  final String bg;
  final double zoom;
  final Offset origin; // toạ độ trên bảng ở góc trên-trái khung nhìn
  final int rev;
  _BoardPainter(this.strokes, this.bg, this.zoom, this.origin, this.rev) : super(repaint: BoardImages.tick);

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
    final visible = view.inflate(20);
    for (final s in strokes) {
      if (s is! Map) continue;
      final g = _geo(s);
      if (visible.overlaps(g.bounds)) _drawStroke(canvas, s, g);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => old.rev != rev || old.zoom != zoom || old.origin != origin || old.bg != bg || !identical(old.strokes, strokes);
}

/// Lớp trên: nét đang vẽ dở + khung chọn.
class _LivePainter extends CustomPainter {
  final Map? live;
  final Rect? sel;
  final bool resizable;
  final Color selColor;
  final double zoom;
  final Offset origin;
  _LivePainter(this.live, this.sel, this.resizable, this.selColor, this.zoom, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    if (live == null && sel == null) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(zoom);
    canvas.translate(-origin.dx, -origin.dy);
    if (live != null) _drawStroke(canvas, live!, _makeGeo(live!));
    final r = sel;
    if (r != null) {
      final pen = Paint()
        ..color = selColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / zoom;
      canvas.drawRect(r.inflate(4 / zoom), pen);
      if (resizable) {
        canvas.drawRect(Rect.fromCenter(center: r.bottomRight, width: 12 / zoom, height: 12 / zoom), Paint()..color = selColor);
      }
    }
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

  // Lịch sử: mỗi mục là bản sao nông danh sách nét (các nét không bị sửa tại chỗ nên dùng chung được).
  final List<List> _undo = [], _redo = [];

  // Chọn / kéo / đổi cỡ.
  int? _sel;
  ({Map orig, Offset start, bool resize, bool moved})? _drag;
  bool _erasing = false;
  final _focus = FocusNode(debugLabel: 'whiteboard');

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
  List get list => _strokes(b);

  bool get _autoShape => context.read<AppState>().setting('boardShapes', true);
  bool get _autoDigits => context.read<AppState>().setting('boardDigits', true);

  // Nhận dạng chữ số: nét bút cỡ chữ viết tay được giữ lại một chút, chờ xem còn nét tiếp theo
  // (chữ số nhiều nét như 4, 5, 7 hay số nhiều chữ số), rồi mới đoán và thay bằng chữ in.
  final List<Map> _ink = [];
  Timer? _inkTimer;
  static const _inkDelay = Duration(milliseconds: 650);

  @override
  void dispose() {
    _inkTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    if (!mounted) return;
    if (widget.onChanged != null) return widget.onChanged!();
    context.read<AppState>().edited();
  }

  /// Nét vẽ đã đổi: vẽ lại lớp nét + lưu.
  void _commit() {
    _bump(list);
    setState(() {});
    _save();
  }

  /// Ghi lại trạng thái hiện tại trước khi đổi (để hoàn tác).
  void _checkpoint() {
    _undo.add(List.of(list));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  void _undoAct() {
    _dropInk();
    if (_undo.isEmpty && list.isEmpty) return;
    _redo.add(List.of(list));
    if (_undo.isNotEmpty) {
      final prev = _undo.removeLast();
      list
        ..clear()
        ..addAll(prev);
    } else {
      list.removeLast(); // mở lại bảng: chưa có lịch sử thì bỏ nét cuối như trước
    }
    _sel = null;
    _commit();
  }

  void _redoAct() {
    _dropInk();
    if (_redo.isEmpty) return;
    _undo.add(List.of(list));
    final next = _redo.removeLast();
    list
      ..clear()
      ..addAll(next);
    _sel = null;
    _commit();
  }

  void _deleteSelected() {
    final i = _sel;
    if (i == null || i >= list.length) return;
    _checkpoint();
    list.removeAt(i);
    _sel = null;
    _commit();
  }

  void _sendToBack() {
    final i = _sel;
    if (i == null || i >= list.length || i == 0) return;
    _checkpoint();
    list.insert(0, list.removeAt(i));
    _sel = 0;
    _commit();
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
      final r = _allBounds(list);
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
    final r = _allBounds(list);
    if (r == null) return _setView(widget.fill ? 1 : _size.width / boardWidth, Offset.zero);
    final box = r.inflate(30);
    final z = math.min(_size.width / box.width, _size.height / box.height).clamp(minZoom, 2.0);
    _setView(z, box.center - Offset(_size.width, _size.height) / (2 * z));
  }

  // ---------- Vẽ ----------
  void _start(Offset p) {
    if (tool == Tool.pen) {
      _inkTimer?.cancel(); // đang viết tiếp → chờ nét này xong rồi mới đoán
    } else {
      _flushInk();
    }
    if (tool == Tool.eraser) {
      _erasing = false;
      _erase(p);
      return;
    }
    if (tool == Tool.select) return _selectAt(p);
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
    if (_drag != null) return _dragTo(p);
    final s = live;
    if (s == null) return;
    final pl = s['p'] as List;
    if (tool == Tool.pen || tool == Tool.highlighter) {
      final last = Offset((pl[pl.length - 2] as num).toDouble(), (pl[pl.length - 1] as num).toDouble());
      if ((p - last).distance * zoom < 2) return;
      pl.addAll([_r(p.dx), _r(p.dy)]);
    } else {
      pl[2] = _r(p.dx);
      pl[3] = _r(p.dy);
    }
    setState(() {});
  }

  void _end() {
    if (_drag != null) {
      final moved = _drag!.moved;
      _drag = null;
      if (moved) _save();
      return;
    }
    final s = live;
    if (s == null) return;
    live = null;
    final pts = (s['p'] as List).cast<num>();
    final shape = s['t'] == 'pen' && _autoShape ? recognizeShape(pts) : null;
    if (s['t'] == 'pen' && _autoDigits) {
      final r = _geo(s).bounds;
      // Nét cỡ chữ viết tay (không phải hình khép kín rõ ràng) → giữ lại chờ đoán chữ số.
      final small = r.height * zoom <= 160 && r.width * zoom <= 160 && r.longestSide * zoom >= 6;
      if (small && (shape == null || shape.t == 'line' || shape.t == 'ellipse')) {
        if (_ink.isNotEmpty && !_nearInk(r)) _flushInk();
        _checkpoint();
        list.add(s);
        _ink.add(s);
        _inkTimer?.cancel();
        _inkTimer = Timer(_inkDelay, _flushInk);
        _commit();
        return;
      }
    }
    _flushInk();
    _checkpoint();
    list.add(s);
    // Tự nắn hình: thay nét tay bằng hình chuẩn ngay khi nhấc bút (Hoàn tác một lần sẽ trả lại nét tay).
    if (shape != null) {
      _checkpoint();
      list[list.length - 1] = {'t': shape.t, 'c': s['c'], 'w': s['w'], 'p': shape.p};
    }
    _commit();
  }

  /// Nét mới có nằm cạnh nhóm nét đang chờ không (cùng dòng, cách nhau không quá một chữ).
  bool _nearInk(Rect r) {
    final g = _ink.map((s) => _geo(s).bounds).reduce((a, b) => a.expandToInclude(b));
    final h = math.max(g.height, r.height);
    final gapX = math.max(0.0, math.max(r.left - g.right, g.left - r.right));
    final sameLine = r.top < g.bottom + 0.3 * h && r.bottom > g.top - 0.3 * h;
    return sameLine && gapX < 0.9 * h;
  }

  /// Bỏ nhóm đang chờ mà không đoán (khi hoàn tác / làm lại).
  void _dropInk() {
    _inkTimer?.cancel();
    _inkTimer = null;
    _ink.clear();
  }

  /// Đoán nhóm nét đang chờ: là số thì thay bằng chữ in cùng cỡ, chỗ; không thì nắn hình từng nét như thường.
  void _flushInk() {
    _inkTimer?.cancel();
    _inkTimer = null;
    if (_ink.isEmpty || !mounted) return;
    final group = List.of(_ink);
    _ink.clear();
    if (!group.every((g) => list.any((x) => identical(x, g)))) return; // đã bị tẩy / xoá
    final strokes = [for (final g in group) (g['p'] as List).cast<num>()];
    var found = recognizeNumber(strokes);
    // Một nét thẳng đứng đứng riêng: chỉ coi là "1" nếu nhỏ cỡ chữ, dài hơn thì là đoạn thẳng.
    if (found != null && found.text == '1' && group.length == 1 && (found.box[3] - found.box[1]) * zoom > 70) found = null;
    if (found != null) {
      _checkpoint();
      final at = list.indexWhere((x) => identical(x, group.first));
      list.removeWhere((x) => group.any((g) => identical(g, x)));
      final fs = ((found.box[3] - found.box[1]) / .71).clamp(6.0, 600.0);
      list.insert(at.clamp(0, list.length), {
        't': 'text',
        'c': group.first['c'],
        'w': group.first['w'],
        'fs': _r(fs),
        'p': [_r(found.box[0]), _r(found.box[1] - .22 * fs)],
        'text': found.text,
      });
      _sel = null;
      _commit();
      return;
    }
    if (!_autoShape) return;
    var changed = false;
    for (final g in group) {
      final shape = recognizeShape((g['p'] as List).cast<num>());
      if (shape == null) continue;
      if (!changed) {
        _checkpoint();
        changed = true;
      }
      list[list.indexWhere((x) => identical(x, g))] = {'t': shape.t, 'c': g['c'], 'w': g['w'], 'p': shape.p};
    }
    if (changed) _commit();
  }

  void _erase(Offset p) {
    final r = (8 + width * 2) / math.max(zoom, .3);
    final hit = <Object>{
      for (final s in list)
        if (s is Map && s['t'] != 'image' && _hits(s, p, r, solid: s['t'] == 'text')) s,
    };
    if (hit.isEmpty) return;
    if (!_erasing) {
      _checkpoint(); // một lần cho cả lượt tẩy
      _erasing = true;
    }
    list.removeWhere(hit.contains);
    _sel = null;
    _commit();
  }

  // ---------- Chọn / di chuyển / đổi cỡ ----------
  Rect? get _selBounds {
    final i = _sel;
    if (i == null || i >= list.length || list[i] is! Map) return null;
    final s = list[i] as Map;
    final g = _geo(s);
    return const {'image', 'rect', 'ellipse'}.contains(s['t']) && g.pts.length >= 2 ? Rect.fromPoints(g.pts[0], g.pts[1]) : g.bounds;
  }

  bool get _selResizable {
    final i = _sel;
    return i != null && i < list.length && const {'image', 'rect', 'ellipse'}.contains((list[i] as Map)['t']);
  }

  void _selectAt(Offset p) {
    final tol = 6 / zoom;
    final sb = _selBounds;
    if (sb != null && _selResizable && (p - sb.bottomRight).distance < 12 / zoom) {
      _drag = (orig: list[_sel!] as Map, start: p, resize: true, moved: false);
      return;
    }
    if (sb != null && sb.inflate(tol).contains(p)) {
      _drag = (orig: list[_sel!] as Map, start: p, resize: false, moved: false);
      return;
    }
    int? hit;
    for (var i = list.length - 1; i >= 0; i--) {
      final s = list[i];
      if (s is Map && _hits(s, p, tol, solid: s['t'] == 'image' || s['t'] == 'text')) {
        hit = i;
        break;
      }
    }
    setState(() => _sel = hit);
    if (hit != null) _drag = (orig: list[hit] as Map, start: p, resize: false, moved: false);
  }

  void _dragTo(Offset p) {
    final d = _drag!;
    final i = _sel;
    if (i == null || i >= list.length) return;
    if (!d.moved) {
      if ((p - d.start).distance * zoom < 2) return;
      _checkpoint();
      _drag = (orig: d.orig, start: d.start, resize: d.resize, moved: true);
    }
    final delta = p - d.start;
    final op = (d.orig['p'] as List).cast<num>();
    List<double> np;
    if (d.resize) {
      final a = Offset(math.min(op[0], op[2]).toDouble(), math.min(op[1], op[3]).toDouble());
      final z = Offset(math.max(op[0], op[2]).toDouble(), math.max(op[1], op[3]).toDouble());
      var w = math.max(8.0, z.dx - a.dx + delta.dx), h = math.max(8.0, z.dy - a.dy + delta.dy);
      if (d.orig['t'] == 'image') {
        // Ảnh giữ đúng tỉ lệ.
        final k = math.max(w / (z.dx - a.dx), h / (z.dy - a.dy));
        w = (z.dx - a.dx) * k;
        h = (z.dy - a.dy) * k;
      }
      np = [_r(a.dx), _r(a.dy), _r(a.dx + w), _r(a.dy + h)];
    } else {
      np = [for (var k = 0; k < op.length; k++) _r(op[k] + (k.isEven ? delta.dx : delta.dy))];
    }
    list[i] = {...d.orig, 'p': np};
    _bump(list);
    setState(() {});
  }

  // ---------- Chữ, ảnh, xuất PNG ----------
  Future<void> _text(Offset p) async {
    final t = await promptBox(context, 'Thêm chữ', 'Nội dung', ok: 'Thêm');
    if (t == null || t.trim().isEmpty) return;
    _checkpoint();
    list.add({
      't': 'text',
      'c': color.toARGB32(),
      'w': width,
      'p': [_r(p.dx), _r(p.dy)],
      'text': t,
    });
    _commit();
  }

  /// Tải ảnh từ máy lên bảng (đặt giữa khung nhìn, sau đó kéo / đổi cỡ bằng công cụ Chọn).
  Future<void> _insertImage() async {
    final ref = await pickAsset(context, FileType.image);
    if (ref == null || !mounted) return;
    await _placeImage(ref, _toBoard(_size.isEmpty ? Offset.zero : _center));
  }

  /// Đặt ảnh có tâm tại điểm `at` (toạ độ bảng), vừa tối đa 60% khung nhìn, rồi chọn ảnh đó.
  Future<bool> _placeImage(String ref, Offset at) async {
    final img = await BoardImages.load(ref);
    if (!mounted) return false;
    if (img == null) {
      toast(context, 'Không đọc được ảnh này.', error: true);
      return false;
    }
    final viewW = (_size.isEmpty ? boardWidth : _size.width) / zoom, viewH = (_size.isEmpty ? 560 : _size.height) / zoom;
    final k = math.min(1.0, math.min(viewW * .6 / img.width, viewH * .6 / img.height));
    final w = img.width * k, h = img.height * k;
    _checkpoint();
    list.add({
      't': 'image',
      'src': ref,
      'p': [_r(at.dx - w / 2), _r(at.dy - h / 2), _r(at.dx + w / 2), _r(at.dy + h / 2)],
    });
    _sel = list.length - 1;
    tool = Tool.select;
    _commit();
    return true;
  }

  /// Kéo thả ảnh từ ngoài vào bảng: đặt ngay chỗ thả (nhiều ảnh thì xếp chéo nhau).
  Future<void> _dropFiles(List<DropItem> files, Offset local) async {
    var at = _toBoard(local);
    var skipped = 0;
    for (final f in files) {
      if (!mimeOf(f.fileName).startsWith('image/')) {
        skipped++;
        continue;
      }
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      final a = await storeAsset(context, f.fileName, bytes, type: FileType.image);
      if (a == null || !mounted) continue;
      if (await _placeImage(a.ref, at)) at += const Offset(28, 28) / zoom;
    }
    if (skipped > 0 && mounted) toast(context, 'Bảng trắng chỉ nhận ảnh — bỏ qua $skipped file khác (thả vào trang sổ tay để đính kèm).');
  }

  /// Lưu toàn bộ nét vẽ thành ảnh PNG (độ nét gấp đôi, tối đa 8000 px mỗi chiều).
  Future<void> _exportPng() async {
    await Future.wait([for (final s in list) if (s is Map && s['t'] == 'image') BoardImages.load('${s['src']}')]);
    final box = (_allBounds(list) ?? const Rect.fromLTWH(0, 0, boardWidth, 560)).inflate(30);
    final z = math.min(2.0, 8000 / math.max(box.width, box.height));
    final size = Size((box.width * z).ceilToDouble(), (box.height * z).ceilToDouble());
    final rec = ui.PictureRecorder();
    _BoardPainter(list, (b['bg'] ?? 'grid') as String, z, box.topLeft, 0).paint(Canvas(rec), size);
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
    final auto = context.select<AppState, bool>((a) => a.setting('boardShapes', true));
    final digits = context.select<AppState, bool>((a) => a.setting('boardDigits', true));
    Widget toolBtn(Tool t) => IconButton(
      tooltip: _toolInfo[t]!.$2,
      visualDensity: VisualDensity.compact,
      isSelected: tool == t,
      style: IconButton.styleFrom(backgroundColor: tool == t ? sel : null),
      icon: Icon(_toolInfo[t]!.$1, size: 20),
      onPressed: () => setState(() {
        tool = t;
        if (t != Tool.select) _sel = null;
      }),
    );
    Widget sep() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.cs.outlineVariant);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final t in Tool.values) toolBtn(t),
        IconButton(
          tooltip: auto ? 'Tự nắn hình: BẬT — vẽ tay đường thẳng, hình tròn, chữ nhật, tam giác sẽ thành hình chuẩn (Hoàn tác để giữ nét tay)' : 'Tự nắn hình: TẮT',
          visualDensity: VisualDensity.compact,
          isSelected: auto,
          style: IconButton.styleFrom(backgroundColor: auto ? sel : null),
          icon: Icon(auto ? Icons.auto_fix_high : Icons.auto_fix_off, size: 20),
          onPressed: () => context.read<AppState>().setSetting('boardShapes', !auto),
        ),
        IconButton(
          tooltip: digits ? 'Nhận dạng chữ số: BẬT — viết tay số (0–9, nhiều chữ số) sẽ thành chữ in sau khi ngừng viết một chút (Hoàn tác để giữ nét tay)' : 'Nhận dạng chữ số: TẮT',
          visualDensity: VisualDensity.compact,
          isSelected: digits,
          style: IconButton.styleFrom(backgroundColor: digits ? sel : null),
          icon: const Icon(Icons.onetwothree, size: 22),
          onPressed: () => context.read<AppState>().setSetting('boardDigits', !digits),
        ),
        IconButton(tooltip: 'Tải ảnh từ máy lên bảng', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_photo_alternate_outlined, size: 20), onPressed: _insertImage),
        sep(),
        for (final c in boardColors)
          InkWell(
            onTap: () => setState(() {
              color = c;
              if (tool == Tool.eraser || tool == Tool.select || tool == Tool.hand) tool = Tool.pen;
              _sel = null;
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
        sep(),
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
            b['bg'] = v;
            _commit();
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'plain', child: Text('Nền trơn')), PopupMenuItem(value: 'grid', child: Text('Kẻ ô')), PopupMenuItem(value: 'dots', child: Text('Chấm'))],
          icon: const Icon(Icons.grid_on, size: 20),
        ),
        IconButton(
          tooltip: 'Hoàn tác (Ctrl+Z)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo, size: 20),
          onPressed: list.isEmpty && _undo.isEmpty ? null : _undoAct,
        ),
        IconButton(
          tooltip: 'Làm lại (Ctrl+Y)',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.redo, size: 20),
          onPressed: _redo.isEmpty ? null : _redoAct,
        ),
        if (_selBounds != null) ...[
          IconButton(tooltip: 'Đưa xuống dưới cùng', visualDensity: VisualDensity.compact, icon: const Icon(Icons.flip_to_back, size: 20), onPressed: _sendToBack),
          IconButton(tooltip: 'Xoá mục đang chọn (Delete)', visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, size: 20, color: context.cs.error), onPressed: _deleteSelected),
        ],
        sep(),
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
          onPressed: list.isEmpty
              ? null
              : () async {
                  if (!await confirmBox(context, 'Xoá hết bảng?', 'Mọi nét vẽ trên bảng sẽ bị xoá (bấm Hoàn tác để lấy lại, hoặc khôi phục từ lịch sử commit).', ok: 'Xoá hết', danger: true)) return;
                  _checkpoint();
                  list.clear();
                  _sel = null;
                  _commit();
                },
        ),
      ],
    );
  }

  // ---------- Bàn phím ----------
  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = HardwareKeyboard.instance;
    final ctrl = k.isControlPressed || k.isMetaPressed;
    final key = e.logicalKey;
    if (ctrl && key == LogicalKeyboardKey.keyZ) {
      k.isShiftPressed ? _redoAct() : _undoAct();
    } else if (ctrl && key == LogicalKeyboardKey.keyY) {
      _redoAct();
    } else if (_sel != null && (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace)) {
      _deleteSelected();
    } else if (_sel != null && key == LogicalKeyboardKey.escape) {
      setState(() => _sel = null);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---------- Thao tác chuột / cảm ứng ----------
  void _down(PointerDownEvent e) {
    if (!widget.ro) _focus.requestFocus();
    if (e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus) {
      _touches[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        // Ngón thứ hai: bỏ nét đang vẽ dở / thao tác kéo, chuyển sang kéo / chụm để phóng to.
        live = null;
        if (_drag?.moved ?? false) list[_sel!] = _drag!.orig;
        _drag = null;
        final ps = _touches.values.toList();
        _pinch = (focal: (ps[0] + ps[1]) / 2, dist: math.max((ps[0] - ps[1]).distance, 1), zoom: zoom, origin: origin);
        _bump(list);
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: CustomPaint(painter: _BoardPainter(list, bg, zoom, origin, _revOf(list)))),
            CustomPaint(painter: _LivePainter(live, _selBounds, _selResizable, context.cs.primary, zoom, origin)),
          ],
        ),
      );
      final framed = Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.cs.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: touchRo
            ? GestureDetector(onTap: widget.onTapReadOnly, child: canvas)
            : Focus(
                focusNode: _focus,
                onKeyEvent: _key,
                child: MouseRegion(
                  cursor: _panning
                      ? SystemMouseCursors.grabbing
                      : tool == Tool.hand || widget.ro
                      ? SystemMouseCursors.grab
                      : tool == Tool.select
                      ? (_drag != null ? SystemMouseCursors.move : SystemMouseCursors.basic)
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
              ),
      );
      return widget.ro ? framed : DropZone(onDrop: _dropFiles, hint: 'Thả ảnh vào bảng', child: framed);
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
