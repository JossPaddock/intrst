import 'package:flutter/widgets.dart';

import 'e2e/qa_app_harness.dart';

/// The shared definition of a Patrol scenario.
///
/// A scenario is written **once** here and executed by two different runners:
///
///  * the headless runner (`test/support/qa_scenario_bridge.dart`) turns every
///    scenario into a `patrolWidgetTest`, so `flutter test`, `scripts/run_tests.sh`
///    and CI keep working exactly as before;
///  * the live runner (`lib/qa/live_qa_driver.dart`) replays the same scenario
///    inside the running app, on screen, at human speed — that is what the admin
///    dashboard shows.
///
/// Because both runners consume the same [QaRegistry], the dashboard's list of
/// tests can never drift from the tests CI actually runs.

/// Something a scenario can point at. Each runner resolves it its own way: the
/// live driver walks the real element tree, the headless driver maps it onto a
/// `flutter_test` `Finder`.
@immutable
sealed class QaLocator {
  const QaLocator();

  /// Human-readable form, used in the dashboard's step log and failure text.
  String get description;
}

class QaTextLocator extends QaLocator {
  const QaTextLocator(this.text);

  final String text;

  @override
  String get description => 'text "$text"';
}

class QaTypeLocator extends QaLocator {
  const QaTypeLocator(this.type);

  final Type type;

  @override
  String get description => 'a $type widget';
}

class QaKeyLocator extends QaLocator {
  const QaKeyLocator(this.key);

  final Key key;

  @override
  String get description => 'key $key';
}

QaLocator qaText(String text) => QaTextLocator(text);
QaLocator qaType(Type type) => QaTypeLocator(type);
QaLocator qaKey(Key key) => QaKeyLocator(key);

/// Thrown when a scenario assertion fails. The live runner catches this and
/// paints the offending step red; under `flutter test` the headless driver uses
/// the normal `expect` machinery instead, so failures read like any other test.
class QaScenarioFailure implements Exception {
  QaScenarioFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The operations a scenario body may perform. Implemented once for widget
/// tests and once for live, on-screen playback.
abstract class QaDriver {
  /// Groups steps under a named phase. Under `flutter test` this reuses the
  /// existing `phase()` helper, so `tool/test_report.dart` still prints the
  /// phase breakdown for failures.
  Future<void> phase(String name, Future<void> Function() body);

  /// Taps the widget [locator] points at.
  Future<void> tap(QaLocator locator);

  /// Replaces the text of the editable field [locator] points at.
  Future<void> enterText(QaLocator locator, String text);

  /// Waits for pending frames and async work to finish.
  Future<void> settle();

  /// Asserts the widget is on screen. Pass [count] to require an exact number
  /// of matches (mirrors `findsNWidgets`); omit it to require at least one.
  Future<void> expectVisible(QaLocator locator, {int? count});

  /// Asserts nothing matching [locator] is on screen.
  Future<void> expectAbsent(QaLocator locator);

  /// Asserts a plain boolean, for scenarios that verify logic rather than UI.
  /// [condition] is a closure so the step is logged before it is evaluated.
  Future<void> check(String label, bool Function() condition);
}

/// Seeds/authenticates the real backend before a live-app run.
typedef QaLiveSetUp = Future<void> Function(QaAppHarness harness);

/// Drives the real running app during a live run — the live counterpart of
/// [QaScenario.body]. It gets both a [QaDriver] (scoped to the whole app) and
/// the [QaAppHarness] used to invoke real navigation.
typedef QaLiveBody = Future<void> Function(
    QaDriver driver, QaAppHarness harness);

/// Undoes whatever [QaLiveSetUp] seeded/changed. Always run, even on failure.
typedef QaLiveTearDown = Future<void> Function(QaAppHarness harness);

/// A single Patrol scenario: what to build, and what to do to it.
///
/// A scenario always carries its **headless** definition ([build] + [body]),
/// which is the CI source of truth. It may *additionally* carry a **live**
/// definition ([liveSetUp]/[liveBody]/[liveTearDown]) that the admin dashboard
/// uses to replay the same behaviour against the real running app. The two are
/// separate because they genuinely differ: the headless run mounts a sandbox
/// tree and taps proxy widgets, while the live run seeds the real backend and
/// drives production screens. The headless bridge ignores the live fields.
@immutable
class QaScenario {
  const QaScenario({
    required this.suite,
    required this.name,
    required this.summary,
    required this.body,
    this.build,
    this.liveSetUp,
    this.liveBody,
    this.liveTearDown,
  });

  /// Groups related scenarios. Becomes the `group(...)` name under
  /// `flutter test` and the section header in the dashboard.
  final String suite;

  /// What this scenario proves, phrased as the test name.
  final String name;

  /// One line explaining why the scenario exists, shown in the dashboard so
  /// the full scope of coverage is readable without opening the code.
  final String summary;

  /// Builds the widget tree to drive. It is called fresh on every run, so a
  /// scenario that captures per-run state must reset that state here.
  ///
  /// Null for pure-logic scenarios that assert on a function rather than UI —
  /// those still run and report in the dashboard, they just have nothing to
  /// watch.
  final Future<Widget> Function()? build;

  /// The scenario itself, written against the runner-agnostic [QaDriver].
  final Future<void> Function(QaDriver driver) body;

  /// Live-app hooks. When [liveBody] is non-null the dashboard drives the real
  /// app (running [liveSetUp] first and [liveTearDown] after); otherwise it
  /// falls back to [body], which for the logic-only scenarios is just a set of
  /// `check`s with nothing to navigate.
  final QaLiveSetUp? liveSetUp;
  final QaLiveBody? liveBody;
  final QaLiveTearDown? liveTearDown;

  bool get hasUi => build != null;

  /// Whether this scenario can be replayed against the real running app.
  bool get hasLive => liveBody != null;

  /// Stable identity for dashboard selection and result bookkeeping.
  String get id => '$suite :: $name';
}
