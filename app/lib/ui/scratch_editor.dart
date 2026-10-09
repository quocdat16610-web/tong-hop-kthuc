// Trình ghép khối kéo thả kiểu Scratch: bảng khối theo nhóm màu, kéo khối vào chương trình,
// thả khối giá trị vào ô, khối lồng (lặp / nếu), biến và hàm (có tham số, đệ quy).
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/scratch.dart';
import '../core/vcs.dart' show Json, deepClone;
import 'theme.dart';
import 'widgets.dart';

final bool _touch = Platform.isAndroid || Platform.isIOS;

/// Khối đang được kéo: lấy ra (tạo mới từ bảng khối, hoặc gỡ khỏi chỗ cũ trong chương trình).
class _Drag {
  final Json node;
  final bool fresh;
  final VoidCallback? detach;
  final List? fromList; // để không thả khối vào chính nó
  _Drag(this.node, {this.fresh = false, this.detach, this.fromList});
  BlockSpec? get spec => specs[node['op']];
  bool get isValue => spec?.isValue ?? false;
}

bool _contains(dynamic tree, Object target) {
  if (identical(tree, target)) return true;
  if (tree is List) return tree.any((x) => _contains(x, target));
  if (tree is Map) {
    final a = tree['a'];
    if (a is Map && a.values.any((x) => _contains(x, target))) return true;
    return _contains(tree['do'], target) || _contains(tree['else'], target);
  }
  return false;
}

Color _darker(Color c, [double f = .22]) => Color.lerp(c, Colors.black, f)!;

// ---------- Hình dạng khối ----------
class _PuzzleBorder extends ShapeBorder {
  final bool notchTop, tabBottom, roundTop;
  final Color? stroke;
  const _PuzzleBorder({this.notchTop = true, this.tabBottom = true, this.roundTop = false, this.stroke});
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect);
  @override
  Path getOuterPath(Rect r, {TextDirection? textDirection}) {
    final l = r.left, t = r.top, rt = r.right, b = r.bottom;
    final p = Path();
    if (roundTop) {
      p.moveTo(l, t + 12);
      p.quadraticBezierTo(l + 40, t - 10, l + 90, t + 4);
      p.lineTo(rt - 4, t + 4);
      p.quadraticBezierTo(rt, t + 4, rt, t + 8);
    } else {
      p.moveTo(l, t + 4);
      p.quadraticBezierTo(l, t, l + 4, t);
      if (notchTop) {
        p.lineTo(l + 12, t);
        p.lineTo(l + 16, t + 4);
        p.lineTo(l + 28, t + 4);
        p.lineTo(l + 32, t);
      }
      p.lineTo(rt - 4, t);
      p.quadraticBezierTo(rt, t, rt, t + 4);
    }
    p.lineTo(rt, b - 4);
    p.quadraticBezierTo(rt, b, rt - 4, b);
    if (tabBottom) {
      p.lineTo(l + 32, b);
      p.lineTo(l + 28, b + 4);
      p.lineTo(l + 16, b + 4);
      p.lineTo(l + 12, b);
    }
    p.lineTo(l + 4, b);
    p.quadraticBezierTo(l, b, l, b - 4);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (stroke == null) return;
    canvas.drawPath(getOuterPath(rect), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = stroke!);
  }

  @override
  ShapeBorder scale(double t) => this;
}

// ---------- Trình soạn ----------
class ScratchEditor extends StatefulWidget {
  final Json program;
  final bool readOnly;
  final VoidCallback onChanged;
  const ScratchEditor({super.key, required this.program, required this.onChanged, this.readOnly = false});
  @override
  State<ScratchEditor> createState() => ScratchEditorState();
}

class ScratchEditorState extends State<ScratchEditor> {
  String cat = 'array';
  bool dragging = false;
  bool draggingExisting = false;
  final vScroll = ScrollController();

  Json get prog => widget.program;
  List get vars => (prog['vars'] ??= <dynamic>[]) as List;
  List<Map> get funcs => ((prog['funcs'] ??= <dynamic>[]) as List).cast<Map>();
  bool get ro => widget.readOnly;

  void setDragging(bool on) => setState(() {
        dragging = on;
        draggingExisting = on;
      });

  void changed() {
    collectVars(prog);
    setState(() {});
    widget.onChanged();
  }

  @override
  void dispose() {
    vScroll.dispose();
    super.dispose();
  }

  // ----- Biến & hàm -----
  Future<String?> newVariable() async {
    final name = (await promptBox(context, 'Biến mới', 'Tên biến (VD: i, dem, a)'))?.trim();
    if (name == null || name.isEmpty) return null;
    if (!vars.contains(name)) vars.add(name);
    changed();
    return name;
  }

  Future<void> renameVariable(String old) async {
    final name = (await promptBox(context, 'Đổi tên biến', 'Tên mới', value: old))?.trim();
    if (name == null || name.isEmpty || name == old) return;
    void walk(dynamic x) {
      if (x is List) {
        x.forEach(walk);
      } else if (x is Map) {
        final s = specs[x['op']];
        final a = x['a'];
        if (s != null && a is Map) {
          s.slots.forEach((k, slot) {
            if (slot.kind == SlotKind.varName && a[k] == old) a[k] = name;
          });
          a.values.forEach(walk);
        }
        walk(x['do']);
        walk(x['else']);
        walk(x['body']);
      }
    }

    walk(prog['main']);
    walk(prog['funcs']);
    vars[vars.indexOf(old)] = name;
    changed();
  }

  Future<void> editFunction([Map? fx]) async {
    final name = TextEditingController(text: '${fx?['name'] ?? 'ham'}');
    final params = TextEditingController(text: ((fx?['params'] ?? const []) as List).join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(fx == null ? 'Tạo hàm' : 'Sửa hàm'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Tên hàm (VD: dfs, quickSort)')),
            const SizedBox(height: 10),
            TextField(controller: params, decoration: const InputDecoration(labelText: 'Tham số, cách nhau bởi dấu cách (VD: u  hoặc  l r)')),
            const SizedBox(height: 8),
            const Text('Hàm có thể gọi chính nó (đệ quy). Tham số dùng như biến trong thân hàm.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lưu')),
        ],
      ),
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    final ps = params.text.split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).toList();
    if (fx == null) {
      if (funcs.any((f) => f['name'] == n)) {
        if (mounted) toast(context, 'Đã có hàm "$n"', error: true);
        return;
      }
      (prog['funcs'] as List).add({'name': n, 'params': ps, 'body': <dynamic>[]});
    } else {
      final old = fx['name'];
      fx['name'] = n;
      fx['params'] = ps;
      void walk(dynamic x) {
        if (x is List) {
          x.forEach(walk);
        } else if (x is Map) {
          if ((x['op'] == 'call' || x['op'] == 'call_value') && (x['a'] as Map?)?['FN'] == old) (x['a'] as Map)['FN'] = n;
          final a = x['a'];
          if (a is Map) a.values.forEach(walk);
          walk(x['do']);
          walk(x['else']);
          walk(x['body']);
        }
      }

      walk(prog['main']);
      walk(prog['funcs']);
    }
    cat = 'func';
    changed();
  }

  // ----- Bảng khối -----
  Widget _palette(double width) {
    final c = categoryOf(cat);
    final items = <Widget>[];
    void add(Json Function() make) {
      items.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: _paletteItem(make)));
    }

    if (cat == 'var') {
      items.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(onPressed: newVariable, child: const Text('Tạo biến'))));
      for (final v in vars) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            _paletteItem(() => newNode('var_get', a: {'VAR': '$v'})),
            const Spacer(),
            PopupMenuButton<String>(
              iconSize: 16,
              tooltip: 'Biến $v',
              onSelected: (x) {
                if (x == 'rename') renameVariable('$v');
                if (x == 'del') {
                  vars.remove(v);
                  changed();
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Đổi tên')), PopupMenuItem(value: 'del', child: Text('Xoá khỏi danh sách'))],
            ),
          ]),
        ));
      }
    }
    if (cat == 'func') {
      items.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(onPressed: editFunction, child: const Text('Tạo hàm'))));
      for (final f in funcs) {
        for (final p in ((f['params'] ?? const []) as List)) {
          add(() => newNode('var_get', a: {'VAR': '$p'}));
        }
      }
      for (final f in funcs) {
        add(() => newNode('call', a: {'FN': '${f['name']}'}));
        add(() => newNode('call_value', a: {'FN': '${f['name']}'}));
      }
      add(() => newNode('return'));
      add(() => newNode('return_void'));
    } else {
      for (final s in paletteOf(cat)) {
        add(() => newNode(s.op, a: vars.isNotEmpty && s.slots['VAR']?.kind == SlotKind.varName && !vars.contains(s.slots['VAR']!.dflt) ? {'VAR': '${vars.first}'} : null));
      }
    }

    final list = ListView(padding: const EdgeInsets.all(10), children: [
      Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: c.color)),
      const SizedBox(height: 8),
      ...items,
      if (cat != 'func' && cat != 'var' && items.isEmpty) const Text('Không có khối'),
    ]);
    final body = DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => !d.data.fresh,
      onAcceptWithDetails: (d) {
        d.data.detach?.call();
        changed();
      },
      builder: (ctx, cand, _) => Stack(children: [
        list,
        if (draggingExisting)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: (cand.isNotEmpty ? context.cs.error : context.cs.surface).withValues(alpha: cand.isNotEmpty ? .25 : .7),
                alignment: Alignment.center,
                child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.delete_outline, size: 40, color: context.cs.error), const Text('Thả vào đây để xoá')]),
              ),
            ),
          ),
      ]),
    );
    return SizedBox(
      width: width,
      child: Row(children: [
        Container(
          width: 64,
          color: context.cs.surfaceContainer,
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
            for (final k in categories)
              InkWell(
                onTap: () => setState(() => cat = k.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: cat == k.id ? context.cs.primaryContainer.withValues(alpha: .5) : null,
                  child: Column(children: [
                    Container(width: 18, height: 18, decoration: BoxDecoration(color: k.color, shape: BoxShape.circle, border: Border.all(color: _darker(k.color)))),
                    const SizedBox(height: 2),
                    Text(k.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, height: 1.1)),
                  ]),
                ),
              ),
          ]),
        ),
        Expanded(child: Container(color: context.cs.surfaceContainerLow, child: body)),
      ]),
    );
  }

  Widget _paletteItem(Json Function() make) {
    final sample = make();
    final view = IgnorePointer(child: BlockView(node: sample, ed: this, preview: true));
    final item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        (prog['main'] as List).add(make());
        changed();
        toast(context, 'Đã thêm vào cuối chương trình. Kéo khối để đặt đúng chỗ.');
      },
      child: Draggable<_Drag>(
        hitTestBehavior: HitTestBehavior.opaque,
        data: _Drag(sample, fresh: true),
        onDragStarted: () => setState(() => dragging = true),
        onDragEnd: (_) => setState(() => dragging = false),
        onDraggableCanceled: (_, _) => setState(() => dragging = false),
        onDragCompleted: () => setState(() => dragging = false),
        feedback: Material(type: MaterialType.transparency, child: Opacity(opacity: .85, child: view)),
        child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, child: view)),
      ),
    );
    final tip = specs[sample['op']]?.tip;
    return tip == null ? item : Tooltip(message: tip, waitDuration: const Duration(milliseconds: 600), child: item);
  }

  /// Nhận khối kéo tới: tạo bản sao khi lấy từ bảng khối, hoặc gỡ khỏi chỗ cũ.
  Json take(_Drag d) {
    if (d.fresh) {
      // Lấy từ bảng khối: dùng bản sao để mẫu trong bảng không bị đổi.
      return deepClone(d.node) as Json;
    }
    d.detach?.call();
    return d.node;
  }

  // ----- Vùng chương trình -----
  Widget _hat(String text, {List<Widget> actions = const [], Color? color}) {
    final c = color ?? categoryOf('event').color;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 6, 8),
      decoration: ShapeDecoration(color: c, shape: _PuzzleBorder(roundTop: true, stroke: _darker(c))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ...actions,
      ]),
    );
  }

  Widget _hatTarget(Widget hat, List list) {
    if (ro) return hat;
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => !d.data.isValue,
      onAcceptWithDetails: (d) {
        final fromSame = identical(d.data.fromList, list);
        final node = take(d.data);
        if (fromSame) list.removeWhere((x) => identical(x, node));
        list.insert(0, node);
        changed();
      },
      builder: (ctx, cand, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        hat,
        if (cand.isNotEmpty) Container(margin: const EdgeInsets.only(top: 3), width: 140, height: 18, decoration: BoxDecoration(color: context.cs.primary.withValues(alpha: .35), borderRadius: BorderRadius.circular(3))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = Scrollbar(
      controller: vScroll,
      child: SingleChildScrollView(
        controller: vScroll,
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hatTarget(_hat('khi bấm ▶ Chạy'), prog['main'] as List),
            StackView(list: prog['main'] as List, ed: this),
            for (final f in funcs) ...[
              const SizedBox(height: 22),
              _hatTarget(_hat(
                'định nghĩa hàm ${f['name']}(${((f['params'] ?? const []) as List).join(', ')})',
                color: categoryOf('func').color,
                actions: ro
                    ? const []
                    : [
                        const SizedBox(width: 4),
                        InkWell(onTap: () => editFunction(f), child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.edit, size: 15, color: Colors.white))),
                        InkWell(
                          onTap: () async {
                            if (!await confirmBox(context, 'Xoá hàm?', 'Xoá hàm "${f['name']}" và các khối bên trong?', ok: 'Xoá', danger: true)) return;
                            (prog['funcs'] as List).remove(f);
                            changed();
                          },
                          child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 15, color: Colors.white)),
                        ),
                      ],
              ), (f['body'] ??= <dynamic>[]) as List),
              StackView(list: f['body'] as List, ed: this),
            ],
            if (!ro) ...[
              const SizedBox(height: 18),
              TextButton.icon(onPressed: editFunction, icon: const Icon(Icons.add, size: 16), label: const Text('Tạo hàm')),
            ],
          ]),
        ),
      ),
    );
    if (ro) return workspace;
    return LayoutBuilder(builder: (context, box) {
      final pw = box.maxWidth < 600 ? box.maxWidth * .46 : 300.0;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _palette(pw),
        VerticalDivider(width: 1, color: context.cs.outlineVariant),
        Expanded(child: Container(color: context.isDark ? const Color(0xFF1B1C1F) : const Color(0xFFF9F9FB), child: workspace)),
      ]);
    });
  }
}

// ---------- Một chồng khối lệnh ----------
class StackView extends StatelessWidget {
  final List list;
  final ScratchEditorState ed;
  const StackView({super.key, required this.list, required this.ed});

  Widget _gap(BuildContext context, int index) {
    if (ed.ro) return const SizedBox(height: 0);
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => !d.data.isValue && !_contains(d.data.node, list),
      onAcceptWithDetails: (d) => _insert(d.data, index),
      builder: (ctx, cand, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: cand.isNotEmpty ? 22 : 4,
        width: cand.isNotEmpty ? 140 : (list.isEmpty ? 120 : 60),
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: cand.isNotEmpty ? context.cs.primary.withValues(alpha: .35) : (ed.dragging ? context.cs.primary.withValues(alpha: .08) : null),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  void _insert(_Drag d, int index) {
    var i = index;
    final fromSame = identical(d.fromList, list);
    final oldIndex = fromSame ? list.indexWhere((x) => identical(x, d.node)) : -1;
    final node = ed.take(d);
    if (fromSame && oldIndex != -1 && oldIndex < i) i--;
    list.insert(i.clamp(0, list.length), node);
    ed.changed();
  }

  /// Thả khối lệnh lên một khối: chèn ngay sau khối đó (như Scratch hút khối vào).
  Widget _dropOnBlock(BuildContext context, int i) {
    // Giữ đúng đối tượng trong danh sách (so sánh danh tính khi kéo / xoá).
    if (list[i] is! Json) list[i] = deepClone(list[i]);
    final node = list[i] as Json;
    final view = BlockView(node: node, ed: ed, parentList: list);
    if (ed.ro) return view;
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => !d.data.isValue && !identical(d.data.node, node) && !_contains(d.data.node, list),
      onAcceptWithDetails: (d) => _insert(d.data, i + 1),
      builder: (ctx, cand, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        view,
        if (cand.isNotEmpty) Container(margin: const EdgeInsets.only(top: 3), width: 140, height: 18, decoration: BoxDecoration(color: context.cs.primary.withValues(alpha: .35), borderRadius: BorderRadius.circular(3))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _gap(context, 0),
      for (var i = 0; i < list.length; i++) ...[
        if (list[i] is Map) _dropOnBlock(context, i),
        _gap(context, i + 1),
      ],
      if (list.isEmpty && ed.ro) const SizedBox(height: 8),
    ]);
  }
}

// ---------- Một khối ----------
class BlockView extends StatelessWidget {
  final Json node;
  final ScratchEditorState ed;
  final List? parentList; // khối lệnh
  final VoidCallback? detachFromSlot; // khối giá trị trong ô
  final bool preview;
  const BlockView({super.key, required this.node, required this.ed, this.parentList, this.detachFromSlot, this.preview = false});

  BlockSpec? get spec => specs[node['op']];

  static final _part = RegExp(r'\{(\w+)\}');

  List<Widget> _label(BuildContext context, BlockSpec s, Color color) {
    final out = <Widget>[];
    var last = 0;
    const style = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500);
    for (final m in _part.allMatches(s.label)) {
      final text = s.label.substring(last, m.start);
      if (text.trim().isNotEmpty) out.add(Text(text.trim(), style: style));
      final name = m.group(1)!;
      final slot = s.slots[name];
      if (slot != null) {
        if (slot.kind == SlotKind.func) {
          out.addAll(_funcSlot(context, color));
        } else {
          out.add(_SlotView(node: node, name: name, slot: slot, ed: ed, color: color, preview: preview));
        }
      }
      last = m.end;
    }
    final tail = s.label.substring(last);
    if (tail.trim().isNotEmpty) out.add(Text(tail.trim(), style: style));
    return out;
  }

  List<Widget> _funcSlot(BuildContext context, Color color) {
    final a = (node['a'] ??= <String, dynamic>{}) as Map;
    final name = '${a['FN'] ?? ''}';
    final fx = ed.funcs.where((f) => f['name'] == name).firstOrNull;
    final params = ((fx?['params'] ?? const []) as List).cast<String>();
    return [
      _Pill(
        text: name.isEmpty ? 'chọn hàm' : name,
        color: _darker(color),
        options: [for (final f in ed.funcs) ('${f['name']}', '${f['name']}')],
        enabled: !ed.ro && !preview,
        onSelected: (v) {
          a['FN'] = v;
          ed.changed();
        },
      ),
      if (params.isNotEmpty) const Text('(', style: TextStyle(color: Colors.white)),
      for (var i = 0; i < params.length; i++) ...[
        Text('${params[i]}:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        _SlotView(node: node, name: 'P$i', slot: const Slot(SlotKind.any, '0'), ed: ed, color: color, preview: preview),
      ],
      if (params.isNotEmpty) const Text(')', style: TextStyle(color: Colors.white)),
    ];
  }

  Widget _row(List<Widget> children) => Wrap(spacing: 5, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children);

  Widget _shape(BuildContext context, BlockSpec s, Color color) {
    final label = _row(_label(context, s, color));
    final stroke = _darker(color, .3);
    switch (s.shape) {
      case Shape.reporter:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: ShapeDecoration(color: color, shape: StadiumBorder(side: BorderSide(color: stroke))),
          child: label,
        );
      case Shape.boolean:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: ShapeDecoration(color: color, shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(13), side: BorderSide(color: stroke))),
          child: label,
        );
      case Shape.stmt:
      case Shape.cap:
        return Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 60),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: ShapeDecoration(color: color, shape: _PuzzleBorder(tabBottom: s.shape != Shape.cap, stroke: stroke)),
          child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: label),
        );
      case Shape.cblock:
      case Shape.ifelse:
        Widget arm(String key) => IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 16, color: color),
                Padding(padding: const EdgeInsets.only(left: 2), child: StackView(list: (node[key] ??= <dynamic>[]) as List, ed: ed)),
              ]),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 120),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: ShapeDecoration(color: color, shape: _PuzzleBorder(tabBottom: false, stroke: stroke)),
            child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: label),
          ),
          preview ? Container(width: 16, height: 14, color: color) : arm('do'),
          if (s.shape == Shape.ifelse) ...[
            Container(
              width: 120,
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              color: color,
              child: const Text('nếu không thì', style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
            preview ? Container(width: 16, height: 14, color: color) : arm('else'),
          ],
          Container(
            width: 120,
            height: 16,
            decoration: ShapeDecoration(color: color, shape: _PuzzleBorder(notchTop: false, stroke: stroke)),
          ),
        ]);
    }
  }

  Future<void> _menu(BuildContext context, Offset pos) async {
    final r = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'dup', child: Text('Nhân bản')),
        PopupMenuItem(value: 'del', child: Text('Xoá')),
      ],
    );
    if (r == 'dup') {
      if (parentList != null) {
        parentList!.insert(parentList!.indexWhere((x) => identical(x, node)) + 1, deepClone(node));
      } else {
        (ed.prog['main'] as List).add(deepClone(node));
      }
      ed.changed();
    } else if (r == 'del') {
      _detach();
      ed.changed();
    }
  }

  void _detach() {
    if (parentList != null) {
      parentList!.removeWhere((x) => identical(x, node));
    } else {
      detachFromSlot?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = spec;
    if (s == null) {
      return Container(padding: const EdgeInsets.all(6), color: Colors.grey, child: Text('khối không rõ: ${node['op']}', style: const TextStyle(color: Colors.white)));
    }
    final color = categoryOf(s.cat).color;
    final view = _shape(context, s, color);
    if (preview || ed.ro) return view;
    final tip = view;
    final data = _Drag(node, detach: _detach, fromList: parentList);
    final feedback = Material(type: MaterialType.transparency, child: Opacity(opacity: .85, child: BlockView(node: node, ed: ed, preview: true)));
    void start() => ed.setDragging(true);
    void end() => ed.setDragging(false);
    final child = GestureDetector(
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      onDoubleTapDown: _touch ? (d) => _menu(context, d.globalPosition) : null,
      child: tip,
    );
    final placeholder = Opacity(opacity: .3, child: view);
    return _touch
        ? LongPressDraggable<_Drag>(
            data: data,
            feedback: feedback,
            childWhenDragging: placeholder,
            onDragStarted: start,
            onDragEnd: (_) => end(),
            child: child,
          )
        : Draggable<_Drag>(
            data: data,
            feedback: feedback,
            childWhenDragging: placeholder,
            onDragStarted: start,
            onDragEnd: (_) => end(),
            child: child,
          );
  }
}

// ---------- Ô trong khối ----------
class _SlotView extends StatelessWidget {
  final Json node;
  final String name;
  final Slot slot;
  final ScratchEditorState ed;
  final Color color;
  final bool preview;
  const _SlotView({required this.node, required this.name, required this.slot, required this.ed, required this.color, required this.preview});

  Map get a => (node['a'] ??= <String, dynamic>{}) as Map;
  bool get editable => !ed.ro && !preview;

  @override
  Widget build(BuildContext context) {
    switch (slot.kind) {
      case SlotKind.varName:
        final v = '${a[name] ?? slot.dflt}';
        return _Pill(
          text: v,
          color: _darker(color),
          enabled: editable,
          options: [for (final x in ed.vars) ('$x', '$x'), ('+ Biến mới…', '\u0000new')],
          onSelected: (x) async {
            if (x == '\u0000new') {
              final n = await ed.newVariable();
              if (n == null) return;
              a[name] = n;
            } else {
              a[name] = x;
            }
            ed.changed();
          },
        );
      case SlotKind.dropdown:
        final v = '${a[name] ?? slot.dflt}';
        final label = slot.options.where((o) => o.$2 == v).firstOrNull?.$1 ?? v;
        return _Pill(
          text: label,
          color: _darker(color),
          enabled: editable,
          options: slot.options,
          onSelected: (x) {
            a[name] = x;
            ed.changed();
          },
        );
      case SlotKind.ident:
      case SlotKind.code:
        return _LitField(
          key: ValueKey(Object.hash(identityHashCode(node), name)),
          value: '${a[name] ?? slot.dflt}',
          enabled: editable,
          mono: slot.kind == SlotKind.code,
          multiline: slot.kind == SlotKind.code,
          dark: true,
          onChanged: (t) {
            a[name] = t;
            ed.widget.onChanged();
          },
        );
      case SlotKind.func:
        return const SizedBox();
      case SlotKind.label:
        // Nhắc lại tên biến của vòng lặp (vd. "i < 10; i++").
        return Text('${a['VAR'] ?? 'i'}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600));
      default:
        final cur = a[name];
        Widget inner;
        if (cur is Map) {
          if (cur is! Json) a[name] = deepClone(cur);
          inner = BlockView(
            node: a[name] as Json,
            ed: ed,
            preview: preview,
            detachFromSlot: () => a[name] = slot.kind == SlotKind.bool ? null : slot.dflt,
          );
        } else if (slot.kind == SlotKind.bool) {
          inner = Container(
            width: 44,
            height: 22,
            decoration: ShapeDecoration(color: _darker(color, .3), shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(11))),
          );
        } else {
          inner = _LitField(
            key: ValueKey(Object.hash(identityHashCode(node), name)),
            value: '${cur ?? slot.dflt}',
            enabled: editable,
            numeric: slot.kind == SlotKind.num,
            hint: slot.kind == SlotKind.list ? '1 2 3' : null,
            onChanged: (t) {
              a[name] = t;
              ed.widget.onChanged();
            },
          );
        }
        if (!editable) return inner;
        return DragTarget<_Drag>(
          onWillAcceptWithDetails: (d) => d.data.isValue && !identical(d.data.node, cur) && !_contains(d.data.node, node),
          onAcceptWithDetails: (d) {
            a[name] = ed.take(d.data);
            ed.changed();
          },
          builder: (ctx, cand, _) => Container(
            decoration: cand.isNotEmpty ? BoxDecoration(boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: .9), blurRadius: 6, spreadRadius: 1)], borderRadius: BorderRadius.circular(12)) : null,
            child: inner,
          ),
        );
    }
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final bool enabled;
  final List<(String, String)> options;
  final void Function(String) onSelected;
  const _Pill({required this.text, required this.color, required this.enabled, required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
      ]),
    );
    if (!enabled || options.isEmpty) return pill;
    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: onSelected,
      itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o.$2, height: 34, child: Text(o.$1))],
      child: pill,
    );
  }
}

/// Ô gõ giá trị (số / chữ) trong khối; tự giãn theo độ dài.
class _LitField extends StatefulWidget {
  final String value;
  final bool enabled, numeric, mono, multiline, dark;
  final String? hint;
  final ValueChanged<String> onChanged;
  const _LitField({super.key, required this.value, required this.enabled, required this.onChanged, this.numeric = false, this.mono = false, this.multiline = false, this.dark = false, this.hint});
  @override
  State<_LitField> createState() => _LitFieldState();
}

class _LitFieldState extends State<_LitField> {
  late final ctl = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _LitField old) {
    super.didUpdateWidget(old);
    if (widget.value != ctl.text && !FocusScope.of(context).hasFocus) ctl.text = widget.value;
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: widget.dark ? Colors.white : Colors.black87, fontFamily: widget.mono ? monoFont : null);
    final lines = widget.multiline ? ctl.text.split('\n') : [ctl.text];
    final longest = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final w = (longest.clamp(widget.hint != null && ctl.text.isEmpty ? widget.hint!.length : 1, 60) * (widget.mono ? 8.0 : 7.8) + 24).clamp(34.0, 460.0);
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: widget.dark ? Colors.black.withValues(alpha: .22) : Colors.white,
        borderRadius: BorderRadius.circular(widget.multiline ? 4 : 12),
        border: Border.all(color: Colors.black26),
      ),
      child: widget.enabled
          ? TextField(
              controller: ctl,
              style: style,
              maxLines: widget.multiline ? null : 1,
              keyboardType: widget.numeric ? const TextInputType.numberWithOptions(signed: true, decimal: true) : (widget.multiline ? TextInputType.multiline : TextInputType.text),
              textAlign: widget.multiline ? TextAlign.start : TextAlign.center,
              decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: style.copyWith(color: Colors.black38)),
              onChanged: (t) {
                setState(() {});
                widget.onChanged(t);
              },
            )
          : Text(ctl.text.isEmpty ? (widget.hint ?? '') : ctl.text, style: style, textAlign: widget.multiline ? TextAlign.start : TextAlign.center),
    );
  }
}
