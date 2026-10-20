import 'package:flutter/material.dart';

import '../utility/MessageEditPolicy.dart';

/// Modal that lets the author rewrite one already-sent message.
///
/// Returns the new content when the user saves, or null when they cancel.
/// Save stays disabled until the text is a valid edit under
/// [MessageEditPolicy], so the caller never has to handle a no-op write.
class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({super.key, required this.originalContent});

  final String originalContent;

  /// Shows the dialog and resolves to the new content, or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String originalContent,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => EditMessageDialog(originalContent: originalContent),
    );
  }

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.originalContent);

  bool get _canSave => MessageEditPolicy.isValidEdit(
        original: widget.originalContent,
        edited: _controller.text,
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(MessageEditPolicy.normalize(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('edit_message_dialog'),
      title: const Text('Edit message'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('edit_message_field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            minLines: 1,
            maxLines: 5,
            maxLength: MessageEditPolicy.maxLength,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Edit your message...',
            ),
          ),
          Text(
            'Everyone in the chat will see this message marked as edited.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('edit_message_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('edit_message_save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
