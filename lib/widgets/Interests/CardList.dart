import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../../login/LoginScreen.dart';
import '../../models/Interest.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';
import '../../utility/url_validator/url_validator.dart';

class CardList extends StatefulWidget {
  static GlobalKey<CardListState> createGlobalKey() =>
      GlobalKey<CardListState>();

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
  });

  final GlobalKey<CardListState> cardListKey;
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final void Function(int) onItemTapped;
  final bool showInputForm;
  final List<bool> editToggles;

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
  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _linkControllers = {};
  final Map<String, QuillController> _quillControllers = {};
  bool _isFriend = false;
  bool _isFollowing = false;
  bool _relationshipsLoaded = false;

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  late QuillController _mobileQuillController;
  bool _isSearchingUsers = false;
  List<String> searchResults = <String>[];
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users =
  FirebaseFirestore.instance.collection('users');
  final Set<String> selectedItems = <String>{};
  final Map<String, String> _userNameCache = <String, String>{};

  late List<Interest> localInterests = widget.interests;

  GeneralUtility gu = GeneralUtilityWeb();

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
    required QuillController quillController,
  }) {
    final title = titleController.text.trim();
    final description = _getQuillPlainText(quillController);

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: interest.sharedWithUids.map((uid) {
              return FutureBuilder<String>(
                future: _resolveUserName(uid),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? 'Loading...';
                  return InputChip(
                    label: Text(name, style: const TextStyle(fontSize: 12)),
                    avatar: const Icon(Icons.person, size: 14),
                    backgroundColor: Colors.blue.shade50,
                    onDeleted: () async {
                      final success = await fu.unshareInterestWithUser(
                        users: FirebaseFirestore.instance.collection('users'),
                        ownerUid: widget.uid,
                        interestId: interest.id,
                        targetUid: uid,
                      );

                      if (success) {
                        setState(() {
                          final idx = localInterests
                              .indexWhere((i) => i.id == interest.id);
                          if (idx != -1) {
                            final updated =
                            List<String>.from(
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
                            content: Text('Could not remove access, please try again.'),
                          ),
                        );
                      }
                    },
                  );
                },
              );
            }).toList(),
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
      return const Center(
        child: Text(''),
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

  @override
  void initState() {
    super.initState();
    _mobileQuillController = QuillController.basic();
    _syncControllersWithInterests();
    _checkRelationships();
  }

  @override
  void didUpdateWidget(covariant CardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interests != oldWidget.interests) {
      setState(() {
        localInterests = widget.interests;
        _syncControllersWithInterests();
      });
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

    for (final id in keysToRemove) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _titleControllers[id]?.dispose();
      });
      _titleControllers.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _quillControllers[id]?.dispose();
      });
      _quillControllers.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _linkControllers[id]?.dispose();
      });
      _linkControllers.remove(id);
    }

    for (final interest in localInterests) {
      final id = interest.id;

      if (!_titleControllers.containsKey(id)) {
        _titleControllers[id] = TextEditingController(text: interest.name);
      }

      if (!_quillControllers.containsKey(id)) {
        _quillControllers[id] = _createQuillController(interest.description);
      }

      if (!_linkControllers.containsKey(id)) {
        _linkControllers[id] = TextEditingController(text: interest.link ?? '');
      }
    }
  }

  QuillController _createQuillController(String text) {
    try {
      final doc = Document.fromJson(jsonDecode(text));
      return QuillController(
        document: doc,
        selection: TextSelection.collapsed(offset: 0),
      );
    } catch (e) {
      final doc = Document()..insert(0, text);
      return QuillController(
        document: doc,
        selection: TextSelection.collapsed(offset: 0),
      );
    }
  }

  String _getQuillPlainText(QuillController controller) {
    return controller.document.toPlainText().trim();
  }

  String _getQuillJson(QuillController controller) {
    return jsonEncode(controller.document.toDelta().toJson());
  }

  void _disposeControllersForId(String id) {
    _titleControllers[id]?.dispose();
    _titleControllers.remove(id);
    _quillControllers[id]?.dispose();
    _quillControllers.remove(id);
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
    for (var controller in _quillControllers.values) {
      controller.dispose();
    }
    _mobileTitleController.dispose();
    _mobileLinkController.dispose();
    _mobileQuillController.dispose();
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
      QuillController quillController,
      TextEditingController linkController,
      int index,
      String id,
      String toggleKey) async {
    if (toggle) {
      CollectionReference users =
      FirebaseFirestore.instance.collection('users');
      Interest newInterest = interest.copyWith(
        name: titleController.text,
        description: _getQuillJson(quillController),
        link: linkController.text,
        created_timestamp: interest.created_timestamp,
        updated_timestamp: DateTime.now(),
      );
      final isBlank = _isInterestBlank(
        titleController: titleController,
        quillController: quillController,
      );
      if (!kIsWeb) {
        final isValid =
        await isUrlResolvable(normalizeUrl(linkController.text));
        if (!isValid) {
          await _showInvalidLinkDialog();
          return;
        }
      }
      fu.updateEditedInterest(users, interest, newInterest, widget.uid);

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

        if (interest.privacy == 4) return true;                                 // Public
        if (interest.privacy == 3 && _isFriend) return true;                   // Friends only
        if (interest.privacy == 2 && (_isFriend || _isFollowing)) return true; // Friends & followers
        return false;                                                            // Private or unmatched
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
                onPressed: () {
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
                    final quillController = _quillControllers[id] ??
                        _createQuillController(interest.description);
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
                                  Container(
                                    decoration: BoxDecoration(
                                      border:
                                      Border.all(color: Colors.grey),
                                      borderRadius:
                                      BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      children: [
                                        QuillSimpleToolbar(
                                          controller: quillController,
                                          config:
                                          const QuillSimpleToolbarConfig(
                                            showFontFamily: false,
                                            showFontSize: false,
                                            showBoldButton: true,
                                            showItalicButton: true,
                                            showUnderLineButton: true,
                                            showListBullets: true,
                                            showListNumbers: true,
                                            showStrikeThrough: false,
                                            showAlignmentButtons: false,
                                            showBackgroundColorButton:
                                            false,
                                            showCenterAlignment: false,
                                            showClearFormat: false,
                                            showClipboardCopy: false,
                                            showClipboardCut: false,
                                            showClipboardPaste: false,
                                            showCodeBlock: false,
                                            showColorButton: false,
                                            showDirection: false,
                                            showDividers: false,
                                            showHeaderStyle: false,
                                            showIndent: false,
                                            showInlineCode: false,
                                            showJustifyAlignment: false,
                                            showLeftAlignment: false,
                                            showLineHeightButton: false,
                                            showLink: true,
                                            showListCheck: false,
                                            showQuote: false,
                                            showRedo: false,
                                            showRightAlignment: false,
                                            showSearchButton: false,
                                            showSmallButton: false,
                                            showSubscript: false,
                                            showSuperscript: false,
                                            showUndo: false,
                                          ),
                                        ),
                                        Container(
                                          height: 150,
                                          padding: EdgeInsets.all(8),
                                          child: QuillEditor.basic(
                                            controller: quillController,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                                  : Container(
                                padding: EdgeInsets.all(8),
                                child: QuillEditor.basic(
                                  focusNode:
                                  FocusNode(canRequestFocus: false),
                                  controller: quillController,
                                  config: QuillEditorConfig(
                                      showCursor: false),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (widget.showInputForm)
                                    DropdownButton<int>(
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
                                            Text("Friends and followers")),
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
                                  if (widget.showInputForm)
                                    IconButton(
                                      icon: Icon(
                                          toggle ? Icons.save : Icons.edit),
                                      onPressed: () async {
                                        await editing(
                                            interest,
                                            toggle,
                                            titleController,
                                            quillController,
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
                      CollectionReference users =
                      FirebaseFirestore.instance.collection('users');
                      Interest interest = Interest(
                          name: '',
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
                    child: Text("Add Interest")),
              ),
              SizedBox(height: 20)
            ],
          )
      ]),
    );
  }
}