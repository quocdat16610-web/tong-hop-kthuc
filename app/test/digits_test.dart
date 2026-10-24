import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/digits.dart';

import 'digit_samples.dart';

void main() {
  test('nhận đúng phần lớn chữ số viết tay, mọi chữ số 0–9', () {
    final r = math.Random(7);
    var ok = 0, total = 0;
    for (final e in hand.entries) {
      var okDigit = 0, n = 0;
      for (final v in e.value) {
        for (var k = 0; k < 10; k++) {
          n++;
          if (recognizeDigit(ink(v, r))?.digit == e.key) okDigit++;
        }
      }
      expect(okDigit / n, greaterThan(.6), reason: 'chữ số ${e.key}: $okDigit/$n');
      ok += okDigit;
      total += n;
    }
    expect(ok / total, greaterThan(.9), reason: '$ok/$total');
  });

  test('ít nhận nhầm nét không phải số (chữ cái, dấu, hình)', () {
    final r = math.Random(5);
    var wrong = 0, total = 0;
    for (final v in neg.values) {
      for (var k = 0; k < 10; k++) {
        total++;
        if (recognizeDigit(ink(v, r)) != null) wrong++;
      }
    }
    expect(wrong / total, lessThan(.1), reason: '$wrong/$total');
  });

  test('hình tròn đều không thành "0", gạch ngang / đoạn xiên dài không thành "1"', () {
    final circle = <num>[for (var i = 0; i <= 40; i++) ...[50 + 30 * math.cos(i / 40 * 2 * math.pi), 50 + 31 * math.sin(i / 40 * 2 * math.pi)]];
    expect(recognizeDigit([circle])?.digit, isNot('0'));
    expect(recognizeDigit([
      [0, 50, 20, 51, 40, 50, 60, 49],
    ]), isNull);
    expect(recognizeDigit([
      [0, 0, 20, 15, 40, 30, 60, 45],
    ]), isNull);
  });

  test('số nhiều chữ số: tách theo chiều ngang, chữ số nhiều nét giữ nguyên', () {
    final r = math.Random(3);
    final strokes = [
      ...ink(hand['2']![0], r, at: (100, 100)),
      ...ink(hand['0']![0], r, at: (145, 101)),
      ...ink(hand['4']![0], r, at: (190, 99)), // "4" hai nét
      ...ink(hand['7']![1], r, at: (240, 100)), // "7" có gạch ngang
    ];
    final n = recognizeNumber(strokes);
    expect(n?.text, '2047');
    expect(n!.box[0], closeTo(100, 15));
    expect(n.box[3] - n.box[1], closeTo(50, 6));
  });
}
