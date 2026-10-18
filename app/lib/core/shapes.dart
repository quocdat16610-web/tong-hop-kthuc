// Nhận dạng hình từ nét vẽ tay (giống "Ink to shape" của Microsoft Whiteboard):
// đường gần thẳng → đường thẳng; nét khép kín → hình tròn / elip / chữ nhật / tam giác / tứ giác.
// Không phụ thuộc Flutter để kiểm thử được bằng `dart test`.
import 'dart:math' as math;

class Pt {
  final double x, y;
  const Pt(this.x, this.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator *(double k) => Pt(x * k, y * k);
  double get len => math.sqrt(x * x + y * y);
  double dist(Pt o) => (this - o).len;
}

/// Kết quả nhận dạng: `t` là loại nét ('line', 'ellipse', 'rect', 'poly'), `p` là toạ độ phẳng [x0, y0, x1, y1, …].
typedef Shape = ({String t, List<double> p});

double _segDist(Pt p, Pt a, Pt b) {
  final ab = b - a;
  final l2 = ab.x * ab.x + ab.y * ab.y;
  if (l2 == 0) return p.dist(a);
  final t = (((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2).clamp(0.0, 1.0);
  return p.dist(a + ab * t);
}

/// Ramer–Douglas–Peucker: giữ lại các điểm "góc".
List<Pt> simplify(List<Pt> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  var idx = 0;
  var dmax = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _segDist(pts[i], pts.first, pts.last);
    if (d > dmax) {
      dmax = d;
      idx = i;
    }
  }
  if (dmax <= eps) return [pts.first, pts.last];
  final a = simplify(pts.sublist(0, idx + 1), eps);
  final b = simplify(pts.sublist(idx), eps);
  return [...a.sublist(0, a.length - 1), ...b];
}

/// Khoảng cách trung bình từ các điểm tới đa giác khép kín.
double _polyErr(List<Pt> pts, List<Pt> poly) {
  var sum = 0.0;
  for (final p in pts) {
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      best = math.min(best, _segDist(p, poly[i], poly[(i + 1) % poly.length]));
    }
    sum += best;
  }
  return sum / pts.length;
}

double _cross(Pt o, Pt a, Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/// Chỉ nắn đa giác lồi (tam giác, chữ nhật xoay, hình thoi…); hình lõm / tự cắt thường là chữ hoặc mũi tên vẽ tay.
bool _convex(List<Pt> poly) {
  var sign = 0;
  for (var i = 0; i < poly.length; i++) {
    final c = _cross(poly[i], poly[(i + 1) % poly.length], poly[(i + 2) % poly.length]);
    final sg = c > 0 ? 1 : (c < 0 ? -1 : 0);
    if (sg == 0) continue;
    if (sign != 0 && sg != sign) return false;
    sign = sg;
  }
  return true;
}

/// Góc gần bội số của 45° thì nắn cho đúng (ngang, dọc, chéo).
Pt _snapEnd(Pt a, Pt b) {
  final d = b - a;
  final ang = math.atan2(d.y, d.x);
  const step = math.pi / 4;
  final snapped = (ang / step).roundToDouble() * step;
  if ((ang - snapped).abs() > 6 * math.pi / 180) return b;
  return a + Pt(math.cos(snapped), math.sin(snapped)) * d.len;
}

double _r(double v) => (v * 10).roundToDouble() / 10;

/// Nhận dạng một nét bút (toạ độ phẳng). Trả về null nếu không giống hình nào (giữ nguyên nét tay).
Shape? recognizeShape(List<num> flat) {
  final pts = <Pt>[for (var i = 0; i + 1 < flat.length; i += 2) Pt(flat[i].toDouble(), flat[i + 1].toDouble())];
  if (pts.length < 4) return null;
  var minX = pts.first.x, maxX = minX, minY = pts.first.y, maxY = minY, len = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
    if (i > 0) len += p.dist(pts[i - 1]);
  }
  final w = maxX - minX, h = maxY - minY;
  final diag = math.sqrt(w * w + h * h);
  if (diag < 16) return null; // chấm / nét quá nhỏ

  final a = pts.first, b = pts.last;
  final chord = a.dist(b);

  // ---- Đường thẳng: độ dài nét gần bằng khoảng cách hai đầu, không lệch xa đoạn thẳng nối hai đầu.
  if (chord > 0.85 * diag && len < chord * 1.12) {
    var dev = 0.0;
    for (final p in pts) {
      dev = math.max(dev, _segDist(p, a, b));
    }
    if (dev < math.max(3.0, chord * 0.06)) {
      final e = _snapEnd(a, b);
      return (t: 'line', p: [_r(a.x), _r(a.y), _r(e.x), _r(e.y)]);
    }
  }

  // ---- Hình khép kín: hai đầu nét gần nhau so với chiều dài nét.
  if (chord > 0.22 * len || len < 1.3 * (w + h)) return null;
  final size = (w + h) / 2;
  if (math.min(w, h) < 0.08 * math.max(w, h)) return null; // quá dẹt → có lẽ là nét gạch

  // Chữ nhật (thẳng trục): mọi điểm sát cạnh khung bao và nét đi qua cả 4 góc.
  var rectErr = 0.0;
  for (final p in pts) {
    rectErr += math.min(math.min((p.x - minX).abs(), (maxX - p.x).abs()), math.min((p.y - minY).abs(), (maxY - p.y).abs()));
  }
  rectErr /= pts.length * size;
  final corners = [Pt(minX, minY), Pt(maxX, minY), Pt(maxX, maxY), Pt(minX, maxY)];
  final cornerTol = 0.16 * math.min(w, h);
  final visited = corners.where((c) => pts.any((p) => p.dist(c) < cornerTol)).length;
  if (visited == 4 && rectErr < 0.05) {
    return (t: 'rect', p: [_r(minX), _r(minY), _r(maxX), _r(maxY)]);
  }

  // Đa giác: tìm các góc bằng RDP rồi bỏ đỉnh gần thẳng hàng (do điểm bắt đầu nằm giữa cạnh).
  var poly = simplify(pts, 0.08 * diag);
  if (poly.length > 2 && poly.first.dist(poly.last) < 0.2 * diag) poly = poly.sublist(0, poly.length - 1);
  var changed = true;
  while (changed && poly.length > 3) {
    changed = false;
    for (var i = 0; i < poly.length; i++) {
      final prev = poly[(i - 1 + poly.length) % poly.length], next = poly[(i + 1) % poly.length];
      if (_segDist(poly[i], prev, next) < 0.08 * diag) {
        poly = [...poly]..removeAt(i);
        changed = true;
        break;
      }
    }
  }
  final polyErr = poly.length >= 3 && _convex(poly) ? _polyErr(pts, poly) / size : double.infinity;

  // Elip / hình tròn: so với elip nội tiếp khung bao.
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2, rx = w / 2, ry = h / 2;
  var ellErr = 0.0;
  final bins = List.filled(12, false);
  for (final p in pts) {
    final dx = (p.x - cx) / rx, dy = (p.y - cy) / ry;
    ellErr += (math.sqrt(dx * dx + dy * dy) - 1).abs();
    bins[(((math.atan2(dy, dx) + math.pi) / (2 * math.pi)) * 12).floor() % 12] = true;
  }
  ellErr /= pts.length;
  final coverage = bins.where((x) => x).length;

  if (poly.length == 3 && polyErr < 0.04 && polyErr < ellErr) {
    return (t: 'poly', p: [for (final v in poly) ...[_r(v.x), _r(v.y)]]);
  }
  if (ellErr < 0.09 && coverage >= 11) {
    if ((w - h).abs() < 0.18 * math.max(w, h)) {
      // Gần tròn → tròn hoàn hảo.
      final r = (w + h) / 4;
      return (t: 'ellipse', p: [_r(cx - r), _r(cy - r), _r(cx + r), _r(cy + r)]);
    }
    return (t: 'ellipse', p: [_r(minX), _r(minY), _r(maxX), _r(maxY)]);
  }
  if (poly.length == 4 && polyErr < 0.035) {
    return (t: 'poly', p: [for (final v in poly) ...[_r(v.x), _r(v.y)]]);
  }
  return null;
}
