import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/e2e/live_e2e_runner.dart';
import 'package:intrst/qa/e2e/qa_app_harness.dart';
import 'package:intrst/qa/e2e/qa_pip_overlay.dart';
import 'package:intrst/qa/qa_scenario.dart';

import 'support/tester_pacer.dart';

/// Exercises the live E2E runner end-to-end under `flutter test`: it drives a
/// (fake) app through the [QaAppHarness], reports into the PiP overlay, runs
/// teardown, and fails gracefully when no app is available.
///
/// The one thing that genuinely needs a *running* app — the harness and the
/// real backend — is faked here; everything else (driver, PiP, lifecycle) is
/// the real code.
void main() {
  // A stand-in app harness: openPreviewFor pops up a dialog with the display
  // name, the way the real Preview would show the tapped user's name.
  _FakeHarness makeHarness(GlobalKey<NavigatorState> navKey) =>
      _FakeHarness(navKey);

  Future<LiveE2eRunner> pumpRunner(
    WidgetTester tester, {
    required QaAppHarness? Function() harnessProvider,
  }) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Center(child: Text('home surface'))),
      ),
    );
    return LiveE2eRunner(
      overlay: navKey.currentState!.overlay!,
      onRevealApp: () {},
      onBackToDashboard: () {},
      pacer: TesterPacer(tester),
      stepDelay: Duration.zero,
      harnessProvider: harnessProvider,
      rootProvider: () => WidgetsBinding.instance.rootElement,
    );
  }

  testWidgets('drives the live app and reports a pass in the PiP',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Center(child: Text('home surface'))),
      ),
    );
    final harness = makeHarness(navKey);

    var tearDownRan = false;
    final scenario = QaScenario(
      suite: 'Live demo',
      name: 'opens a preview and reads the name',
      summary: 'drives the fake app',
      body: (_) async {},
      liveSetUp: (h) async {}, // nothing to seed in the fake
      liveBody: (d, h) async {
        await h.openPreviewFor('other', 'Ada Lovelace');
        await d.expectVisible(qaText('Ada Lovelace'));
      },
      liveTearDown: (h) async {
        tearDownRan = true;
      },
    );

    final runner = LiveE2eRunner(
      overlay: navKey.currentState!.overlay!,
      onRevealApp: () {},
      onBackToDashboard: () {},
      pacer: TesterPacer(tester),
      stepDelay: Duration.zero,
      harnessProvider: () => harness,
      rootProvider: () => WidgetsBinding.instance.rootElement,
    );

    // The run pumps the tester itself (through TesterPacer), so await it rather
    // than pumping alongside it.
    await runner.run(<QaScenario>[scenario]);
    await tester.pump();

    expect(runner.view.status, QaRunStatus.passed);
    expect(runner.view.finished, isTrue);
    expect(tearDownRan, isTrue, reason: 'teardown must always run');

    // The PiP is up and shows the pass (its own text is chrome, so the driver
    // never saw it, but the test finder does).
    expect(find.text('passed'), findsWidgets);
    expect(find.text('opens a preview and reads the name'), findsOneWidget);
  });

  testWidgets('fails gracefully, and still tears down, with no app harness',
      (tester) async {
    final runner = await pumpRunner(tester, harnessProvider: () => null);

    final scenario = QaScenario(
      suite: 'Live demo',
      name: 'needs the app',
      summary: 'no harness available',
      body: (_) async {},
      liveBody: (d, h) async {
        await d.expectVisible(qaText('never reached'));
      },
    );

    await runner.run(<QaScenario>[scenario]);
    await tester.pump();

    expect(runner.view.status, QaRunStatus.failed);
    // The failing step carries the "app is not running" explanation.
    expect(
      runner.view.steps.any((s) => s.failure?.contains('not running') ?? false),
      isTrue,
    );
  });

  testWidgets('a logic-only scenario (no liveBody) still runs its checks',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    final runner = LiveE2eRunner(
      overlay: navKey.currentState!.overlay!,
      onRevealApp: () {},
      onBackToDashboard: () {},
      pacer: TesterPacer(tester),
      stepDelay: Duration.zero,
      harnessProvider: () => null,
      rootProvider: () => WidgetsBinding.instance.rootElement,
    );

    final scenario = QaScenario(
      suite: 'Policy',
      name: 'one equals one',
      summary: 'pure logic',
      body: (d) => d.check('one is one', () => 1 == 1),
    );

    await runner.run(<QaScenario>[scenario]);
    await tester.pump();

    expect(runner.view.status, QaRunStatus.passed);
  });

  // A widget scenario has its own tree mounted for it under `flutter test`. In
  // the app there is nothing to mount it into, so running its body here would
  // assert against the real app instead — quietly passing any check that only
  // looks for absence. It has to fail loudly instead.
  testWidgets('a widget scenario with no liveBody fails instead of running '
      'against the real app', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    final runner = LiveE2eRunner(
      overlay: navKey.currentState!.overlay!,
      onRevealApp: () {},
      onBackToDashboard: () {},
      pacer: TesterPacer(tester),
      stepDelay: Duration.zero,
      harnessProvider: () => null,
      rootProvider: () => WidgetsBinding.instance.rootElement,
    );

    var bodyRan = false;
    final scenario = QaScenario(
      suite: 'Widget',
      name: 'mounts its own tree',
      summary: 'headless-only',
      build: () async => const MaterialApp(home: Text('mounted')),
      body: (d) async {
        bodyRan = true;
        // Would pass vacuously against an app that never mounted this widget.
        await d.expectAbsent(qaText('never rendered'));
      },
    );

    await runner.run(<QaScenario>[scenario]);
    await tester.pump();

    expect(runner.view.status, QaRunStatus.failed);
    expect(bodyRan, isFalse,
        reason: 'the body must not run against the real app tree');
    expect(
      runner.view.steps.any((s) => s.failure?.contains('flutter test') ?? false),
      isTrue,
      reason: 'the failure should explain the scenario is headless-only',
    );
  });
}

class _FakeHarness implements QaAppHarness {
  _FakeHarness(this.navKey);

  final GlobalKey<NavigatorState> navKey;
  bool _signedIn = true;

  @override
  String get currentUid => 'fake-viewer';

  @override
  bool get signedIn => _signedIn;

  @override
  Future<void> signInTestUser() async => _signedIn = true;

  @override
  Future<void> signOutTestUser() async => _signedIn = false;

  @override
  Future<void> goHome() async {}

  @override
  Future<void> openSignupWizard(
      {String email = 'qa-signup@example.com'}) async {}

  @override
  Future<void> resetToBaseline() async {}

  @override
  Future<void> openPreviewFor(String uid, String displayName) async {
    // Mirrors the real handler: open a dialog showing the tapped user's name.
    showDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => AlertDialog(content: Text(displayName)),
    );
  }

  @override
  Future<void> openConversationWith(String uid, String displayName) async {}

  // --- Map surface. This fake exists to exercise the runner, not the map, so
  // these keep just enough state for a scenario to be driven end to end.
  List<String> _markerIds = <String>['fake-viewer', 'fake-other'];
  double _zoom = 10;

  @override
  List<String> visibleMarkerIds() => _markerIds;

  @override
  double get currentMapZoom => _zoom;

  @override
  double get initialMapZoom => 10;

  @override
  Future<double?> rememberedCameraZoom() async => 10;

  @override
  Future<void> applyMapZoom(double zoom) async => _zoom = zoom;

  @override
  Future<void> reloadMarkers() async {}

  @override
  Future<void> enterSearch(String term) async =>
      _markerIds = <String>['fake-other'];

  @override
  Future<void> clearSearch() async =>
      _markerIds = <String>['fake-viewer', 'fake-other'];

  @override
  Future<void> setRelationshipFilters({
    bool? friends,
    bool? followers,
    bool? following,
  }) async {}

  @override
  Future<void> openPreviewForMarkerId(String markerId, String displayName) =>
      openPreviewFor(markerId, displayName);
}
