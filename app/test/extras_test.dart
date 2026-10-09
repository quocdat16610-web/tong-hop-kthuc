import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/ui/extras.dart' show fold;

void main() {
  test('tìm kiếm không phân biệt dấu', () {
    expect(fold('Sắp xếp NỔI BỌT'), 'sap xep noi bot');
    expect(fold('Đường đi ngắn nhất'), 'duong di ngan nhat');
  });
}
