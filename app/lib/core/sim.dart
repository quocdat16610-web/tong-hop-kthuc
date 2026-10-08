// Chạy kịch bản mô phỏng (JavaScript + thư viện viz) bằng QuickJS trong một isolate riêng.
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

class SimResult {
  final List<Map<String, dynamic>> frames;
  final List<String> logs;
  final String? error;
  SimResult(this.frames, this.logs, this.error);
}

String? _runtimeSrc;

String _runInIsolate(String runtime, String code, String input) {
  // timeout (ms): QuickJS tự ngắt khi chạy quá lâu (vòng lặp vô hạn).
  final rt = QuickJsRuntime2(timeout: 4000);
  try {
    final init = rt.evaluate(runtime);
    if (init.isError) return jsonEncode({'frames': [], 'logs': [], 'error': 'Lỗi khởi tạo: ${init.stringResult}'});
    final r = rt.evaluate('__runSim(${jsonEncode(code)}, ${jsonEncode(input)})');
    if (r.isError) {
      final msg = r.stringResult;
      return jsonEncode({
        'frames': [],
        'logs': [],
        'error': msg.contains('interrupted') ? 'Quá thời gian chạy 4 giây — có thể có vòng lặp vô hạn.' : msg,
      });
    }
    return r.stringResult;
  } finally {
    rt.dispose();
  }
}

Future<SimResult> runSimulation(String code, String input) async {
  _runtimeSrc ??= await rootBundle.loadString('assets/sim_runtime.js');
  final runtime = _runtimeSrc!;
  try {
    final out = await Isolate.run(() => _runInIsolate(runtime, code, input)).timeout(const Duration(seconds: 8));
    final d = jsonDecode(out) as Map;
    return SimResult(
      ((d['frames'] ?? []) as List).cast<Map>().map((m) => m.cast<String, dynamic>()).toList(),
      ((d['logs'] ?? []) as List).map((x) => '$x').toList(),
      d['error'] as String?,
    );
  } on TimeoutException {
    return SimResult([], [], 'Quá thời gian chạy — có thể có vòng lặp vô hạn.');
  } catch (e) {
    return SimResult([], [], '$e');
  }
}
