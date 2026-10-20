/// Pure rules deciding whether a message in a conversation may be edited, and
/// whether a proposed edit is worth writing.
///
/// Kept free of Firebase and Flutter so the same rules can be asserted by the
/// unit tests in `lib/qa/unit/` and reused by both the chat UI (to decide
/// whether to offer the Edit affordance) and the write path (to reject an edit
/// that slipped through the UI).
class MessageEditPolicy {
  const MessageEditPolicy._();

  /// How long after sending a message stays editable.
  ///
  /// A window rather than "forever" so a conversation the other person has
  /// already read and replied to cannot be rewritten underneath them.
  static const Duration editWindow = Duration(minutes: 15);

  /// Maximum length of an edited message, matching what the composer allows.
  static const int maxLength = 2000;

  /// Whether [viewerUid] may edit a message sent by [senderUid].
  ///
  /// Only the author may edit, only inside [editWindow], and never in a
  /// conversation where messaging is blocked in either direction (see
  /// `MessageBlockPolicy`). A message with no [sentAt] has not been confirmed
  /// by the server yet, so it is not editable.
  static bool canEdit({
    required String senderUid,
    required String viewerUid,
    required bool conversationBlocked,
    required DateTime? sentAt,
    required DateTime now,
  }) {
    if (conversationBlocked) return false;
    if (viewerUid.isEmpty || senderUid.isEmpty) return false;
    if (senderUid != viewerUid) return false;
    if (sentAt == null) return false;
    return !isExpired(sentAt: sentAt, now: now);
  }

  /// Whether the edit window has closed for a message sent at [sentAt].
  ///
  /// A [sentAt] in the future (clock skew between the device and the server)
  /// counts as not expired rather than as an error.
  static bool isExpired({required DateTime sentAt, required DateTime now}) =>
      now.difference(sentAt) > editWindow;

  /// How long is left to edit a message sent at [sentAt], never negative.
  static Duration remainingWindow({
    required DateTime sentAt,
    required DateTime now,
  }) {
    final remaining = editWindow - now.difference(sentAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// The text that would actually be stored for [input]: trimmed, and with
  /// trailing blank lines from a multi-line composer removed.
  static String normalize(String input) => input.trim();

  /// Whether [edited] is a change worth writing over [original].
  ///
  /// An edit that only adds surrounding whitespace, or that empties the
  /// message, is rejected — deleting is a separate action, not an edit.
  static bool isValidEdit({
    required String original,
    required String edited,
  }) {
    final next = normalize(edited);
    if (next.isEmpty) return false;
    if (next.length > maxLength) return false;
    return next != normalize(original);
  }
}
