import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:so_tay_dsa/app_state.dart';
import 'package:so_tay_dsa/core/storage.dart';
import 'package:so_tay_dsa/ui/whiteboard.dart';

void main() {
  setUpAll(() async {
    await Storage.init(override: Directory.systemTemp.createTempSync('sotay-board'));
  });

  Future<Map<String, dynamic>> pump(WidgetTester t) async {
    final block = <String, dynamic>{'id': 'b1', 'type': 'board', 'title': '', 'height': 560, 'bg': 'plain', 'strokes': <dynamic>[]};
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(home: Scaffold(body: Whiteboard(block: block, ro: false, fill: true, onChanged: () {}))),
    ));
    return block;
  }

  Future<void> drawPath(WidgetTester t, List<Offset> pts) async {
    final g = await t.startGesture(pts.first, kind: PointerDeviceKind.mouse);
    for (final p in pts.skip(1)) {
      await g.moveTo(p);
    }
    await g.up();
    await t.pump();
  }

  testWidgets('vẽ tay vòng tròn méo → hình tròn; Hoàn tác trả lại nét tay', (t) async {
    final block = await pump(t);
    final box = t.getRect(find.byType(Listener).last);
    final c = box.center;
    await drawPath(t, [for (var i = 0; i <= 50; i++) c + Offset((100 + 6 * math.sin(i * .9)) * math.cos(i / 50 * 2.05 * math.pi), 94 * math.sin(i / 50 * 2.05 * math.pi))]);
    final strokes = block['strokes'] as List;
    expect(strokes, hasLength(1));
    expect((strokes.single as Map)['t'], 'ellipse');
    final p = ((strokes.single as Map)['p'] as List).cast<num>();
    expect(p[2] - p[0], closeTo(p[3] - p[1], .01));

    await t.tap(find.byIcon(Icons.undo));
    await t.pump();
    expect((strokes.single as Map)['t'], 'pen');
    await t.tap(find.byIcon(Icons.redo));
    await t.pump();
    expect((strokes.single as Map)['t'], 'ellipse');
  });

  testWidgets('công cụ Chọn kéo được hình, Delete xoá', (t) async {
    final block = await pump(t);
    final box = t.getRect(find.byType(Listener).last);
    final a = box.center - const Offset(150, 0);
    await drawPath(t, [for (var i = 0; i <= 20; i++) a + Offset(i * 15.0, (i % 3) * 1.0)]);
    final strokes = block['strokes'] as List;
    expect((strokes.single as Map)['t'], 'line');
    final before = ((strokes.single as Map)['p'] as List).cast<num>().toList();

    await t.tap(find.byIcon(Icons.near_me_outlined));
    await t.pump();
    await drawPath(t, [a + const Offset(150, 0), a + const Offset(160, 20), a + const Offset(170, 40)]);
    final after = ((strokes.single as Map)['p'] as List).cast<num>().toList();
    expect(after[0] - before[0], closeTo(20, 1.5));
    expect(after[1] - before[1], closeTo(40, 1.5));

    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(strokes, isEmpty);
  });
}
