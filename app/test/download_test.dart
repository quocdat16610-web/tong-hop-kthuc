import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/updater.dart';

void main() {
  test('tải song song nhiều luồng (HTTP Range) ra file đúng từng byte', () async {
    final data = Uint8List.fromList(List.generate(9 * 1024 * 1024 + 123, (i) => Random(i).nextInt(256)));
    var rangeRequests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      if (range != null && req.uri.path == '/range') {
        rangeRequests++;
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final a = int.parse(m[1]!), b = int.parse(m[2]!);
        req.response
          ..statusCode = 206
          ..headers.set('content-range', 'bytes $a-$b/${data.length}')
          ..add(data.sublist(a, b + 1));
      } else {
        req.response.add(data); // máy chủ không hỗ trợ Range
      }
      await req.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final progress = <double>[];
    final f1 = await download('$base/range', 'test-range.bin', progress.add);
    expect(await f1.readAsBytes(), data);
    expect(rangeRequests, 5); // 1 lần hỏi kích thước + 4 luồng
    expect(progress.last, closeTo(1, 1e-9));
    final f2 = await download('$base/plain', 'test-plain.bin', (_) {});
    expect(await f2.readAsBytes(), data);
    await server.close(force: true);
    f1.deleteSync();
    f2.deleteSync();
  });
}
