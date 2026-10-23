import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:so_tay_dsa/app_state.dart';
import 'package:so_tay_dsa/core/storage.dart';
import 'package:so_tay_dsa/ui/drop.dart';
import 'package:so_tay_dsa/ui/whiteboard.dart';

import 'digit_samples.dart' as samples;

void main() {
  setUpAll(() async {
    await Storage.init(override: Directory.systemTemp.createTempSync('sotay-board'));
  });

  Future<void> native(String method, Object? args) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'desktop_drop',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );

  Future<Map<String, dynamic>> pump(WidgetTester t, {List<String>? outerDrops}) async {
    final block = <String, dynamic>{'id': 'b1', 'type': 'board', 'title': '', 'height': 560, 'bg': 'plain', 'strokes': <dynamic>[]};
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        home: Scaffold(
          body: AppDropTarget(
            child: DropZone(
              hint: 'trang',
              onDrop: (files, _) async => outerDrops?.addAll(files.map((f) => f.fileName)),
              child: Padding(padding: const EdgeInsets.all(100), child: Whiteboard(block: block, ro: false, fill: true, onChanged: () {})),
            ),
          ),
        ),
      ),
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

  testWidgets('kéo thả: ảnh vào bảng thì thành ảnh trên bảng, thả ra ngoài bảng thì vùng ngoài nhận', (t) async {
    final dir = Directory.systemTemp.createTempSync('sotay-drop');
    final img = File(p.join(dir.path, 'anh.png'));
    await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 20), Paint()..color = const Color(0xFF0969DA));
      final data = await (await rec.endRecording().toImage(40, 20)).toByteData(format: ui.ImageByteFormat.png);
      img.writeAsBytesSync(data!.buffer.asUint8List());
    });
    final doc = File(p.join(dir.path, 'bai.pdf'))..writeAsStringSync('%PDF-1.4');
    final outer = <String>[];
    final block = await pump(t, outerDrops: outer);
    final board = t.getRect(find.byType(Listener).last);

    await t.runAsync(() async {
      await native('entered', [board.center.dx, board.center.dy]);
      await native('performOperation', [img.path]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    final strokes = block['strokes'] as List;
    expect(strokes, hasLength(1));
    expect((strokes.single as Map)['t'], 'image');
    expect('${(strokes.single as Map)['src']}', startsWith('asset:'));
    expect(outer, isEmpty);

    await t.runAsync(() async {
      await native('entered', [50.0, 50.0]); // lề ngoài bảng
      await native('performOperation', [doc.path]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pump();
    expect(outer, ['bai.pdf']);
    expect(strokes, hasLength(1));
  });

  test('tên file thả vào không kèm thư mục, dù đường dẫn dùng / hay \\', () {
    expect(DropItemFile(r'C:\Users\a\Desktop\bai tap.pdf').fileName, 'bai tap.pdf');
    expect(DropItemFile('/home/a/anh.png').fileName, 'anh.png');
    expect(DropItemFile(r'D:\tmp/sotay-drop/bai.pdf').fileName, 'bai.pdf');
  });

  testWidgets('viết tay số "12" → thành chữ in sau khi ngừng viết; Hoàn tác trả lại nét tay', (t) async {
    final block = await pump(t);
    final c = t.getRect(find.byType(Listener).last).center;
    final r = math.Random(2);
    final strokes = block['strokes'] as List;
    for (final (digit, dx) in [('1', 0.0), ('2', 45.0)]) {
      for (final s in samples.ink(samples.hand[digit]![0], r, at: (c.dx + dx, c.dy))) {
        await drawPath(t, [for (var i = 0; i + 1 < s.length; i += 2) Offset(s[i].toDouble(), s[i + 1].toDouble())]);
      }
      await t.pump(const Duration(milliseconds: 200)); // viết chữ tiếp theo trước khi hết thời gian chờ
    }
    expect(strokes.every((s) => (s as Map)['t'] == 'pen'), isTrue, reason: 'chưa ngừng viết thì vẫn là nét tay');
    await t.pump(const Duration(milliseconds: 700));
    expect(strokes, hasLength(1));
    final text = strokes.single as Map;
    expect(text['t'], 'text');
    expect(text['text'], '12');
    expect((text['fs'] as num) * .71, closeTo(50, 8)); // chữ in cao bằng chữ viết tay

    await t.tap(find.byIcon(Icons.undo));
    await t.pump();
    expect(strokes.length, greaterThanOrEqualTo(2));
    expect(strokes.every((s) => (s as Map)['t'] == 'pen'), isTrue);
  });

  testWidgets('vòng tròn nhỏ (cỡ chữ) vẫn thành hình tròn, không thành số 0', (t) async {
    final block = await pump(t);
    final c = t.getRect(find.byType(Listener).last).center;
    await drawPath(t, [for (var i = 0; i <= 40; i++) c + Offset(30 * math.cos(i / 40 * 2.05 * math.pi), 29 * math.sin(i / 40 * 2.05 * math.pi))]);
    await t.pump(const Duration(milliseconds: 700));
    final strokes = block['strokes'] as List;
    expect((strokes.single as Map)['t'], 'ellipse');
  });
}
