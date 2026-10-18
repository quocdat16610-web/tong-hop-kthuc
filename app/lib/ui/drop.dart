// Kéo thả file từ ngoài (Explorer, Finder, app khác trên điện thoại chia đôi màn hình) vào app.
// Một DropTarget duy nhất ở gốc; mỗi vùng nhận file là một DropZone, file thả xuống được giao cho
// vùng nhỏ nhất (trong cùng) đang hiện dưới con trỏ — vd. bảng trắng nằm trong trang sổ tay.
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

export 'package:desktop_drop/desktop_drop.dart' show DropItem, DropItemFile;

extension DropItemName on DropItem {
  /// Tên file (không kèm thư mục) — đường dẫn có thể dùng cả `/` lẫn `\` tuỳ hệ điều hành / app gửi file.
  String get fileName => name.split(RegExp(r'[\\/]')).last;
}

/// `local`: vị trí thả, tính trong vùng.
typedef DropHandler = Future<void> Function(List<DropItem> files, Offset local);

class DropZone extends StatefulWidget {
  final DropHandler? onDrop; // null = vùng tạm không nhận file
  final String hint;
  final Widget child;
  const DropZone({super.key, required this.onDrop, required this.hint, required this.child});
  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  static final Set<_DropZoneState> _zones = {};
  bool _over = false;
  bool _shown = true; // tab ẩn trong IndexedStack / trang nằm dưới màn hình khác thì không nhận

  @override
  void initState() {
    super.initState();
    _zones.add(this);
  }

  @override
  void dispose() {
    _zones.remove(this);
    super.dispose();
  }

  Rect? get _rect {
    if (!mounted || !_shown || widget.onDrop == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _setOver(bool v) {
    if (_over != v && mounted) setState(() => _over = v);
  }

  /// Vùng trong cùng chứa điểm (theo toạ độ màn hình).
  static _DropZoneState? at(Offset global) {
    _DropZoneState? best;
    var area = double.infinity;
    for (final z in _zones) {
      final r = z._rect;
      if (r == null || !r.contains(global)) continue;
      final a = r.width * r.height;
      if (a < area) {
        area = a;
        best = z;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    _shown = TickerMode.valuesOf(context).enabled;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: context.cs.primary.withValues(alpha: .08),
                  border: Border.all(color: context.cs.primary, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined, size: 18, color: context.cs.onPrimary),
                      const SizedBox(width: 6),
                      Flexible(child: Text(widget.hint, style: TextStyle(color: context.cs.onPrimary, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Đặt một lần ở gốc giao diện.
/// `intercept`: xử lý trước một số file (vd. mở notebook .dsanote.json), trả về các file còn lại.
/// `fallback`: khi thả ra ngoài mọi vùng.
class AppDropTarget extends StatefulWidget {
  final Widget child;
  final Future<List<DropItem>> Function(List<DropItem> files)? intercept;
  final void Function(List<DropItem> files)? fallback;
  const AppDropTarget({super.key, required this.child, this.intercept, this.fallback});
  @override
  State<AppDropTarget> createState() => _AppDropTargetState();
}

class _AppDropTargetState extends State<AppDropTarget> {
  _DropZoneState? _hover;

  void _hoverAt(Offset? global) {
    final z = global == null ? null : _DropZoneState.at(global);
    if (z == _hover) return;
    _hover?._setOver(false);
    z?._setOver(true);
    _hover = z;
  }

  Future<void> _done(DropDoneDetails d) async {
    _hoverAt(null);
    var files = d.files.where((f) => f is! DropItemDirectory).toList();
    if (files.isEmpty) return;
    // Tìm vùng trước khi xử lý (hộp thoại mở ra có thể che vùng).
    final zone = _DropZoneState.at(d.globalPosition);
    final rect = zone?._rect;
    if (widget.intercept != null) files = await widget.intercept!(files);
    if (files.isEmpty) return;
    if (zone == null || rect == null || !zone.mounted) return widget.fallback?.call(files);
    await zone.widget.onDrop!(files, d.globalPosition - rect.topLeft);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (d) => _hoverAt(d.globalPosition),
    onDragUpdated: (d) => _hoverAt(d.globalPosition),
    onDragExited: (_) => _hoverAt(null),
    onDragDone: _done,
    child: widget.child,
  );
}
