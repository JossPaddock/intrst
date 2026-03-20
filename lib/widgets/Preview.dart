import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/Interest.dart';
import '../models/UserModel.dart';

class Preview extends StatefulWidget {
  const Preview({
    super.key,
    required this.uid,
    required this.alternateUid,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
    required this.onDrawerOpened,
    required this.onOpenMessages,
  });
  final String uid;
  final String alternateUid;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final void Function(int) onItemTapped;
  final bool signedIn;
  final VoidCallback onDrawerOpened;
  final void Function(String userUid, String userName) onOpenMessages;

  @override
  _InterestAlertDialogState createState() => _InterestAlertDialogState();
}

class _InterestAlertDialogState extends State<Preview> {
  List<Interest> _previewInterests = [];
  String _name = '';
  FirebaseUsersUtility fuu = FirebaseUsersUtility();
  CollectionReference users = FirebaseFirestore.instance.collection('users');

  bool _isFollowing = false;
  bool _followStateLoading = false;
  bool _followActionLoading = false;

  String _friendshipStatus = '';
  String _friendshipType = '';
  bool _friendStateLoading = false;
  bool _friendActionLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNameAndButtonLabels();
    _loadFollowState();
    _loadFriendshipState();
  }

  Future<void> _fetchNameAndButtonLabels() async {
    List<Interest> interests = await fuu.pullInterestsForUser(users, widget.alternateUid);
    String name = await fuu.lookUpNameByUserUid(users, widget.alternateUid);
    if (!mounted) return;
    setState(() {
      _previewInterests = interests;
      _name = name;
    });
  }

  Future<void> _loadFollowState() async {
    if (!widget.signedIn || widget.uid.isEmpty || widget.alternateUid.isEmpty || widget.uid == widget.alternateUid) return;
    setState(() => _followStateLoading = true);
    final isFollowing = await fuu.isFollowingUser(users, widget.uid, widget.alternateUid);
    if (!mounted) return;
    setState(() {
      _isFollowing = isFollowing;
      _followStateLoading = false;
    });
  }

  Future<void> _loadFriendshipState() async {
    if (!widget.signedIn || widget.uid.isEmpty || widget.alternateUid.isEmpty || widget.uid == widget.alternateUid) return;
    setState(() => _friendStateLoading = true);

    final query = await users.where('user_uid', isEqualTo: widget.uid).limit(1).get();

    if (query.docs.isNotEmpty) {
      final doc = await query.docs.first.reference
          .collection('friendships')
          .doc(widget.alternateUid)
          .get();

      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _friendshipStatus = doc.data()?['status'] ?? '';
          _friendshipType = doc.data()?['type'] ?? '';
          _friendStateLoading = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _friendshipStatus = '';
      _friendshipType = '';
      _friendStateLoading = false;
    });
  }

  Future<void> _toggleFollowState() async {
    if (!widget.signedIn) {
      Navigator.pop(context);
      widget.onItemTapped(1);
      return;
    }
    setState(() => _followActionLoading = true);
    final nowFollowing = await fuu.toggleFollowUser(users, widget.uid, widget.alternateUid);
    if (!mounted) return;
    setState(() {
      _isFollowing = nowFollowing;
      _followActionLoading = false;
    });
  }

  Future<void> _handleFriendAction() async {
    if (!widget.signedIn) {
      Navigator.pop(context);
      widget.onItemTapped(1);
      return;
    }

    setState(() => _friendActionLoading = true);

    try {
      if (_friendshipStatus == '') {
        await fuu.sendFriendRequest(users, widget.uid, widget.alternateUid);
      } else if (_friendshipStatus == 'requested' && _friendshipType == 'outgoing') {
        await fuu.resetFriendship(users, widget.uid, widget.alternateUid);
      } else if (_friendshipStatus == 'requested' && _friendshipType == 'incoming') {
        await fuu.approveFriendRequest(users, widget.uid, widget.alternateUid);
      } else if (_friendshipStatus == 'approved') {
        await fuu.resetFriendship(users, widget.uid, widget.alternateUid);
      }

      await _loadFriendshipState();
    } catch (e) {
      print("Friend action failed: $e");
    } finally {
      if (mounted) setState(() => _friendActionLoading = false);
    }
  }

  void _handlePreviewToInterestsWidgetFlow({String highlightedInterestId = ''}) {
    if (widget.signedIn) {
      UserModel userModel = Provider.of<UserModel>(context, listen: false);
      userModel.changeAlternateUid(widget.alternateUid);
      userModel.changeAlternateName(_name);

      final sanitizedInterestId = highlightedInterestId.trim();
      if (sanitizedInterestId.isNotEmpty) {
        userModel.setFeedInterestHighlight(ownerUid: widget.alternateUid, interestId: sanitizedInterestId);
      } else {
        userModel.clearFeedInterestHighlight();
      }
      widget.scaffoldKey.currentState?.openEndDrawer();
      widget.onDrawerOpened();
    } else {
      widget.onItemTapped(1);
      Navigator.of(context).pop(false);
    }
  }

  void _openMessagesFromPreview() {
    if (!widget.signedIn) {
      Navigator.pop(context);
      widget.onItemTapped(1);
      return;
    }
    widget.onOpenMessages(widget.alternateUid, _name);
    Navigator.pop(context);
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    String finalUrl = url.startsWith('http') ? url : 'http://$url';
    if (await canLaunch(finalUrl)) await launch(finalUrl);
  }

  String formatTextByWords(String text, int wordsPerLine) {
    final words = text.split(' ');
    final buffer = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      buffer.write(words[i]);
      if (i < words.length - 1) {
        if ((i + 1) % wordsPerLine == 0) buffer.write('\n');
        else buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  List<Interest> get _filteredInterests {
    // If viewing own profile, show everything
    if (widget.uid == widget.alternateUid) return _previewInterests;

    return _previewInterests.where((interest) {
      if (interest.privacy == 4) return true; // Public
      if (interest.privacy == 3 && _friendshipStatus == 'approved') return true; // Friends only
      if (interest.privacy == 2 && (_friendshipStatus == 'approved' || _isFollowing)) return true; // Friends & followers
      return false; // Private or unmatched
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    String friendLabel = "Add friend";
    IconData friendIcon = Icons.person_add;

    if (_friendshipStatus == 'requested') {
      if (_friendshipType == 'outgoing') {
        friendLabel = "Cancel request";
        friendIcon = Icons.hourglass_empty;
      } else {
        friendLabel = "Accept friend";
        friendIcon = Icons.check_circle_outline;
      }
    } else if (_friendshipStatus == 'approved') {
      friendLabel = "Unfriend";
      friendIcon = Icons.person_remove;
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      title: Text(_name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16.0,
            runSpacing: 8.0,
            children: _filteredInterests.take(5).map((interest) {
              final interestLink = (interest.link ?? '').trim();
              return ElevatedButton(
                onPressed: () => interestLink.isEmpty
                    ? _handlePreviewToInterestsWidgetFlow(highlightedInterestId: interest.id)
                    : _launchUrl(interest.link),
                child: Text(
                  formatTextByWords(interest.name, 3),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: interestLink.isEmpty ? Colors.black : Colors.blue,
                    decoration: interestLink.isEmpty ? TextDecoration.none : TextDecoration.underline,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16.0),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              ElevatedButton.icon(
                onPressed: _openMessagesFromPreview,
                icon: const Icon(Icons.chat),
                label: const Text('Chat', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton.icon(
                onPressed: _handlePreviewToInterestsWidgetFlow,
                icon: const Icon(Icons.add),
                label: const Text('All interests', style: TextStyle(fontSize: 12)),
              ),
              if (widget.signedIn && widget.uid != widget.alternateUid)
                ElevatedButton.icon(
                  onPressed: (_followStateLoading || _followActionLoading) ? null : _toggleFollowState,
                  icon: _followActionLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_isFollowing ? Icons.person_remove : Icons.person_add),
                  label: Text(_isFollowing ? 'Unfollow' : 'Follow', style: const TextStyle(fontSize: 12)),
                ),
              if (widget.signedIn && widget.uid != widget.alternateUid)
                ElevatedButton.icon(
                  onPressed: (_friendActionLoading || _friendStateLoading) ? null : _handleFriendAction,
                  icon: (_friendActionLoading || _friendStateLoading)
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(friendIcon),
                  label: Text(friendLabel, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}