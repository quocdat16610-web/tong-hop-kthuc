// Nhận dạng chữ số viết tay (0–9, một hay nhiều nét, một hay nhiều chữ số liền nhau) trên bảng trắng.
// Dùng thuật toán $P (Vatavu, Anthony, Wobbrock 2012): so "đám mây điểm" của nét vẽ với các mẫu,
// không phụ thuộc thứ tự / chiều vẽ nét, nên viết "4" hai nét hay một nét, "5" vẽ gạch ngang trước hay sau đều nhận.
// Không phụ thuộc Flutter để kiểm thử được bằng `dart test`.
import 'dart:math' as math;

import 'shapes.dart' show Pt, recognizeShape;

const _n = 32; // số điểm sau khi lấy mẫu lại

class _P {
  final double x, y;
  final int stroke;
  const _P(this.x, this.y, this.stroke);
}

List<List<Pt>> _parse(List<List<num>> strokes) => [
  for (final s in strokes) [for (var i = 0; i + 1 < s.length; i += 2) Pt(s[i].toDouble(), s[i + 1].toDouble())],
];

double _pathLen(List<_P> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    if (pts[i].stroke == pts[i - 1].stroke) d += math.sqrt(math.pow(pts[i].x - pts[i - 1].x, 2) + math.pow(pts[i].y - pts[i - 1].y, 2));
  }
  return d;
}

List<_P> _resample(List<_P> pts, int n) {
  final total = _pathLen(pts);
  if (total == 0) return List.filled(n, pts.first);
  final step = total / (n - 1);
  var acc = 0.0;
  final out = <_P>[pts.first];
  final src = List.of(pts);
  for (var i = 1; i < src.length && out.length < n; i++) {
    final a = src[i - 1], b = src[i];
    if (a.stroke != b.stroke) continue;
    final d = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    if (acc + d >= step && d > 0) {
      final t = (step - acc) / d;
      final q = _P(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y), a.stroke);
      out.add(q);
      src.insert(i, q);
      acc = 0;
    } else {
      acc += d;
    }
  }
  while (out.length < n) {
    out.add(src.last);
  }
  return out;
}

class _Cloud {
  final List<_P> pts;
  final List<Pt> ends; // đầu mút các nét hở (nét khép kín như "0" không có đầu mút)
  final double aspect; // rộng / cao
  _Cloud(this.pts, this.ends, this.aspect);
}

/// Chuẩn hoá: co giãn đều theo cạnh dài của khung bao (giữ tỉ lệ — "1" vẫn mảnh), dời trọng tâm về gốc.
_Cloud _normalize(List<List<Pt>> strokes) {
  final pts = <_P>[
    for (var s = 0; s < strokes.length; s++)
      for (final p in strokes[s]) _P(p.x, p.y, s),
  ];
  var r = _resample(pts, _n);
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final p in r) {
    minX = math.min(minX, p.x);
    minY = math.min(minY, p.y);
    maxX = math.max(maxX, p.x);
    maxY = math.max(maxY, p.y);
  }
  final size = math.max(math.max(maxX - minX, maxY - minY), 1e-6);
  r = [for (final p in r) _P((p.x - minX) / size, (p.y - minY) / size, p.stroke)];
  var cx = 0.0, cy = 0.0;
  for (final p in r) {
    cx += p.x;
    cy += p.y;
  }
  cx /= r.length;
  cy /= r.length;
  final ends = <Pt>[
    for (final st in strokes)
      if (st.isNotEmpty && st.first.dist(st.last) > 0.18 * size)
        for (final e in [st.first, st.last]) Pt((e.x - minX) / size - cx, (e.y - minY) / size - cy),
  ];
  return _Cloud([for (final p in r) _P(p.x - cx, p.y - cy, p.stroke)], ends, (maxX - minX) / math.max(maxY - minY, 1e-6));
}

/// Khoảng cách giữa hai tập đầu mút (ghép tham lam điểm gần nhất); đầu mút thừa bị phạt.
double _endsDistance(List<Pt> a, List<Pt> b) {
  if (a.isEmpty && b.isEmpty) return 0;
  final used = List.filled(b.length, false);
  var sum = 0.0;
  var unmatched = 0;
  for (final p in a) {
    var best = double.infinity;
    var idx = -1;
    for (var j = 0; j < b.length; j++) {
      if (used[j]) continue;
      final d = p.dist(b[j]);
      if (d < best) {
        best = d;
        idx = j;
      }
    }
    if (idx < 0) {
      unmatched++;
    } else {
      used[idx] = true;
      sum += best;
    }
  }
  unmatched += used.where((u) => !u).length;
  return sum + _unmatchedPenalty * unmatched;
}

const _unmatchedPenalty = .6;
const _endsWeight = .5;

double _cloudDistance(List<_P> a, List<_P> b, int start) {
  final matched = List.filled(a.length, false);
  var sum = 0.0;
  var i = start;
  do {
    var best = double.infinity;
    var idx = -1;
    for (var j = 0; j < b.length; j++) {
      if (matched[j]) continue;
      final d = math.sqrt(math.pow(a[i].x - b[j].x, 2) + math.pow(a[i].y - b[j].y, 2));
      if (d < best) {
        best = d;
        idx = j;
      }
    }
    matched[idx] = true;
    final weight = 1 - ((i - start + a.length) % a.length) / a.length;
    sum += weight * best;
    i = (i + 1) % a.length;
  } while (i != start);
  return sum;
}

double _greedyMatch(_Cloud ca, _Cloud cb) {
  final a = ca.pts, b = cb.pts;
  final step = math.sqrt(_n).floor();
  var best = double.infinity;
  for (var i = 0; i < _n; i += step) {
    best = math.min(best, math.min(_cloudDistance(a, b, i), _cloudDistance(b, a, i)));
  }
  return best / _n * 10 + _endsWeight * _endsDistance(ca.ends, cb.ends);
}

// ---------- Mẫu chữ số (toạ độ trong khung 1×1, y hướng xuống) ----------
List<(double, double)> _arc(double cx, double cy, double rx, double ry, double from, double to, [int k = 12]) => [
  for (var i = 0; i <= k; i++) (cx + rx * math.cos(from + (to - from) * i / k), cy + ry * math.sin(from + (to - from) * i / k)),
];

const _pi = math.pi;

final Map<String, List<List<List<(double, double)>>>> _raw = {
  '0': [
    [_arc(.5, .5, .32, .5, -_pi / 2, 3 * _pi / 2, 20)],
    [_arc(.5, .5, .3, .5, -_pi / 2 + .3, 3 * _pi / 2 + .3, 20)],
  ],
  '1': [
    [
      [(.5, 0), (.5, 1)],
    ],
    [
      [(.25, .22), (.5, 0), (.5, 1)],
    ],
    [
      [(.25, .22), (.5, 0), (.5, 1)],
      [(.25, 1), (.75, 1)],
    ],
  ],
  '2': [
    [
      [..._arc(.5, .3, .32, .3, _pi * 1.05, _pi * 2.1), (.12, 1), (.9, 1)],
    ],
    [
      [(.15, .2), (.4, 0), (.75, .05), (.82, .3), (.55, .6), (.12, 1), (.45, .9), (.9, 1)],
    ],
  ],
  '3': [
    [
      [..._arc(.48, .25, .3, .25, _pi * 1.1, _pi * 2.5), ..._arc(.48, .74, .34, .26, -_pi / 2, _pi * .9)],
    ],
    [
      [(.15, 0), (.85, 0), (.4, .42), ..._arc(.48, .7, .36, .28, -_pi / 2, _pi * .9)],
    ],
  ],
  '4': [
    [
      [(.62, 0), (.08, .66), (.92, .66)],
      [(.68, .32), (.68, 1)],
    ],
    [
      [(.2, 0), (.15, .6), (.88, .6)],
      [(.68, 0), (.68, 1)],
    ],
    [
      [(.68, 1), (.68, 0), (.08, .66), (.92, .66)],
    ],
  ],
  '5': [
    [
      [(.82, 0), (.25, 0), (.2, .45), ..._arc(.48, .7, .36, .3, -_pi * .75, _pi * .8)],
    ],
    [
      [(.25, 0), (.2, .45), ..._arc(.48, .7, .36, .3, -_pi * .75, _pi * .8)],
      [(.25, 0), (.82, 0)],
    ],
  ],
  '6': [
    [
      [(.75, .02), (.42, .05), (.18, .35), (.12, .65), ..._arc(.48, .72, .36, .28, _pi, _pi * 3)],
    ],
    [
      [(.62, 0), (.3, .35), ..._arc(.5, .7, .32, .3, _pi * .95, _pi * 2.85)],
    ],
  ],
  '7': [
    [
      [(.08, 0), (.92, 0), (.38, 1)],
    ],
    [
      [(.08, 0), (.92, 0), (.38, 1)],
      [(.35, .52), (.8, .52)],
    ],
    [
      [(.05, .14), (.1, 0), (.92, 0), (.6, .45), (.45, 1)],
    ],
  ],
  '8': [
    [
      [..._arc(.5, .25, .26, .24, -_pi * .1, -_pi * 1.5), ..._arc(.5, .73, .32, .27, -_pi / 2, _pi * 1.5).reversed, ..._arc(.5, .25, .26, .24, _pi * .5, -_pi * .1)],
    ],
    [
      _arc(.5, .24, .26, .24, 0, 2 * _pi),
      _arc(.5, .74, .32, .26, 0, 2 * _pi),
    ],
    [
      [..._arc(.5, .25, .26, .24, _pi * 1.1, _pi * 2.5), ..._arc(.5, .73, .32, .27, -_pi / 2, _pi * 1.5).reversed, ..._arc(.5, .25, .26, .24, _pi * .5, _pi * 1.1)],
    ],
  ],
  '9': [
    [
      [..._arc(.5, .27, .3, .27, 0, -2 * _pi), (.8, .3), (.75, 1)],
    ],
    [
      [..._arc(.48, .27, .3, .27, -_pi * .1, -2.1 * _pi), (.78, .6), (.6, 1)],
    ],
  ],
};

final List<(String, _Cloud)> _templates = [
  for (final e in _raw.entries)
    for (final variant in e.value) (e.key, _normalize([for (final s in variant) [for (final (x, y) in s) Pt(x, y)]])),
];

/// Ngưỡng khoảng cách $P để chấp nhận (thấp hơn = giống hơn).
const digitThreshold = .8;

/// Chữ số giống nhất cho một nhóm nét (một chữ số). Trả về null nếu không đủ giống chữ số nào.
({String digit, double score})? recognizeDigit(List<List<num>> strokes) {
  final parsed = _parse(strokes).where((s) => s.isNotEmpty).toList();
  if (parsed.isEmpty) return null;
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final s in parsed) {
    for (final p in s) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
  }
  final w = maxX - minX, h = maxY - minY;
  if (h < 4) return null;
  if (w > 1.4 * h) return null; // chữ số viết tay luôn cao hơn hoặc gần bằng bề rộng
  // Nét khép kín ra chữ nhật / tam giác / tứ giác là hình vẽ, không phải chữ số.
  if (strokes.length == 1) {
    final sh = recognizeShape(strokes.single);
    if (sh != null && (sh.t == 'rect' || sh.t == 'poly')) return null;
    if (sh != null && sh.t == 'ellipse' && h < 1.2 * w) return null; // vòng gần tròn đều là hình tròn
  }
  final cloud = _normalize(parsed);
  var best = double.infinity;
  String? digit;
  // Vòng gần tròn đều là hình tròn, không phải "0"; nét rộng (không mảnh) không phải "1".
  final no0 = h < 1.2 * w, no1 = parsed.length == 1 && h < 2.5 * w && w > 0.25 * h;
  for (final (d, t) in _templates) {
    if ((d == '0' && no0) || (d == '1' && no1)) continue;
    final s = _greedyMatch(cloud, t);
    if (s < best) {
      best = s;
      digit = d;
    }
  }
  if (digit == null || best > digitThreshold) return null;
  return (digit: digit, score: best);
}

/// Tách nhóm nét thành từng chữ số theo chiều ngang rồi nhận dạng từng chữ số.
/// Trả về chuỗi số và khung bao [minX, minY, maxX, maxY], hoặc null nếu có chữ số không nhận được.
({String text, List<double> box})? recognizeNumber(List<List<num>> strokes) {
  final items = [
    for (final s in strokes)
      if (s.length >= 2) (s: s, box: _box(s)),
  ];
  if (items.isEmpty) return null;
  items.sort((a, b) => a.box[0].compareTo(b.box[0]));
  var minY = double.infinity, maxY = -double.infinity;
  for (final it in items) {
    minY = math.min(minY, it.box[1]);
    maxY = math.max(maxY, it.box[3]);
  }
  final h = maxY - minY;
  // Gom các nét chồng lên nhau theo chiều ngang thành một chữ số.
  final groups = <({List<List<num>> strokes, double l, double r})>[];
  for (final it in items) {
    final l = it.box[0], r = it.box[2];
    final pad = 0.08 * h;
    if (groups.isNotEmpty) {
      final g = groups.last;
      final overlap = math.min(g.r, r + pad) - math.max(g.l, l - pad);
      final narrow = math.max(math.min(g.r - g.l, r - l), 0.12 * h);
      if (overlap > 0.35 * narrow) {
        groups[groups.length - 1] = (strokes: [...g.strokes, it.s], l: math.min(g.l, l), r: math.max(g.r, r));
        continue;
      }
    }
    groups.add((strokes: [it.s], l: l, r: r));
  }
  if (groups.length > 12) return null;
  final out = StringBuffer();
  for (final g in groups) {
    final d = recognizeDigit(g.strokes);
    if (d == null) return null;
    out.write(d.digit);
  }
  final minX = groups.first.l, maxX = groups.map((g) => g.r).reduce(math.max);
  return (text: out.toString(), box: [minX, minY, maxX, maxY]);
}

List<double> _box(List<num> s) {
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (var i = 0; i + 1 < s.length; i += 2) {
    minX = math.min(minX, s[i].toDouble());
    maxX = math.max(maxX, s[i].toDouble());
    minY = math.min(minY, s[i + 1].toDouble());
    maxY = math.max(maxY, s[i + 1].toDouble());
  }
  return [minX, minY, maxX, maxY];
}
