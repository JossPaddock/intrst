import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/unit/unit_test.dart';

/// Runs [UnitTest]s as ordinary `flutter test` cases.
///
/// The tests themselves live in `lib/qa/unit/` so the admin dashboard's
/// **Unit tests** tab can run them in-app; this bridge is what makes
/// `flutter test`, `scripts/run_tests.sh` and CI execute those same definitions
/// headlessly. Read-only listings (no [UnitTest.body]) are skipped — they only
/// run under their own `testWidgets` files.
void registerUnitTests(List<UnitTest> tests) {
  final bySuite = <String, List<UnitTest>>{};
  for (final test in tests) {
    if (test.body == null) continue;
    bySuite.putIfAbsent(test.suite, () => <UnitTest>[]).add(test);
  }

  bySuite.forEach((suite, suiteTests) {
    group(suite, () {
      for (final unitTest in suiteTests) {
        test(unitTest.name, () {
          final context = UnitTestContext();
          try {
            unitTest.body!(context);
          } on UnitTestFailure catch (e) {
            fail(e.message);
          }
        });
      }
    });
  });
}
