import 'admin_access_unit_tests.dart';
import 'date_time_unit_tests.dart';
import 'harness_only_unit_tests.dart';
import 'ip_placement_unit_tests.dart';
import 'map_camera_memory_unit_tests.dart';
import 'map_fly_path_unit_tests.dart';
import 'message_edit_unit_tests.dart';
import 'signup_wizard_unit_tests.dart';
import 'marker_visibility_unit_tests.dart';
import 'unit_test.dart';

/// The catalogue of every unit test in the project — the single source of truth
/// for the admin dashboard's **Unit tests** tab and the `flutter test` bridge
/// (`test/*_unit_test.dart`), so the two can never drift.
///
/// Runnable tests (pure logic) carry a [UnitTest.body] and execute both in-app
/// and under `flutter test`. Harness-only entries are read-only listings shown
/// for completeness (see [harnessOnlyUnitTests]).
///
/// To add coverage: write the test under `lib/qa/unit/`, add it below, and it
/// appears in both places automatically.
class UnitTestRegistry {
  const UnitTestRegistry._();

  static List<UnitTest> all() => <UnitTest>[
        ...adminAccessUnitTests(),
        ...dateTimeUnitTests(),
        ...markerVisibilityUnitTests(),
        ...mapCameraMemoryUnitTests(),
        ...mapFlyPathUnitTests(),
        ...ipPlacementUnitTests(),
        ...messageEditUnitTests(),
        ...signupWizardUnitTests(),
        ...harnessOnlyUnitTests(),
      ];

  /// Only the tests that can run inside the app (have a body).
  static List<UnitTest> runnable() =>
      all().where((t) => t.runnable).toList();

  /// [all], grouped by suite, preserving declaration order.
  static Map<String, List<UnitTest>> bySuite() {
    final grouped = <String, List<UnitTest>>{};
    for (final test in all()) {
      grouped.putIfAbsent(test.suite, () => <UnitTest>[]).add(test);
    }
    return grouped;
  }
}
