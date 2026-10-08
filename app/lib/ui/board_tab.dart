// Tab "Bảng trắng": nhiều bảng vẽ riêng (không cần mở notebook), có thể đưa một bảng vào trang sổ tay.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/storage.dart';
import '../core/vcs.dart';
import 'theme.dart';
import 'whiteboard.dart';
import 'widgets.dart';

class BoardTab extends StatefulWidget {
  const BoardTab({super.key});
  @override
  State<BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<BoardTab> {
  late final Json data = Storage.I.readKv('boards', {'items': <dynamic>[], 'active': 0});
  Timer? _timer;

  List get items => (data['items'] ??= <dynamic>[]) as List;
  int get active => ((data['active'] ?? 0) as int).clamp(0, items.isEmpty ? 0 : items.length - 1);

  @override
  void initState() {
    super.initState();
    if (items.isEmpty) _add(save: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    Storage.I.writeKv('boards', data);
    super.dispose();
  }

  void _save() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () => Storage.I.writeKv('boards', data));
  }

  void _add({bool save = true}) {
    items.add({'id': newId(12), 'type': 'board', 'title': 'Bảng ${items.length + 1}', 'height': 640, 'bg': 'grid', 'strokes': <dynamic>[]});
    data['active'] = items.length - 1;
    if (save) {
      setState(() {});
      _save();
    }
  }

  Future<void> _rename(Json b) async {
    final t = await promptBox(context, 'Đổi tên bảng', 'Tên', value: '${b['title'] ?? ''}');
    if (t == null || t.trim().isEmpty) return;
    setState(() => b['title'] = t.trim());
    _save();
  }

  Future<void> _delete(int i) async {
    final b = items[i] as Map;
    if (((b['strokes'] ?? const []) as List).isNotEmpty && !await confirmBox(context, 'Xoá bảng?', 'Xoá "${b['title']}" và mọi nét vẽ trên đó?', ok: 'Xoá', danger: true)) return;
    setState(() {
      items.removeAt(i);
      if (items.isEmpty) _add(save: false);
      data['active'] = active;
    });
    _save();
  }

  void _toNotebook(Json b) {
    final app = context.read<AppState>();
    if (app.repo == null || app.readOnly || app.page == null) {
      toast(context, 'Hãy mở một notebook (ở tab Sổ tay) trước.', error: true);
      return;
    }
    final copy = deepClone(b) as Json..['id'] = newId(12);
    (app.page!['blocks'] as List).add(copy);
    app.changed();
    toast(context, 'Đã thêm bảng vào cuối trang "${app.page!['title']}"');
  }

  @override
  Widget build(BuildContext context) {
    final cur = items[active] as Json;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 40,
        decoration: BoxDecoration(color: context.cs.surfaceContainer, border: Border(bottom: BorderSide(color: context.cs.outlineVariant))),
        child: Row(children: [
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (var i = 0; i < items.length; i++)
                InkWell(
                  onTap: () => setState(() => data['active'] = i),
                  onDoubleTap: () => _rename(items[i] as Json),
                  child: Container(
                    padding: const EdgeInsets.only(left: 12, right: 2),
                    decoration: BoxDecoration(
                      color: i == active ? context.cs.surface : null,
                      border: Border(top: BorderSide(color: i == active ? context.cs.primary : Colors.transparent, width: 2), right: BorderSide(color: context.cs.outlineVariant)),
                    ),
                    child: Row(children: [
                      Icon(Icons.draw_outlined, size: 15, color: context.cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text('${(items[i] as Map)['title']}', style: TextStyle(fontSize: 13, fontWeight: i == active ? FontWeight.w600 : null)),
                      IconButton(visualDensity: VisualDensity.compact, iconSize: 15, tooltip: 'Xoá bảng', onPressed: () => _delete(i), icon: const Icon(Icons.close)),
                    ]),
                  ),
                ),
              IconButton(tooltip: 'Bảng mới', iconSize: 18, onPressed: _add, icon: const Icon(Icons.add)),
            ]),
          ),
          IconButton(tooltip: 'Đổi tên', iconSize: 18, onPressed: () => _rename(cur), icon: const Icon(Icons.edit_outlined)),
          TextButton.icon(onPressed: () => _toNotebook(cur), icon: const Icon(Icons.post_add, size: 18), label: const Text('Đưa vào sổ tay')),
          const SizedBox(width: 6),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Whiteboard(key: ObjectKey(cur), block: cur, ro: false, fit: true, onChanged: _save),
        ),
      ),
    ]);
  }
}
