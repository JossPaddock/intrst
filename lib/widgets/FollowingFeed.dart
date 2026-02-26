import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FollowingFeed extends StatefulWidget {
  const FollowingFeed({
    super.key,
    required this.userUid,
    required this.onOpenInterests,
    required this.onOpenMessages,
    required this.onOpenUserOnMap,
  });

  final String userUid;
  final Future<void> Function(
      String userUid, String userName, String interestId) onOpenInterests;
  final void Function(String userUid, String userName) onOpenMessages;
  final Future<void> Function(String userUid, String userName) onOpenUserOnMap;

  @override
  State<FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<FollowingFeed> {
  static const double _feedItemWidth = 500;
  static const double _feedItemHorizontalInset = 24;
  static const double _scrollToTopThreshold = 260;
  late Stream<QuerySnapshot> _currentUserStream;
  late Stream<QuerySnapshot> _activityStream;
  late final ScrollController _feedScrollController;
  bool _showScrollToTop = false;

  bool _isSelfProfileStatisticEventType(String type) {
    return type == 'longest_streak_milestone' ||
        type == 'messages_sent_milestone' ||
        type == 'messages_received_milestone';
  }

  bool _isSelfVisibleEventType(String type) {
    return _isSelfProfileStatisticEventType(type) || type == 'interest_posted';
  }

  String _extractFirstName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'User';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  void initState() {
    super.initState();
    _feedScrollController = ScrollController()..addListener(_handleFeedScroll);
    _buildStreams();
  }

  @override
  void didUpdateWidget(covariant FollowingFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userUid != widget.userUid) {
      _buildStreams();
      if (_showScrollToTop) {
        setState(() {
          _showScrollToTop = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_feedScrollController.hasClients) return;
        _feedScrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _feedScrollController.removeListener(_handleFeedScroll);
    _feedScrollController.dispose();
    super.dispose();
  }

  void _buildStreams() {
    final users = FirebaseFirestore.instance.collection('users');
    final feed = FirebaseFirestore.instance.collection('activity_feed');
    _currentUserStream =
        users.where('user_uid', isEqualTo: widget.userUid).limit(1).snapshots();
    _activityStream =
        feed.where('target_uids', arrayContains: widget.userUid).snapshots();
  }

  void _handleFeedScroll() {
    if (!_feedScrollController.hasClients) return;
    final shouldShow = _feedScrollController.offset > _scrollToTopThreshold;
    if (shouldShow != _showScrollToTop && mounted) {
      setState(() {
        _showScrollToTop = shouldShow;
      });
    }
  }

  Future<void> _scrollFeedToTop() async {
    if (!_feedScrollController.hasClients) return;
    await _feedScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _deletePostedInterestActivity(String activityDocId) async {
    final sanitizedId = activityDocId.trim();
    if (sanitizedId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('activity_feed')
          .doc(sanitizedId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post removed from feed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete post: $e')),
      );
    }
  }

  Future<void> _confirmDeletePostedInterestActivity(
      String activityDocId) async {
    if (activityDocId.trim().isEmpty) return;
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete feed post?'),
              content: const Text(
                'This will delete the post from your feed and all followers.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) return;
    await _deletePostedInterestActivity(activityDocId);
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final eventTime = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final diff = now.difference(eventTime);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final month = eventTime.month.toString().padLeft(2, '0');
    final day = eventTime.day.toString().padLeft(2, '0');
    final year = eventTime.year.toString();
    return '$month/$day/$year';
  }

  String _messagePreview(String value) {
    final cleaned = value.trim().replaceAll('\n', ' ');
    if (cleaned.length <= 140) return cleaned;
    return '${cleaned.substring(0, 140)}...';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userUid.isEmpty) {
      return const Center(
        child: Text('Sign in to see activity from people you follow.'),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _currentUserStream,
      builder: (context, currentUserSnapshot) {
        if (currentUserSnapshot.hasError) {
          return Center(
            child: Text(
                'Error loading feed settings: ${currentUserSnapshot.error}'),
          );
        }

        if (!currentUserSnapshot.hasData ||
            currentUserSnapshot.data!.docs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final currentUserData =
            currentUserSnapshot.data!.docs.first.data() as Map<String, dynamic>;
        final followingUids = (currentUserData['following_uids'] as List?)
                ?.map((uid) => uid.toString())
                .where((uid) => uid.isNotEmpty)
                .toSet() ??
            <String>{};

        return StreamBuilder<QuerySnapshot>(
          stream: _activityStream,
          builder: (context, activitySnapshot) {
            if (activitySnapshot.hasError) {
              return Center(
                  child: Text('Error loading feed: ${activitySnapshot.error}'));
            }

            if (!activitySnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final entries = activitySnapshot.data?.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return <String, dynamic>{
                    ...data,
                    'activity_doc_id': doc.id,
                  };
                }).where((data) {
                  final actorUid = (data['actor_uid'] ?? '').toString();
                  final type = (data['type'] ?? '').toString();
                  if (followingUids.contains(actorUid)) {
                    return true;
                  }
                  return actorUid == widget.userUid &&
                      _isSelfVisibleEventType(type);
                }).toList() ??
                [];

            entries.sort((a, b) {
              final aTs = a['created_at'] as Timestamp?;
              final bTs = b['created_at'] as Timestamp?;
              return (bTs?.millisecondsSinceEpoch ?? 0)
                  .compareTo(aTs?.millisecondsSinceEpoch ?? 0);
            });

            if (entries.isEmpty) {
              return const Center(child: Text('No activity yet.'));
            }

            return Stack(
              children: [
                ListView.builder(
                  controller: _feedScrollController,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    final type = (item['type'] ?? '').toString();
                    final actorUid = (item['actor_uid'] ?? '').toString();
                    final actorName =
                        (item['actor_name'] ?? 'Unknown user').toString();
                    final interestId =
                        (item['interest_id'] ?? '').toString().trim();
                    final activityDocId =
                        (item['activity_doc_id'] ?? '').toString();
                    final createdAt = item['created_at'] as Timestamp?;

                    Widget action;
                    switch (type) {
                      case 'interest_created':
                        action = Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  widget.onOpenUserOnMap(actorUid, actorName),
                              child: Text(actorName),
                            ),
                            const Text(' created a new interest, '),
                            TextButton(
                              onPressed: () => widget.onOpenInterests(
                                  actorUid, actorName, interestId),
                              child: const Text('check it out here'),
                            ),
                          ],
                        );
                        break;
                      case 'interest_updated':
                        final interestName =
                            (item['interest_name'] ?? '').toString().trim();
                        final updateText = interestName.isEmpty
                            ? ' has updated their interest, '
                            : ' has updated their interest "$interestName", ';
                        action = Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  widget.onOpenUserOnMap(actorUid, actorName),
                              child: Text(actorName),
                            ),
                            Text(updateText),
                            TextButton(
                              onPressed: () => widget.onOpenInterests(
                                  actorUid, actorName, interestId),
                              child: const Text('check it out here'),
                            ),
                          ],
                        );
                        break;
                      case 'message_sent':
                        final messageContent = _messagePreview(
                          (item['message_content'] ?? '').toString(),
                        );
                        action = Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  widget.onOpenUserOnMap(actorUid, actorName),
                              child: Text(actorName),
                            ),
                            Text(' sent you a message "$messageContent", '),
                            TextButton(
                              onPressed: () =>
                                  widget.onOpenMessages(actorUid, actorName),
                              child: const Text('click here to chat'),
                            ),
                          ],
                        );
                        break;
                      case 'longest_streak_milestone':
                      case 'messages_sent_milestone':
                      case 'messages_received_milestone':
                        final feedMessage =
                            (item['feed_message'] ?? '').toString().trim();
                        if (feedMessage.isEmpty) {
                          action = const SizedBox.shrink();
                        } else {
                          action = Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(feedMessage),
                          );
                        }
                        break;
                      case 'interest_posted':
                        final interestName =
                            (item['interest_name'] ?? '').toString().trim();
                        final safeInterestName = interestName.isEmpty
                            ? 'this interest'
                            : interestName;
                        final postMessage =
                            (item['message_content'] ?? '').toString().trim();
                        final safePostMessage =
                            postMessage.isEmpty ? '(no message)' : postMessage;
                        final isOwnPost = actorUid == widget.userUid;
                        if (isOwnPost) {
                          action = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text('You posted: '),
                                  TextButton(
                                    onPressed: () => widget.onOpenInterests(
                                        actorUid, actorName, interestId),
                                    child: Text('"$safeInterestName"'),
                                  ),
                                  Text(
                                    ' with message: "$safePostMessage". This is viewable by anyone that follows you.',
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: activityDocId.isEmpty
                                      ? null
                                      : () =>
                                          _confirmDeletePostedInterestActivity(
                                              activityDocId),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete'),
                                ),
                              ),
                            ],
                          );
                        } else {
                          final actorFirstName = _extractFirstName(actorName);
                          action = Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    widget.onOpenUserOnMap(actorUid, actorName),
                                child: Text(actorFirstName),
                              ),
                              const Text(' posted an interest: '),
                              TextButton(
                                onPressed: () => widget.onOpenInterests(
                                    actorUid, actorName, interestId),
                                child: Text('"$safeInterestName"'),
                              ),
                              Text('"$safePostMessage"'),
                            ],
                          );
                        }
                        break;
                      default:
                        action = const SizedBox.shrink();
                    }

                    if (action is SizedBox) {
                      return const SizedBox.shrink();
                    }

                    final viewportWidth = MediaQuery.sizeOf(context).width;
                    final cardWidth = math
                        .max(
                          0,
                          math.min(
                            _feedItemWidth,
                            viewportWidth - _feedItemHorizontalInset,
                          ),
                        )
                        .toDouble();

                    return Center(
                      child: SizedBox(
                        width: cardWidth,
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                action,
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 8.0, bottom: 4.0),
                                  child: Text(
                                    _formatTimestamp(createdAt),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_showScrollToTop)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'following_feed_scroll_to_top',
                      onPressed: _scrollFeedToTop,
                      child: const Icon(Icons.keyboard_arrow_up),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
