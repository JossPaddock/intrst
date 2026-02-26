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
  final Future<void> Function(String userUid, String userName) onOpenInterests;
  final void Function(String userUid, String userName) onOpenMessages;
  final Future<void> Function(String userUid, String userName) onOpenUserOnMap;

  @override
  State<FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<FollowingFeed> {
  late Stream<QuerySnapshot> _currentUserStream;
  late Stream<QuerySnapshot> _activityStream;

  @override
  void initState() {
    super.initState();
    _buildStreams();
  }

  @override
  void didUpdateWidget(covariant FollowingFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userUid != widget.userUid) {
      _buildStreams();
    }
  }

  void _buildStreams() {
    final users = FirebaseFirestore.instance.collection('users');
    final feed = FirebaseFirestore.instance.collection('activity_feed');
    _currentUserStream =
        users.where('user_uid', isEqualTo: widget.userUid).limit(1).snapshots();
    _activityStream =
        feed.where('target_uids', arrayContains: widget.userUid).snapshots();
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

        if (followingUids.isEmpty) {
          return const Center(
            child: Text('Follow people to see their activity here.'),
          );
        }

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

            final entries = activitySnapshot.data?.docs
                    .map((doc) => doc.data() as Map<String, dynamic>)
                    .where((data) {
                  final actorUid = (data['actor_uid'] ?? '').toString();
                  return followingUids.contains(actorUid);
                }).toList() ??
                [];

            entries.sort((a, b) {
              final aTs = a['created_at'] as Timestamp?;
              final bTs = b['created_at'] as Timestamp?;
              return (bTs?.millisecondsSinceEpoch ?? 0)
                  .compareTo(aTs?.millisecondsSinceEpoch ?? 0);
            });

            if (entries.isEmpty) {
              return const Center(
                child: Text('No activity yet from people you follow.'),
              );
            }

            return ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final item = entries[index];
                final type = (item['type'] ?? '').toString();
                final actorUid = (item['actor_uid'] ?? '').toString();
                final actorName =
                    (item['actor_name'] ?? 'Unknown user').toString();
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
                          onPressed: () =>
                              widget.onOpenInterests(actorUid, actorName),
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
                          onPressed: () =>
                              widget.onOpenInterests(actorUid, actorName),
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
                  default:
                    action = const SizedBox.shrink();
                }

                if (action is SizedBox) {
                  return const SizedBox.shrink();
                }

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        action,
                        Padding(
                          padding:
                              const EdgeInsets.only(left: 8.0, bottom: 4.0),
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
                );
              },
            );
          },
        );
      },
    );
  }
}
