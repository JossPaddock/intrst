import 'package:flutter/material.dart';

/// Shown in place of the message input when a 1:1 conversation is blocked.
///
/// The wording depends on who blocked whom:
///  - if the current viewer is the blocker, they are told they blocked the
///    other person and how to undo it;
///  - if the other person blocked the viewer, the viewer is told, without
///    revealing that they were blocked, that messages aren't being accepted.
class BlockedMessageNotice extends StatelessWidget {
  const BlockedMessageNotice({
    super.key,
    required this.viewerIsBlocker,
    required this.otherDisplayName,
  });

  /// True when the current viewer is the one who blocked the other user.
  /// When both sides have blocked each other this should be true, so the
  /// viewer always sees the actionable "unblock" copy for their own block.
  final bool viewerIsBlocker;

  /// Display name of the other conversation participant.
  final String otherDisplayName;

  /// Copy shown to the person who did the blocking.
  static String blockerMessage(String otherDisplayName) =>
      'You have blocked $otherDisplayName, unblock them to continue messaging this user.';

  /// Copy shown to the person who was blocked. Intentionally does not reveal
  /// that a block is in place.
  static const String blockedMessage =
      'This person is not accepting messages right now.';

  String get message =>
      viewerIsBlocker ? blockerMessage(otherDisplayName) : blockedMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
