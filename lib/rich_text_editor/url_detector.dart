/// Utilities for detecting and normalising URLs inside plain text.
///
/// Three patterns are matched (case-insensitive):
///   1. Scheme-based  — `http://`, `https://`, `ftp://`
///   2. www-prefixed  — `www.example.com`
///   3. Bare domains  — `example.com`, `example.io`, etc. (common TLDs only,
///      to avoid false positives like file extensions).
abstract class UrlDetector {
  UrlDetector._();

  // ── Regex ─────────────────────────────────────────────────────────────────

  /// Matches URLs embedded anywhere in a longer string.
  static final RegExp _embeddedPattern = RegExp(
    r'(?:'
    // 1. Scheme-based URLs
    r'(?:https?|ftp)://[^\s<>"{}|\\^`\[\]]+'
    r'|'
    // 2. www-prefixed (no scheme required)
    r'www\.[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+(?:/[^\s<>"{}|\\^`\[\]]*)?'
    r'|'
    // 3. Bare domain with a recognised TLD
    // Negative look-behind so we don't match things like "3.14" or "v1.2"
    r'(?<![0-9@/\\.])(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)'
    r'(?:com|org|net|io|co|app|dev|edu|gov|mil|ai|me|tv|info|biz|gg|sh|ly|'
    r'uk|us|ca|au|nz|de|fr|jp|cn|ru|br|in|it|es|nl|se|no|dk|fi|sg|hk|mx)'
    r'(?:/[^\s<>"{}|\\^`\[\]]*)?'
    r')',
    caseSensitive: false,
  );

  /// Matches a string that is *entirely* a URL (possibly with surrounding
  /// whitespace).  Used to classify a single word / pasted token.
  static final RegExp _standalonePattern = RegExp(
    r'^\s*(?:'
    r'(?:https?|ftp)://[^\s<>"{}|\\^`\[\]]+'
    r'|'
    r'www\.[a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)+(?:/[^\s<>"{}|\\^`\[\]]*)?'
    r'|'
    r'(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)'
    r'(?:com|org|net|io|co|app|dev|edu|gov|mil|ai|me|tv|info|biz|gg|sh|ly|'
    r'uk|us|ca|au|nz|de|fr|jp|cn|ru|br|in|it|es|nl|se|no|dk|fi|sg|hk|mx)'
    r'(?:/[^\s<>"{}|\\^`\[\]]*)?'
    r')\s*$',
    caseSensitive: false,
  );

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all URL matches found in [text], in left-to-right order.
  static Iterable<RegExpMatch> findAll(String text) =>
      _embeddedPattern.allMatches(text);

  /// Returns `true` if [text] (ignoring surrounding whitespace) is a single URL.
  static bool isUrl(String text) => _standalonePattern.hasMatch(text);

  /// Ensures [url] has an `https://` (or existing) scheme so it can be opened
  /// by a URL launcher.
  ///
  /// Examples
  /// ─────────
  ///   `"google.com"`       → `"https://google.com"`
  ///   `"www.google.com"`   → `"https://www.google.com"`
  ///   `"http://google.com"` → unchanged
  static String normalise(String url) {
    final lower = url.toLowerCase().trimLeft();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('ftp://')) {
      return url.trim();
    }
    return 'https://${url.trim()}';
  }
}