import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:intrst/qa/qa_scenario.dart';

// Aliased because this file defines its own `phase` (the QaDriver method).
import 'test_phase.dart' as test_phase;

/// Runs [QaScenario]s as ordinary Patrol widget tests.
///
/// The scenarios themselves live in `lib/qa/` so the admin dashboard can replay
/// them on screen; this bridge is what makes `flutter test`,
/// `scripts/run_tests.sh` and CI execute those same definitions headlessly.

/// Executes a scenario against a real [PatrolTester].
class PatrolQaDriver implements QaDriver {
  PatrolQaDriver(this._$);

  final PatrolTester _$;

  Finder _finder(QaLocator locator) => switch (locator) {
        QaTextLocator(:final text) => find.text(text),
        QaTypeLocator(:final type) => find.byType(type),
        QaKeyLocator(:final key) => find.byKey(key),
      };

  @override
  // Reuses the existing phase() helper, so tool/test_report.dart still prints
  // the phase breakdown when a scenario fails.
  Future<void> phase(String name, Future<void> Function() body) =>
      test_phase.phase(name, body);

  @override
  Future<void> tap(QaLocator locator) async {
    await _$.tester.tap(_finder(locator));
    await _$.pumpAndSettle();
  }

  @override
  Future<void> enterText(QaLocator locator, String text) async {
    await _$.tester.enterText(_finder(locator), text);
    await _$.pumpAndSettle();
  }

  @override
  Future<void> settle() => _$.pumpAndSettle();

  @override
  Future<void> expectVisible(QaLocator locator, {int? count}) async {
    expect(
      _finder(locator),
      count == null ? findsAtLeastNWidgets(1) : findsNWidgets(count),
      reason: 'expected ${locator.description} to be visible',
    );
  }

  @override
  Future<void> expectAbsent(QaLocator locator) async {
    expect(
      _finder(locator),
      findsNothing,
      reason: 'expected ${locator.description} not to be present',
    );
  }

  @override
  Future<void> check(String label, bool Function() condition) async {
    expect(condition(), isTrue, reason: label);
  }
}

/// Registers [scenarios] as Patrol widget tests, grouped by suite so the test
/// names read the same way they did before the scenarios were extracted.
void registerQaScenarios(List<QaScenario> scenarios) {
  final bySuite = <String, List<QaScenario>>{};
  for (final scenario in scenarios) {
    bySuite.putIfAbsent(scenario.suite, () => <QaScenario>[]).add(scenario);
  }

  bySuite.forEach((suite, suiteScenarios) {
    group(suite, () {
      for (final scenario in suiteScenarios) {
        patrolWidgetTest(scenario.name, ($) async {
          final build = scenario.build;
          if (build != null) {
            await $.pumpWidgetAndSettle(await build());
          }
          await scenario.body(PatrolQaDriver($));
        });
      }
    });
  });
}
