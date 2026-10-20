part of '../CardList.dart';

// How many lines of description a card shows in the list before it's
// tapped open.
const int _collapsedDescriptionLines = 2;
const double _collapsedImageMaxHeight = 50.0;

const double _defaultImageMaxHeight = 160.0;

final List<({String label, double height})> _imageSizePresets = [
  (label: 'S', height: 80),
  (label: 'M', height: 160),
  (label: 'L', height: 280),
  (label: 'XL', height: 400),
];

// Matches an image URL with optional |<pixels> height and optional |<L|C|R>
// alignment suffix, e.g. "https://example.com/photo.jpg|300|L".
final RegExp _imageUrlPattern = RegExp(
  r'(https?://[^\s<>"{}|\\^`\[\]]+\.(?:jpg|jpeg|png|gif|webp|svg)(?:\?[^\s|]*)?)(?:\|(\d+))?(?:\|([LCR]))?',
  caseSensitive: false,
);

const List<(String char, IconData icon)> _imageAlignOptions = [
  ('L', Icons.format_align_left),
  ('C', Icons.format_align_center),
  ('R', Icons.format_align_right),
];

// Renders an interest's rich-text description inline, including embedded
// images with resize/align controls, or as a short truncated preview while
// the card is collapsed in the list.
mixin _CardListDescriptionMixin on _CardListStateBase {
  String _updateImageInDescription(
    String descJson,
    String baseUrl,
    double newHeight,
    String newAlignChar,
  ) {
    final doc = RichTextDocument.fromJsonString(descJson);
    // Match base URL + optional |digits + optional |[LCR]
    final urlPattern = RegExp(
      RegExp.escape(baseUrl) + r'(\|\d+)?(\|[LCR])?',
      caseSensitive: false,
    );
    final suffix = newAlignChar == 'C'
        ? '|${newHeight.round()}'
        : '|${newHeight.round()}|$newAlignChar';
    final replacement = '$baseUrl$suffix';

    final updatedOps = doc.ops.map((op) {
      if (!urlPattern.hasMatch(op.text)) return op;
      return op.copyWith(text: op.text.replaceFirst(urlPattern, replacement));
    }).toList();

    return RichTextDocument(
      version: doc.version,
      ops: updatedOps,
    ).normalised().toJsonString();
  }

  Future<void> _applyImageUpdate(
    Interest interest,
    RichTextEditorController richTextController,
    String baseUrl,
    double newHeight,
    String newAlignChar,
  ) async {
    final newDescJson = _updateImageInDescription(
      interest.description,
      baseUrl,
      newHeight,
      newAlignChar,
    );
    final newInterest = interest.copyWith(
      description: newDescJson,
      updated_timestamp: DateTime.now(),
    );

    setState(() {
      final idx = localInterests.indexWhere((i) => i.id == interest.id);
      if (idx != -1) localInterests[idx] = newInterest;
    });
    richTextController.loadDocument(
      RichTextDocument.fromJsonString(newDescJson),
    );

    await fu.updateEditedInterest(
      FirebaseFirestore.instance.collection('users'),
      interest,
      newInterest,
      widget.uid,
    );
  }

  // Splits a RichTextDocument into alternating text-op lists and image records,
  // in document order. Each item is either List<RichTextOp> or
  // ({String url, double maxHeight, String alignChar}).
  List<Object> _splitDocumentAtImages(RichTextDocument doc) {
    final parts = <Object>[];
    var pendingTextOps = <RichTextOp>[];

    for (final op in doc.ops) {
      var text = op.text;

      while (text.isNotEmpty) {
        final match = _imageUrlPattern.firstMatch(text);
        if (match == null) {
          pendingTextOps.add(op.copyWith(text: text));
          break;
        }

        if (match.start > 0) {
          pendingTextOps.add(op.copyWith(text: text.substring(0, match.start)));
        }

        if (pendingTextOps.isNotEmpty) {
          parts.add(List<RichTextOp>.from(pendingTextOps));
          pendingTextOps = [];
        }

        final baseUrl = match.group(1)!;
        final heightStr = match.group(2);
        final alignStr = match.group(3)?.toUpperCase();
        final maxHeight = heightStr != null
            ? (double.tryParse(heightStr) ?? _defaultImageMaxHeight).clamp(
                40.0,
                800.0,
              )
            : _defaultImageMaxHeight;
        parts.add((
          url: baseUrl,
          maxHeight: maxHeight,
          alignChar: alignStr ?? 'C',
        ));

        text = text.substring(match.end);
      }
    }

    if (pendingTextOps.isNotEmpty) {
      parts.add(List<RichTextOp>.from(pendingTextOps));
    }

    return parts;
  }

  Widget _buildTextOpsView(BuildContext context, List<RichTextOp> ops) {
    final nonEmpty = ops.where((op) => op.text.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();

    final baseStyle = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];

    for (final op in nonEmpty) {
      if (op.isLink) {
        final url = op.link!;
        spans.add(
          TextSpan(
            text: op.text,
            style: baseStyle.copyWith(
              color: const Color(0xFF1A73E8),
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFF1A73E8),
            ),
            recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
          ),
        );
      } else {
        spans.add(TextSpan(text: op.text, style: baseStyle));
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: RichText(
        text: TextSpan(children: spans, style: baseStyle),
        maxLines: null,
      ),
    );
  }

  Widget _buildSingleImageSection(
    ({String url, double maxHeight, String alignChar}) img, {
    bool canResize = false,
    Interest? interest,
    RichTextEditorController? richTextController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Align(
            alignment: switch (img.alignChar) {
              'L' => Alignment.centerLeft,
              'R' => Alignment.centerRight,
              _ => Alignment.center,
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: img.maxHeight),
                child: Image.network(
                  img.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        if (canResize && interest != null && richTextController != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final preset in _imageSizePresets)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text(
                        preset.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: (img.maxHeight - preset.height).abs() < 1,
                      onSelected: (_) => _applyImageUpdate(
                        interest,
                        richTextController,
                        img.url,
                        preset.height,
                        img.alignChar,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 0,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                const SizedBox(width: 8),
                for (final (char, icon) in _imageAlignOptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Icon(icon, size: 14),
                      selected: img.alignChar == char,
                      onSelected: (_) => _applyImageUpdate(
                        interest,
                        richTextController,
                        img.url,
                        img.maxHeight,
                        char,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 0,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget _buildInlineDescription(
    BuildContext context,
    String id,
    RichTextEditorController richTextController, {
    bool canResize = false,
    Interest? interest,
    bool collapsed = false,
  }) {
    final parts = _splitDocumentAtImages(richTextController.document);

    if (collapsed) return _buildCollapsedDescription(context, parts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final part in parts)
          if (part is List<RichTextOp>)
            _buildTextOpsView(context, part)
          else if (part is ({String url, double maxHeight, String alignChar}))
            _buildSingleImageSection(
              part,
              canResize: canResize,
              interest: interest,
              richTextController: richTextController,
            ),
      ],
    );
  }

  // The list preview: the description's text flattened onto at most
  // [_collapsedDescriptionLines] lines, ending in an ellipsis whenever
  // anything is cut off — overflowing text or images the preview leaves
  // out — so the reader knows tapping the card shows more. Links keep their
  // styling but aren't tappable here, so a tap anywhere opens the card.
  Widget _buildCollapsedDescription(BuildContext context, List<Object> parts) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final linkStyle = baseStyle.copyWith(
      color: const Color(0xFF1A73E8),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFF1A73E8),
    );

    final spans = <TextSpan>[];
    final images = <({String url, double maxHeight, String alignChar})>[];
    for (final part in parts) {
      if (part is List<RichTextOp>) {
        for (final op in part) {
          // Line breaks become spaces so the preview fills both lines and
          // the ellipsis lands where the text is actually cut.
          final text = op.text.replaceAll(RegExp(r'\s+'), ' ');
          if (text.isEmpty) continue;
          spans.add(
            TextSpan(text: text, style: op.isLink ? linkStyle : baseStyle),
          );
        }
      } else if (part is ({String url, double maxHeight, String alignChar})) {
        images.add(part);
      }
    }
    final bool hasText = spans.any((s) => s.text!.trim().isNotEmpty);

    // Image-only description: show a thumbnail of the first image instead.
    if (!hasText) {
      if (images.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _collapsedImageMaxHeight,
                ),
                child: Image.network(
                  images.first.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            if (images.length > 1) Text(' …', style: baseStyle),
          ],
        ),
      );
    }

    final textSpan = TextSpan(children: spans, style: baseStyle);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var span = textSpan;
          // TextOverflow.ellipsis covers text that runs past the last line;
          // when the text fits but images were dropped, add one by hand.
          if (images.isNotEmpty) {
            final painter = TextPainter(
              text: textSpan,
              maxLines: _collapsedDescriptionLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final bool textOverflows = painter.didExceedMaxLines;
            painter.dispose();
            if (!textOverflows) {
              span = TextSpan(
                children: [...spans, const TextSpan(text: ' …')],
                style: baseStyle,
              );
            }
          }
          return Text.rich(
            span,
            maxLines: _collapsedDescriptionLines,
            overflow: TextOverflow.ellipsis,
          );
        },
      ),
    );
  }
}
