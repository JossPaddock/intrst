import 'package:cloud_firestore/cloud_firestore.dart';

import '../qa_scenario.dart';

/// The last recorded run of one scenario.
class QaRunRecord {
  const QaRunRecord({required this.lastRunAt, required this.passed});

  final DateTime lastRunAt;
  final bool passed;
}

/// Persists and reads the **last run** of each scenario, so the admin dashboard
/// can show "last run · pass/fail" on every tile across sessions.
///
/// One fixed document per scenario lives in the `qa_test_runs` collection (id
/// derived from the scenario id, with the real id stored alongside for
/// matching). Writes overwrite in place, so this never accumulates junk.
///
/// Firestore is resolved lazily (like [QaSeeder]) so constructing this — which
/// happens when the panel builds, including under `flutter test` where Firebase
/// isn't initialised — never touches Firebase until a read/write actually runs.
class QaRunHistory {
  QaRunHistory({FirebaseFirestore? firestore}) : _explicitDb = firestore;

  final FirebaseFirestore? _explicitDb;

  FirebaseFirestore get _db => _explicitDb ?? FirebaseFirestore.instance;

  static const String collection = 'qa_test_runs';

  CollectionReference<Map<String, dynamic>> get _runs =>
      _db.collection(collection);

  /// A stable, Firestore-safe document id from a `suite :: name` id.
  static String docIdFrom(String id) =>
      id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  /// A stable, Firestore-safe document id for [scenario].
  static String docIdFor(QaScenario scenario) => docIdFrom(scenario.id);

  /// Records the outcome of a run of [scenario]. Best-effort — callers ignore
  /// failures so a logging hiccup never breaks a run.
  Future<void> record(QaScenario scenario, {required bool passed}) =>
      recordById(
        id: scenario.id,
        suite: scenario.suite,
        name: scenario.name,
        passed: passed,
      );

  /// Records a run keyed by a raw `suite :: name` id, so non-scenario runs (the
  /// unit-test tab) can share the same "last run" store and [loadAll].
  Future<void> recordById({
    required String id,
    required String suite,
    required String name,
    required bool passed,
  }) async {
    await _runs.doc(docIdFrom(id)).set(<String, dynamic>{
      'scenario_id': id,
      'suite': suite,
      'name': name,
      'last_run_at': FieldValue.serverTimestamp(),
      'last_status': passed ? 'passed' : 'failed',
    });
  }

  /// Loads the last run of every scenario, keyed by [QaScenario.id].
  Future<Map<String, QaRunRecord>> loadAll() async {
    final snapshot = await _runs.get();
    final result = <String, QaRunRecord>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final id = (data['scenario_id'] as String?) ?? '';
      final ranAt = data['last_run_at'];
      if (id.isEmpty || ranAt is! Timestamp) continue;
      result[id] = QaRunRecord(
        lastRunAt: ranAt.toDate(),
        passed: (data['last_status'] as String?) == 'passed',
      );
    }
    return result;
  }
}
