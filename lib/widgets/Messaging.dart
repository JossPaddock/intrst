import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/widgets/CollapsibleChatScreen.dart';
import '../utility/FirebaseMessagesUtility.dart';
import '../utility/FirebaseUsersUtility.dart';

class Messaging extends StatefulWidget {
  const Messaging({
    super.key,
    required this.user_uid,
    this.openWithUserUid,
  });

  final String user_uid;
  final String? openWithUserUid;

  @override
  _MessagingState createState() => _MessagingState();
}

class _MessagingState extends State<Messaging> {
  static const int _chatsTabIndex = 1;

  final FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users =
      FirebaseFirestore.instance.collection('users');
  final TextEditingController _searchController = TextEditingController();

  final Set<String> selectedItems = <String>{};
  final Map<String, String> _userNameCache = <String, String>{};

  List<String> searchResults = <String>[];
  List<Map<String, dynamic>> messageData = <Map<String, dynamic>>[];
  List<DocumentReference> messageDocumentReference = <DocumentReference>[];

  String? _openedChatForUid;
  String? _openChatDocumentPath;
  StreamSubscription<QuerySnapshot>? _subscription;

  bool _openingRequestedChat = false;
  bool _isSearchingUsers = false;
  int _selectedMessagingTab = _chatsTabIndex;

  @override
  void initState() {
    super.initState();
    _bindMessageSubscription();
    getMessages();
    loadFCMToken();
  }

  @override
  void didUpdateWidget(covariant Messaging oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.user_uid != widget.user_uid) {
      _openedChatForUid = null;
      _openChatDocumentPath = null;
      _searchController.clear();
      searchResults = <String>[];
      selectedItems.clear();
      _subscription?.cancel();
      _bindMessageSubscription();
      getMessages();
    }

    if (oldWidget.openWithUserUid != widget.openWithUserUid) {
      _openedChatForUid = null;
      _maybeOpenRequestedChat();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _bindMessageSubscription() {
    if (widget.user_uid.trim().isEmpty) {
      _subscription = null;
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('messages')
        .where('user_uids', arrayContains: widget.user_uid)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      if (snapshot.docChanges.isNotEmpty) {
        getMessages();
      }
    });
  }

  void loadFCMToken() async {
    if (widget.user_uid.trim().isEmpty) return;

    final notificationSettings =
        await FirebaseMessaging.instance.requestPermission(provisional: true);
    print(notificationSettings.authorizationStatus);

    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken != null) {
      print('APNs token is available: $apnsToken');
    } else {
      print('APNs token is NOT available');
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('fcm token is available: $fcmToken');
      fuu.addFcmTokenForUser(widget.user_uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }
  }

  DateTime _getLatestMessageTimestamp(Map<String, dynamic> conversation) {
    if (conversation.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final messageTimestamps = conversation.values
        .map((message) => message['timestamp']?.toDate())
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    return messageTimestamps.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : messageTimestamps.first;
  }

  Future<void> getMessages() async {
    if (widget.user_uid.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        messageData = <Map<String, dynamic>>[];
        messageDocumentReference = <DocumentReference>[];
        _openChatDocumentPath = null;
      });
      return;
    }

    final data = await fmu.getMessageDocumentsByUserUid(widget.user_uid);
    final extractedList = data.map((entry) => entry.values.first).toList();
    final extractedDocumentReference =
        data.map((entry) => entry.keys.first).toList();

    final combinedList = List.generate(
      extractedList.length,
      (index) =>
          MapEntry(extractedList[index], extractedDocumentReference[index]),
    );

    combinedList.sort((a, b) {
      final timestampA = _getLatestMessageTimestamp(
        (a.key['conversation'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      final timestampB = _getLatestMessageTimestamp(
        (b.key['conversation'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );
      return timestampB.compareTo(timestampA);
    });

    if (!mounted) return;
    setState(() {
      messageData = combinedList.map((e) => e.key).toList();
      messageDocumentReference = combinedList.map((e) => e.value).toList();

      if (_openChatDocumentPath != null &&
          !messageDocumentReference
              .any((docRef) => docRef.path == _openChatDocumentPath)) {
        _openChatDocumentPath = null;
      }
    });

    await _maybeOpenRequestedChat();
  }

  String _conversationKeyForParticipants(Iterable<dynamic> participants) {
    final normalized = participants
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return normalized.join(',');
  }

  String _conversationKeyFromDocument(Map<String, dynamic> data) {
    return _conversationKeyForParticipants((data['user_uids'] as List?) ?? []);
  }

  String? _findConversationPathByKey(String key) {
    if (key.isEmpty) return null;

    for (int i = 0; i < messageData.length; i++) {
      if (_conversationKeyFromDocument(messageData[i]) == key) {
        return messageDocumentReference[i].path;
      }
    }
    return null;
  }

  String? _findConversationPathForUser(String otherUid) {
    for (int i = 0; i < messageData.length; i++) {
      final participants = (messageData[i]['user_uids'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          <String>[];

      if (participants.contains(widget.user_uid) &&
          participants.contains(otherUid)) {
        return messageDocumentReference[i].path;
      }
    }
    return null;
  }

  Future<void> _maybeOpenRequestedChat() async {
    final targetUid = widget.openWithUserUid;
    if (targetUid == null ||
        targetUid.isEmpty ||
        targetUid == widget.user_uid ||
        _openedChatForUid == targetUid ||
        _openingRequestedChat) {
      return;
    }

    _openingRequestedChat = true;
    try {
      String? path = _findConversationPathForUser(targetUid);
      if (path == null) {
        await fmu.createMessageDocument([widget.user_uid, targetUid]);
        await getMessages();
        path = _findConversationPathForUser(targetUid);
      }

      if (path != null && mounted) {
        setState(() {
          _openChatDocumentPath = path;
          _selectedMessagingTab = _chatsTabIndex;
        });
        _openedChatForUid = targetUid;
      }
    } finally {
      _openingRequestedChat = false;
    }
  }

  Future<String> _resolveUserName(String uid) async {
    final cached = _userNameCache[uid];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final name = await fuu.lookUpNameByUserUid(users, uid);
    final safeName = name.trim().isEmpty ? 'Unknown user' : name.trim();
    _userNameCache[uid] = safeName;
    return safeName;
  }

  Future<void> _runUserSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isSearchingUsers = false;
        searchResults = <String>[];
      });
      return;
    }

    setState(() {
      _isSearchingUsers = true;
    });

    final requestQuery = trimmed;
    final results = await fuu.searchForPeopleAndInterestsReturnUIDs(
      users,
      requestQuery,
      false,
    );
    if (!mounted || _searchController.text.trim() != requestQuery) return;

    final filtered = results
        .map((value) => value.trim())
        .where((value) =>
            value.isNotEmpty &&
            value != widget.user_uid &&
            !selectedItems.contains(value))
        .toSet()
        .toList();

    setState(() {
      searchResults = filtered;
      _isSearchingUsers = false;
    });
  }

  void _toggleSelectedUser(String uid) {
    final sanitized = uid.trim();
    if (sanitized.isEmpty) return;

    setState(() {
      if (selectedItems.contains(sanitized)) {
        selectedItems.remove(sanitized);
      } else {
        selectedItems.add(sanitized);
      }
      searchResults.removeWhere((value) => selectedItems.contains(value));
    });
  }

  Future<void> _createOrOpenConversationFromSelection() async {
    if (selectedItems.isEmpty || widget.user_uid.trim().isEmpty) return;

    final participants = <String>{...selectedItems, widget.user_uid}.toList();
    final conversationKey = _conversationKeyForParticipants(participants);

    final created = await fmu.createMessageDocument(participants);
    await getMessages();

    if (!mounted) return;

    final path = _findConversationPathByKey(conversationKey);
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that conversation.')),
      );
      return;
    }

    setState(() {
      _openChatDocumentPath = path;
      _selectedMessagingTab = _chatsTabIndex;
      selectedItems.clear();
      searchResults = <String>[];
      _searchController.clear();
      _isSearchingUsers = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created
              ? 'Chat created. Opening it now.'
              : 'Chat already exists. Opening it now.',
        ),
      ),
    );
  }

  Widget _buildSelectedParticipantsRow() {
    if (selectedItems.isEmpty) return const SizedBox.shrink();

    final selected = selectedItems.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selected.map((uid) {
            return FutureBuilder<String>(
              future: _resolveUserName(uid),
              builder: (context, snapshot) {
                final name = snapshot.data ?? 'Loading...';
                return InputChip(
                  label: Text(name),
                  onDeleted: () => _toggleSelectedUser(uid),
                  avatar: const Icon(Icons.person, size: 16),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return const Center(
        child: Text('Search by name to start a new conversation.'),
      );
    }

    if (_isSearchingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchResults.isEmpty) {
      return const Center(child: Text('No people found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final uid = searchResults[index];
        return FutureBuilder<String>(
          future: _resolveUserName(uid),
          builder: (context, snapshot) {
            final name = snapshot.data ?? 'Loading...';
            final initial = name.isEmpty ? '?' : name.substring(0, 1);
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(initial.toUpperCase())),
                title: Text(name),
                subtitle: Text(uid),
                trailing: const Icon(Icons.add_circle_outline),
                onTap: () => _toggleSelectedUser(uid),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNewChatTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              fillColor: Colors.white,
              filled: true,
              hintText: 'Find people to message',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
            onChanged: _runUserSearch,
          ),
        ),
        _buildSelectedParticipantsRow(),
        Expanded(child: _buildSearchResultsList()),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: selectedItems.isEmpty
                ? null
                : _createOrOpenConversationFromSelection,
            icon: const Icon(Icons.forum_outlined),
            label: Text(
              selectedItems.isEmpty
                  ? 'Select people to create chat'
                  : 'Create chat with ${selectedItems.length} selected',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChatsTab() {
    if (messageData.isEmpty) {
      return const Center(child: Text('No chats yet.'));
    }

    return RefreshIndicator(
      onRefresh: getMessages,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(kIsWeb ? 10 : 0, 10, kIsWeb ? 10 : 0, 20),
        itemCount: messageData.length,
        itemBuilder: (context, index) {
          final documentReference = messageDocumentReference[index];
          final isExpanded = documentReference.path == _openChatDocumentPath;

          return CollapsibleChatScreen(
            key: ValueKey(documentReference.path),
            getMessages: getMessages,
            uid: widget.user_uid,
            documentData: messageData[index],
            documentReference: documentReference,
            isExpanded: isExpanded,
            onOpen: () {
              if (!mounted) return;
              setState(() {
                _openChatDocumentPath = documentReference.path;
              });
            },
            onClose: () {
              if (!mounted) return;
              setState(() {
                if (_openChatDocumentPath == documentReference.path) {
                  _openChatDocumentPath = null;
                }
              });
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user_uid.trim().isEmpty) {
      return const Center(child: Text('Sign in to use messaging.'));
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: IndexedStack(
          index: _selectedMessagingTab,
          children: [
            _buildNewChatTab(),
            _buildChatsTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedMessagingTab,
        onTap: (index) {
          setState(() {
            _selectedMessagingTab = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_add_alt_1),
            label: 'New chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chats',
          ),
        ],
      ),
    );
  }
}
