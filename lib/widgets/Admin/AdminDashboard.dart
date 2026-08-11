import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/AdminUtility.dart';
import 'package:intrst/widgets/Admin/AdminUserCard.dart';
import 'package:intrst/widgets/Admin/QaTestRunnerPanel.dart';

/// Web + debug-only admin dashboard.
///
/// **Users** lets an admin browse every intrst user (loaded in buffered batches
/// of [AdminUtility.pageSize] as they scroll), search across users, and
/// permanently delete a user's account.
///
/// **Patrol tests** lists every scenario in the project's test registry and
/// replays any of them live on screen — see [QaTestRunnerPanel].
///
/// This screen is gated to `kIsWeb && kDebugMode`; the entry point that opens
/// it (a Drawer item in the home page) applies the same gate, and the delete
/// Cloud Function independently verifies the caller is an admin.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, this.initialTabIndex = 0});

  /// Which tab to open on: 0 = Users, 1 = Patrol tests. The PiP's "Back to
  /// dashboard" returns straight to the Patrol tests tab.
  final int initialTabIndex;

  /// Tab index of the Patrol tests tab.
  static const int patrolTestsTabIndex = 1;

  static const Color _brand = Color(0xFF082D38);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AdminUtility _admin = AdminUtility();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Browse (paginated) state.
  final List<AdminUserRecord> _users = <AdminUserRecord>[];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoadingPage = false;
  bool _didInitialLoad = false;
  String? _loadError;

  // Search state.
  Timer? _searchDebounce;
  String _searchQuery = '';
  bool _isSearching = false;
  List<AdminUserRecord> _searchResults = <AdminUserRecord>[];

  // Deletion state (uids currently being deleted).
  final Set<String> _deletingUids = <String>{};

  // Emails (from Firebase Auth) keyed by user uid. Absent = not yet fetched;
  // empty string = fetched but none on file. Loaded lazily per visible batch.
  final Map<String, String> _emailsByUid = <String, String>{};
  final Set<String> _emailsInFlight = <String>{};

  bool get _searchMode => _searchQuery.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_searchMode) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingPage || !_hasMore) return;
    setState(() {
      _isLoadingPage = true;
      _loadError = null;
    });
    try {
      final page = await _admin.fetchUserPage(startAfter: _lastDoc);
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
        _didInitialLoad = true;
      });
      _fetchEmailsFor(page.users.map((u) => u.userUid).toList());
      // If the freshly loaded content doesn't fill the viewport there is
      // nothing to scroll, so keep pulling batches of 5 until it does (or we
      // run out of users).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _searchMode) return;
        if (_hasMore &&
            !_isLoadingPage &&
            _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent <= 0) {
          _loadNextPage();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load users: $e';
        _didInitialLoad = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPage = false;
        });
      }
    }
  }

  /// Fetches (and caches) Firebase Auth emails for any of [uids] not already
  /// loaded or in flight, then updates the cards showing them.
  Future<void> _fetchEmailsFor(List<String> uids) async {
    final needed = uids
        .where((u) => u.isNotEmpty)
        .where((u) => !_emailsByUid.containsKey(u))
        .where((u) => !_emailsInFlight.contains(u))
        .toSet()
        .toList();
    if (needed.isEmpty) return;

    _emailsInFlight.addAll(needed);
    try {
      final emails = await _admin.fetchUserEmails(needed);
      if (!mounted) return;
      setState(() {
        for (final uid in needed) {
          _emailsByUid[uid] = emails[uid] ?? '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      // Mark as resolved (empty) so the cards stop showing a loading state.
      setState(() {
        for (final uid in needed) {
          _emailsByUid.putIfAbsent(uid, () => '');
        }
      });
    } finally {
      _emailsInFlight.removeAll(needed);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String value) async {
    final trimmed = value.trim();
    setState(() {
      _searchQuery = value;
    });
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = <AdminUserRecord>[];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });
    try {
      final results = await _admin.searchUsers(trimmed);
      if (!mounted || _searchController.text.trim() != trimmed) return;
      setState(() {
        _searchResults = results;
      });
      _fetchEmailsFor(results.map((u) => u.userUid).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _confirmDelete(AdminUserRecord record) async {
    final label = record.fullName.isEmpty ? record.userUid : record.fullName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete user permanently?'),
          content: Text(
            'This permanently deletes $label\'s Firebase Auth account and all '
            'of their data (interests, friendships, activity, and messages). '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete forever'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteUser(record);
    }
  }

  Future<void> _deleteUser(AdminUserRecord record) async {
    final uid = record.userUid;
    if (uid.isEmpty || _deletingUids.contains(uid)) return;

    setState(() {
      _deletingUids.add(uid);
    });
    try {
      await _admin.deleteUserCompletely(uid);
      if (!mounted) return;
      setState(() {
        _users.removeWhere((u) => u.userUid == uid);
        _searchResults.removeWhere((u) => u.userUid == uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${record.fullName.isEmpty ? uid : record.fullName}.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingUids.remove(uid);
        });
      }
    }
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search users by name or UID',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _runSearch('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text('No users match "${_searchQuery.trim()}".'),
      );
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final record = _searchResults[index];
        return AdminUserCard(
          record: record,
          email: _emailsByUid[record.userUid],
          isDeleting: _deletingUids.contains(record.userUid),
          onDelete: () => _confirmDelete(record),
        );
      },
    );
  }

  Widget _buildBrowseList() {
    if (!_didInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _users.isEmpty) {
      return Center(child: Text(_loadError!));
    }
    if (_users.isEmpty) {
      return const Center(child: Text('No users found.'));
    }

    // One extra row at the end for the loader / "load more" / end-of-list.
    return ListView.builder(
      controller: _scrollController,
      itemCount: _users.length + 1,
      itemBuilder: (context, index) {
        if (index < _users.length) {
          final record = _users[index];
          return AdminUserCard(
            record: record,
            email: _emailsByUid[record.userUid],
            isDeleting: _deletingUids.contains(record.userUid),
            onDelete: () => _confirmDelete(record),
          );
        }
        return _buildListFooter();
      },
    );
  }

  Widget _buildListFooter() {
    if (_isLoadingPage) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton(
            onPressed: _loadNextPage,
            child: const Text('Load more'),
          ),
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Text(
          'End of list',
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Defense in depth: this screen must never render outside web debug builds.
    if (!(kIsWeb && kDebugMode)) {
      return const Scaffold(
        body: Center(
          child: Text('The admin dashboard is only available in web debug builds.'),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F5),
        appBar: AppBar(
          backgroundColor: AdminDashboard._brand,
          foregroundColor: Colors.white,
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.science_outlined), text: 'Patrol tests'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(),
            const QaTestRunnerPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        _buildSearchField(),
        Expanded(
          child: _searchMode ? _buildSearchResults() : _buildBrowseList(),
        ),
      ],
    );
  }
}
