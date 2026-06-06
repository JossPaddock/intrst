import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/DateTimeUtility.dart';
import 'package:intrst/widgets/ChatBubble.dart';

import '../utility/FirebaseUsersUtility.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.uid, required this.documentData});

  final String uid;
  final Map<String, dynamic> documentData;

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
    for (final value in raw.values) {
      if (value is! Map) continue;
      parsed.add({
        'message_content': value['message_content'],
        'timestamp': value['timestamp'] != null
            ? (value['timestamp'] as Timestamp).toDate()
            : DateTime.now(),
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
                  message: _dtu.getFormattedTime(message['timestamp']),
                  child: ChatBubble(
                    message: message['message_content'],
                    isSender: isUserMessage,
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