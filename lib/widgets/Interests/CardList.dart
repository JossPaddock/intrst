import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../../login/LoginScreen.dart';
import '../../models/Interest.dart';
import 'dart:convert';
import '../../rich_text_editor/rich_text_document.dart';
import '../../rich_text_editor/rich_text_editor_controller.dart';
import '../../rich_text_editor/rich_text_editor_widget.dart';
import '../../rich_text_editor/rich_text_op.dart';
import '../../utility/url_validator/url_validator.dart';

class CardList extends StatefulWidget {
  static GlobalKey<CardListState> createGlobalKey() =>
      GlobalKey<CardListState>();

  final GlobalKey<CardListState> cardListKey;
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final void Function(int) onItemTapped;
  final bool showInputForm;
  final List<bool> editToggles;
  final bool shouldCreateInterest;
  final String initialInterestName;

  const CardList({
    super.key,
    required this.cardListKey,
    required this.name,
    required this.scaffoldKey,
    required this.uid,
    required this.signedIn,
    required this.interests,
    required this.onItemTapped,
    required this.showInputForm,
    required this.editToggles,
    this.shouldCreateInterest = false,
    this.initialInterestName = '',
  });

  @override
  CardListState createState() => CardListState();
}

class CardListState extends State<CardList>
    with AutomaticKeepAliveClientMixin<CardList> {
  @override
  bool get wantKeepAlive => true;

  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  bool get isEditingAny {
    final userModel = Provider.of<UserModel>(context, listen: false);
    return localInterests.any(
      (i) => userModel.getToggle(i.id) == true,
    );
  }

  final TextEditingController _searchController = TextEditingController();
  // FocusNode with skipTraversal: true prevents the OS/Flutter focus system
  // from auto-jumping to this field when the emoji keyboard triggers a focus
  // transition while the user is typing in the RichText description editor.
  final FocusNode _searchFocusNode = FocusNode(skipTraversal: true);
  // True while the search field has focus (keyboard is up). Used to hide the
  // title, link, and description fields so the search results have full room.
  bool _searchKeyboardActive = false;
  final Map<String, bool> _expandedDescriptions = {};

  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _linkControllers = {};
  final Map<String, RichTextEditorController> _richTextControllers = {};
  bool _isFriend = false;
  bool _isFollowing = false;
  bool _relationshipsLoaded = false;

  // Load hardening: tracks how many retries have been attempted and whether
  // a retry is currently scheduled.
  int _interestLoadRetries = 0;
  static const int _maxInterestLoadRetries = 3;
  static const Duration _interestRetryDelay = Duration(seconds: 1);

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  late RichTextEditorController _mobileRichTextController;
  bool _isSearchingUsers = false;
  List<String> searchResults = <String>[];
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users =
      FirebaseFirestore.instance.collection('users');
  final Set<String> selectedItems = <String>{};
  final Map<String, String> _userNameCache = <String, String>{};

  late List<Interest> localInterests = widget.interests;

  GeneralUtility gu = GeneralUtilityWeb();

  // Loads interests for the current user with retry hardening.
  // If the result is empty and we have retries remaining, schedules another
  // attempt after [_interestRetryDelay].

  Future<void> createNewInterest({String? initialName}) async {
    final String? interestName =
        await _showCreateInterestDialog(initialName: initialName);
    if (interestName == null || !mounted) return;

    CollectionReference users = FirebaseFirestore.instance.collection('users');
    Interest interest = Interest(
        name: interestName,
        description: '',
        link: '',
        created_timestamp: DateTime.now(),
        updated_timestamp: DateTime.now());

    await fu.addInterestForUser(users, interest, widget.uid);
    await refreshInterestsForUser(widget.uid).then((updatedInterests) {
      setState(() {
        localInterests = updatedInterests;
        _syncControllersWithInterests();
      });
    });
    editTopMostInterest();
  }

  Future<void> _loadInterestsWithRetry() async {
    if (!mounted) return;

    final loaded = await fetchSortedInterestsForUser(widget.uid);

    if (!mounted) return;

    if (loaded.isNotEmpty || _interestLoadRetries >= _maxInterestLoadRetries) {
      if (loaded.isEmpty && _interestLoadRetries >= _maxInterestLoadRetries) {
        print(
          'CardList: interests still empty after $_maxInterestLoadRetries retries for ${widget.uid}.',
        );
      }
      setState(() {
        localInterests = loaded;
        _syncControllersWithInterests();
      });
      return;
    }

    _interestLoadRetries++;
    print(
      'CardList: no interests loaded, scheduling retry '
      '$_interestLoadRetries/$_maxInterestLoadRetries for ${widget.uid}.',
    );

    await Future.delayed(_interestRetryDelay);
    await _loadInterestsWithRetry();
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
            value != widget.uid &&
            !selectedItems.contains(value))
        .toSet()
        .toList();

    setState(() {
      searchResults = filtered;
      _isSearchingUsers = false;
    });
  }

  Future<void> _deleteInterestSilently(Interest interest) async {
    final users = FirebaseFirestore.instance.collection('users');

    final Interest oldInterest = Interest(
      id: interest.id,
      nextInterestId: interest.nextInterestId,
      active: interest.active,
      name: interest.name,
      description: interest.description,
      link: interest.link,
      favorite: interest.favorite,
      favorited_timestamp: interest.favorited_timestamp,
      created_timestamp: interest.created_timestamp,
      updated_timestamp: interest.updated_timestamp,
    );

    await fu.removeInterest(users, oldInterest, widget.uid);

    setState(() {
      _disposeControllersForId(interest.id);
      localInterests.removeWhere((i) => i.id == interest.id);
    });

    updateToggles(interest.id, false);
  }

  Future<void> _showBlankInterestDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Missing content'),
        content: const Text('This interest will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isInterestBlank({
    required TextEditingController titleController,
    required RichTextEditorController richTextController,
  }) {
    final title = titleController.text.trim();
    final description = _getRichTextPlainText(richTextController);

    return title.isEmpty && description.isEmpty;
  }

  void editTopMostInterest() {
    if (localInterests.isEmpty) return;
    final Interest top = localInterests.first;
    final String id = top.id;
    Provider.of<UserModel>(context, listen: false).updateToggle(id, true);
    setState(() {});
  }

  Future<List<Interest>> fetchSortedInterestsForUser(String userUid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, userUid);
    interests
        .sort((x, y) => y.updated_timestamp.compareTo(x.updated_timestamp));
    return interests;
  }

  Future<List<Interest>> refreshInterestsForUser(String user_uid) async {
    return fetchSortedInterestsForUser(user_uid);
  }

  Future<void> _checkRelationships() async {
    if (widget.showInputForm) {
      if (mounted) setState(() => _relationshipsLoaded = true);
      return;
    }

    try {
      UserModel userModel = Provider.of<UserModel>(context, listen: false);
      final String viewerUid = widget.uid;
      final String ownerUid = userModel.alternateUid;

      final ownerSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('user_uid', isEqualTo: ownerUid)
          .limit(1)
          .get();

      bool isFriend = false;
      if (ownerSnap.docs.isNotEmpty) {
        final friendshipDoc = await ownerSnap.docs.first.reference
            .collection('friendships')
            .doc(viewerUid)
            .get();

        isFriend = friendshipDoc.exists &&
            (friendshipDoc.data()?['status'] == 'approved');
      }

      final viewerSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('user_uid', isEqualTo: viewerUid)
          .limit(1)
          .get();

      bool isFollowing = false;
      if (viewerSnap.docs.isNotEmpty) {
        final viewerData = viewerSnap.docs.first.data();
        final List<dynamic> viewerFollowing =
            viewerData['following_uids'] ?? [];
        isFollowing = viewerFollowing.contains(ownerUid);
      }

      if (mounted) {
        setState(() {
          _isFriend = isFriend;
          _isFollowing = isFollowing;
          _relationshipsLoaded = true;
        });
      }
    } catch (e) {
      print("Error checking relationships: $e");
      if (mounted) setState(() => _relationshipsLoaded = true);
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

  // Shows existing shares for an interest so the owner can see who already has access
  Widget _buildAlreadySharedRow(Interest interest) {
    if (interest.sharedWithUids.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Already shared with:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          // This allows the row to overflow and scroll horizontally
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: interest.sharedWithUids.map((uid) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FutureBuilder<String>(
                    future: _resolveUserName(uid),
                    builder: (context, snapshot) {
                      final name = snapshot.data ?? 'Loading...';
                      return InputChip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.person, size: 14),
                        backgroundColor: Colors.blue.shade50,
                        onDeleted: () async {
                          final success = await fu.unshareInterestWithUser(
                            users:
                                FirebaseFirestore.instance.collection('users'),
                            ownerUid: widget.uid,
                            interestId: interest.id,
                            targetUid: uid,
                          );

                          if (success) {
                            setState(() {
                              final idx = localInterests
                                  .indexWhere((i) => i.id == interest.id);
                              if (idx != -1) {
                                final updated = List<String>.from(
                                    localInterests[idx].sharedWithUids)
                                  ..remove(uid);
                                localInterests[idx] = localInterests[idx]
                                    .copyWith(sharedWithUids: updated);
                              }
                            });
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Could not remove access, please try again.'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewChatTab(Interest interest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAlreadySharedRow(interest),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              fillColor: Colors.white,
              filled: true,
              hintText: 'Find people to share this interest with',
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
                : () => _createOrOpenConversationFromSelection(interest),
            icon: const Icon(Icons.forum_outlined),
            label: Text(
              selectedItems.isEmpty
                  ? 'Select people to share interest with'
                  : 'Share with ${selectedItems.length} selected',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createOrOpenConversationFromSelection(Interest interest) async {
    if (selectedItems.isEmpty || widget.uid.trim().isEmpty) return;

    final targets = selectedItems.toList();
    bool shared = false;

    try {
      shared = await fu.shareInterestWithUsers(
        users: FirebaseFirestore.instance.collection('users'),
        ownerUid: widget.uid,
        interestId: interest.id,
        interestName: interest.name,
        targetUids: targets,
      );

      if (shared) {
        // Merge new targets into the local interest immediately so the
        // "already shared with" row updates without needing a full refresh
        final updatedSharedWith =
            {...interest.sharedWithUids, ...targets}.toList();

        setState(() {
          final idx = localInterests.indexWhere((i) => i.id == interest.id);
          if (idx != -1) {
            localInterests[idx] =
                localInterests[idx].copyWith(sharedWithUids: updatedSharedWith);
          }
        });
      }
    } catch (e) {
      debugPrint('Error sharing interest: $e');
    }

    setState(() {
      selectedItems.clear();
      searchResults = <String>[];
      _searchController.clear();
      _isSearchingUsers = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shared
              ? 'Interest shared — ${targets.length} ${targets.length == 1 ? 'person' : 'people'} can now view it.'
              : 'Something went wrong, please try again.',
        ),
      ),
    );
  }

  Widget _buildSearchResultsList() {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isSearchingUsers) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text('No people found.')),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: searchResults.map((uid) {
            return FutureBuilder<String>(
              future: _resolveUserName(uid),
              builder: (context, snapshot) {
                final name = snapshot.data ?? '...';
                final initial = name.isEmpty ? '?' : name[0].toUpperCase();

                return ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      initial,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(
                    name,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _toggleSelectedUser(uid),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mobileRichTextController = RichTextEditorController();
    _syncControllersWithInterests();
    _checkRelationships();
    // Hide title/link/description while the search keyboard is up so the
    // search results panel has maximum space.
    _searchFocusNode.addListener(() {
      setState(() {
        _searchKeyboardActive = _searchFocusNode.hasFocus;
      });
    });
    // If the widget was initialised with no interests (e.g. the parent fetched
    // too early), kick off the hardened load immediately.
    if (localInterests.isEmpty && widget.showInputForm) {
      _loadInterestsWithRetry();
    }
    if (widget.shouldCreateInterest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        createNewInterest(initialName: widget.initialInterestName);
      });
    }
  }

  @override
  void didUpdateWidget(covariant CardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldCreateInterest && !oldWidget.shouldCreateInterest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        createNewInterest(initialName: widget.initialInterestName);
      });
    }
    if (widget.interests != oldWidget.interests) {
      setState(() {
        localInterests = widget.interests;
        _syncControllersWithInterests();
      });
      // If the parent pushed down an empty list and we haven't exhausted
      // retries, try reloading.
      if (localInterests.isEmpty &&
          widget.showInputForm &&
          _interestLoadRetries < _maxInterestLoadRetries) {
        _loadInterestsWithRetry();
      }
    }
  }

  void _syncControllersWithInterests() {
    final currentIds = localInterests.map((i) => i.id).toSet();
    final keysToRemove = <String>[];

    for (final existingId in _titleControllers.keys) {
      if (!currentIds.contains(existingId)) {
        keysToRemove.add(existingId);
      }
    }

    // Interests that are gone — safe to dispose synchronously because no
    // widget can be showing them (they've been removed from localInterests).
    for (final id in keysToRemove) {
      _titleControllers[id]?.dispose();
      _titleControllers.remove(id);
      _richTextControllers[id]?.dispose();
      _richTextControllers.remove(id);
      _linkControllers[id]?.dispose();
      _linkControllers.remove(id);
    }

    for (final interest in localInterests) {
      final id = interest.id;

      if (!_titleControllers.containsKey(id)) {
        _titleControllers[id] = TextEditingController(text: interest.name);
      }

      final existingRtc = _richTextControllers[id];
      if (existingRtc == null) {
        // First time seeing this interest — create fresh.
        _richTextControllers[id] =
            _createRichTextController(interest.description);
      } else {
        // Already have a controller — update its document in-place rather than
        // disposing and recreating. Disposing while animated widgets inside
        // TextField still hold a reference causes use-after-dispose crashes.
        final incoming = RichTextDocument.fromJsonString(interest.description);
        if (incoming != existingRtc.document) {
          existingRtc.loadDocument(incoming);
        }
      }

      if (!_linkControllers.containsKey(id)) {
        _linkControllers[id] = TextEditingController(text: interest.link ?? '');
      }
    }
  }

  RichTextEditorController _createRichTextController(String text) {
    return RichTextEditorController(
      initialDocument: RichTextDocument.fromJsonString(text),
    );
  }

  String _getRichTextPlainText(RichTextEditorController controller) {
    return controller.document.plainText.trim();
  }

  String _getRichTextJson(RichTextEditorController controller) {
    return controller.document.toJsonString();
  }

  Future<void> _openFullscreenRichTextEditor(
      RichTextEditorController richTextController) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Enter/edit description'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
          body: Container(
              padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
              child: RichTextEditorWidget(
                mode: RichTextEditorMode.edit,
                controller: richTextController,
                autofocus: true,
                maxLines: null,
                decoration:
                    const InputDecoration(hintText: 'enter your interest description here'),
              )),
        );
      },
    );
  }

  void _disposeControllersForId(String id) {
    _titleControllers[id]?.dispose();
    _titleControllers.remove(id);
    _richTextControllers[id]?.dispose();
    _richTextControllers.remove(id);
    _linkControllers[id]?.dispose();
    _linkControllers.remove(id);
  }

  @override
  void dispose() {
    for (var controller in _titleControllers.values) {
      controller.dispose();
    }
    for (var controller in _linkControllers.values) {
      controller.dispose();
    }
    for (var controller in _richTextControllers.values) {
      controller.dispose();
    }
    _mobileTitleController.dispose();
    _mobileLinkController.dispose();
    _mobileRichTextController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void updateToggles(String interestId, bool toggle) {
    Provider.of<UserModel>(context, listen: false)
        .updateToggle(interestId, toggle);
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://' + url;
    }
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<void> forceRefresh() async {
    List<Interest> updated = await refreshInterestsForUser(widget.uid);
    setState(() {
      localInterests = updated;
      _syncControllersWithInterests();
    });
  }

  Future<void> _showInvalidLinkDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid link'),
        content: const Text(
          'The link you entered does not appear to be reachable. '
          'Please try fix it before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPostInterestToFeedDialog(Interest interest) async {
    if (widget.uid.trim().isEmpty) return;

    final TextEditingController postMessageController = TextEditingController();
    bool isPosting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Post "${interest.name}" to your feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: postMessageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Say something about this interest...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isPosting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isPosting
                      ? null
                      : () async {
                          final message = postMessageController.text.trim();
                          if (message.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Please add a message before posting.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isPosting = true;
                          });

                          try {
                            await fu.createInterestPostedActivity(
                              actorUid: widget.uid,
                              interest: interest,
                              message: message,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Posted to feed.')),
                            );
                          } catch (e) {
                            setDialogState(() {
                              isPosting = false;
                            });
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Could not post: $e')),
                            );
                          }
                        },
                  child: isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Post to my Feed'),
                ),
              ],
            );
          },
        );
      },
    );

    postMessageController.dispose();
  }

  // Shows a modal prompting the user to enter a name before the interest is
  // created. Returns the trimmed name string, or null if the user cancelled.
  Future<String?> _showCreateInterestDialog({String? initialName}) async {
    final TextEditingController nameController =
        TextEditingController(text: initialName);
    String? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Name your interest'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Astrophysics, Jazz guitar…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    result = value.trim();
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    result = null;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: nameController.text.trim().isEmpty
                      ? null
                      : () {
                          result = nameController.text.trim();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Create Interest'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });
    return result;
  }

  String normalizeUrl(String input) {
    String url = input.trim();

    if (url.isEmpty) return url;

    if (!url.startsWith('http://www.') && !url.startsWith('https://www.')) {
      url = 'https://www.$url';
    }

    return url;
  }

  Future<void> editing(
      Interest interest,
      bool toggle,
      TextEditingController titleController,
      RichTextEditorController richTextController,
      TextEditingController linkController,
      int index,
      String id,
      String toggleKey) async {
    if (toggle) {
      CollectionReference users =
          FirebaseFirestore.instance.collection('users');
      Interest newInterest = interest.copyWith(
        name: titleController.text,
        description: _getRichTextJson(richTextController),
        link: linkController.text,
        created_timestamp: interest.created_timestamp,
        updated_timestamp: DateTime.now(),
      );
      final isBlank = _isInterestBlank(
        titleController: titleController,
        richTextController: richTextController,
      );
      if (!kIsWeb && linkController.text != '') {
        final isValid =
            await isUrlResolvable(normalizeUrl(linkController.text));
        if (!isValid) {
          await _showInvalidLinkDialog();
          return;
        }
      }
      await fu.updateEditedInterest(users, interest, newInterest, widget.uid);

      if (isBlank) {
        await _showBlankInterestDialog();
        await _deleteInterestSilently(interest);
      }

      final updated = await refreshInterestsForUser(widget.uid);

      setState(() {
        localInterests = updated;
        _syncControllersWithInterests();
      });

      updateToggles(toggleKey, false);
    }
    updateToggles(toggleKey, !toggle);
  }

  String getStatusText(int statusId) {
    switch (statusId) {
      case 0:
        return 'shared privately';
      case 2:
        return 'shared with friends and followers';
      case 3:
        return 'shared with friends';
      case 4:
        return 'shared publicly';
      default:
        return 'Unknown Status';
    }
  }

  Future<bool?> _showSaveDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must choose
      builder: (context) {
        return AlertDialog(
          title: const Text("You may have unsaved changes"),
          content: const Text("Do you want to save your work?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // discard
              },
              child: const Text("Discard"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // save
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  static const double _collapsedDescriptionHeight = 60.0;
  static const int _descriptionCollapseThreshold = 150;

  static const double _defaultImageMaxHeight = 160.0;

  static final List<({String label, double height})> _imageSizePresets = [
    (label: 'S', height: 80),
    (label: 'M', height: 160),
    (label: 'L', height: 280),
    (label: 'XL', height: 400),
  ];

  // Matches an image URL with optional |<pixels> height and optional |<L|C|R>
  // alignment suffix, e.g. "https://example.com/photo.jpg|300|L".
  static final RegExp _imageUrlPattern = RegExp(
    r'(https?://[^\s<>"{}|\\^`\[\]]+\.(?:jpg|jpeg|png|gif|webp|svg)(?:\?[^\s|]*)?)(?:\|(\d+))?(?:\|([LCR]))?',
    caseSensitive: false,
  );

  String _updateImageInDescription(
      String descJson, String baseUrl, double newHeight, String newAlignChar) {
    final doc = RichTextDocument.fromJsonString(descJson);
    // Match base URL + optional |digits + optional |[LCR]
    final urlPattern = RegExp(
        RegExp.escape(baseUrl) + r'(\|\d+)?(\|[LCR])?',
        caseSensitive: false);
    final suffix = newAlignChar == 'C'
        ? '|${newHeight.round()}'
        : '|${newHeight.round()}|$newAlignChar';
    final replacement = '$baseUrl$suffix';

    final updatedOps = doc.ops.map((op) {
      if (!urlPattern.hasMatch(op.text)) return op;
      return op.copyWith(text: op.text.replaceFirst(urlPattern, replacement));
    }).toList();

    return RichTextDocument(version: doc.version, ops: updatedOps)
        .normalised()
        .toJsonString();
  }

  Future<void> _applyImageUpdate(
      Interest interest,
      RichTextEditorController richTextController,
      String baseUrl,
      double newHeight,
      String newAlignChar) async {
    final newDescJson = _updateImageInDescription(
        interest.description, baseUrl, newHeight, newAlignChar);
    final newInterest = interest.copyWith(
      description: newDescJson,
      updated_timestamp: DateTime.now(),
    );

    setState(() {
      final idx = localInterests.indexWhere((i) => i.id == interest.id);
      if (idx != -1) localInterests[idx] = newInterest;
    });
    richTextController
        .loadDocument(RichTextDocument.fromJsonString(newDescJson));

    await fu.updateEditedInterest(
      FirebaseFirestore.instance.collection('users'),
      interest,
      newInterest,
      widget.uid,
    );
  }

  // Splits a RichTextDocument into alternating text-op lists and image records,
  // in document order. Each item is either List<RichTextOp> or
  // ({String url, double maxHeight, String alignChar}).
  List<Object> _splitDocumentAtImages(RichTextDocument doc) {
    final parts = <Object>[];
    var pendingTextOps = <RichTextOp>[];

    for (final op in doc.ops) {
      var text = op.text;

      while (text.isNotEmpty) {
        final match = _imageUrlPattern.firstMatch(text);
        if (match == null) {
          pendingTextOps.add(op.copyWith(text: text));
          break;
        }

        if (match.start > 0) {
          pendingTextOps
              .add(op.copyWith(text: text.substring(0, match.start)));
        }

        if (pendingTextOps.isNotEmpty) {
          parts.add(List<RichTextOp>.from(pendingTextOps));
          pendingTextOps = [];
        }

        final baseUrl = match.group(1)!;
        final heightStr = match.group(2);
        final alignStr = match.group(3)?.toUpperCase();
        final maxHeight = heightStr != null
            ? (double.tryParse(heightStr) ?? _defaultImageMaxHeight)
                .clamp(40.0, 800.0)
            : _defaultImageMaxHeight;
        parts.add((
          url: baseUrl,
          maxHeight: maxHeight,
          alignChar: alignStr ?? 'C',
        ));

        text = text.substring(match.end);
      }
    }

    if (pendingTextOps.isNotEmpty) {
      parts.add(List<RichTextOp>.from(pendingTextOps));
    }

    return parts;
  }

  Widget _buildTextOpsView(BuildContext context, List<RichTextOp> ops) {
    final nonEmpty = ops.where((op) => op.text.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();

    final baseStyle = DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];

    for (final op in nonEmpty) {
      if (op.isLink) {
        final url = op.link!;
        spans.add(TextSpan(
          text: op.text,
          style: baseStyle.copyWith(
            color: const Color(0xFF1A73E8),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF1A73E8),
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
        ));
      } else {
        spans.add(TextSpan(text: op.text, style: baseStyle));
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      child: RichText(
        text: TextSpan(children: spans, style: baseStyle),
        maxLines: null,
      ),
    );
  }

  Widget _buildSingleImageSection(
    ({String url, double maxHeight, String alignChar}) img, {
    bool canResize = false,
    Interest? interest,
    RichTextEditorController? richTextController,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Align(
            alignment: switch (img.alignChar) {
              'L' => Alignment.centerLeft,
              'R' => Alignment.centerRight,
              _ => Alignment.center,
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: img.maxHeight),
                child: Image.network(
                  img.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        if (canResize && interest != null && richTextController != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final preset in _imageSizePresets)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text(
                        preset.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: (img.maxHeight - preset.height).abs() < 1,
                      onSelected: (_) => _applyImageUpdate(
                        interest,
                        richTextController,
                        img.url,
                        preset.height,
                        img.alignChar,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                const SizedBox(width: 8),
                for (final (char, icon) in _imageAlignOptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Icon(icon, size: 14),
                      selected: img.alignChar == char,
                      onSelected: (_) => _applyImageUpdate(
                        interest,
                        richTextController,
                        img.url,
                        img.maxHeight,
                        char,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInlineDescription(
    BuildContext context,
    String id,
    RichTextEditorController richTextController, {
    bool canResize = false,
    Interest? interest,
  }) {
    final plainText = _getRichTextPlainText(richTextController);
    final bool isLong = plainText.length > _descriptionCollapseThreshold;
    final bool isExpanded = _expandedDescriptions[id] ?? false;

    final parts = _splitDocumentAtImages(richTextController.document);

    final inlineContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final part in parts)
          if (part is List<RichTextOp>)
            _buildTextOpsView(context, part)
          else if (part is ({String url, double maxHeight, String alignChar}))
            _buildSingleImageSection(
              part,
              canResize: canResize,
              interest: interest,
              richTextController: richTextController,
            ),
      ],
    );

    if (isLong && !isExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _collapsedDescriptionHeight,
            child: ClipRect(child: inlineContent),
          ),
          GestureDetector(
            onTap: () => setState(() => _expandedDescriptions[id] = true),
            child: Center(
              child:
                  Icon(Icons.expand_more, color: Colors.grey[400], size: 20),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inlineContent,
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expandedDescriptions[id] = false),
            child: Center(
              child:
                  Icon(Icons.expand_less, color: Colors.grey[400], size: 20),
            ),
          ),
      ],
    );
  }

  static const List<(String char, IconData icon)> _imageAlignOptions = [
    ('L', Icons.format_align_left),
    ('C', Icons.format_align_center),
    ('R', Icons.format_align_right),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    UserModel userModel = Provider.of<UserModel>(context);

    if (!widget.showInputForm && !_relationshipsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    double deviceScreenHeight = MediaQuery.of(context).size.height;
    double maxHeight = deviceScreenHeight * 0.88;

    // --- PRIVACY FILTERING LOGIC ---
    List<Interest> filteredInterests = localInterests;

    if (!widget.showInputForm) {
      final String viewerUid = widget.uid;

      filteredInterests = localInterests.where((interest) {
        // Explicit per-user share always wins, regardless of privacy level
        if (interest.sharedWithUids.contains(viewerUid)) return true;

        if (interest.privacy == 4) return true; // Public
        if (interest.privacy == 3 && _isFriend) return true; // Friends only
        if (interest.privacy == 2 && (_isFriend || _isFollowing))
          return true; // Friends & followers
        return false; // Private or unmatched
      }).toList();
    }

    final editingEntry = userModel.editToggles.entries.firstWhere(
      (e) => e.value == true,
      orElse: () => MapEntry('', false),
    );
    final editingId = editingEntry.key;

    final visibleInterests = editingId.isEmpty
        ? filteredInterests
        : filteredInterests.where((i) => (i.id) == editingId).toList();

    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent, width: 5.0),
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(width: 45),
              Container(
                padding: EdgeInsets.all(3),
                color: Color.fromRGBO(6, 28, 39, 1.0),
                child: Text(
                  widget.name,
                  style: TextStyle(
                    color: Colors.white,
                    backgroundColor: Color.fromRGBO(6, 28, 39, 1.0),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                iconSize: 20,
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () async {
                  // Only prompt when something is actively being edited.
                  if (isEditingAny) {
                    final bool? save = await _showSaveDialog(context);
                    if (save == null) return; // user dismissed the dialog — do nothing

                    if (save) {
                      // Look up the editing interest and its controllers by ID.
                      final idx = localInterests.indexWhere((i) => i.id == editingId);
                      if (idx != -1) {
                        final interest = localInterests[idx];
                        final titleController =
                            _titleControllers[editingId] ?? TextEditingController();
                        final richTextController = _richTextControllers[editingId] ??
                            _createRichTextController(interest.description);
                        final linkController =
                            _linkControllers[editingId] ?? TextEditingController();

                        await editing(
                          interest,
                          true, // currently in edit mode
                          titleController,
                          richTextController,
                          linkController,
                          idx,
                          editingId,
                          editingId,
                        );
                      }
                    }
                    // If save == false (Discard), fall through and just close.
                  }

                  widget.scaffoldKey.currentState?.closeEndDrawer();
                },
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show a subtle loading indicator while retries are in flight
                // so the user knows the app is working and not just blank.
                if (localInterests.isEmpty &&
                    widget.showInputForm &&
                    _interestLoadRetries < _maxInterestLoadRetries)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Loading interests…',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: visibleInterests.length,
                  itemBuilder: (context, index) {
                    final interest = visibleInterests[index];
                    final String id = interest.id;
                    final String toggleKey = id;
                    bool toggle = userModel.getToggle(toggleKey);
                    final shouldHighlightFromFeed =
                        userModel.feedHighlightedInterestOwnerUid ==
                                userModel.alternateUid &&
                            userModel.feedHighlightedInterestId == id;

                    final titleController =
                        _titleControllers[id] ?? TextEditingController();
                    final richTextController = _richTextControllers[id] ??
                        _createRichTextController(interest.description);
                    final linkController =
                        _linkControllers[id] ?? TextEditingController();

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 8.0),
                      child: Card(
                        key: ValueKey(id),
                        color: shouldHighlightFromFeed
                            ? const Color(0xFFFFF3CD)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: shouldHighlightFromFeed
                                ? const Color(0xFFF0AD4E)
                                : Colors.transparent,
                            width: shouldHighlightFromFeed ? 2 : 0,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // While the search keyboard is active, hide
                              // title/link/description to give search results
                              // full vertical space. They reappear automatically
                              // when the keyboard is dismissed.
                              if (!_searchKeyboardActive) ...[
                                GestureDetector(
                                  onTap: () => _launchUrl(interest.link),
                                  child: toggle
                                      ? TextField(
                                          controller: titleController,
                                          decoration: InputDecoration(
                                            labelText: 'Edit title here',
                                            border: OutlineInputBorder(),
                                          ),
                                        )
                                      : Text(
                                          interest.name,
                                          style: TextStyle(
                                              color: interest.link == ""
                                                  ? Colors.black
                                                  : Colors.blue,
                                              decoration: interest.link == ""
                                                  ? TextDecoration.none
                                                  : TextDecoration.underline),
                                        ),
                                ),
                                SizedBox(height: 4),
                                toggle
                                    ? Column(
                                        children: [
                                          TextField(
                                            controller: linkController,
                                            decoration: InputDecoration(
                                              labelText: 'Edit link here',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          GestureDetector(
                                            onTap: () async {
                                              await _openFullscreenRichTextEditor(
                                                  richTextController);
                                              if (mounted) setState(() {});
                                            },
                                            child: Container(
                                              padding: EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.grey),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _getRichTextPlainText(
                                                                richTextController)
                                                            .trim()
                                                            .isEmpty
                                                        ? Text(
                                                            'Enter a description of the interest.',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .grey[600]),
                                                          )
                                                        : SingleChildScrollView(
                                                            child:
                                                                RichTextEditorWidget(
                                                              mode:
                                                                  RichTextEditorMode
                                                                      .view,
                                                              controller:
                                                                  richTextController,
                                                              maxLines: null,
                                                            ),
                                                          ),
                                                  ),
                                                  Icon(Icons.edit,
                                                      color: Colors.grey[600]),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : _buildInlineDescription(
                                        context,
                                        id,
                                        richTextController,
                                        canResize: widget.showInputForm,
                                        interest: interest,
                                      ),
                                Container(
                                  alignment: Alignment.bottomRight,
                                  child: Text(
                                    getStatusText(interest.privacy),
                                    style: TextStyle(fontSize: 8),
                                  ),
                                ),
                              ],
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (widget.showInputForm && isEditingAny)
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 175),
                                      child: DropdownButton<int>(
                                        value: [0, 2, 3, 4]
                                                .contains(interest.privacy)
                                            ? interest.privacy
                                            : 4,
                                        items: const [
                                          DropdownMenuItem(
                                              value: 0, child: Text("Private")),
                                          DropdownMenuItem(
                                              value: 2,
                                              child:
                                                  Text("Friends & followers")),
                                          DropdownMenuItem(
                                              value: 3,
                                              child: Text("Friends only")),
                                          DropdownMenuItem(
                                              value: 4, child: Text("Public")),
                                        ],
                                        onChanged: (int? newValue) async {
                                          if (newValue == null) return;

                                          Interest newInterest = interest
                                              .copyWith(privacy: newValue);

                                          setState(() {
                                            localInterests[index] = newInterest;
                                          });

                                          await fu.updateEditedInterest(
                                            FirebaseFirestore.instance
                                                .collection('users'),
                                            interest,
                                            newInterest,
                                            widget.uid,
                                          );
                                        },
                                      ),
                                    ),
                                  SizedBox(width: 20),
                                  if (widget.showInputForm)
                                    IconButton(
                                        icon: Icon(Icons.star,
                                            color: interest.favorite
                                                ? Colors.orange
                                                : Colors.blueGrey),
                                        onPressed: () async {
                                          CollectionReference users =
                                              FirebaseFirestore.instance
                                                  .collection('users');
                                          bool favorited = !interest.favorite;
                                          Interest newInterest =
                                              interest.copyWith(
                                                  favorite: !interest.favorite,
                                                  favorited_timestamp: favorited
                                                      ? DateTime.now()
                                                      : interest
                                                          .favorited_timestamp);

                                          setState(() {
                                            localInterests[index] = newInterest;
                                            final nid = newInterest.id;
                                            _titleControllers[nid]?.text =
                                                newInterest.name;
                                            _linkControllers[nid]?.text =
                                                newInterest.link ?? '';
                                          });

                                          await fu.updateEditedInterest(
                                              users,
                                              interest,
                                              newInterest,
                                              widget.uid);
                                          List<Interest> updatedInterests =
                                              await refreshInterestsForUser(
                                                  widget.uid);

                                          setState(() {
                                            localInterests = updatedInterests;
                                            _syncControllersWithInterests();
                                          });
                                        }),
                                  if (widget.showInputForm && !toggle)
                                    IconButton(
                                      tooltip: 'Post to my feed',
                                      icon: const Icon(Icons.share),
                                      onPressed: () {
                                        _showPostInterestToFeedDialog(interest);
                                      },
                                    ),
                                  if (widget.showInputForm &&
                                      !_searchKeyboardActive)
                                    IconButton(
                                      icon: Icon(
                                          toggle ? Icons.save : Icons.edit),
                                      onPressed: () async {
                                        await editing(
                                            interest,
                                            toggle,
                                            titleController,
                                            richTextController,
                                            linkController,
                                            index,
                                            id,
                                            toggleKey);
                                      },
                                    ),
                                  if (widget.showInputForm && !toggle)
                                    IconButton(
                                      icon: Icon(Icons.delete),
                                      onPressed: () => showDialog<String>(
                                        context: context,
                                        builder: (BuildContext context) =>
                                            AlertDialog(
                                          title: const Text(
                                              'Are you sure you want\nto delete this interest?'),
                                          content: Text(
                                              'This will permanently delete\nthe interest \"${interest.name}\"',
                                              textAlign: TextAlign.center),
                                          actions: <Widget>[
                                            Center(
                                              child: Column(children: <Widget>[
                                                TextButton(
                                                  onPressed: () {
                                                    CollectionReference users =
                                                        FirebaseFirestore
                                                            .instance
                                                            .collection(
                                                                'users');
                                                    Interest oldInterest =
                                                        Interest(
                                                      id: interest.id,
                                                      nextInterestId: interest
                                                          .nextInterestId,
                                                      active: interest.active,
                                                      name: interest.name,
                                                      description:
                                                          interest.description,
                                                      link: interest.link,
                                                      favorite:
                                                          interest.favorite,
                                                      favorited_timestamp: interest
                                                          .favorited_timestamp,
                                                      created_timestamp: interest
                                                          .created_timestamp,
                                                      updated_timestamp: interest
                                                          .updated_timestamp,
                                                      privacy: interest.privacy,
                                                    );

                                                    fu.removeInterest(
                                                        users,
                                                        oldInterest,
                                                        widget.uid);

                                                    setState(() {
                                                      _disposeControllersForId(
                                                          id);
                                                      localInterests
                                                          .removeAt(index);
                                                    });

                                                    Navigator.pop(
                                                        context, 'Delete');
                                                  },
                                                  child: const Text('Yes'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context,
                                                          'Never mind'),
                                                  child: const Text('No'),
                                                ),
                                              ]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (widget.showInputForm && toggle)
                                SizedBox(
                                  child: _buildNewChatTab(interest),
                                  height: 300,
                                  width: double.infinity,
                                )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (!widget.signedIn)
          Align(
            alignment: Alignment.center,
            child: Card(
              margin: EdgeInsets.all(16),
              child: SizedBox(
                  width: 300,
                  height: 150,
                  child: Column(children: [
                    Padding(
                        padding: EdgeInsets.all(10),
                        child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onItemTapped(1);
                            },
                            child: Text("Sign in or Sign Up"))),
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Center(
                        child: Text(
                          'to access your interests page.',
                          style: TextStyle(
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ])),
            ),
          ),
        if (widget.signedIn && widget.showInputForm && !isEditingAny)
          Column(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: TextButton(
                    onPressed: () async {
                      // Prompt for a name before creating the interest.
                      // If the user cancels (returns null) we do nothing.
                      final String? interestName =
                          await _showCreateInterestDialog();
                      if (interestName == null || !mounted) return;

                      CollectionReference users =
                          FirebaseFirestore.instance.collection('users');
                      Interest interest = Interest(
                          name: interestName,
                          description: '',
                          link: '',
                          created_timestamp: DateTime.now(),
                          updated_timestamp: DateTime.now());

                      await fu.addInterestForUser(users, interest, widget.uid);
                      await refreshInterestsForUser(widget.uid)
                          .then((updatedInterests) {
                        setState(() {
                          localInterests = updatedInterests;
                          _syncControllersWithInterests();
                        });
                      });
                      widget.cardListKey.currentState?.editTopMostInterest();
                    },
                    child: Text(
                      "Add Interest",
                      style: TextStyle(color: Colors.white),
                    )),
              ),
              SizedBox(height: 20)
            ],
          )
      ]),
    );
  }
}
