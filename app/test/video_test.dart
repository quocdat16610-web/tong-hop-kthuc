import 'package:flutter_test/flutter_test.dart';
import 'package:so_tay_dsa/core/templates.dart';

void main() {
  test('nhận link và mã nhúng video', () {
    (String, String, int)? p(String s) {
      final v = parseVideo(s);
      return v == null ? null : (v.kind, v.value, v.start);
    }

    expect(p('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=90'), ('youtube', 'dQw4w9WgXcQ', 90));
    expect(p('https://youtu.be/dQw4w9WgXcQ?t=1m5s'), ('youtube', 'dQw4w9WgXcQ', 65));
    expect(p('youtube.com/shorts/abcDEF12345'), ('youtube', 'abcDEF12345', 0));
    expect(
        p('<iframe width="560" height="315" src="https://www.youtube.com/embed/dQw4w9WgXcQ?si=xyz&amp;start=30" title="YouTube video player" frameborder="0" allowfullscreen></iframe>'),
        ('youtube', 'dQw4w9WgXcQ', 30));
    expect(p('<iframe src="https://drive.google.com/file/d/1AbC_def-GHI/preview" width="640"></iframe>'), ('drive', '1AbC_def-GHI', 0));
    expect(p('https://example.com/bai-giang/video.mp4'), ('file', 'https://example.com/bai-giang/video.mp4', 0));
    expect(p('https://www.facebook.com/watch/?v=123')?.$1, 'link');
    expect(p('khong phai link'), isNull);
  });
}
