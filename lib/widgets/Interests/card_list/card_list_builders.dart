part of '../CardList.dart';

const int _maxFavorites = 5;

// Top-level build() plus the Favorites-section grouping and individual
// interest-card rendering.
mixin _CardListBuildersMixin on _CardListStateBase {
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

    // Drag-to-reorder is only for the signed-in owner outside edit mode. That
    // also guarantees visibleInterests is localInterests itself (no privacy
    // filtering), which the Favorites/rest split and
    // _handleReorderWithinGroup rely on.
    final bool canReorder =
        widget.signedIn && widget.showInputForm && editingId.isEmpty;

    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent, width: 5.0),
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        children: [
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
                      if (save == null)
                        return; // user dismissed the dialog — do nothing

                      if (save) {
                        // Look up the editing interest and its controllers by ID.
                        final idx = localInterests.indexWhere(
                          (i) => i.id == editingId,
                        );
                        if (idx != -1) {
                          final interest = localInterests[idx];
                          final titleController =
                              _titleControllers[editingId] ??
                              TextEditingController();
                          final richTextController =
                              _richTextControllers[editingId] ??
                              _createRichTextController(interest.description);
                          final linkController =
                              _linkControllers[editingId] ??
                              TextEditingController();

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
            child: visibleInterests.isEmpty
                ? SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show a subtle loading indicator while retries are in
                        // flight so the user knows the app is working and not
                        // just blank.
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
                      ],
                    ),
                  )
                : _buildInterestList(
                    context,
                    userModel,
                    visibleInterests,
                    canReorder,
                    groupFavorites: editingId.isEmpty,
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
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(10),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onItemTapped(1);
                          },
                          child: Text("Sign in or Sign Up"),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(10),
                        child: Center(
                          child: Text(
                            'to access your interests page.',
                            style: TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.signedIn && widget.showInputForm && !isEditingAny)
            Column(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton(
                    onPressed: () async {
                      await createNewInterest();
                    },
                    child: Text(
                      "Add Interest",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
        ],
      ),
    );
  }

  // Builds the whole interests list: the pinned "Favorites" section (a
  // collapsible dropdown showing the starred interests, capped at 5 by the
  // database) followed by the rest, in the persisted manual order. When a
  // single interest is being edited, [groupFavorites] is false and only that
  // one card is shown, with no sectioning or dragging.
  Widget _buildInterestList(
    BuildContext context,
    UserModel userModel,
    List<Interest> visibleInterests,
    bool canReorder, {
    required bool groupFavorites,
  }) {
    if (!groupFavorites) {
      return SingleChildScrollView(
        child: Column(
          children: visibleInterests
              .map(
                (interest) => KeyedSubtree(
                  key: ValueKey(interest.id),
                  child: _buildInterestCard(context, userModel, interest),
                ),
              )
              .toList(),
        ),
      );
    }

    final favoriteInterests = visibleInterests
        .where((i) => i.favorite)
        .toList();
    final otherInterests = visibleInterests.where((i) => !i.favorite).toList();

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (favoriteInterests.isNotEmpty) ...[
            _buildFavoritesSectionHeader(favoriteInterests.length),
            if (_favoritesExpanded)
              _buildInterestSection(
                context,
                userModel,
                favoriteInterests,
                canReorder,
                true,
              ),
            if (otherInterests.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Divider(color: Colors.grey[300], height: 1),
              ),
          ],
          _buildInterestSection(
            context,
            userModel,
            otherInterests,
            canReorder,
            false,
          ),
        ],
      ),
    );
  }

  // Header row for the pinned Favorites section — a dropdown the owner (or
  // anyone browsing) can tap to expand or collapse the starred interests.
  Widget _buildFavoritesSectionHeader(int count) {
    return InkWell(
      onTap: () => setState(() => _favoritesExpanded = !_favoritesExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            const Icon(Icons.star, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              'Favorites ($count/$_maxFavorites)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Icon(
              _favoritesExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  // Renders one section (either the pinned favorites or the rest) as either
  // a plain list (read-only viewers, or when dragging is disabled) or a
  // ReorderableListView (the owner, who can long-press/click-and-drag a
  // card's handle to reorder it within this section).
  Widget _buildInterestSection(
    BuildContext context,
    UserModel userModel,
    List<Interest> items,
    bool canReorder,
    bool isFavoriteGroup,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    if (!canReorder) {
      return Column(
        children: items
            .map(
              (interest) => KeyedSubtree(
                key: ValueKey(interest.id),
                child: _buildInterestCard(context, userModel, interest),
              ),
            )
            .toList(),
      );
    }

    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) =>
          _handleReorderWithinGroup(items, isFavoriteGroup, oldIndex, newIndex),
      itemBuilder: (itemContext, index) => _buildInterestCard(
        itemContext,
        userModel,
        items[index],
        dragIndex: index,
      ),
    );
  }

  // Builds a single interest card. When [dragIndex] is provided, a drag
  // handle is attached so the card can be reordered within whichever
  // ReorderableListView it lives in: long-press on touch devices, or the
  // trailing drag handle on desktop and web.
  Widget _buildInterestCard(
    BuildContext context,
    UserModel userModel,
    Interest interest, {
    int? dragIndex,
  }) {
    final String id = interest.id;
    final String toggleKey = id;
    bool toggle = userModel.getToggle(toggleKey);
    final shouldHighlightFromFeed =
        userModel.feedHighlightedInterestOwnerUid == userModel.alternateUid &&
        userModel.feedHighlightedInterestId == id;

    final titleController = _titleControllers[id] ?? TextEditingController();
    final richTextController =
        _richTextControllers[id] ??
        _createRichTextController(interest.description);
    final linkController = _linkControllers[id] ?? TextEditingController();

    final Widget card = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Card(
        color: shouldHighlightFromFeed ? const Color(0xFFFFF3CD) : null,
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
                                : TextDecoration.underline,
                          ),
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
                                richTextController,
                              );
                              if (mounted) setState(() {});
                            },
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child:
                                        _getRichTextPlainText(
                                          richTextController,
                                        ).trim().isEmpty
                                        ? Text(
                                            'Enter a description of the interest.',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                            ),
                                          )
                                        : SingleChildScrollView(
                                            child: RichTextEditorWidget(
                                              mode: RichTextEditorMode.view,
                                              controller: richTextController,
                                              maxLines: null,
                                            ),
                                          ),
                                  ),
                                  Icon(Icons.edit, color: Colors.grey[600]),
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
                    // Flexible + isExpanded let the dropdown shrink below
                    // its widest item ("Friends & followers") instead of
                    // forcing the row past the drawer width, which was
                    // overflowing on narrow screens. The selected label
                    // ellipsizes when space is tight; menu items are
                    // unaffected.
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 175),
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: [0, 2, 3, 4].contains(interest.privacy)
                              ? interest.privacy
                              : 4,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text("Private")),
                            DropdownMenuItem(
                              value: 2,
                              child: Text(
                                "Friends & followers",
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text("Friends only"),
                            ),
                            DropdownMenuItem(value: 4, child: Text("Public")),
                          ],
                          onChanged: (int? newValue) async {
                            if (newValue == null) return;

                            Interest newInterest = interest.copyWith(
                              privacy: newValue,
                            );

                            setState(() {
                              final li = localInterests.indexWhere(
                                (i) => i.id == id,
                              );
                              if (li != -1) {
                                localInterests[li] = newInterest;
                              }
                            });

                            await fu.updateEditedInterest(
                              FirebaseFirestore.instance.collection('users'),
                              interest,
                              newInterest,
                              widget.uid,
                            );
                          },
                        ),
                      ),
                    ),
                  SizedBox(width: 20),
                  if (widget.showInputForm)
                    IconButton(
                      icon: Icon(
                        Icons.star,
                        color: interest.favorite
                            ? Colors.orange
                            : Colors.blueGrey,
                      ),
                      onPressed: () async {
                        CollectionReference users = FirebaseFirestore.instance
                            .collection('users');
                        bool favorited = !interest.favorite;
                        Interest newInterest = interest.copyWith(
                          favorite: !interest.favorite,
                          favorited_timestamp: favorited
                              ? DateTime.now()
                              : interest.favorited_timestamp,
                        );

                        setState(() {
                          final li = localInterests.indexWhere(
                            (i) => i.id == id,
                          );
                          if (li != -1) {
                            localInterests[li] = newInterest;
                          }
                          final nid = newInterest.id;
                          _titleControllers[nid]?.text = newInterest.name;
                          _linkControllers[nid]?.text = newInterest.link ?? '';
                        });

                        await fu.updateEditedInterest(
                          users,
                          interest,
                          newInterest,
                          widget.uid,
                        );
                        List<Interest> updatedInterests =
                            await refreshInterestsForUser(widget.uid);

                        setState(() {
                          localInterests = updatedInterests;
                          _syncControllersWithInterests();
                        });
                      },
                    ),
                  if (widget.showInputForm && !toggle)
                    IconButton(
                      tooltip: 'Post to my feed',
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        _showPostInterestToFeedDialog(interest);
                      },
                    ),
                  if (widget.showInputForm && !_searchKeyboardActive)
                    IconButton(
                      icon: Icon(toggle ? Icons.save : Icons.edit),
                      onPressed: () async {
                        final li = localInterests.indexWhere((i) => i.id == id);
                        await editing(
                          interest,
                          toggle,
                          titleController,
                          richTextController,
                          linkController,
                          li,
                          id,
                          toggleKey,
                        );
                      },
                    ),
                  if (widget.showInputForm && !toggle)
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () => showDialog<String>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: const Text(
                            'Are you sure you want\nto delete this interest?',
                          ),
                          content: Text(
                            'This will permanently delete\nthe interest \"${interest.name}\"',
                            textAlign: TextAlign.center,
                          ),
                          actions: <Widget>[
                            Center(
                              child: Column(
                                children: <Widget>[
                                  TextButton(
                                    onPressed: () {
                                      CollectionReference users =
                                          FirebaseFirestore.instance.collection(
                                            'users',
                                          );
                                      Interest oldInterest = Interest(
                                        id: interest.id,
                                        nextInterestId: interest.nextInterestId,
                                        active: interest.active,
                                        name: interest.name,
                                        description: interest.description,
                                        link: interest.link,
                                        favorite: interest.favorite,
                                        favorited_timestamp:
                                            interest.favorited_timestamp,
                                        created_timestamp:
                                            interest.created_timestamp,
                                        updated_timestamp:
                                            interest.updated_timestamp,
                                        privacy: interest.privacy,
                                      );

                                      fu.removeInterest(
                                        users,
                                        oldInterest,
                                        widget.uid,
                                      );

                                      setState(() {
                                        _disposeControllersForId(id);
                                        localInterests.removeWhere(
                                          (i) => i.id == id,
                                        );
                                      });

                                      Navigator.pop(context, 'Delete');
                                    },
                                    child: const Text('Yes'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, 'Never mind'),
                                    child: const Text('No'),
                                  ),
                                ],
                              ),
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
                ),
            ],
          ),
        ),
      ),
    );

    // ReorderableListView needs the key on the widget the
    // item builder returns, not on a descendant.
    if (dragIndex == null) {
      return KeyedSubtree(key: ValueKey(id), child: card);
    }

    switch (Theme.of(context).platform) {
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
        // Custom drag handle: the framework default sits flush against
        // the card edge, so give it its own padding and inset.
        return Stack(
          key: ValueKey(id),
          children: [
            card,
            Positioned.directional(
              textDirection: Directionality.of(context),
              top: 8,
              bottom: 8,
              end: 12,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ReorderableDragStartListener(
                  index: dragIndex,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return ReorderableDelayedDragStartListener(
          key: ValueKey(id),
          index: dragIndex,
          child: card,
        );
    }
  }
}
