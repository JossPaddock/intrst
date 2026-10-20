/// A single, runner-agnostic unit test.
///
/// Written **once** here in `lib/` and executed by two runners, exactly like
/// [QaScenario] is for Patrol tests:
///
///  * the headless bridge (`test/support/unit_test_bridge.dart`) turns every
///    runnable [UnitTest] into an ordinary `test(...)`, so `flutter test` and CI
///    keep running them as the source of truth;
///  * the in-app runner (`unit_test_runner.dart`) runs the same body inside the
///    live app and streams its console output into the admin dashboard's
///    **Unit tests** tab.
///
/// A [UnitTest] with a null [body] is a **read-only listing** — a test that can
/// only run under the `flutter test` harness (e.g. `testWidgets`), shown in the
/// dashboard for completeness but not runnable in-app.
library;

/// The assertions a [UnitTest] body may make. Deliberately tiny and dependency
/// free (no `package:flutter_test`) so the very same body runs inside the app
/// and under `flutter test`. Each failed assertion throws [UnitTestFailure];
/// the bridge translates that into a normal `expect` failure, the in-app runner
/// paints it red.
class UnitTestContext {
  /// Console-style lines the test emits explicitly (in addition to anything the
  /// code under test `print`s, which the in-app runner captures separately).
  final List<String> log = <String>[];

  /// Adds a line to this test's console output.
  void note(String message) => log.add(message);

  /// Asserts deep equality. Sets compare unordered and collections compare
  /// structurally, mirroring `flutter_test`'s default `equals` matcher.
  void expectEqual(Object? actual, Object? expected, {String? reason}) {
    if (!_deepEquals(actual, expected)) {
      throw UnitTestFailure(
          reason ?? 'Expected <$expected> but got <$actual>');
    }
  }

  void expectTrue(bool condition, {String? reason}) {
    if (!condition) throw UnitTestFailure(reason ?? 'Expected true, was false');
  }

  void expectFalse(bool condition, {String? reason}) {
    if (condition) throw UnitTestFailure(reason ?? 'Expected false, was true');
  }

  void expectEmpty(Iterable<Object?> actual, {String? reason}) {
    if (actual.isNotEmpty) {
      throw UnitTestFailure(
          reason ?? 'Expected empty, had ${actual.length} element(s)');
    }
  }

  /// Asserts `|actual - expected| <= delta` (the `closeTo` matcher).
  void expectClose(num actual, num expected, num delta, {String? reason}) {
    if ((actual - expected).abs() > delta) {
      throw UnitTestFailure(reason ??
          'Expected <$expected> ±$delta but got <$actual>');
    }
  }

  /// Asserts `actual <= max` (the `lessThanOrEqualTo` matcher).
  void expectLessOrEqual(num actual, num max, {String? reason}) {
    if (actual > max) {
      throw UnitTestFailure(reason ?? 'Expected <= <$max> but got <$actual>');
    }
  }
}

/// Thrown by a [UnitTestContext] assertion when it fails.
class UnitTestFailure implements Exception {
  UnitTestFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The test body: a synchronous set of assertions against [t].
typedef UnitTestBody = void Function(UnitTestContext t);

/// One named unit test.
class UnitTest {
  const UnitTest({
    required this.suite,
    required this.name,
    required this.summary,
    this.doc,
    this.body,
    this.harnessOnlyReason,
  });

  /// Groups related tests. Becomes the `group(...)` name under `flutter test`
  /// and the section header in the dashboard.
  final String suite;

  /// What this test proves, phrased as the test name.
  final String name;

  /// One line explaining why the test exists, shown on the dashboard tile.
  final String summary;

  /// Long-form documentation for this test, shown in a scrollable preview when
  /// its tile is tapped in the dashboard. Lightweight markdown (`##` headings,
  /// `-` bullets, `**bold**`, `` `code` ``). Falls back to [summary] when null
  /// — see [docText].
  final String? doc;

  /// The doc to show, falling back to the one-line [summary].
  String get docText => (doc == null || doc!.trim().isEmpty) ? summary : doc!;

  /// The assertions. Null for read-only listings that only run under the
  /// `flutter test` harness (see [harnessOnlyReason]).
  final UnitTestBody? body;

  /// Why a read-only listing can't run in-app (shown greyed in the dashboard).
  final String? harnessOnlyReason;

  /// Whether this test can be executed inside the running app.
  bool get runnable => body != null;

  /// Stable identity for dashboard selection and result bookkeeping.
  String get id => '$suite :: $name';
}

/// Structural equality: unordered for [Set], positional for [List], key-wise
/// for [Map], `==` otherwise.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Set && b is Set) {
    if (a.length != b.length) return false;
    for (final element in a) {
      if (!b.any((other) => _deepEquals(element, other))) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}
