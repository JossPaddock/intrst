import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/e2e/qa_run_history.dart';
import 'package:intrst/qa/unit/unit_test_registry.dart';
import 'package:intrst/widgets/Admin/UnitTestRunnerPanel.dart';

/// Covers the admin dashboard's Unit tests panel itself: that it lists the real
/// registry, greys out harness-only listings, and that its ▶ runs a test in-app
/// and shows the captured console output. The individual test *definitions* are
/// verified headlessly by the unit-test bridge (test/DateTimeUtility_test.dart,
/// test/marker_visibility_test.dart).
void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnitTestRunnerPanel(
            history: QaRunHistory(firestore: FakeFirebaseFirestore()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the whole registry, so the tab cannot drift from it',
      (tester) async {
    await pumpPanel(tester);

    final tests = UnitTestRegistry.all();
    final suites = tests.map((t) => t.suite).toSet();

    // The header proves the full scope; the list is lazy, so only assert the
    // first suite is rendered (the rest are covered by scrolling below).
    expect(
      find.text('${tests.length} unit tests across ${suites.length} suites'),
      findsOneWidget,
    );
    expect(find.text(tests.first.suite), findsWidgets);
  });

  testWidgets('harness-only tests are listed but not runnable', (tester) async {
    await pumpPanel(tester);

    // The harness-only listings sit at the bottom; scroll them into view.
    const suite = 'LiveQaDriver (test-harness only)';
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(suite), 300,
        scrollable: scrollable);
    await tester.pumpAndSettle();

    // Present, with its "why it can't run" note and a lock (not play) icon.
    expect(find.text(suite), findsWidgets);
    expect(find.textContaining('flutter test'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
  });

  testWidgets('running a test streams its output into the log reader',
      (tester) async {
    await pumpPanel(tester);

    // A marker test that prints to the console when it runs.
    const name = 'a lone marker labels (no neighbour at all)';
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(name), 250,
        scrollable: scrollable);
    await tester.pumpAndSettle();

    final card = find.ancestor(of: find.text(name), matching: find.byType(Card));
    final runButton = find.descendant(
      of: card,
      matching: find.widgetWithIcon(IconButton, Icons.play_arrow),
    );
    await tester.tap(runButton);
    await tester.pumpAndSettle();

    // The tile records a passing last-run...
    expect(
      find.descendant(of: card, matching: find.textContaining('passed')),
      findsWidgets,
    );
    // ...and the docked log reader shows a PASS block with the printed output.
    expect(find.textContaining('PASS  $name'), findsOneWidget);
    expect(find.textContaining('markers shown as labels'), findsWidgets);
  });

  testWidgets('tapping a tile opens a scrollable doc preview', (tester) async {
    await pumpPanel(tester);

    const name = 'a lone marker labels (no neighbour at all)';
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(name), 250,
        scrollable: scrollable);
    await tester.pumpAndSettle();

    // Tap the tile body (not the ▶ / doc buttons) to open the preview.
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();

    // The sheet shows a heading rendered from the test's markdown doc.
    expect(find.text('What it checks'), findsOneWidget);
    expect(find.textContaining('no neighbour at all'), findsWidgets);
  });

  testWidgets('the log reader can be cleared', (tester) async {
    await pumpPanel(tester);

    // Run the first runnable test via Run all-free path: tap its tile ▶.
    final firstRun =
        find.widgetWithIcon(IconButton, Icons.play_arrow).first;
    await tester.tap(firstRun);
    await tester.pumpAndSettle();

    expect(find.textContaining('PASS'), findsWidgets);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('PASS'), findsNothing);
    expect(
      find.textContaining('run a test to see its console output'),
      findsOneWidget,
    );
  });
}
