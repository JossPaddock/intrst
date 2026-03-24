import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';

class FriendsManagerWidget extends StatefulWidget {
  final String currentUserUid;

  const FriendsManagerWidget({
    super.key,
    required this.currentUserUid,
  });

  @override
  _FriendsManagerWidgetState createState() => _FriendsManagerWidgetState();
}

class _FriendsManagerWidgetState extends State<FriendsManagerWidget> {
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users = FirebaseFirestore.instance.collection('users');

  bool _isLoading = true;
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _currentFriends = [];
  Set<String> _processingUids = {};

  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>? _requestsSub;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _requestsSub?.cancel();
    super.dispose();
  }

  Future<void> _setupListeners() async {
    try {
      // 1. Find the current user's document reference
      QuerySnapshot userSnap = await users.where('user_uid', isEqualTo: widget.currentUserUid).limit(1).get();

      if (userSnap.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      DocumentReference userDocRef = userSnap.docs.first.reference;

      // 2. Listen to incoming friend requests in real-time
      _requestsSub = userDocRef
          .collection('friendships')
          .where('status', isEqualTo: 'requested')
          .where('type', isEqualTo: 'incoming')
          .snapshots()
          .listen((snapshot) async {
        List<Map<String, dynamic>> requestsData = [];
        for (var doc in snapshot.docs) {
          String senderUid = doc.id;
          String senderName = await fuu.lookUpNameByUserUid(users, senderUid);
          requestsData.add({'uid': senderUid, 'name': senderName});
        }
        if (mounted) setState(() => _incomingRequests = requestsData);
      });

      // 3. Listen to the user's main document for friends list changes
      _userSub = userDocRef.snapshots().listen((snapshot) async {
        if (!snapshot.exists) return;

        List<dynamic> friendUids = [];
        var data = snapshot.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('friends_uids')) {
          friendUids = data['friends_uids'] ?? [];
        }

        List<Map<String, dynamic>> friendsData = [];
        for (String friendUid in friendUids) {
          String friendName = await fuu.lookUpNameByUserUid(users, friendUid);
          friendsData.add({'uid': friendUid, 'name': friendName});
        }

        if (mounted) {
          setState(() {
            _currentFriends = friendsData;
            _isLoading = false; // Turn off initial loading once we get our first data
          });
        }
      });

    } catch (e) {
      print("Error setting up listeners: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRequestAction(String targetUid, bool isAccepting, bool isUnfriending) async {
    setState(() => _processingUids.add(targetUid));

    try {
      if (isAccepting) {
        await fuu.approveFriendRequest(users, widget.currentUserUid, targetUid);
      } else {
        await fuu.resetFriendship(users, widget.currentUserUid, targetUid);
      }
      // Note: We no longer manually update _incomingRequests or _currentFriends here.
      // The Firestore streams will detect the backend change and update the UI automatically.
    } catch (e) {
      print("Action failed: $e");
    } finally {
      if (mounted) setState(() => _processingUids.remove(targetUid));
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Pending Requests (${_incomingRequests.length})"),
          if (_incomingRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("No pending friend requests.", style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _incomingRequests.length,
              itemBuilder: (context, index) {
                final request = _incomingRequests[index];
                final senderUid = request['uid'];
                final senderName = request['name'];
                final isProcessing = _processingUids.contains(senderUid);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(senderName.isNotEmpty ? senderName[0].toUpperCase() : '?')),
                    title: Text(senderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: isProcessing
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => _handleRequestAction(senderUid, false, false),
                          tooltip: "Deny",
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => _handleRequestAction(senderUid, true, false),
                          tooltip: "Accept",
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const Divider(height: 32),

          _buildSectionHeader("My Friends (${_currentFriends.length})"),
          if (_currentFriends.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("You haven't added any friends yet.", style: TextStyle(color: Colors.grey)),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _currentFriends.length,
              itemBuilder: (context, index) {
                final friend = _currentFriends[index];
                final friendUid = friend['uid'];
                final friendName = friend['name'];
                final isProcessing = _processingUids.contains(friendUid);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(friendName.isNotEmpty ? friendName[0].toUpperCase() : '?')),
                    title: Text(friendName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: isProcessing
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                      onPressed: () => _handleRequestAction(friendUid, false, true),
                      tooltip: "Unfriend",
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}