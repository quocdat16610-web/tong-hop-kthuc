import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/ui/ide.dart';

void main() {
  test('đọc thông báo lỗi của g++ để nhảy tới dòng', () {
    const log = '''main.cpp: In function 'int main()':
main.cpp:9:15: error: expected ';' before '}' token
    9 |     return 0
/tmp/x/main.cpp:4:5: warning: unused variable 'a' [-Wunused-variable]
C:\\Users\\a\\lib.h:12:1: note: declared here''';
    final m = parseBuildLog(log);
    expect(m.length, 3);
    expect((m[0].file, m[0].line, m[0].col, m[0].kind), ('main.cpp', 9, 15, 'error'));
    expect((m[1].file, m[1].kind, m[1].text), ('main.cpp', 'warning', "unused variable 'a' [-Wunused-variable]"));
    expect(m[2].line, 12);
  });

  test('đọc traceback của Python để nhảy tới dòng', () {
    const log = '''Traceback (most recent call last):
  File "C:\\tmp\\main.py", line 7, in <module>
    main()
  File "C:\\tmp\\main.py", line 4, in main
    print(a[9])
          ~^^^
IndexError: list index out of range''';
    final m = parseBuildLog(log);
    expect(m.length, 1);
    expect((m[0].file, m[0].line, m[0].kind), ('main.py', 4, 'error'));
    expect(m[0].text, contains('IndexError'));
  });
}
