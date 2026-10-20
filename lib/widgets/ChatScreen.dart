import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/DateTimeUtility.dart';
import 'package:intrst/utility/MessageEditPolicy.dart';
import 'package:intrst/widgets/ChatBubble.dart';
import 'package:intrst/widgets/EditMessageDialog.dart';

import '../utility/FirebaseUsersUtility.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.uid,
    required this.documentData,
    this.onEditMessage,
    this.conversationBlocked = false,
  });

  final String uid;
  final Map<String, dynamic> documentData;

  /// Persists an edit. Given the message's id and the new content, returns
  /// whether the write succeeded. Null means editing is unavailable (e.g. a
  /// read-only preview of a conversation).
  final Future<bool> Function(String messageId, String newContent)?
      onEditMessage;

  /// When true no message is editable — messaging is blocked in this
  /// conversation (see `MessageBlockPolicy`).
  final bool conversationBlocked;

  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final ScrollController scrollController = ScrollController();
  final FirebaseUsersUtility _fu = FirebaseUsersUtility();
  final DateTimeUtility _dtu = DateTimeUtility();
  final CollectionReference _users =
  FirebaseFirestore.instance.collection('users');

  // Stable sorted message list — only replaced when content actually changes.
  List<Map<String, dynamic>> _messages = [];

  // Cache of uid -> display name so we never re-fetch a name we already have.
  final Map<String, String> _nameCache = {};

  // Track which UIDs currently have an in-flight lookup so we don't
  // fire duplicate requests.
  final Set<String> _pendingLookups = {};

  // Whether the user has scrolled away from the latest message (bottom of
  // a reverse list = offset 0).
  bool _showScrollToBottom = false;

  // Threshold in logical pixels — within this distance of offset 0 we
  // consider the view "at the bottom" and hide the button.
  static const double _atBottomThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    _rebuildMessages(widget.documentData);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-process when the conversation data actually changed.
    if (widget.documentData != oldWidget.documentData) {
      _rebuildMessages(widget.documentData);
    }
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;

    // With reverse: true, offset 0 is the bottom (latest message).
    final isAtBottom = scrollController.offset <= _atBottomThreshold;
    if (isAtBottom != !_showScrollToBottom) {
      setState(() {
        _showScrollToBottom = !isAtBottom;
      });
    }
  }

  void _scrollToBottom() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Parse + sort messages from raw Firestore data, then kick off any
  /// missing name lookups. Calls setState once when names come back,
  /// not once per bubble.
  void _rebuildMessages(Map<String, dynamic> documentData) {
    final raw = documentData['conversation'];
    if (raw == null || raw is! Map) {
      if (_messages.isNotEmpty) {
        setState(() => _messages = []);
      }
      return;
    }

    final parsed = <Map<String, dynamic>>[];
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final timestampRaw = value['timestamp'];
      parsed.add({
        // The conversation map is keyed by the message's uuid; carrying it
        // through is what lets a bubble address its own message on edit.
        'id': entry.key.toString(),
        'message_content': value['message_content'],
        'timestamp':
            timestampRaw is Timestamp ? timestampRaw.toDate() : DateTime.now(),
        // Null until the message has been edited at least once.
        'sent_at': timestampRaw is Timestamp ? timestampRaw.toDate() : null,
        'edited_at': value['edited_at'] is Timestamp
            ? (value['edited_at'] as Timestamp).toDate()
            : null,
        'user_uid': value['user_uid'] ?? '',
      });
    }
    parsed.sort((a, b) =>
        (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

    // Update the list. We always replace since message content may have
    // changed even if the count is the same.
    setState(() => _messages = parsed);

    // Kick off name lookups only for UIDs we haven't resolved yet.
    final unseenUids = parsed
        .map((m) => m['user_uid'] as String)
        .where((uid) =>
    uid.isNotEmpty &&
        !_nameCache.containsKey(uid) &&
        !_pendingLookups.contains(uid))
        .toSet();

    if (unseenUids.isEmpty) return;

    for (final uid in unseenUids) {
      _pendingLookups.add(uid);
      _fu.lookUpNameByUserUid(_users, uid).then((name) {
        if (!mounted) return;
        _pendingLookups.remove(uid);
        final resolved =
        (name.trim().length <= 1) ? 'Deleted account' : name.trim();
        if (_nameCache[uid] != resolved) {
          setState(() => _nameCache[uid] = resolved);
        }
      });
    }
  }

  /// Whether the pencil should be offered on [message]. Recomputed on every
  /// build so the affordance disappears on its own once the edit window
  /// closes and the list rebuilds.
  bool _canEdit(Map<String, dynamic> message) {
    if (widget.onEditMessage == null) return false;
    return MessageEditPolicy.canEdit(
      senderUid: (message['user_uid'] ?? '').toString(),
      viewerUid: widget.uid,
      conversationBlocked: widget.conversationBlocked,
      sentAt: message['sent_at'] as DateTime?,
      now: DateTime.now(),
    );
  }

  /// The hover text on a bubble: when it was sent, plus when it was edited.
  String _tooltipFor(Map<String, dynamic> message) {
    final sent = _dtu.getFormattedTime(message['timestamp']);
    final editedAt = message['edited_at'] as DateTime?;
    if (editedAt == null) return sent;
    return '$sent\nEdited ${_dtu.getFormattedTime(editedAt)}';
  }

  Future<void> _promptEdit(Map<String, dynamic> message) async {
    final onEditMessage = widget.onEditMessage;
    if (onEditMessage == null) return;

    final messageId = (message['id'] ?? '').toString();
    final original = (message['message_content'] ?? '').toString();
    if (messageId.isEmpty) return;

    final updated = await EditMessageDialog.show(
      context,
      originalContent: original,
    );
    if (updated == null || !mounted) return;

    // Re-check the window: the dialog may have been open long enough for the
    // message to become uneditable while the user was typing.
    if (!_canEdit(message)) {
      _showEditFailure('That message can no longer be edited.');
      return;
    }

    final saved = await onEditMessage(messageId, updated);
    if (!mounted || saved) return;
    _showEditFailure('Could not edit that message. Please try again.');
  }

  void _showEditFailure(String reason) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(reason)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      width: double.infinity,
      child: Stack(
        children: [
          ListView.builder(
            reverse: true,
            controller: scrollController,
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final uid = message['user_uid'] as String;
              final isUserMessage = uid == widget.uid;

              // Read from cache — no FutureBuilder, no waiting state, no flash.
              final displayName = _nameCache[uid] ?? '';

              return ListTile(
                title: displayName.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                  padding: const EdgeInsets.only(left: 15, right: 15),
                  child: Text(
                    displayName,
                    style: const TextStyle(fontSize: 13.0),
                    textAlign:
                    isUserMessage ? TextAlign.right : TextAlign.left,
                  ),
                ),
                subtitle: Tooltip(
                  message: _tooltipFor(message),
                  child: ChatBubble(
                    message: message['message_content'],
                    isSender: isUserMessage,
                    isEdited: message['edited_at'] != null,
                    onEdit: _canEdit(message)
                        ? () => _promptEdit(message)
                        : null,
                  ),
                ),
              );
            },
          ),

          // Floating scroll-to-bottom button — only shown when the user
          // has scrolled away from the latest message.
          if (_showScrollToBottom)
            Positioned(
              bottom: 8,
              right: 8,
              child: _ScrollToBottomButton(onTap: _scrollToBottom),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small self-contained widget so the button appearance is easy to tweak.
// ---------------------------------------------------------------------------
class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0D3B66),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}