// Các khối trong trang: tiêu đề, văn bản, ảnh, video, code C++, mô phỏng, bài tập.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';

import '../app_state.dart';
import '../core/scratch.dart';
import '../core/scratch_templates.dart';
import '../core/storage.dart';
import '../core/templates.dart';
import '../core/vcs.dart';
import 'code_editor.dart';
import 'extras.dart' show pickSnippet;
import 'media.dart';
import 'problem.dart';
import 'scratch_editor.dart';
import 'sim_player.dart';
import 'theme.dart';
import 'whiteboard.dart';
import 'widgets.dart';

const blockTypes = [
  ('heading', 'Tiêu đề', Icons.title),
  ('markdown', 'Văn bản', Icons.notes),
  ('image', 'Ảnh', Icons.image_outlined),
  ('video', 'Video', Icons.smart_display_outlined),
  ('code', 'Code C++', Icons.code),
  ('sim', 'Mô phỏng', Icons.animation),
  ('board', 'Bảng trắng', Icons.draw_outlined),
  ('problem', 'Bài tập', Icons.assignment_outlined),
];

Json newBlock(String kind) {
  final id = newId(12);
  final Json b = switch (kind) {
    'heading' => {'id': id, 'type': 'heading', 'level': 2, 'text': ''},
    'markdown' => {'id': id, 'type': 'markdown', 'text': ''},
    'image' => {'id': id, 'type': 'image', 'src': '', 'caption': '', 'width': 'full'},
    'video' => {'id': id, 'type': 'video', 'title': '', 'url': '', 'timestamps': ''},
    'board' => {'id': id, 'type': 'board', 'title': '', 'height': 560, 'bg': 'grid', 'strokes': <dynamic>[]},
    'code' => {'id': id, 'type': 'code', 'title': '', 'code': cppTemplate, 'stdin': ''},
    'sim' => {'id': id, 'type': 'sim', 'mode': 'blocks', 'title': blockTemplates.first.name, 'scratch': blockTemplates.first.program(), 'code': generateJs(blockTemplates.first.program()), 'input': blockTemplates.first.input},
    _ => {'id': id, 'type': 'problem', ...newProblem()},
  };
  return deepClone(b) as Json;
}

Future<String?> pickAsset(BuildContext context, FileType type) async {
  final r = await FilePicker.platform.pickFiles(type: type, withData: true);
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  Uint8List? bytes = f.bytes;
  if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
  if (bytes == null) return null;
  if (bytes.length > 200 * 1024 * 1024 && context.mounted) {
    if (!await confirmBox(context, 'File lớn', 'File ${(bytes.length / 1048576).round()} MB sẽ làm file chia sẻ rất nặng. Vẫn thêm?', ok: 'Thêm')) return null;
  }
  final ext = (f.extension ?? '').toLowerCase();
  final mime = type == FileType.image ? 'image/${ext == 'jpg' ? 'jpeg' : ext}' : 'video/$ext';
  return Storage.I.addAsset(bytes, type: mime, name: f.name);
}

/// Khung bao một khối: nút tuỳ chọn (sửa, di chuyển, xoá) + nội dung.
class BlockFrame extends StatelessWidget {
  final Json page, block;
  final GlobalKey anchorKey;
  const BlockFrame({super.key, required this.page, required this.block, required this.anchorKey});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final ro = app.readOnly;
    final type = block['type'] as String;
    final editing = !ro && app.editing.contains(block['id']);
    final framed = const ['video', 'code', 'sim', 'problem', 'board'].contains(type);
    final blocks = page['blocks'] as List;

    void move(int d) {
      final i = blocks.indexOf(block);
      final j = i + d;
      if (j < 0 || j >= blocks.length) return;
      blocks[i] = blocks[j];
      blocks[j] = block;
      app.changed();
    }

    void toggleEdit() {
      editing ? app.editing.remove(block['id']) : app.editing.add(block['id'] as String);
      app.changed();
    }

    final menu = ro
        ? null
        : PopupMenuButton<String>(
            tooltip: 'Tuỳ chọn khối',
            icon: Icon(Icons.more_vert, size: 18, color: context.cs.onSurfaceVariant),
            padding: EdgeInsets.zero,
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  toggleEdit();
                case 'h1' || 'h2' || 'h3':
                  block['level'] = int.parse(v.substring(1));
                  app.changed();
                case 'rename':
                  final t = await promptBox(context, 'Tên bảng trắng', 'Tên', value: '${block['title'] ?? ''}');
                  if (t == null) return;
                  block['title'] = t.trim();
                  app.changed();
                case 'up':
                  move(-1);
                case 'down':
                  move(1);
                case 'dup':
                  blocks.insert(blocks.indexOf(block) + 1, {...deepClone(block) as Json, 'id': newId(12)});
                  app.changed();
                case 'del':
                  final empty = '${block['text'] ?? ''}${block['url'] ?? ''}${block['title'] ?? ''}${block['src'] ?? ''}'.isEmpty;
                  if (!empty && !await confirmBox(context, 'Xoá khối?', 'Xoá ${blockName(block)}?', ok: 'Xoá', danger: true)) return;
                  blocks.remove(block);
                  app.editing.remove(block['id']);
                  app.changed();
              }
            },
            itemBuilder: (_) => [
              if (type != 'heading' && type != 'code' && type != 'board') PopupMenuItem(value: 'edit', child: Text(editing ? 'Xong' : 'Sửa')),
              if (type == 'board') const PopupMenuItem(value: 'rename', child: Text('Đặt tên bảng')),
              if (type == 'heading') ...[
                const PopupMenuItem(value: 'h1', child: Text('Tiêu đề lớn (H1)')),
                const PopupMenuItem(value: 'h2', child: Text('Tiêu đề vừa (H2)')),
                const PopupMenuItem(value: 'h3', child: Text('Tiêu đề nhỏ (H3)')),
              ],
              const PopupMenuItem(value: 'up', child: Text('Lên trên')),
              const PopupMenuItem(value: 'down', child: Text('Xuống dưới')),
              const PopupMenuItem(value: 'dup', child: Text('Nhân bản')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'del', child: Text('Xoá khối', style: TextStyle(color: context.cs.error))),
            ],
          );

    final body = switch (type) {
      'heading' => HeadingBlock(key: ValueKey('h${block['id']}'), block: block, ro: ro),
      'markdown' => MarkdownBlock(key: ValueKey('m${block['id']}'), block: block, editing: editing, onEdit: ro ? null : toggleEdit),
      'image' => ImageBlock(key: ValueKey('i${block['id']}'), block: block, editing: editing),
      'video' => VideoBlock(key: ValueKey('v${block['id']}'), block: block, editing: editing),
      'code' => CodeBlock(key: ValueKey('c${block['id']}'), block: block, ro: ro),
      'board' => WhiteboardBlock(key: ValueKey('w${block['id']}'), block: block, ro: ro),
      'sim' => SimBlock(key: ValueKey('s${block['id']}'), block: block, editing: editing),
      'problem' => editing ? ProblemEditor(key: ValueKey('pe${block['id']}'), block: block) : ProblemView(key: ValueKey('pv${block['id']}'), block: block),
      _ => Text('Loại khối chưa hỗ trợ: $type'),
    };

    return Container(
      key: anchorKey,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: framed || editing
          ? BoxDecoration(border: Border.all(color: editing ? context.cs.primary : context.cs.outlineVariant), borderRadius: BorderRadius.circular(4))
          : null,
      padding: framed || editing ? const EdgeInsets.fromLTRB(14, 6, 6, 12) : const EdgeInsets.only(right: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Padding(padding: EdgeInsets.only(top: framed || editing ? 6 : 0), child: body)),
        if (menu != null) SizedBox(width: 32, child: menu),
      ]),
    );
  }
}

class HeadingBlock extends StatelessWidget {
  final Json block;
  final bool ro;
  const HeadingBlock({super.key, required this.block, required this.ro});

  @override
  Widget build(BuildContext context) {
    final lvl = ((block['level'] ?? 1) as num).toInt().clamp(1, 3);
    final style = (lvl == 1 ? context.tt.headlineSmall : lvl == 2 ? context.tt.titleLarge : context.tt.titleMedium)?.copyWith(fontWeight: FontWeight.w700);
    if (ro) return Padding(padding: const EdgeInsets.only(top: 10), child: Text('${block['text'] ?? ''}', style: style));
    return Padding(
      padding: EdgeInsets.only(top: lvl == 1 ? 14 : 8),
      child: TextFormField(
        initialValue: (block['text'] ?? '') as String,
        style: style,
        decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, hintText: lvl == 1 ? 'Tiêu đề' : 'Tiêu đề mục', isDense: true, contentPadding: EdgeInsets.zero),
        onChanged: (v) {
          block['text'] = v;
          context.read<AppState>().edited();
        },
        onFieldSubmitted: (_) => context.read<AppState>().changed(),
        onTapOutside: (_) => context.read<AppState>().changed(),
      ),
    );
  }
}

class MarkdownBlock extends StatelessWidget {
  final Json block;
  final bool editing;
  final VoidCallback? onEdit;
  const MarkdownBlock({super.key, required this.block, required this.editing, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final text = (block['text'] ?? '') as String;
    if (editing) return _MarkdownEditor(block: block);
    if (text.isEmpty) {
      return GestureDetector(
        onDoubleTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(onEdit == null ? '' : 'Văn bản trống — nhấp đúp để viết.', style: TextStyle(color: context.cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
        ),
      );
    }
    return GestureDetector(onDoubleTap: onEdit, child: MarkdownView(text));
  }
}

class _MarkdownEditor extends StatefulWidget {
  final Json block;
  const _MarkdownEditor({required this.block});
  @override
  State<_MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<_MarkdownEditor> {
  late final TextEditingController ctl = TextEditingController(text: (widget.block['text'] ?? '') as String);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _insert(String s) {
    final sel = ctl.selection;
    final start = sel.isValid ? sel.start : ctl.text.length;
    final end = sel.isValid ? sel.end : ctl.text.length;
    ctl.text = ctl.text.replaceRange(start, end, s);
    ctl.selection = TextSelection.collapsed(offset: start + s.length);
    _save();
  }

  void _wrap(String pre, [String? post]) {
    final sel = ctl.selection;
    if (!sel.isValid) return;
    final t = sel.textInside(ctl.text);
    final rep = '$pre${t.isEmpty ? 'chữ' : t}${post ?? pre}';
    ctl.text = ctl.text.replaceRange(sel.start, sel.end, rep);
    ctl.selection = TextSelection(baseOffset: sel.start, extentOffset: sel.start + rep.length);
    _save();
  }

  void _save() {
    widget.block['text'] = ctl.text;
    context.read<AppState>().edited();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 2, children: [
          IconButton(tooltip: 'Đậm', icon: const Icon(Icons.format_bold, size: 18), onPressed: () => _wrap('**')),
          IconButton(tooltip: 'Nghiêng', icon: const Icon(Icons.format_italic, size: 18), onPressed: () => _wrap('*')),
          IconButton(tooltip: 'Code', icon: const Icon(Icons.code, size: 18), onPressed: () => _wrap('`')),
          IconButton(tooltip: 'Tiêu đề', icon: const Icon(Icons.title, size: 18), onPressed: () => _insert('\n## ')),
          IconButton(tooltip: 'Danh sách', icon: const Icon(Icons.format_list_bulleted, size: 18), onPressed: () => _insert('\n- ')),
          TextButton.icon(
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Chèn ảnh'),
            onPressed: () async {
              final ref = await pickAsset(context, FileType.image);
              if (ref != null) _insert('\n![]($ref)\n');
            },
          ),
        ]),
        TextField(
          controller: ctl,
          autofocus: true,
          minLines: 5,
          maxLines: null,
          style: TextStyle(fontFamily: monoFont, fontSize: 14, height: 1.5),
          decoration: const InputDecoration(hintText: 'Viết ghi chú (Markdown): # Tiêu đề, **đậm**, *nghiêng*, `code`, - danh sách…'),
          onChanged: (_) => _save(),
        ),
      ]);
}

class ImageBlock extends StatelessWidget {
  final Json block;
  final bool editing;
  const ImageBlock({super.key, required this.block, required this.editing});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final src = (block['src'] ?? '') as String;
    final width = (block['width'] ?? 'full') as String;
    final factor = {'large': .75, 'medium': .5, 'small': .33}[width] ?? 1.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (src.isEmpty)
        Container(height: 100, alignment: Alignment.center, color: context.cs.surfaceContainer, child: const Text('Chưa có ảnh.'))
      else
        LayoutBuilder(
          builder: (c, box) => Center(
            child: GestureDetector(
              onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: assetImage(src)))),
              child: SizedBox(width: box.maxWidth * factor, child: assetImage(src, width: box.maxWidth * factor)),
            ),
          ),
        ),
      if ((block['caption'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('${block['caption']}', textAlign: TextAlign.center, style: context.tt.bodySmall)),
      if (editing) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(src.isEmpty ? 'Chọn ảnh từ máy' : 'Đổi ảnh'),
            onPressed: () async {
              final ref = await pickAsset(context, FileType.image);
              if (ref == null) return;
              block['src'] = ref;
              app.changed();
            },
          ),
          SizedBox(
            width: 280,
            child: TextFormField(
              initialValue: src.startsWith('asset:') ? '' : src,
              decoration: const InputDecoration(labelText: 'hoặc dán link ảnh'),
              onFieldSubmitted: (v) {
                block['src'] = v.trim();
                app.changed();
              },
            ),
          ),
          DropdownButton<String>(
            value: width,
            items: const [('full', 'Toàn bộ'), ('large', 'Lớn'), ('medium', 'Vừa'), ('small', 'Nhỏ')].map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
            onChanged: (v) {
              block['width'] = v;
              app.changed();
            },
          ),
        ]),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: (block['caption'] ?? '') as String,
          decoration: const InputDecoration(labelText: 'Chú thích'),
          onChanged: (v) {
            block['caption'] = v;
            app.edited();
          },
        ),
      ],
    ]);
  }
}

class VideoBlock extends StatelessWidget {
  final Json block;
  final bool editing;
  const VideoBlock({super.key, required this.block, required this.editing});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final url = (block['url'] ?? '') as String;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _kind(context, Icons.smart_display_outlined, (block['title'] ?? '').toString().isEmpty ? 'Video' : '${block['title']}'),
      if (editing) ...[
        TextFormField(
          initialValue: url.startsWith('asset:') ? '' : url,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Link video hoặc mã nhúng',
            helperText: 'YouTube (mọi dạng link, cả mã <iframe> nhúng), Google Drive, file .mp4 / .m3u8. Trang khác mở bằng trình duyệt.',
            hintText: url.startsWith('asset:') ? 'Đang dùng video trên máy' : 'https://www.youtube.com/watch?v=…  hoặc  <iframe src=…>',
          ),
          onFieldSubmitted: (v) {
            block['url'] = v.trim();
            app.changed();
          },
          onChanged: (v) {
            block['url'] = v.trim();
            app.edited();
          },
        ),
        const SizedBox(height: 6),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.video_file_outlined, size: 18),
            label: const Text('Chọn file video từ máy'),
            onPressed: () async {
              final ref = await pickAsset(context, FileType.video);
              if (ref == null) return;
              block['url'] = ref;
              app.changed();
            },
          ),
          const SizedBox(width: 8),
          if (url.startsWith('asset:')) Text('Đang dùng video lưu trên máy.', style: context.tt.bodySmall),
        ]),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: (block['title'] ?? '') as String,
          decoration: const InputDecoration(labelText: 'Tiêu đề / nguồn'),
          onChanged: (v) {
            block['title'] = v;
            app.edited();
          },
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: (block['timestamps'] ?? '') as String,
          minLines: 2,
          maxLines: 8,
          style: TextStyle(fontFamily: monoFont, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Mốc thời gian (mỗi dòng: mm:ss nội dung)', hintText: '00:00 Giới thiệu\n03:15 Ý tưởng'),
          onChanged: (v) {
            block['timestamps'] = v;
            app.edited();
          },
        ),
        const SizedBox(height: 8),
      ],
      VideoView(url: url, timestamps: (block['timestamps'] ?? '') as String),
    ]);
  }
}

Widget _kind(BuildContext context, IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: context.tt.labelLarge?.copyWith(color: context.cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
      ]),
    );

/// Gọi từ khối code để mở trong IDE (do shell đăng ký).
void Function(String name, String code)? openInIde;

class CodeBlock extends StatefulWidget {
  final Json block;
  final bool ro;
  const CodeBlock({super.key, required this.block, required this.ro});
  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  late final CodeLineEditingController ctl = CodeLineEditingController.fromText((widget.block['code'] ?? '') as String);
  late final TextEditingController stdin = TextEditingController(text: (widget.block['stdin'] ?? '') as String);
  String? output;
  bool outputErr = false;
  String header = '';
  bool running = false;

  @override
  void initState() {
    super.initState();
    ctl.addListener(() {
      if (widget.block['code'] != ctl.text) {
        widget.block['code'] = ctl.text;
        context.read<AppState>().edited();
      }
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    stdin.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final app = context.read<AppState>();
    setState(() {
      running = true;
      output = null;
    });
    try {
      final be = await app.backend();
      final c = await be.compile(ctl.text);
      if (!c.ok) {
        setState(() {
          header = 'Lỗi biên dịch · ${be.name}';
          output = c.error;
          outputErr = true;
        });
      } else {
        final r = await be.run(c.id, stdin.text, 5000);
        be.dispose(c.id);
        setState(() {
          if (r.compileError != null) {
            header = 'Lỗi biên dịch · ${be.name}';
            output = r.compileError;
            outputErr = true;
          } else {
            header = '${r.timedOut ? 'Quá thời gian (5 giây)' : 'Kết quả · mã thoát ${r.exitCode} · ${r.timeMs} ms'} · ${be.name}';
            output = r.stdout + (r.stderr.isNotEmpty ? '\n[stderr]\n${r.stderr}' : '');
            outputErr = r.exitCode != 0 || r.timedOut;
          }
        });
      }
    } catch (e) {
      setState(() {
        header = 'Không chạy được';
        output = '$e\n${Platform.isAndroid ? 'Cần Internet để biên dịch online (godbolt.org).' : 'Kiểm tra g++ trong Cài đặt.'}';
        outputErr = true;
      });
    }
    setState(() => running = false);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final lines = '\n'.allMatches(ctl.text).length + 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.code, size: 16, color: context.cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: widget.ro
              ? Text('${b['title'] ?? ''}', style: TextStyle(fontFamily: monoFont))
              : TextFormField(
                  initialValue: (b['title'] ?? '') as String,
                  style: TextStyle(fontFamily: monoFont, fontSize: 13),
                  decoration: const InputDecoration(hintText: 'tên file, VD: quick_sort.cpp', border: InputBorder.none, enabledBorder: InputBorder.none, isDense: true),
                  onChanged: (v) {
                    b['title'] = v;
                    context.read<AppState>().edited();
                  },
                ),
        ),
      ]),
      const SizedBox(height: 4),
      Container(
        height: (lines * 20.0 + 24).clamp(80, 460),
        decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
        child: CodeArea(controller: ctl, readOnly: widget.ro),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        initiallyExpanded: (b['stdin'] ?? '').toString().isNotEmpty,
        title: Text('stdin', style: context.tt.bodySmall),
        children: [
          TextField(
            controller: stdin,
            readOnly: widget.ro,
            minLines: 2,
            maxLines: 8,
            style: TextStyle(fontFamily: monoFont, fontSize: 13),
            onChanged: (v) {
              b['stdin'] = v;
              context.read<AppState>().edited();
            },
          ),
        ],
      ),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(onPressed: running ? null : _run, icon: const Icon(Icons.play_arrow, size: 18), label: Text(running ? 'Đang chạy…' : 'Chạy')),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: ctl.text));
            toast(context, 'Đã sao chép code');
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Sao chép'),
        ),
        TextButton.icon(
          onPressed: () => saveTextFile(context, '${slugify(((b['title'] ?? '') as String).replaceAll('.cpp', '')).replaceAll('file', 'main')}.cpp', ctl.text),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Lưu .cpp'),
        ),
        if (!widget.ro)
          TextButton.icon(
            onPressed: () async {
              final code = await pickSnippet(context);
              if (code != null) ctl.replaceSelection(code);
            },
            icon: const Icon(Icons.library_books_outlined, size: 16),
            label: const Text('Code mẫu'),
          ),
        TextButton.icon(
          onPressed: () => openInIde?.call(((b['title'] ?? '') as String).isEmpty ? 'main.cpp' : b['title'] as String, ctl.text),
          icon: const Icon(Icons.terminal, size: 16),
          label: const Text('Mở trong IDE'),
        ),
      ]),
      if (output != null) ...[
        const SizedBox(height: 6),
        Text(header, style: context.tt.labelMedium?.copyWith(color: outputErr ? context.cs.error : (context.isDark ? okColorDark : okColor), fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        MonoBox(output!),
      ],
    ]);
  }
}

/// Chương trình khối của mô phỏng (tạo mới, hoặc chuyển từ khối Blockly của bản cũ).
Json simProgram(Json b) {
  final p = b['scratch'];
  if (p is Map) return p.cast<String, dynamic>();
  final legacy = b['blocks'];
  final Json prog;
  if (legacy is Map) {
    try {
      prog = fromBlockly(legacy);
    } catch (_) {
      return b['scratch'] = emptyProgram();
    }
  } else {
    prog = emptyProgram();
  }
  b['scratch'] = prog;
  return prog;
}

class SimBlock extends StatefulWidget {
  final Json block;
  final bool editing;
  const SimBlock({super.key, required this.block, required this.editing});
  @override
  State<SimBlock> createState() => _SimBlockState();
}

class _SimBlockState extends State<SimBlock> {
  late CodeLineEditingController ctl = CodeLineEditingController.fromText((widget.block['code'] ?? '') as String);
  late final TextEditingController input = TextEditingController(text: (widget.block['input'] ?? '') as String);
  int runKey = 0;
  bool showBlocks = false;
  double editorHeight = 460;

  Json get b => widget.block;
  bool get blocksMode => b['mode'] == 'blocks';

  @override
  void initState() {
    super.initState();
    if (blocksMode) {
      simProgram(b);
      final code = generateJs(simProgram(b));
      if (b['code'] != code) b['code'] = code;
      ctl.text = code;
    }
    ctl.addListener(_onCode);
  }

  void _onCode() {
    if (!blocksMode && b['code'] != ctl.text) {
      b['code'] = ctl.text;
      context.read<AppState>().edited();
    }
  }

  void _onBlocks() {
    final code = generateJs(simProgram(b));
    b['code'] = code;
    ctl.removeListener(_onCode);
    ctl.text = code;
    ctl.addListener(_onCode);
    context.read<AppState>().edited();
  }

  @override
  void dispose() {
    ctl.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> _setMode(String mode) async {
    if (mode == b['mode']) return;
    if (mode == 'code') {
      if (!await confirmBox(context, 'Chuyển sang viết code?', 'Code JavaScript được sinh từ các khối sẽ được giữ lại để bạn sửa tiếp. Sửa code sẽ không cập nhật ngược lại các khối.', ok: 'Chuyển')) return;
      b['code'] = generateJs(simProgram(b));
    } else if (b['scratch'] == null && b['blocks'] == null && ctl.text.trim().isNotEmpty) {
      if (!await confirmBox(context, 'Chuyển sang kéo thả?', 'Code hiện tại không chuyển được thành khối. Bạn sẽ bắt đầu với chương trình khối trống (code cũ vẫn lưu, có thể quay lại).', ok: 'Chuyển')) return;
    }
    setState(() {
      b['mode'] = mode;
      if (mode == 'blocks') {
        _onBlocks();
      } else {
        ctl.text = (b['code'] ?? '') as String;
      }
    });
    if (mounted) context.read<AppState>().edited();
  }

  Future<void> _template(String id) async {
    if (blocksMode) {
      final t = blockTemplates.firstWhere((x) => x.id == id);
      final prog = simProgram(b);
      if (((prog['main'] as List).isNotEmpty || (prog['funcs'] as List).isNotEmpty) &&
          !await confirmBox(context, 'Thay chương trình?', 'Các khối hiện tại sẽ bị thay bằng mẫu.', ok: 'Thay')) {
        return;
      }
      setState(() {
        b['scratch'] = t.program();
        input.text = t.input;
        b['input'] = t.input;
        if ((b['title'] ?? '').toString().isEmpty) b['title'] = t.name;
        _onBlocks();
        runKey++;
      });
      return;
    }
    final t = simTemplates.firstWhere((x) => x.id == id);
    if (ctl.text.trim().isNotEmpty && !await confirmBox(context, 'Thay code?', 'Code mô phỏng hiện tại sẽ bị thay bằng mẫu.', ok: 'Thay')) return;
    setState(() {
      ctl.text = t.code;
      input.text = t.input;
      b['input'] = t.input;
      if ((b['title'] ?? '').toString().isEmpty) b['title'] = t.name;
      runKey++;
    });
  }

  Future<void> _fullscreen() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (c) => Scaffold(
        appBar: AppBar(
          title: Text((b['title'] ?? '').toString().isEmpty ? 'Ghép khối mô phỏng' : '${b['title']}'),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(c);
                setState(() => runKey++);
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Xong & chạy thử'),
            ),
          ],
        ),
        body: ScratchEditor(program: simProgram(b), onChanged: _onBlocks),
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ro = context.read<AppState>().readOnly;
    final editing = widget.editing && !ro;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _kind(context, blocksMode ? Icons.extension_outlined : Icons.animation, (b['title'] ?? '').toString().isEmpty ? 'Mô phỏng' : '${b['title']}'),
      if (editing) ...[
        TextFormField(
          initialValue: (b['title'] ?? '') as String,
          decoration: const InputDecoration(labelText: 'Tiêu đề'),
          onChanged: (v) {
            b['title'] = v;
            context.read<AppState>().edited();
          },
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'blocks', icon: Icon(Icons.extension_outlined, size: 16), label: Text('Kéo thả')),
              ButtonSegment(value: 'code', icon: Icon(Icons.code, size: 16), label: Text('Code JS')),
            ],
            selected: {blocksMode ? 'blocks' : 'code'},
            onSelectionChanged: (v) => _setMode(v.first),
          ),
          DropdownButton<String>(
            hint: const Text('Chèn mẫu…'),
            items: blocksMode
                ? [for (final t in blockTemplates) DropdownMenuItem(value: t.id, child: Text(t.name))]
                : [for (final t in simTemplates) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (id) => id == null ? null : _template(id),
          ),
          if (blocksMode)
            TextButton.icon(icon: const Icon(Icons.fullscreen, size: 18), label: const Text('Toàn màn hình'), onPressed: _fullscreen)
          else
            TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('Các hàm viz'),
              onPressed: () => showPanel<void>(context, title: 'Các hàm mô phỏng (viz)', builder: (_, _) => MarkdownView(simApiDoc), width: 900),
            ),
          if (blocksMode)
            TextButton.icon(
              icon: const Icon(Icons.data_object, size: 18),
              label: const Text('Xem code sinh ra'),
              onPressed: () => showPanel<void>(context, title: 'Code JavaScript sinh từ khối', builder: (_, _) => MonoBox(ctl.text, maxHeight: 600), width: 900),
            ),
        ]),
        const SizedBox(height: 6),
        if (blocksMode) ...[
          Container(
            height: editorHeight,
            decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
            clipBehavior: Clip.antiAlias,
            child: ScratchEditor(program: simProgram(b), onChanged: _onBlocks),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            child: GestureDetector(
              onVerticalDragUpdate: (d) => setState(() => editorHeight = (editorHeight + d.delta.dy).clamp(260.0, 1400.0)),
              child: Container(height: 8, alignment: Alignment.center, child: Container(width: 40, height: 3, color: context.cs.outlineVariant)),
            ),
          ),
          Text('Kéo khối từ bảng bên trái vào chương trình (bấm vào khối để thêm vào cuối). Kéo khối giá trị (bo tròn / lục giác) vào các ô. Kéo khối về bảng để xoá; chuột phải để nhân bản.',
              style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        ] else
          Container(
            height: 320,
            decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
            child: CodeArea(controller: ctl, lang: 'js'),
          ),
        const SizedBox(height: 6),
      ] else if (blocksMode) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => showBlocks = !showBlocks),
            icon: Icon(showBlocks ? Icons.expand_less : Icons.extension_outlined, size: 18),
            label: Text(showBlocks ? 'Ẩn các khối' : 'Xem các khối kéo thả'),
          ),
        ),
        if (showBlocks)
          Container(
            constraints: const BoxConstraints(maxHeight: 420),
            decoration: BoxDecoration(border: Border.all(color: context.cs.outlineVariant), borderRadius: BorderRadius.circular(4)),
            child: ScratchEditor(program: simProgram(b), readOnly: true, onChanged: () {}),
          ),
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: input,
            readOnly: ro,
            minLines: 1,
            maxLines: 6,
            style: TextStyle(fontFamily: monoFont, fontSize: 13),
            decoration: const InputDecoration(labelText: 'Dữ liệu vào'),
            onChanged: (v) {
              b['input'] = v;
              context.read<AppState>().edited();
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(onPressed: () => setState(() => runKey++), icon: const Icon(Icons.play_arrow, size: 18), label: Text(widget.editing ? 'Chạy thử' : 'Chạy lại')),
      ]),
      const SizedBox(height: 8),
      SimPlayer(code: ctl.text, input: input.text, runKey: runKey),
    ]);
  }
}
