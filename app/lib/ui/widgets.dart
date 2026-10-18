// Hộp thoại và tiện ích giao diện dùng chung.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/storage.dart';

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

const _mimes = {
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp', 'svg': 'image/svg+xml',
  'mp4': 'video/mp4', 'webm': 'video/webm', 'mkv': 'video/x-matroska', 'mov': 'video/quicktime', 'mp3': 'audio/mpeg', 'wav': 'audio/wav',
  'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown', 'csv': 'text/csv', 'json': 'application/json', 'zip': 'application/zip',
  'cpp': 'text/x-c++src', 'h': 'text/x-c', 'py': 'text/x-python',
  'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

String mimeOf(String name) {
  final i = name.lastIndexOf('.');
  return _mimes[i < 0 ? '' : name.substring(i + 1).toLowerCase()] ?? 'application/octet-stream';
}

String formatSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// Chọn file trên máy và lưu vào kho ảnh / file của app. Trả về danh sách (tham chiếu "asset:…", tên, kích thước).
Future<List<({String ref, String name, int size, String type})>> pickAssets(BuildContext context, FileType type, {bool multiple = false}) async {
  final r = await FilePicker.platform.pickFiles(type: type, withData: true, allowMultiple: multiple);
  if (r == null || r.files.isEmpty) return const [];
  final out = <({String ref, String name, int size, String type})>[];
  for (final f in r.files) {
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) continue;
    if (bytes.length > 200 * 1024 * 1024 && context.mounted) {
      if (!await confirmBox(context, 'File lớn', 'File "${f.name}" ${(bytes.length / 1048576).round()} MB sẽ làm file chia sẻ rất nặng. Vẫn thêm?', ok: 'Thêm')) continue;
    }
    var mime = mimeOf(f.name);
    if (type == FileType.video && !mime.startsWith('video/')) mime = 'video/${(f.extension ?? '').toLowerCase()}';
    out.add((ref: Storage.I.addAsset(bytes, type: mime, name: f.name), name: f.name, size: bytes.length, type: mime));
  }
  return out;
}

Future<String?> pickAsset(BuildContext context, FileType type) async => (await pickAssets(context, type)).firstOrNull?.ref;
