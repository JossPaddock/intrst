import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// A single user record for the admin dashboard. Wraps the raw Firestore
/// document so the info card can surface every field, while keeping the
/// underlying [DocumentSnapshot] around to use as a pagination cursor.
class AdminUserRecord {
  AdminUserRecord({
    required this.docId,
    required this.data,
    this.snapshot,
  });

  final String docId;
  final Map<String, dynamic> data;
  final DocumentSnapshot? snapshot;

  factory AdminUserRecord.fromSnapshot(DocumentSnapshot doc) {
    return AdminUserRecord(
      docId: doc.id,
      data: (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{},
      snapshot: doc,
    );
  }

  String get userUid => (data['user_uid'] ?? '').toString();
  String get firstName => (data['first_name'] ?? '').toString();
  String get lastName => (data['last_name'] ?? '').toString();
  String get fullName => '$firstName $lastName'.trim();

  int _lengthOf(String key) => data[key] is List ? (data[key] as List).length : 0;
  int get interestsCount => _lengthOf('interests');
  int get followingCount => _lengthOf('following_uids');
  int get friendsCount => _lengthOf('friends_uids');
  int get fcmTokenCount => _lengthOf('fcm_tokens');

  Map<String, dynamic> get _stats => data['profile_statistics'] is Map
      ? Map<String, dynamic>.from(data['profile_statistics'] as Map)
      : <String, dynamic>{};

  Timestamp? get profileCreatedAt => _stats['profile_created_at'] as Timestamp?;
  Timestamp? get birthday => data['birthday'] as Timestamp?;
  int get longestStreak =>
      (_stats['longest_app_usage_streak'] as num?)?.toInt() ?? 0;
  int get messagesSent => (_stats['messages_sent_count'] as num?)?.toInt() ?? 0;
  int get messagesReceived =>
      (_stats['messages_received_count'] as num?)?.toInt() ?? 0;
  GeoPoint? get location => data['location'] as GeoPoint?;
}

/// One page of paginated users plus the cursor needed to fetch the next page.
class AdminUserPage {
  AdminUserPage({
    required this.users,
    required this.lastDoc,
    required this.hasMore,
  });

  final List<AdminUserRecord> users;
  final DocumentSnapshot? lastDoc;
  final bool hasMore;
}

/// Backend for the (web + debug only) admin dashboard: buffered/paginated user
/// loading, search, and permanent user deletion via a Cloud Function.
class AdminUtility {
  AdminUtility({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;
  final CollectionReference _users =
      FirebaseFirestore.instance.collection('users');

  /// How many users are loaded per scroll batch.
  static const int pageSize = 5;

  /// Fetches the next [pageSize] users, ordered alphabetically by first name,
  /// starting after [startAfter] (pass null for the first page). Every user
  /// created through the app has a `first_name`, so they all appear here.
  Future<AdminUserPage> fetchUserPage({DocumentSnapshot? startAfter}) async {
    Query query = _users.orderBy('first_name').limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snap = await query.get();
    final users = snap.docs.map(AdminUserRecord.fromSnapshot).toList();
    return AdminUserPage(
      users: users,
      lastDoc: snap.docs.isNotEmpty ? snap.docs.last : startAfter,
      hasMore: snap.docs.length == pageSize,
    );
  }

  /// Full-collection search over name / user id / doc id. Firestore has no
  /// native substring search, and the app already scans the users collection
  /// for people search, so this mirrors that approach.
  Future<List<AdminUserRecord>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return <AdminUserRecord>[];

    final snap = await _users.get();
    final results = <AdminUserRecord>[];
    for (final doc in snap.docs) {
      final record = AdminUserRecord.fromSnapshot(doc);
      final haystack =
          '${record.fullName} ${record.userUid} ${record.docId}'.toLowerCase();
      if (haystack.contains(q)) results.add(record);
    }
    results.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return results;
  }

  /// Looks up emails (which live in Firebase Auth, not Firestore) for the given
  /// user uids via an admin-only Cloud Function. Returns a { uid: email } map;
  /// a uid maps to an empty string when no email is on file.
  Future<Map<String, String>> fetchUserEmails(List<String> uids) async {
    final cleaned = uids.where((u) => u.trim().isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return <String, String>{};

    final callable = _functions.httpsCallable('admin_get_user_emails');
    final result = await callable.call<dynamic>({'uids': cleaned});
    final emailsRaw = result.data is Map ? (result.data as Map)['emails'] : null;
    if (emailsRaw is Map) {
      return emailsRaw.map(
        (key, value) => MapEntry(key.toString(), (value ?? '').toString()),
      );
    }
    return <String, String>{};
  }

  /// Calls the admin-only Cloud Function that permanently deletes a user's
  /// Firebase Auth account and all of their Firestore data. Throws a
  /// [FirebaseFunctionsException] if the caller is not authorized or the
  /// deletion fails.
  Future<Map<String, dynamic>> deleteUserCompletely(String targetUid) async {
    final callable = _functions.httpsCallable('admin_delete_user');
    final result = await callable.call<dynamic>({'target_uid': targetUid});
    final data = result.data;
    return data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'success': true};
  }
}
