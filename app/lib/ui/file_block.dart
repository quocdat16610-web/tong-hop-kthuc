// Khối "File đính kèm": tải file bất kỳ (PDF, Word, ảnh, code, zip…) lên trang; mở bằng app trên máy hoặc lưu / chia sẻ.
// File lưu trong kho "asset:<hash>" của app nên đi kèm khi xuất / chia sẻ / sao lưu notebook như ảnh và video.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/vcs.dart' show Json;
import 'media.dart';
import 'theme.dart';
import 'widgets.dart';

List _files(Json b) => (b['files'] ??= <dynamic>[]) as List;

/// Chọn một hay nhiều file và thêm vào khối. Trả về số file đã thêm.
Future<int> addFilesTo(BuildContext context, Json block) async {
  final picked = await pickAssets(context, FileType.any, multiple: true);
  for (final f in picked) {
    _files(block).add({'src': f.ref, 'name': f.name, 'size': f.size, 'type': f.type});
  }
  return picked.length;
}

IconData _icon(String name, String type) {
  final ext = p.extension(name).toLowerCase();
  if (type.startsWith('image/')) return Icons.image_outlined;
  if (type.startsWith('video/')) return Icons.movie_outlined;
  if (type.startsWith('audio/')) return Icons.audiotrack_outlined;
  return switch (ext) {
    '.pdf' => Icons.picture_as_pdf_outlined,
    '.doc' || '.docx' || '.txt' || '.md' => Icons.description_outlined,
    '.xls' || '.xlsx' || '.csv' => Icons.table_chart_outlined,
    '.ppt' || '.pptx' => Icons.slideshow_outlined,
    '.zip' || '.rar' || '.7z' => Icons.folder_zip_outlined,
    '.cpp' || '.c' || '.h' || '.hpp' || '.py' || '.js' || '.json' => Icons.code,
    _ => Icons.insert_drive_file_outlined,
  };
}

class FileBlock extends StatelessWidget {
  final Json block;
  final bool ro;
  const FileBlock({super.key, required this.block, required this.ro});

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Máy tính: chép ra thư mục tạm với đúng tên file rồi mở bằng app mặc định.
  Future<void> _open(BuildContext context, File src, String name) async {
    try {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'so-tay-dsa-files', p.basename(src.path).substring(0, 12)))..createSync(recursive: true);
      final out = File(p.join(dir.path, name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')));
      if (!out.existsSync() || out.lengthSync() != src.lengthSync()) await src.copy(out.path);
      if (!await launchUrl(Uri.file(out.path)) && context.mounted) toast(context, 'Không có app nào mở được file này.', error: true);
    } catch (e) {
      if (context.mounted) toast(context, 'Không mở được file: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final files = _files(block);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.attach_file, size: 16, color: context.cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                (block['title'] ?? '').toString().isEmpty ? 'File đính kèm' : '${block['title']}',
                style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
            if (!ro)
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Tải file lên'),
                onPressed: () async {
                  if (await addFilesTo(context, block) > 0) app.changed();
                },
              ),
          ],
        ),
        if (files.isEmpty)
          Container(
            height: 64,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 6),
            color: context.cs.surfaceContainer,
            child: Text(ro ? 'Chưa có file.' : 'Chưa có file — bấm "Tải file lên" để chọn một hoặc nhiều file trên máy.', style: context.tt.bodySmall),
          ),
        for (final f in files.whereType<Map>()) _row(context, app, f),
      ],
    );
  }

  Widget _row(BuildContext context, AppState app, Map f) {
    final src = '${f['src'] ?? ''}';
    final name = '${f['name'] ?? 'file'}';
    final type = '${f['type'] ?? ''}';
    final file = Storage.I.assetFile(src);
    final size = file == null ? null : ((f['size'] as num?)?.toInt() ?? file.lengthSync());
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: type.startsWith('image/') && file != null
                ? ClipRRect(borderRadius: BorderRadius.circular(4), child: assetImage(src, fit: BoxFit.cover))
                : Icon(_icon(name, type), size: 28, color: context.cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  file == null ? 'Không có file này trên máy (thiếu khi chia sẻ?)' : formatSize(size!),
                  style: context.tt.bodySmall?.copyWith(color: file == null ? context.cs.error : context.cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (file != null && _desktop) IconButton(tooltip: 'Mở bằng app trên máy', icon: const Icon(Icons.open_in_new, size: 20), onPressed: () => _open(context, file, name)),
          if (file != null)
            IconButton(
              tooltip: _desktop ? 'Lưu về máy' : 'Mở / chia sẻ bằng app khác',
              icon: Icon(_desktop ? Icons.download_outlined : Icons.share_outlined, size: 20),
              onPressed: () async {
                final bytes = await file.readAsBytes();
                if (context.mounted) await saveBytesFile(context, name, bytes);
              },
            ),
          if (!ro)
            IconButton(
              tooltip: 'Gỡ file khỏi khối',
              icon: Icon(Icons.close, size: 20, color: context.cs.error),
              onPressed: () async {
                if (!await confirmBox(context, 'Gỡ file?', 'Gỡ "$name" khỏi trang?', ok: 'Gỡ', danger: true)) return;
                _files(block).remove(f);
                app.changed();
              },
            ),
        ],
      ),
    );
  }
}
