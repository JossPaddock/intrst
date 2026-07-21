part of '../CardList.dart';

// "Share this interest" tab: user search, selection chips, and the
// already-shared-with row.
mixin _CardListSharingMixin on _CardListStateBase {
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
        .where(
          (value) =>
              value.isNotEmpty &&
              value != widget.uid &&
              !selectedItems.contains(value),
        )
        .toSet()
        .toList();

    setState(() {
      searchResults = filtered;
      _isSearchingUsers = false;
    });
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
                            users: FirebaseFirestore.instance.collection(
                              'users',
                            ),
                            ownerUid: widget.uid,
                            interestId: interest.id,
                            targetUid: uid,
                          );

                          if (success) {
                            setState(() {
                              final idx = localInterests.indexWhere(
                                (i) => i.id == interest.id,
                              );
                              if (idx != -1) {
                                final updated = List<String>.from(
                                  localInterests[idx].sharedWithUids,
                                )..remove(uid);
                                localInterests[idx] = localInterests[idx]
                                    .copyWith(sharedWithUids: updated);
                              }
                            });
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not remove access, please try again.',
                                ),
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

  @override
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
        final updatedSharedWith = {
          ...interest.sharedWithUids,
          ...targets,
        }.toList();

        setState(() {
          final idx = localInterests.indexWhere((i) => i.id == interest.id);
          if (idx != -1) {
            localInterests[idx] = localInterests[idx].copyWith(
              sharedWithUids: updatedSharedWith,
            );
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
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  label: Text(name, style: const TextStyle(fontSize: 13)),
                  onPressed: () => _toggleSelectedUser(uid),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
