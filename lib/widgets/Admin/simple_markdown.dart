import 'package:flutter/material.dart';

/// A tiny, dependency-free markdown renderer for the admin dashboard's test-doc
/// previews. It supports just what those docs use:
///
///  * `#` / `##` / `###` headings,
///  * `-` or `*` bullet lines,
///  * blank lines as paragraph breaks,
///  * inline `**bold**` and `` `code` ``.
///
/// Anything else renders as a plain paragraph. This deliberately avoids pulling
/// in `flutter_markdown`; the docs are short and fully under our control.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown(this.source, {super.key, this.baseColor});

  final String source;
  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    final color = baseColor ?? const Color(0xFF23323A);
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];

    for (var raw in lines) {
      final line = raw.trimRight();
      final trimmed = line.trimLeft();

      if (trimmed.isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      if (trimmed.startsWith('### ')) {
        blocks.add(_heading(trimmed.substring(4), 13.5, color));
      } else if (trimmed.startsWith('## ')) {
        blocks.add(_heading(trimmed.substring(3), 15, color));
      } else if (trimmed.startsWith('# ')) {
        blocks.add(_heading(trimmed.substring(2), 17, color));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.add(_bullet(trimmed.substring(2), color));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: _richParagraph(trimmed, color),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _heading(String text, double size, Color color) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      );

  Widget _bullet(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(child: _richParagraph(text, color)),
          ],
        ),
      );

  Widget _richParagraph(String text, Color color) => RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13, height: 1.45, color: color),
          children: _inlineSpans(text, color),
        ),
      );

  /// Parses `**bold**` and `` `code` `` runs into spans. Unmatched markers are
  /// treated as literal text.
  List<InlineSpan> _inlineSpans(String text, Color color) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
    var index = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(
          text: match.group(2),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            backgroundColor: color.withValues(alpha: 0.07),
          ),
        ));
      }
      index = match.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return spans;
  }
}
