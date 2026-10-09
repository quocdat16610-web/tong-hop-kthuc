// Trình soạn code (re_editor): tô màu C++/JS, số dòng, lề điểm dừng, đánh dấu dòng lỗi và dòng đang gỡ lỗi.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'theme.dart';

class EditorMarks {
  final Set<int> breakpoints; // chỉ số dòng (0-based)
  final int? current;
  final Set<int> errors;
  const EditorMarks({this.breakpoints = const {}, this.current, this.errors = const {}});
  EditorMarks copyWith({Set<int>? breakpoints, int? current, bool clearCurrent = false, Set<int>? errors}) =>
      EditorMarks(breakpoints: breakpoints ?? this.breakpoints, current: clearCurrent ? null : current ?? this.current, errors: errors ?? this.errors);
}

class _ContextMenu implements SelectionToolbarController {
  const _ContextMenu();
  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    PopupMenuItem<void> item(String t, VoidCallback f) => PopupMenuItem(height: 34, onTap: f, child: Text(t));
    showMenu<void>(
      context: context,
      position: RelativeRect.fromSize(anchors.primaryAnchor & const Size(160, double.infinity), MediaQuery.sizeOf(context)),
      items: [
        item('Cắt', controller.cut),
        item('Sao chép', controller.copy),
        item('Dán', controller.paste),
        item('Chọn tất cả', controller.selectAll),
      ],
    );
  }
}

// Bỏ Ctrl+S (và tìm/thay thế) của re_editor để phím tắt của app (Lưu / Commit) nhận được.
class _Keys extends DefaultCodeShortcutsActivatorsBuilder {
  const _Keys();
  @override
  List<ShortcutActivator>? build(CodeShortcutType type) => switch (type) {
        CodeShortcutType.save || CodeShortcutType.find || CodeShortcutType.replace || CodeShortcutType.esc => null,
        _ => super.build(type),
      };
}

class CodeArea extends StatelessWidget {
  final CodeLineEditingController controller;
  final String lang;
  final bool readOnly;
  final ValueListenable<EditorMarks>? marks;
  final void Function(int line)? onGutterTap;
  final double fontSize;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<CodeLineEditingValue>? onChanged;

  const CodeArea({
    super.key,
    required this.controller,
    this.lang = 'cpp',
    this.readOnly = false,
    this.marks,
    this.onGutterTap,
    this.fontSize = 14,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return CodeEditor(
      controller: controller,
      readOnly: readOnly,
      autofocus: autofocus,
      focusNode: focusNode,
      wordWrap: false,
      onChanged: onChanged,
      toolbarController: const _ContextMenu(),
      shortcutsActivatorsBuilder: const _Keys(),
      style: CodeEditorStyle(
        fontSize: fontSize,
        fontFamily: monoFont,
        backgroundColor: dark ? const Color(0xFF1E1F22) : Colors.white,
        codeTheme: CodeHighlightTheme(
          languages: {lang: CodeHighlightThemeMode(mode: switch (lang) { 'py' => langPython, 'js' => langJavascript, _ => langCpp })},
          theme: dark ? atomOneDarkTheme : atomOneLightTheme,
        ),
      ),
      indicatorBuilder: (context, editing, chunk, notifier) => Row(children: [
        if (marks != null || onGutterTap != null) _Gutter(notifier: notifier, marks: marks, onTap: onGutterTap),
        DefaultCodeLineNumber(controller: editing, notifier: notifier),
        const SizedBox(width: 6),
      ]),
      leadingDivider: Container(width: 1, color: context.cs.outlineVariant),
    );
  }
}

class _Gutter extends StatelessWidget {
  final CodeIndicatorValueNotifier notifier;
  final ValueListenable<EditorMarks>? marks;
  final void Function(int line)? onTap;
  const _Gutter({required this.notifier, this.marks, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = marks ?? ValueNotifier(const EditorMarks());
    return ValueListenableBuilder<EditorMarks>(
      valueListenable: m,
      builder: (context, mk, _) => ValueListenableBuilder<CodeIndicatorValue?>(
        valueListenable: notifier,
        builder: (context, v, _) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (v == null || onTap == null) return;
            for (final p in v.paragraphs) {
              if (d.localPosition.dy >= p.top && d.localPosition.dy < p.bottom) {
                onTap!(p.index);
                return;
              }
            }
          },
          child: SizedBox(width: 18, height: double.infinity, child: CustomPaint(painter: _GutterPainter(v, mk, context.cs.primary))),
        ),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  final CodeIndicatorValue? v;
  final EditorMarks m;
  final Color accent;
  _GutterPainter(this.v, this.m, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    if (v == null) return;
    for (final p in v!.paragraphs) {
      final cy = p.top + p.preferredLineHeight / 2;
      if (m.errors.contains(p.index)) {
        canvas.drawRect(Rect.fromLTWH(0, p.top, 3, p.preferredLineHeight), Paint()..color = const Color(0xFFE5534B));
      }
      if (m.breakpoints.contains(p.index)) {
        canvas.drawCircle(Offset(10, cy), 5, Paint()..color = const Color(0xFFE5534B));
      }
      if (m.current == p.index) {
        final path = Path()
          ..moveTo(1, cy - 7)
          ..lineTo(14, cy)
          ..lineTo(1, cy + 7)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFEAB308));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) => true;
}
