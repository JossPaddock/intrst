part of '../CardList.dart';

const int _maxInterestLoadRetries = 3;
const Duration _interestRetryDelay = Duration(seconds: 1);

// Lifecycle, Firestore data loading/persisting, and text-controller
// bookkeeping for CardListState.
mixin _CardListDataMixin on _CardListStateBase {
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

  @override
  Future<void> createNewInterest({String? initialName}) async {
    final String? interestName = await _showCreateInterestDialog(
      initialName: initialName,
    );
    if (interestName == null || !mounted) return;

    CollectionReference users = FirebaseFirestore.instance.collection('users');
    Interest interest = Interest(
      name: interestName,
      description: '',
      link: '',
      created_timestamp: DateTime.now(),
      updated_timestamp: DateTime.now(),
    );

    await fu.addInterestForUser(users, interest, widget.uid);
    await refreshInterestsForUser(widget.uid).then((updatedInterests) {
      setState(() {
        localInterests = updatedInterests;
        _syncControllersWithInterests();
      });
    });
    // Open the interest we just created — with starred interests pinned to
    // the top it is no longer necessarily the first card in the list.
    editInterestById(interest.id);
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

  bool _isInterestBlank({
    required TextEditingController titleController,
    required RichTextEditorController richTextController,
  }) {
    final title = titleController.text.trim();
    final description = _getRichTextPlainText(richTextController);

    return title.isEmpty && description.isEmpty;
  }

  void editInterestById(String id) {
    if (!localInterests.any((i) => i.id == id)) return;
    Provider.of<UserModel>(context, listen: false).updateToggle(id, true);
    setState(() {});
  }

  Future<List<Interest>> fetchSortedInterestsForUser(String userUid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, userUid);
    interests.sort(Interest.compareForDisplay);
    return interests;
  }

  @override
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

        isFriend =
            friendshipDoc.exists &&
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

  @override
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
        _richTextControllers[id] = _createRichTextController(
          interest.description,
        );
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

  @override
  RichTextEditorController _createRichTextController(String text) {
    return RichTextEditorController(
      initialDocument: RichTextDocument.fromJsonString(text),
    );
  }

  @override
  String _getRichTextPlainText(RichTextEditorController controller) {
    return controller.document.plainText.trim();
  }

  String _getRichTextJson(RichTextEditorController controller) {
    return controller.document.toJsonString();
  }

  @override
  void _disposeControllersForId(String id) {
    _titleControllers[id]?.dispose();
    _titleControllers.remove(id);
    _richTextControllers[id]?.dispose();
    _richTextControllers.remove(id);
    _linkControllers[id]?.dispose();
    _linkControllers.remove(id);
  }

  void updateToggles(String interestId, bool toggle) {
    Provider.of<UserModel>(
      context,
      listen: false,
    ).updateToggle(interestId, toggle);
  }

  @override
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

  // Reorders a drag within a single section — either the pinned Favorites
  // group or the rest — and persists the new order to Firestore. Favorites
  // always stay pinned above the rest; only the dragged group's relative
  // order changes.
  @override
  Future<void> _handleReorderWithinGroup(
    List<Interest> group,
    bool isFavoriteGroup,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) return;

    final reordered = List<Interest>.from(group);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final otherGroup = localInterests
        .where((i) => i.favorite != isFavoriteGroup)
        .toList();

    final combined = isFavoriteGroup
        ? [...reordered, ...otherGroup]
        : [...otherGroup, ...reordered];

    // Renumber positions descending so an interest created later (which falls
    // back to created_timestamp, a far larger value) still lands on top.
    final n = combined.length;
    final renumbered = [
      for (int i = 0; i < n; i++) combined[i].copyWith(sort_order: n - i),
    ];

    setState(() {
      localInterests = renumbered;
      _syncControllersWithInterests();
    });

    try {
      await fu.persistInterestOrder(users, widget.uid, renumbered);
    } catch (e) {
      print('Failed to persist interest order: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the new order, please try again.'),
        ),
      );
    }
  }

  String normalizeUrl(String input) {
    String url = input.trim();

    if (url.isEmpty) return url;

    if (!url.startsWith('http://www.') && !url.startsWith('https://www.')) {
      url = 'https://www.$url';
    }

    return url;
  }

  @override
  Future<void> editing(
    Interest interest,
    bool toggle,
    TextEditingController titleController,
    RichTextEditorController richTextController,
    TextEditingController linkController,
    int index,
    String id,
    String toggleKey,
  ) async {
    if (toggle) {
      CollectionReference users = FirebaseFirestore.instance.collection(
        'users',
      );
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
        final isValid = await isUrlResolvable(
          normalizeUrl(linkController.text),
        );
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

  @override
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
}
