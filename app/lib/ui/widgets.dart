// Hộp thoại và tiện ích giao diện dùng chung.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'theme.dart';

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? context.cs.error : null,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

Future<bool> confirmBox(BuildContext context, String title, String text, {String ok = 'Đồng ý', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Text(text)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: c.cs.error, foregroundColor: c.cs.onError) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptBox(BuildContext context, String title, String label, {String value = '', String ok = 'OK'}) {
  final ctl = TextEditingController(text: value);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: label), onSubmitted: (v) => Navigator.pop(c, v.trim())),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

/// Hộp thoại rộng với nội dung cuộn được.
Future<T?> showPanel<T>(BuildContext context, {required String title, required Widget Function(BuildContext, StateSetter) builder, List<Widget> Function(BuildContext)? actions, double width = 720}) {
  return showDialog<T>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setSt) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(c).height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(children: [
                Expanded(child: Text(title, style: c.tt.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.close), tooltip: 'Đóng', onPressed: () => Navigator.pop(c)),
              ]),
            ),
            const Divider(),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: builder(c, setSt))),
            if (actions != null) ...[
              const Divider(),
              Padding(padding: const EdgeInsets.all(12), child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions(c))),
            ],
          ]),
        ),
      ),
    ),
  );
}

String timeAgo(int t) {
  final s = (DateTime.now().millisecondsSinceEpoch - t) / 1000;
  if (s < 60) return 'vừa xong';
  if (s < 3600) return '${s ~/ 60} phút trước';
  if (s < 86400) return '${s ~/ 3600} giờ trước';
  if (s < 86400 * 30) return '${s ~/ 86400} ngày trước';
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  return '${d.day}/${d.month}/${d.year}';
}

String fullTime(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)} ${d.day}/${d.month}/${d.year}';
}

/// Lưu file: máy tính → hộp thoại Lưu; Android → bảng chia sẻ (Zalo, Messenger, Drive…).
Future<void> saveTextFile(BuildContext context, String name, String text) => saveBytesFile(context, name, utf8.encode(text));

Future<void> saveBytesFile(BuildContext context, String name, List<int> bytes) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], title: name));
      return;
    }
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Lưu file', fileName: name);
    if (path == null) return;
    File(path).writeAsBytesSync(bytes);
    if (context.mounted) toast(context, 'Đã lưu $path');
  } catch (e) {
    if (context.mounted) toast(context, 'Không lưu được: $e', error: true);
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 6, 4),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: context.tt.labelSmall?.copyWith(color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: .6)),
          ),
          ?trailing,
        ]),
      );
}

/// Khung chữ đơn cách (output, input, log).
class MonoBox extends StatelessWidget {
  final String text;
  final Color? color;
  final double? maxHeight;
  const MonoBox(this.text, {super.key, this.color, this.maxHeight});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight ?? 260),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: context.cs.surfaceContainer, borderRadius: BorderRadius.circular(4)),
        child: SingleChildScrollView(
          child: SelectableText(text.isEmpty ? '(trống)' : text, style: TextStyle(fontFamily: monoFont, fontSize: 13, color: color)),
        ),
      );
}
