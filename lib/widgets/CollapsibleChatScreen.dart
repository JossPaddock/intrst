import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utility/FirebaseMessagesUtility.dart';
import '../utility/FirebaseUsersUtility.dart';
import 'ChatScreen.dart';

class CollapsibleChatScreen extends StatefulWidget {
  const CollapsibleChatScreen({
    super.key,
    this.showNameAtTop = true,
    this.autoOpen = false,
    this.isExpanded = false,
    required this.uid,
    required this.documentData,
    required this.documentReference,
    this.getMessages,
    this.onOpen,
    this.onClose,
  });

  final bool showNameAtTop;
  final bool autoOpen;
  final bool isExpanded;
  final Map<String, dynamic> documentData;
  final String uid;
  final DocumentReference documentReference;
  final void Function()? getMessages;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  @override
  State<CollapsibleChatScreen> createState() =>
      _CollapsibleChatContainerState();
}

class _CollapsibleChatContainerState extends State<CollapsibleChatScreen> {
  static const double _webConversationMaxWidth = 500;
  final TextEditingController _sendMessageController = TextEditingController();
  final FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users =
      FirebaseFirestore.instance.collection('users');

  bool _isExpanded = false;
  bool _isLoading = false;
  bool hasNotification = false;
  int notificationCount = 0;
  List<String> _participantNames = <String>[];
  String _participantKey = '';

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.autoOpen || widget.isExpanded;
    _participantKey = _participantUidsKey(widget.documentData);
    _loadParticipantNames();
    _loadNotificationCount();
    if (_isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markConversationRead();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CollapsibleChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final latestParticipantKey = _participantUidsKey(widget.documentData);
    if (latestParticipantKey != _participantKey) {
      _participantKey = latestParticipantKey;
      _loadParticipantNames();
    }

    if (!widget.autoOpen && widget.isExpanded && !_isExpanded) {
      _expandChat(notifyParent: false);
    }

    if (!widget.autoOpen && !widget.isExpanded && _isExpanded) {
      setState(() {
        _isExpanded = false;
      });
    }

    if (widget.autoOpen && !_isExpanded) {
      _expandChat(notifyParent: false);
    }
  }

  @override
  void dispose() {
    _sendMessageController.dispose();
    super.dispose();
  }

  String _participantUidsKey(Map<String, dynamic> data) {
    final userUids = ((data['user_uids'] as List?) ?? <dynamic>[])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    return userUids.join(',');
  }

  Future<void> _loadParticipantNames() async {
    final otherUids =
        ((widget.documentData['user_uids'] as List?) ?? <dynamic>[])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty && value != widget.uid)
            .toList();

    if (otherUids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _participantNames = <String>[];
      });
      return;
    }

    final names = await Future.wait(
      otherUids.map((uid) => fuu.lookUpNameByUserUid(users, uid)),
    );

    if (!mounted) return;
    setState(() {
      _participantNames = names
          .map((name) {
            final cleaned = name.trim();
            if (cleaned.isEmpty || cleaned.length == 1) {
              return 'Deleted account';
            }
            return cleaned;
          })
          .where((name) => name.isNotEmpty)
          .toList();
    });
  }

  Future<void> _loadNotificationCount() async {
    final count = await fuu.retrieveNotificationCount(
      users,
      widget.uid,
      widget.documentReference.path,
    );

    if (!mounted) return;
    setState(() {
      if (count > 0) {
        hasNotification = true;
        notificationCount = count;
      } else {
        hasNotification = false;
        notificationCount = 0;
      }
    });
  }

  Future<void> _markConversationRead() async {
    await fuu.removeUnreadNotifications(
        widget.documentReference.path, widget.uid);
    await _loadNotificationCount();
  }

  Future<void> _expandChat({required bool notifyParent}) async {
    if (_isExpanded) return;

    setState(() {
      _isLoading = true;
    });

    await _markConversationRead();

    if (!mounted) return;
    setState(() {
      _isExpanded = true;
      _isLoading = false;
    });

    if (notifyParent) {
      widget.onOpen?.call();
    }
  }

  void _collapseChat({required bool notifyParent}) {
    if (!_isExpanded) return;

    setState(() {
      _isExpanded = false;
    });

    if (notifyParent) {
      widget.onClose?.call();
    }
  }

  Future<void> _toggleExpanded() async {
    if (_isExpanded) {
      _collapseChat(notifyParent: true);
      return;
    }
    await _expandChat(notifyParent: true);
  }

  void _showDeleteDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    bool isCorrect = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm Deletion'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Type 'delete' to confirm."),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    onChanged: (value) {
                      setState(() {
                        isCorrect = value.trim().toLowerCase() == 'delete';
                      });
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'type here...',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isCorrect
                      ? () async {
                          Navigator.of(context).pop();
                          final userUids =
                              await fmu.retrieveMessageDocumentUserUids(
                            widget.documentReference,
                          );
                          await Future.wait(userUids.map((userUid) =>
                              fuu.removeUnreadNotifications(
                                  widget.documentReference.path,
                                  userUid.toString())));
                          await fmu
                              .deleteMessageDocument(widget.documentReference);
                          widget.getMessages?.call();
                        }
                      : null,
                  child: const Text('Really Delete!'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _latestMessageData() {
    final conversationRaw = widget.documentData['conversation'];
    if (conversationRaw is! Map || conversationRaw.isEmpty) {
      return null;
    }

    Map<String, dynamic>? latest;
    DateTime latestTimestamp = DateTime.fromMillisecondsSinceEpoch(0);

    for (final value in conversationRaw.values) {
      if (value is! Map) continue;
      final message = Map<String, dynamic>.from(value);
      final timestampRaw = message['timestamp'];
      final timestamp =
          timestampRaw is Timestamp ? timestampRaw.toDate() : DateTime.now();

      if (timestamp.isAfter(latestTimestamp)) {
        latestTimestamp = timestamp;
        latest = message;
      }
    }

    return latest;
  }

  DateTime? _latestMessageTimestamp() {
    final latest = _latestMessageData();
    final timestampRaw = latest?['timestamp'];
    if (timestampRaw is Timestamp) {
      return timestampRaw.toDate();
    }
    return null;
  }

  String _latestMessagePreview() {
    final latest = _latestMessageData();
    if (latest == null) {
      return 'No messages yet';
    }

    final content = (latest['message_content'] ?? '').toString().trim();
    final senderUid = (latest['user_uid'] ?? '').toString().trim();
    final prefix = senderUid == widget.uid ? 'You: ' : '';

    if (content.isEmpty) {
      return '${prefix}Sent a message';
    }

    if (content.length > 80) {
      return '$prefix${content.substring(0, 80)}...';
    }

    return '$prefix$content';
  }

  String _formatTimestampLabel(BuildContext context, DateTime timestamp) {
    final now = DateTime.now();
    final timestampDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);
    final nowDate = DateTime(now.year, now.month, now.day);

    if (timestampDate == nowDate) {
      return TimeOfDay.fromDateTime(timestamp).format(context);
    }

    final dayDiff = nowDate.difference(timestampDate).inDays;
    if (dayDiff < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[timestamp.weekday - 1];
    }

    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }

  String _conversationTitle() {
    if (_participantNames.isEmpty) {
      return 'Conversation';
    }
    if (_participantNames.length == 1) {
      return _participantNames.first;
    }
    if (_participantNames.length == 2) {
      return '${_participantNames[0]}, ${_participantNames[1]}';
    }
    return '${_participantNames[0]}, ${_participantNames[1]} +${_participantNames.length - 2}';
  }

  Widget _buildParticipantScroller() {
    if (_participantNames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _participantNames.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final name = _participantNames[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                name,
                style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handleSendMessage() async {
    final text = _sendMessageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final messageUuid = await fmu.sendMessage(
      text,
      widget.documentReference,
      widget.uid,
    );
    if (messageUuid == 'Error') {
      return;
    }

    if (!mounted) return;
    setState(() {
      _sendMessageController.clear();
    });

    await fuu.incrementSentMessageCount(users, widget.uid, 1);

    final userUids =
        await fmu.retrieveMessageDocumentUserUids(widget.documentReference);

    for (final id in userUids) {
      final recipientUid = id.toString();
      if (recipientUid.isEmpty || recipientUid == widget.uid) {
        continue;
      }

      await fuu.incrementReceivedMessageCount(users, recipientUid, 1);
      await fuu.addUnreadNotification(
          'users', recipientUid, widget.documentReference.path, messageUuid);
      await fuu.createMessageActivity(
        senderUid: widget.uid,
        recipientUid: recipientUid,
        messageContent: text,
      );
    }

    fuu.updateUnreadNotificationCounts('users');
  }

  Widget _buildHeader(BuildContext context) {
    final fullNames = _participantNames.join(', ');
    final latestTimestamp = _latestMessageTimestamp();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF0D3B66),
            foregroundColor: Colors.white,
            child: Icon(
                _participantNames.length > 1 ? Icons.groups_2 : Icons.person),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showNameAtTop)
                  Tooltip(
                    message: fullNames,
                    child: Text(
                      _conversationTitle(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _latestMessagePreview(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                _buildParticipantScroller(),
              ],
            ),
          ),
          if (!widget.autoOpen)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (latestTimestamp != null)
                  Text(
                    _formatTimestampLabel(context, latestTimestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasNotification && notificationCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          notificationCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down),
                      onPressed: _isLoading ? null : _toggleExpanded,
                      tooltip: _isExpanded ? 'Collapse' : 'Expand',
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _showDeleteDialog(context);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete chat'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody() {
    if (!_isExpanded) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Divider(height: 1),
        SizedBox(
          height: widget.autoOpen ? 150 : 300,
          child: StreamBuilder<DocumentSnapshot>(
            stream: widget.documentReference.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Something went wrong.'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text('No messages found'));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;
              if (_isLoading) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                });
              }

              return ChatScreen(
                uid: widget.uid,
                documentData: data,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sendMessageController,
                  decoration: InputDecoration(
                    fillColor: Colors.white,
                    filled: true,
                    hintText: 'Send message',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onSubmitted: (_) => _handleSendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF0D3B66),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _handleSendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatMaxWidth = kIsWeb ? _webConversationMaxWidth : double.infinity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: chatMaxWidth),
          child: SizedBox(
            width: double.infinity,
            child: Card(
              elevation: 1.5,
              shadowColor: Colors.black12,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showNameAtTop || !widget.autoOpen)
                      _buildHeader(context),
                    _buildExpandedBody(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
