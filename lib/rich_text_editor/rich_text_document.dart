import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'rich_text_op.dart';

/// An immutable, serialisable rich-text document.
///
/// Internally a flat list of [RichTextOp]s (runs).  The plain-text content
/// is the concatenation of all runs' `.text` fields; formatting is carried
/// by each run's `.attributes` map.
///
/// ## Versioning
/// The [version] field guards forward compatibility.  A reader that sees an
/// unknown [version] should fall back gracefully (e.g. render plain text).
/// The current format is version `1`.
///
/// ## Storage recommendation
/// Persist as [toJsonString] (a JSON string).  On load, call
/// [RichTextDocument.fromJsonString], which gracefully falls back to plain
/// text if the string is not valid JSON.
@immutable
class RichTextDocument {
  const RichTextDocument({
    this.version = _kCurrentVersion,
    this.ops = const <RichTextOp>[],
  });

  static const int _kCurrentVersion = 1;

  /// Increment this when making breaking schema changes.
  final int version;

  /// The ordered list of text runs that make up the document.
  final List<RichTextOp> ops;

  // ── Derived properties ───────────────────────────────────────────────────

  /// The plain (un-formatted) text content.
  String get plainText => ops.map((op) => op.text).join();

  bool get isEmpty => ops.every((op) => op.text.isEmpty);
  bool get isNotEmpty => !isEmpty;

  // ── Factory constructors ─────────────────────────────────────────────────

  factory RichTextDocument.empty() => const RichTextDocument();

  /// Wraps [text] in a single plain run.
  factory RichTextDocument.fromPlainText(String text) => RichTextDocument(
    ops: text.isEmpty ? const [] : [RichTextOp(text: text)],
  );

  factory RichTextDocument.fromJson(Map<String, dynamic> json) =>
      RichTextDocument(
        version: (json['version'] as int?) ?? _kCurrentVersion,
        ops: ((json['ops'] as List<dynamic>?) ?? [])
            .map((e) => RichTextOp.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  /// Parses [jsonString].  Falls back silently to a plain-text document if
  /// [jsonString] is not valid JSON (so old plain-text values don't crash).
  factory RichTextDocument.fromJsonString(String jsonString) {
    if (jsonString.isEmpty) return RichTextDocument.empty();
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return RichTextDocument.fromJson(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return RichTextDocument.fromPlainText(jsonString);
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'ops': ops.map((op) => op.toJson()).toList(),
  };

  String toJsonString() => jsonEncode(toJson());

  // ── Normalisation ────────────────────────────────────────────────────────

  /// Returns a new document with adjacent ops that share identical [attributes]
  /// merged into a single op.  Always call this after mutating the op list.
  ///
  /// Also strips zero-length ops.
  RichTextDocument normalised() {
    if (ops.isEmpty) return this;
    final result = <RichTextOp>[];
    for (final op in ops) {
      if (op.text.isEmpty) continue;
      if (result.isNotEmpty &&
          mapEquals(result.last.attributes, op.attributes)) {
        final prev = result.removeLast();
        result.add(prev.copyWith(text: prev.text + op.text));
      } else {
        result.add(op);
      }
    }
    return RichTextDocument(version: version, ops: result);
  }

  // ── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RichTextDocument &&
              version == other.version &&
              listEquals(ops, other.ops);

  @override
  int get hashCode => Object.hash(version, Object.hashAll(ops));

  @override
  String toString() => 'RichTextDocument(v$version, ${ops.length} ops)';
}