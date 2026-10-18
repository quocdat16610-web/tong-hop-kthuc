import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/shapes.dart';

/// Nét vẽ tay giả lập: đi theo các điểm cho trước, thêm rung tay ngẫu nhiên.
List<double> _ink(List<(double, double)> path, {double jitter = 2, int seed = 1}) {
  final rnd = math.Random(seed);
  final out = <double>[];
  for (var i = 0; i + 1 < path.length; i++) {
    final (x0, y0) = path[i];
    final (x1, y1) = path[i + 1];
    final n = math.max(2, (math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 5).round());
    for (var k = 0; k < n; k++) {
      final t = k / n;
      out.addAll([x0 + (x1 - x0) * t + (rnd.nextDouble() - .5) * jitter, y0 + (y1 - y0) * t + (rnd.nextDouble() - .5) * jitter]);
    }
  }
  out.addAll([path.last.$1, path.last.$2]);
  return out;
}

List<(double, double)> _ellipse(double cx, double cy, double rx, double ry, {double start = 0, double sweep = 2 * math.pi, double wobble = 0}) => [
  for (var i = 0; i <= 72; i++)
    (cx + (rx + wobble * math.sin(i * 0.7)) * math.cos(start + sweep * i / 72), cy + (ry + wobble * math.cos(i * 0.5)) * math.sin(start + sweep * i / 72)),
];

void main() {
  test('đường gần thẳng → đường thẳng, nắn về nằm ngang', () {
    final s = recognizeShape(_ink([(10, 100), (100, 103), (200, 99), (300, 102)]));
    expect(s?.t, 'line');
    expect(s!.p[1], s.p[3]); // nằm ngang hoàn hảo
  });

  test('đường chéo xiên 30° giữ nguyên góc', () {
    final s = recognizeShape(_ink([(0, 0), (173, 100)], jitter: 3));
    expect(s?.t, 'line');
    expect(s!.p[2], closeTo(173, 1));
    expect(s.p[3], closeTo(100, 1));
  });

  test('hình tròn vẽ méo → tròn hoàn hảo', () {
    final s = recognizeShape(_ink(_ellipse(200, 200, 100, 92, start: .3, sweep: 2 * math.pi * 1.04, wobble: 6), jitter: 3));
    expect(s?.t, 'ellipse');
    expect(s!.p[2] - s.p[0], closeTo(s.p[3] - s.p[1], 0.01));
  });

  test('vòng tròn chưa khép hẳn vẫn nhận', () {
    expect(recognizeShape(_ink(_ellipse(0, 0, 80, 80, sweep: 2 * math.pi * .9, wobble: 3)))?.t, 'ellipse');
  });

  test('elip dẹt → elip', () {
    final s = recognizeShape(_ink(_ellipse(0, 0, 160, 70, wobble: 3)));
    expect(s?.t, 'ellipse');
    expect(s!.p[2] - s.p[0], greaterThan(1.8 * (s.p[3] - s.p[1])));
  });

  test('chữ nhật', () {
    expect(recognizeShape(_ink([(50, 40), (250, 45), (248, 160), (52, 158), (50, 42)], jitter: 3))?.t, 'rect');
  });

  test('bắt đầu giữa cạnh vẫn ra chữ nhật', () {
    expect(recognizeShape(_ink([(150, 40), (250, 40), (250, 160), (50, 160), (50, 40), (152, 41)], jitter: 3))?.t, 'rect');
  });

  test('tam giác', () {
    final s = recognizeShape(_ink([(100, 20), (180, 160), (20, 160), (100, 22)], jitter: 3));
    expect(s?.t, 'poly');
    expect(s!.p.length, 6);
  });

  test('hình thoi → tứ giác', () {
    final s = recognizeShape(_ink([(100, 0), (200, 100), (100, 200), (0, 100), (100, 2)], jitter: 3));
    expect(s?.t, 'poly');
    expect(s!.p.length, 8);
  });

  test('nét nguệch ngoạc, chữ viết tay, nét quá nhỏ giữ nguyên', () {
    expect(recognizeShape(_ink([(0, 0), (40, 80), (80, 0), (120, 80), (160, 0)])), isNull); // zigzag
    expect(recognizeShape(_ink([(0, 0), (50, 50), (100, 0), (50, 60), (0, 10)])), isNull);
    expect(recognizeShape(_ink([(0, 0), (5, 5), (8, 2)])), isNull);
    expect(recognizeShape(_ink(_ellipse(0, 0, 100, 100, sweep: math.pi))), isNull); // nửa vòng tròn (cung)
  });
}
