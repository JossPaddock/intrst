import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final bool isSender;

  /// Whether the message has been rewritten since it was sent. Shown as a
  /// small "(edited)" marker so the other participant can tell the text they
  /// are reading is not what first arrived.
  final bool isEdited;

  /// Offered only for the viewer's own, still-editable messages. Null hides
  /// the edit affordance entirely.
  final VoidCallback? onEdit;

  ChatBubble({
    required this.message,
    required this.isSender,
    this.isEdited = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
      decoration: BoxDecoration(
        color: isSender ? Colors.blue : Colors.red,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: isSender ? Radius.circular(20) : Radius.zero,
          bottomRight: isSender ? Radius.zero : Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(
              color: isSender ? Colors.white : Colors.black,
              fontSize: 17.0,
            ),
          ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '(edited)',
                key: const Key('chat_bubble_edited_marker'),
                style: TextStyle(
                  color: (isSender ? Colors.white : Colors.black)
                      .withValues(alpha: 0.7),
                  fontSize: 11.0,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onEdit != null && isSender) _EditButton(onTap: onEdit!),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Pencil shown next to the viewer's own editable messages. Kept small and
/// outside the bubble so it never reflows the message text.
class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('chat_bubble_edit_button'),
      icon: const Icon(Icons.edit, size: 16),
      color: Colors.grey[600],
      splashRadius: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: 'Edit message',
      onPressed: onTap,
    );
  }
}
