import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Seeds — and precisely un-seeds — the **live** Firestore for a single live QA
/// run.
///
/// The live runner drives production against the real project, so this is the
/// safety layer. Two rules make cleanup unable to touch real data:
///
///  1. Every document this creates lives under the reserved [prefix] id
///     namespace (`users/qa_e2e_*`, `messages/qa_e2e_conv_*`), created with an
///     **explicit** document id we control.
///  2. Cleanup deletes only the exact [DocumentReference]s it created (tracked
///     in [_created]) — never a query-and-delete — and reverses field mutations
///     on real docs (e.g. a block added to the test account) by removing only
///     the exact value it added.
///
/// A [QaSeeder] is single-use: create one per run, and call [cleanup] in a
/// `finally` so a failed body still tidies up.
class QaSeeder {
  QaSeeder({FirebaseFirestore? firestore}) : _explicitDb = firestore;

  // Resolved lazily: a QaSeeder is constructed eagerly when the scenario
  // registry is built (including under `flutter test`, where Firebase is not
  // initialized), but Firestore is only ever touched once a live run actually
  // seeds — where Firebase is guaranteed to be up.
  final FirebaseFirestore? _explicitDb;

  FirebaseFirestore get _db => _explicitDb ?? FirebaseFirestore.instance;

  /// The reserved id namespace. Nothing outside it is ever created or deleted.
  static const String prefix = 'qa_e2e_';

  /// A convenient uid for "the other user" in a two-party scenario.
  static const String otherUid = '${prefix}other';

  final List<DocumentReference<Map<String, dynamic>>> _created =
      <DocumentReference<Map<String, dynamic>>>[];
  final List<_ArrayFieldRestore> _restores = <_ArrayFieldRestore>[];

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _messages =>
      _db.collection('messages');

  int get createdCount => _created.length;

  /// Creates a `users` doc under the reserved namespace. [uid] must start with
  /// [prefix]; it becomes both the document id and the `user_uid` field the app
  /// looks users up by.
  Future<void> seedUser({
    required String uid,
    required String firstName,
    required String lastName,
    List<Map<String, dynamic>> interests = const <Map<String, dynamic>>[],
    List<String> blockedUids = const <String>[],
  }) async {
    assert(uid.startsWith(prefix), 'seeded uid must be namespaced: $uid');
    final ref = _users.doc(uid);
    await ref.set(<String, dynamic>{
      'user_uid': uid,
      'first_name': firstName,
      'last_name': lastName,
      'interests': interests,
      'blocked_uids': blockedUids,
      'location': const GeoPoint(0, 0),
    });
    _created.add(ref);
  }

  /// Creates a 1:1 conversation between [selfUid] and [otherUid] with an
  /// explicit, namespaced id so cleanup can delete exactly it. Returns the ref.
  Future<DocumentReference<Map<String, dynamic>>> seedConversation({
    required String selfUid,
    required String otherUid,
  }) async {
    final id = '${prefix}conv_${_slug(selfUid)}_${_slug(otherUid)}';
    final ref = _messages.doc(id);
    await ref.set(<String, dynamic>{
      'user_uids': <String>[selfUid, otherUid],
      'conversation': <String, dynamic>{},
    });
    _created.add(ref);
    return ref;
  }

  /// Adds [targetUid] to the `blocked_uids` of the **real** user [ownerUid]
  /// (typically the signed-in test account) and records the change so [cleanup]
  /// removes exactly that value again. No-op if the owner doc isn't found.
  Future<void> addBlockOnRealUser({
    required String ownerUid,
    required String targetUid,
  }) async {
    final snapshot =
        await _users.where('user_uid', isEqualTo: ownerUid).limit(1).get();
    if (snapshot.docs.isEmpty) return;
    final ref = snapshot.docs.first.reference;
    await ref.update(<String, dynamic>{
      'blocked_uids': FieldValue.arrayUnion(<String>[targetUid]),
    });
    _restores.add(_ArrayFieldRestore(ref, 'blocked_uids', targetUid));
  }

  /// Reverses every mutation and deletes every seeded document, most-recent
  /// first. Best-effort: each step is guarded so one failure can't strand the
  /// rest. Safe to call more than once.
  Future<void> cleanup() async {
    for (final restore in _restores.reversed) {
      try {
        await restore.ref.update(<String, dynamic>{
          restore.field: FieldValue.arrayRemove(<dynamic>[restore.value]),
        });
      } catch (e) {
        debugPrint('[QA] cleanup: could not restore ${restore.field}: $e');
      }
    }
    _restores.clear();

    for (final ref in _created.reversed) {
      try {
        await ref.delete();
      } catch (e) {
        debugPrint('[QA] cleanup: could not delete ${ref.path}: $e');
      }
    }
    if (kDebugMode && _created.isNotEmpty) {
      debugPrint('[QA] cleanup: deleted ${_created.length} seeded doc(s)');
    }
    _created.clear();
  }

  /// Keeps a doc id valid and short: lowercased, non-alphanumerics dropped.
  static String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _ArrayFieldRestore {
  _ArrayFieldRestore(this.ref, this.field, this.value);

  final DocumentReference<Map<String, dynamic>> ref;
  final String field;
  final Object value;
}
