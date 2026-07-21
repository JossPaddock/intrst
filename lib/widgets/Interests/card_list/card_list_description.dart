part of '../CardList.dart';

const double _collapsedDescriptionHeight = 50.0;
const int _descriptionCollapseThreshold = 150;

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
// images with resize/align controls and the collapse/expand behaviour for
// long descriptions.
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
  }) {
    final plainText = _getRichTextPlainText(richTextController);
    final bool isLong = plainText.length > _descriptionCollapseThreshold;
    final bool isExpanded = _expandedDescriptions[id] ?? false;

    final parts = _splitDocumentAtImages(richTextController.document);

    final inlineContent = Column(
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

    if (isLong && !isExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _collapsedDescriptionHeight,
            child: ClipRect(
              // OverflowBox lets the content column lay out at its natural
              // height (it can contain images far taller than the collapsed
              // preview); the ClipRect shows just the top slice. Without it
              // the column is forced into the 60px box and reports a
              // RenderFlex overflow.
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: inlineContent,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _expandedDescriptions[id] = true),
            child: Center(
              child: Icon(Icons.expand_more, color: Colors.grey[400], size: 20),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inlineContent,
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expandedDescriptions[id] = false),
            child: Center(
              child: Icon(Icons.expand_less, color: Colors.grey[400], size: 20),
            ),
          ),
      ],
    );
  }
}
