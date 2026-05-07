import 'package:flutter/foundation.dart';

/// A single contiguous run of text with a uniform set of formatting attributes.
///
/// Inspired by the Quill Delta format.  Every [RichTextDocument] is a flat
/// list of these ops; the document's plain text is just their `.text` fields
/// concatenated.
///
/// ## Extensibility
/// The [attributes] map is open: today only `"link"` is recognised, but any
/// future attribute (e.g. `"bold"`, `"italic"`, `"color"`) can be added by
/// inserting a new key.  Unknown keys are **preserved** on round-trips, so
/// data written by a newer app version can still be read by an older one
/// without data loss.
@immutable
class RichTextOp {
  const RichTextOp({
    required this.text,
    this.attributes = const <String, dynamic>{},
  });

  /// The raw text content of this run.
  final String text;

  /// Formatting attributes applied uniformly to [text].
  ///
  /// Currently recognised keys
  /// ─────────────────────────
  /// • `"link"` – `String` – a URL that makes this run a tappable hyperlink.
  ///
  /// Future keys (bold, italic, colour, …) follow the same pattern.
  final Map<String, dynamic> attributes;

  // ── Convenience accessors ────────────────────────────────────────────────

  /// The URL stored under the `"link"` key, or `null`.
  String? get link => attributes['link'] as String?;

  /// Whether this run is a hyperlink.
  bool get isLink => link != null && link!.isNotEmpty;

  // ── Mutations (return new instances – ops are immutable) ─────────────────

  RichTextOp copyWith({
    String? text,
    Map<String, dynamic>? attributes,
  }) =>
      RichTextOp(
        text: text ?? this.text,
        attributes: attributes ?? this.attributes,
      );

  /// Returns a copy with the `"link"` attribute set to [url].
  RichTextOp withLink(String url) =>
      copyWith(attributes: {...attributes, 'link': url});

  /// Returns a copy with the `"link"` attribute removed (all other attrs kept).
  RichTextOp withoutLink() {
    final next = Map<String, dynamic>.from(attributes)..remove('link');
    return copyWith(attributes: next);
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
    'insert': text,
    if (attributes.isNotEmpty) 'attributes': attributes,
  };

  factory RichTextOp.fromJson(Map<String, dynamic> json) => RichTextOp(
    text: (json['insert'] as String?) ?? '',
    attributes: Map<String, dynamic>.from(
      (json['attributes'] as Map?)?.cast<String, dynamic>() ?? {},
    ),
  );

  // ── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RichTextOp &&
              text == other.text &&
              mapEquals(attributes, other.attributes);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(attributes.values));

  @override
  String toString() => 'RichTextOp(text: "$text", attrs: $attributes)';
}