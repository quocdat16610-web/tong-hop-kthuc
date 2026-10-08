import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/scratch.dart';
import 'package:so_tay_dsa/core/scratch_templates.dart';

// Chạy code sinh ra bằng Node (nếu có) với thư viện viz thật để chắc chắn mẫu chạy đúng.
Map<String, dynamic>? runNode(String code, String input) {
  final node = Process.runSync('node', ['--version']);
  if (node.exitCode != 0) return null;
  final dir = Directory.systemTemp.createTempSync('scratch');
  final f = File('${dir.path}/run.js')
    ..writeAsStringSync('${File('assets/sim_runtime.js').readAsStringSync()}\nprocess.stdout.write(__runSim(${jsonEncode(code)}, ${jsonEncode(input)}));');
  final r = Process.runSync('node', [f.path]);
  dir.deleteSync(recursive: true);
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

bool get hasNode {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

void main() {
  test('tên biến tiếng Việt thành tên JS hợp lệ', () {
    expect(jsName('v_', 'i'), 'v_i');
    expect(jsName('v_', 'đếm'), isNot(contains('đ')));
    expect(jsName('v_', 'đếm'), isNot(jsName('v_', 'dem')));
  });

  for (final t in blockTemplates) {
    test('mẫu khối "${t.name}" sinh code chạy được', () {
      final code = generateJs(t.program());
      final r = runNode(code, t.input)!;
      expect(r['error'], isNull, reason: code);
      expect((r['frames'] as List).length, greaterThan(3));
    }, skip: !hasNode);
  }

  test('kết quả đúng: sắp xếp, tìm kiếm nhị phân, ngoặc, BFS, DFS', () {
    String lastNote(String id, String input) {
      final t = blockTemplates.firstWhere((x) => x.id == id);
      final r = runNode(generateJs(t.program()), input)!;
      expect(r['error'], isNull);
      return ((r['frames'] as List).last as Map)['note'] as String;
    }

    final bubble = runNode(generateJs(blockTemplates.first.program()), '5 1 4 2 8 3')!;
    final arr = (((bubble['frames'] as List).last as Map)['s'] as List).first as Map;
    expect(arr['v'], [1, 2, 3, 4, 5, 8]);
    expect(lastNote('k-binary', '1 3 5 7 9 11 13\n11'), contains('vị trí 5'));
    expect(lastNote('k-brackets', '({[]})'), 'Dãy ngoặc ĐÚNG');
    expect(lastNote('k-brackets', '(]'), 'Dãy ngoặc SAI');
    expect(lastNote('k-bfs', 'S.#\n..E'), 'Đến đích sau 3 bước');
    expect(lastNote('k-dfs', '1 2 1 3 2 4'), 'Thứ tự thăm: 1 2 4 3');
  }, skip: !hasNode);

  test('chuyển khối Blockly của bản cũ', () {
    final legacy = {
      'blocks': {
        'languageVersion': 0,
        'blocks': [
          {
            'type': 'dsa_array_create',
            'x': 20,
            'y': 20,
            'fields': {'VAR': {'id': 'A'}, 'STYLE': 'bars'},
            'inputs': {'LIST': {'block': {'type': 'dsa_read_numbers'}}},
            'next': {
              'block': {
                'type': 'controls_for',
                'fields': {'VAR': {'id': 'I'}},
                'inputs': {
                  'FROM': {'shadow': {'type': 'math_number', 'fields': {'NUM': 0}}},
                  'TO': {
                    'shadow': {'type': 'math_number', 'fields': {'NUM': 9}},
                    'block': {
                      'type': 'math_arithmetic',
                      'fields': {'OP': 'MINUS'},
                      'inputs': {
                        'A': {'block': {'type': 'dsa_array_length', 'fields': {'VAR': {'id': 'A'}}}},
                        'B': {'shadow': {'type': 'math_number', 'fields': {'NUM': 1}}},
                      },
                    },
                  },
                  'BY': {'shadow': {'type': 'math_number', 'fields': {'NUM': 1}}},
                  'DO': {
                    'block': {
                      'type': 'controls_if',
                      'extraState': {'hasElse': true},
                      'inputs': {
                        'IF0': {
                          'block': {
                            'type': 'logic_compare',
                            'fields': {'OP': 'GT'},
                            'inputs': {
                              'A': {'block': {'type': 'dsa_array_get', 'fields': {'VAR': {'id': 'A'}}, 'inputs': {'I': {'block': {'type': 'variables_get', 'fields': {'VAR': {'id': 'I'}}}}}}},
                              'B': {'shadow': {'type': 'math_number', 'fields': {'NUM': 3}}},
                            },
                          },
                        },
                        'DO0': {'block': {'type': 'dsa_array_mark', 'fields': {'VAR': {'id': 'A'}, 'COLOR': 'done'}, 'inputs': {'I': {'block': {'type': 'variables_get', 'fields': {'VAR': {'id': 'I'}}}}}}},
                        'ELSE': {'block': {'type': 'dsa_array_mark', 'fields': {'VAR': {'id': 'A'}, 'COLOR': 'dim'}, 'inputs': {'I': {'block': {'type': 'variables_get', 'fields': {'VAR': {'id': 'I'}}}}}}},
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
      'variables': [
        {'name': 'a', 'id': 'A'},
        {'name': 'i', 'id': 'I'},
      ],
    };
    final prog = fromBlockly(legacy);
    final main = prog['main'] as List;
    expect(main.length, 2);
    expect((main[1] as Map)['op'], 'for');
    expect(((main[1] as Map)['do'] as List).first['op'], 'ifelse');
    if (hasNode) {
      final r = runNode(generateJs(prog), '1 5 2 7')!;
      expect(r['error'], isNull);
      final arr = (((r['frames'] as List).last as Map)['s'] as List).first as Map;
      expect(arr['st'], {'0': 'dim', '1': 'done', '2': 'dim', '3': 'done'});
    }
  });
}
