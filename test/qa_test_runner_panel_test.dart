import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/e2e/qa_run_history.dart';
import 'package:intrst/qa/qa_registry.dart';
import 'package:intrst/qa/qa_scenario.dart';
import 'package:intrst/widgets/Admin/QaTestRunnerPanel.dart';

/// Covers the admin dashboard's Patrol panel itself: that it lists the real
/// registry, and that its run controls launch the right scenarios. The actual
/// live run drives the real app + PiP (see LiveE2eRunner), which is exercised
/// separately; here the launch is intercepted via [QaTestRunnerPanel.onLaunch].
void main() {
  Future<List<QaScenario>?> tapAndCapture(
    WidgetTester tester,
    Finder control,
  ) async {
    List<QaScenario>? launched;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QaTestRunnerPanel(onLaunch: (scenarios) => launched = scenarios),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(control);
    await tester.pump();
    return launched;
  }

  testWidgets('lists the whole registry, so the dashboard cannot drift from it',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QaTestRunnerPanel())),
    );
    await tester.pumpAndSettle();

    final scenarios = QaRegistry.all();
    final suites = scenarios.map((s) => s.suite).toSet();

    expect(
      find.text('${scenarios.length} scenarios across ${suites.length} suites'),
      findsOneWidget,
    );
    for (final suite in suites) {
      expect(find.text(suite), findsWidgets, reason: 'missing suite $suite');
    }
  });

  testWidgets("a scenario's ▶ launches just that scenario", (tester) async {
    final launched = await tapAndCapture(
      tester,
      find.widgetWithIcon(IconButton, Icons.play_arrow).first,
    );

    expect(launched, isNotNull);
    expect(launched!.length, 1);
    expect(launched.single.name, QaRegistry.all().first.name);
  });

  testWidgets('Run all launches every scenario in the registry',
      (tester) async {
    final launched = await tapAndCapture(
      tester,
      find.widgetWithText(OutlinedButton, 'Run all'),
    );

    expect(launched, isNotNull);
    expect(launched!.length, QaRegistry.all().length);
  });

  testWidgets('a logic-only scenario is labelled as having nothing to watch',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QaTestRunnerPanel())),
    );
    await tester.pumpAndSettle();

    expect(find.text('logic check — nothing to watch'), findsWidgets);
  });

  testWidgets('shows each scenario\'s last-run time and status', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Seed one scenario's last run into a fake backend.
    final fake = FakeFirebaseFirestore();
    final first = QaRegistry.all().first;
    await fake.collection(QaRunHistory.collection).doc('seeded').set({
      'scenario_id': first.id,
      'suite': first.suite,
      'name': first.name,
      'last_run_at': Timestamp.fromDate(DateTime(2026, 8, 10, 14, 30)),
      'last_status': 'passed',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QaTestRunnerPanel(history: QaRunHistory(firestore: fake)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The recorded scenario shows its time + status; the rest show "Not run yet".
    expect(find.text('Last run 2026-08-10 14:30 · passed'), findsOneWidget);
    expect(find.text('Not run yet'), findsWidgets);
  });
}
