import 'package:flutter/material.dart';
import 'package:intrst/rich_text_editor/rich_text_document.dart';
import 'package:intrst/rich_text_editor/rich_text_op.dart';
import 'package:intrst/rich_text_editor/url_detector.dart';

import 'link_visit_store.dart';

// ── Internal annotation model ─────────────────────────────────────────────────

/// A mutable link range tracked over the raw text buffer.
///
/// `start` is inclusive, `end` is exclusive — matching Dart string semantics.
class LinkAnnotation {
  LinkAnnotation({
    required this.start,
    required this.end,
    required this.url,
  }) : assert(start <= end);

  int start;
  int end;
  String url;

  int get length => end - start;

  /// Returns `true` if [offset] falls inside this annotation.
  /// The half-open interval `[start, end)` is used: the character AT `start`
  /// is inside the link; the character at `end` is NOT.
  bool contains(int offset) => offset >= start && offset < end;

  @override
  String toString() => 'LinkAnnotation($start‥$end "$url")';
}

// ── Controller ────────────────────────────────────────────────────────────────

/// A [TextEditingController] that understands [RichTextDocument] and renders
/// hyperlinks inside any standard Flutter [TextField] / [TextFormField].
///
/// ## Key capabilities
/// * Loads and exports a [RichTextDocument] (Quill-Delta-inspired JSON).
/// * Renders link ranges in blue (unvisited) / purple (visited) with underline
///   via the [buildTextSpan] override — this is what keeps the iOS magnifier
///   glass working correctly, because the actual editing widget remains a
///   plain [TextField].
/// * Reconciles link annotations against every text edit (insertion /
///   deletion) so ranges stay accurate.
/// * Auto-detects URLs on spacebar / newline (word completion) and on paste.
/// * Provides [getLinkAtOffset], [addLink], [updateLink], [removeLink] for
///   programmatic link management.
///
/// ## Adding future rich-text features
/// Follow the same pattern:
///   1. Add a new key to [RichTextOp.attributes] (e.g. `"bold": true`).
///   2. Add a `MyCategoryAnnotation` class alongside [LinkAnnotation].
///   3. Handle it in [reconcile], [_buildDocument], [buildTextSpan].
///   4. Existing JSON without that key is unaffected (backward compatible).
class RichTextEditorController extends TextEditingController {
  RichTextEditorController({RichTextDocument? initialDocument}) {
    final doc = initialDocument ?? RichTextDocument.empty();
    _applyDocument(doc);
  }

  // ── State ──────────────────────────────────────────────────────────────────

  final List<LinkAnnotation> _links = [];

  /// The plain text as of the last [reconcile] call.  Used to diff edits.
  String _previousText = '';

  // ── Document I/O ───────────────────────────────────────────────────────────

  /// The current document state.  Rebuild-safe: call this to serialise.
  RichTextDocument get document => _buildDocument();

  /// Replaces the entire buffer with [doc], resetting the cursor to the end.
  void loadDocument(RichTextDocument doc) {
    _applyDocument(doc);
    notifyListeners();
  }

  void _applyDocument(RichTextDocument doc) {
    _links.clear();
    int cursor = 0;
    for (final op in doc.ops) {
      if (op.isLink) {
        _links.add(LinkAnnotation(
          start: cursor,
          end: cursor + op.text.length,
          url: op.link!,
        ));
      }
      cursor += op.text.length;
    }
    final plain = doc.plainText;
    _previousText = plain;
    // Set value directly (avoids triggering reconcile via onChanged).
    value = TextEditingValue(
      text: plain,
      selection: TextSelection.collapsed(offset: plain.length),
    );
  }

  RichTextDocument _buildDocument() {
    final txt = text;
    if (txt.isEmpty) return RichTextDocument.empty();

    final sorted = _sortedLinks();
    final ops = <RichTextOp>[];
    int cursor = 0;

    for (final link in sorted) {
      if (link.start > cursor) {
        ops.add(RichTextOp(text: txt.substring(cursor, link.start)));
      }
      ops.add(RichTextOp(
        text: txt.substring(link.start, link.end),
        attributes: {'link': link.url},
      ));
      cursor = link.end;
    }
    if (cursor < txt.length) {
      ops.add(RichTextOp(text: txt.substring(cursor)));
    }

    return RichTextDocument(ops: ops).normalised();
  }

  // ── Link management ────────────────────────────────────────────────────────

  /// Returns a read-only view of the annotation at [offset], or `null`.
  ({String url, int start, int end})? getLinkAtOffset(int offset) {
    final ann = _linkAt(offset);
    if (ann == null) return null;
    return (url: ann.url, start: ann.start, end: ann.end);
  }

  /// Returns the mutable annotation that contains [offset], or `null`.
  LinkAnnotation? _linkAt(int offset) {
    for (final ann in _links) {
      if (ann.contains(offset)) return ann;
    }
    return null;
  }

  /// Wraps the current selection (or the word at the cursor when collapsed)
  /// in a link pointing to [url].
  void addLink({required TextSelection selection, required String url}) {
    final txt = text;
    var start = selection.start.clamp(0, txt.length);
    var end = selection.end.clamp(0, txt.length);

    // Expand to word boundaries for a collapsed selection.
    if (start == end) {
      while (start > 0 && !_isWordBoundary(txt[start - 1])) start--;
      while (end < txt.length && !_isWordBoundary(txt[end])) end++;
    }
    if (start >= end) return;

    _removeLinksOverlapping(start, end);
    _links.add(LinkAnnotation(start: start, end: end, url: url));
    notifyListeners();
  }

  /// Updates an existing link that contains [offset].
  ///
  /// Supplying [newText] replaces the display text in the buffer; supplying
  /// [newUrl] changes the destination without touching the text.
  void updateLink({
    required int offset,
    String? newText,
    String? newUrl,
  }) {
    final ann = _linkAt(offset);
    if (ann == null) return;

    if (newText != null) {
      final old = text;
      final before = old.substring(0, ann.start);
      final after = old.substring(ann.end);
      final next = before + newText + after;
      final delta = newText.length - ann.length;
      ann.end = ann.start + newText.length;

      // Shift all OTHER links that come after this one.
      for (final other in _links) {
        if (identical(other, ann)) continue;
        if (other.start >= ann.end - delta) {
          other.start += delta;
          other.end += delta;
        }
      }

      _previousText = next;
      value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: ann.end),
      );
    }

    if (newUrl != null) ann.url = newUrl;

    notifyListeners();
  }

  /// Removes the link annotation at [offset] (plain text is unchanged).
  void removeLink(int offset) {
    _links.removeWhere((a) => a.contains(offset));
    notifyListeners();
  }

  // ── Reconciliation ─────────────────────────────────────────────────────────

  /// Must be called by the widget from `onChanged` on every user keystroke.
  ///
  /// Diffs [newText] against the last known text, updates link ranges
  /// accordingly, and runs URL auto-detection on the changed region.
  void reconcile(String newText) {
    final oldText = _previousText;
    if (newText == oldText) return;

    final delta = newText.length - oldText.length;

    // Find the first point where the two strings diverge.
    int changeStart = 0;
    final minLen = oldText.length < newText.length ? oldText.length : newText.length;
    while (changeStart < minLen &&
        oldText[changeStart] == newText[changeStart]) {
      changeStart++;
    }

    if (delta > 0) {
      _shiftForInsertion(changeStart, delta);
    } else if (delta < 0) {
      _shiftForDeletion(changeStart, -delta);
    }

    _previousText = newText;
    _autoDetectUrls(newText, changeStart, delta);
  }

  // ── Range maths ────────────────────────────────────────────────────────────

  void _shiftForInsertion(int at, int count) {
    for (final ann in _links) {
      if (at <= ann.start) {
        // Insertion before or at the start — shift the whole annotation.
        ann.start += count;
        ann.end += count;
      } else if (at < ann.end) {
        // Insertion strictly inside — extend the annotation to include
        // the new characters (typing inside a link keeps the link alive).
        ann.end += count;
      }
      // at >= ann.end: insertion after, no change.
    }
  }

  void _shiftForDeletion(int from, int count) {
    final to = from + count;
    _links.removeWhere((ann) {
      ann.start = _collapsePos(ann.start, from, to, count);
      ann.end = _collapsePos(ann.end, from, to, count);
      return ann.start >= ann.end; // Annotation fully consumed — drop it.
    });
  }

  /// Adjusts a single text position [pos] after deleting `[from, to)`.
  static int _collapsePos(int pos, int from, int to, int count) {
    if (pos <= from) return pos;        // Before deletion — unchanged.
    if (pos < to) return from;          // Inside deletion — collapse to start.
    return pos - count;                 // After deletion — shift left.
  }

  void _removeLinksOverlapping(int start, int end) {
    _links.removeWhere((ann) => ann.start < end && ann.end > start);
  }

  // ── URL auto-detection ─────────────────────────────────────────────────────

  void _autoDetectUrls(String newText, int changeStart, int delta) {
    if (delta <= 0) return; // Only detect on insertions.

    if (delta == 1) {
      // Single character typed: check if previous word is now a complete URL.
      final ch = newText[changeStart];
      if (ch == ' ' || ch == '\n' || ch == '\t') {
        _detectUrlBeforeCursor(newText, changeStart);
      }
    } else {
      // Multi-character insertion (paste): scan the entire inserted region.
      _detectUrlsInRegion(newText, changeStart, changeStart + delta);

      // Also check the word immediately after the insertion endpoint in case
      // the paste completed a partial URL that was already present.
      _detectUrlBeforeCursor(newText, changeStart + delta);
    }
  }

  /// Checks whether the token immediately before [cursorPos] in [text] is a URL.
  void _detectUrlBeforeCursor(String text, int cursorPos) {
    if (cursorPos == 0) return;
    int wordStart = cursorPos - 1;
    // Walk back to the previous word boundary.
    while (wordStart > 0 && !_isWordBoundary(text[wordStart - 1])) {
      wordStart--;
    }
    if (wordStart >= cursorPos) return;
    final word = text.substring(wordStart, cursorPos);
    if (UrlDetector.isUrl(word) && _linkAt(wordStart) == null) {
      _removeLinksOverlapping(wordStart, cursorPos);
      _links.add(LinkAnnotation(
        start: wordStart,
        end: cursorPos,
        url: UrlDetector.normalise(word),
      ));
    }
  }

  /// Scans `text[regionStart, regionEnd)` for all URLs and annotates them.
  void _detectUrlsInRegion(String text, int regionStart, int regionEnd) {
    final snippet = text.substring(regionStart, regionEnd);
    for (final match in UrlDetector.findAll(snippet)) {
      final start = regionStart + match.start;
      final end = regionStart + match.end;
      if (_linkAt(start) == null) {
        _removeLinksOverlapping(start, end);
        _links.add(LinkAnnotation(
          start: start,
          end: end,
          url: UrlDetector.normalise(match.group(0)!),
        ));
      }
    }
  }

  static bool _isWordBoundary(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r';

  // ── buildTextSpan ──────────────────────────────────────────────────────────
  //
  // This override is the key to making coloured links appear inside a standard
  // TextField while keeping iOS magnifier, text selection, composing indicators
  // and every other native editing behaviour intact.
  //
  // IMPORTANT: the child TextSpans must NOT carry TapGestureRecognizers here —
  // TextField ignores them.  Link tapping is handled at the widget level via a
  // GestureDetector and TextPainter hit-testing.

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final txt = text;
    final sorted = _sortedLinks();

    // Fast path: no links → let the default composing handling work normally.
    if (sorted.isEmpty) {
      return _defaultSpan(txt, style, withComposing);
    }

    final composing = value.composing;
    final hasComposing = withComposing &&
        value.isComposingRangeValid &&
        composing != TextRange.empty;

    // Build the styled spans list, then (if needed) splice composing underline.
    final rawSpans = _buildLinkSpans(txt, sorted, style);

    if (!hasComposing) {
      return TextSpan(children: rawSpans, style: style);
    }

    // Re-split any span that overlaps the composing region and add the IME
    // underline so CJK / other IME input renders correctly.
    final composingStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
    );
    final spliced = _spliceComposing(rawSpans, txt, composing, composingStyle);
    return TextSpan(children: spliced, style: style);
  }

  List<InlineSpan> _buildLinkSpans(
      String txt,
      List<LinkAnnotation> sorted,
      TextStyle? baseStyle,
      ) {
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final ann in sorted) {
      if (ann.start > cursor) {
        spans.add(TextSpan(
          text: txt.substring(cursor, ann.start),
          style: baseStyle,
        ));
      }
      final visited = LinkVisitStore.instance.hasVisited(ann.url);
      final linkColor =
      visited ? const Color(0xFF6A0DAD) : const Color(0xFF1A73E8);
      spans.add(TextSpan(
        text: txt.substring(ann.start, ann.end),
        style: (baseStyle ?? const TextStyle()).copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
      ));
      cursor = ann.end;
    }

    if (cursor < txt.length) {
      spans.add(TextSpan(text: txt.substring(cursor), style: baseStyle));
    }

    return spans;
  }

  /// Splices composing-region underline into an already-built span list.
  /// Walks character positions accumulated from the spans to find overlaps.
  List<InlineSpan> _spliceComposing(
      List<InlineSpan> spans,
      String txt,
      TextRange composing,
      TextStyle composingStyle,
      ) {
    final result = <InlineSpan>[];
    int charPos = 0;

    for (final span in spans) {
      if (span is! TextSpan || span.text == null) {
        result.add(span);
        continue;
      }
      final spanText = span.text!;
      final spanStart = charPos;
      final spanEnd = charPos + spanText.length;
      charPos = spanEnd;

      final overlapStart =
      composing.start > spanStart ? composing.start : spanStart;
      final overlapEnd =
      composing.end < spanEnd ? composing.end : spanEnd;

      if (overlapStart >= overlapEnd) {
        // No overlap — keep the span as-is.
        result.add(span);
        continue;
      }

      // Split into up to three sub-spans: before, composing, after.
      if (overlapStart > spanStart) {
        result.add(TextSpan(
          text: spanText.substring(0, overlapStart - spanStart),
          style: span.style,
        ));
      }
      result.add(TextSpan(
        text: spanText.substring(
          overlapStart - spanStart,
          overlapEnd - spanStart,
        ),
        style: (span.style ?? const TextStyle()).merge(composingStyle),
      ));
      if (overlapEnd < spanEnd) {
        result.add(TextSpan(
          text: spanText.substring(overlapEnd - spanStart),
          style: span.style,
        ));
      }
    }

    return result;
  }

  TextSpan _defaultSpan(String txt, TextStyle? style, bool withComposing) {
    final composing = value.composing;
    if (!withComposing ||
        !value.isComposingRangeValid ||
        composing == TextRange.empty) {
      return TextSpan(text: txt, style: style);
    }
    final composingStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
    );
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: composing.textBefore(txt)),
        TextSpan(text: composing.textInside(txt), style: composingStyle),
        TextSpan(text: composing.textAfter(txt)),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<LinkAnnotation> _sortedLinks() =>
      (_links.toList())..sort((a, b) => a.start.compareTo(b.start));

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    super.dispose();
  }
}