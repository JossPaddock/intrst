import 'qa_scenario.dart';
import 'scenarios/blocking_scenarios.dart';
import 'scenarios/marker_preview_scenarios.dart';
import 'scenarios/preview_login_scenarios.dart';

/// The catalogue of every Patrol scenario in the project.
///
/// This is the single source of truth. `test/*_patrol_test.dart` registers
/// these as `patrolWidgetTest`s for `flutter test` / CI, and the admin
/// dashboard lists and replays the very same entries — so the dashboard always
/// shows the full scope of what is tested, and cannot drift from it.
///
/// To add coverage: write the scenario under `lib/qa/scenarios/`, add it below,
/// and it appears in both places automatically.
class QaRegistry {
  const QaRegistry._();

  /// Built fresh on each call so scenarios that hold per-run state start clean.
  static List<QaScenario> all() => <QaScenario>[
        ...blockingScenarios(),
        ...markerPreviewScenarios(),
        ...previewLoginScenarios(),
      ];

  /// [all], grouped by suite, preserving declaration order.
  static Map<String, List<QaScenario>> bySuite() {
    final grouped = <String, List<QaScenario>>{};
    for (final scenario in all()) {
      grouped.putIfAbsent(scenario.suite, () => <QaScenario>[]).add(scenario);
    }
    return grouped;
  }
}
