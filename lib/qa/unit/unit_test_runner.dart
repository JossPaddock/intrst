import 'dart:async';

import 'unit_test.dart';

/// The result of running one [UnitTest] inside the app.
class UnitTestResult {
  const UnitTestResult({
    required this.passed,
    required this.output,
    this.failure,
  });

  final bool passed;

  /// Console output for the dashboard: everything the code under test
  /// `print`ed, plus any explicit [UnitTestContext.note] lines, plus a final
  /// failure line when it failed.
  final List<String> output;

  /// The failure message, or null when it passed.
  final String? failure;
}

/// Runs [UnitTest]s inside the live app (the dashboard's counterpart to the
/// `flutter test` bridge). It captures `print` output via a [Zone] so the code
/// under test needs no special hooks, and never throws — a failed assertion
/// becomes a failed [UnitTestResult].
class UnitTestRunner {
  const UnitTestRunner._();

  static UnitTestResult run(UnitTest test) {
    final body = test.body;
    if (body == null) {
      return UnitTestResult(
        passed: false,
        output: <String>[
          test.harnessOnlyReason ?? 'Not runnable in the app.',
        ],
        failure: 'Not runnable in the app.',
      );
    }

    final context = UnitTestContext();
    final captured = <String>[];
    bool passed = false;
    String? failure;

    runZoned(
      () {
        try {
          body(context);
          passed = true;
        } on UnitTestFailure catch (e) {
          failure = e.message;
        } catch (e) {
          failure = e.toString();
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => captured.add(line),
      ),
    );

    return UnitTestResult(
      passed: passed,
      output: <String>[
        ...captured,
        ...context.log,
        if (failure != null) 'FAILED: $failure',
      ],
      failure: failure,
    );
  }
}
