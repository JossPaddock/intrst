import 'dart:async';

import 'package:flutter/material.dart';

import '../live_qa_driver.dart';
import '../qa_scenario.dart';
import 'qa_app_controller.dart';
import 'qa_app_harness.dart';
import 'qa_chrome.dart';
import 'qa_pip_overlay.dart';
import 'qa_run_history.dart';

/// Runs [QaScenario]s against the **real running app**, streaming progress into
/// a draggable [QaPipOverlay].
///
/// This is what the admin dashboard's ▶ triggers. It outlives the dashboard
/// route on purpose: the panel starts a run and then pops itself so the live
/// app is visible, so the runner cannot rely on any dashboard widget staying
/// mounted. It holds only a root-overlay handle (captured before the pop), the
/// app harness (from [QaAppController]) and the app's root element.
///
/// A scenario with a live definition ([QaScenario.hasLive]) drives production
/// screens; one without (the logic-only `MessageBlockPolicy` checks) still runs
/// its `check`s and reports in the PiP, it just has nothing to navigate.
class LiveE2eRunner {
  LiveE2eRunner({
    required this.overlay,
    required this.onRevealApp,
    required this.onBackToDashboard,
    this.pacer = const LiveQaPacer(),
    this.stepDelay = const Duration(milliseconds: 400),
    this.debug = false,
    this.history,
    QaAppHarness? Function()? harnessProvider,
    Element? Function()? rootProvider,
  })  : _harnessProvider =
            harnessProvider ?? (() => QaAppController.instance.harness),
        _rootProvider =
            rootProvider ?? (() => WidgetsBinding.instance.rootElement);

  /// Root overlay the PiP + highlight are inserted into. Captured before the
  /// dashboard route is popped so it survives navigation.
  final OverlayState overlay;

  /// Pops the dashboard to reveal the running app. Called once, up front.
  final VoidCallback onRevealApp;

  /// Re-opens the dashboard (used by the PiP's "Back to dashboard").
  final VoidCallback onBackToDashboard;

  final QaPacer pacer;
  final Duration stepDelay;

  /// When true, the run pauses before every step until [continueRun] is called
  /// (the PiP's Continue button), so it can be watched one step at a time.
  final bool debug;

  /// Records each scenario's pass/fail so the dashboard can show "last run".
  /// Null in tests; the panel supplies a real [QaRunHistory].
  final QaRunHistory? history;

  final QaAppHarness? Function() _harnessProvider;
  final Element? Function() _rootProvider;

  final QaRunView view = QaRunView();
  QaPipOverlay? _pip;
  bool _cancelled = false;

  // Completed by [continueRun] to release a step-through run from its pause.
  Completer<void>? _continueGate;

  /// Runs [scenarios] in order. Inserts the PiP, reveals the app, then leaves
  /// the PiP up showing the final result until the user closes it.
  Future<void> run(List<QaScenario> scenarios) async {
    view.debugMode = debug;
    _pip = QaPipOverlay(
      overlay: overlay,
      view: view,
      onClose: _handleClose,
      onBackToDashboard: _handleBack,
      onContinue: continueRun,
    );
    _pip!.insert();
    onRevealApp();
    await pacer.settle();

    var anyFailed = false;
    for (var i = 0; i < scenarios.length; i++) {
      if (_cancelled) return;
      final scenario = scenarios[i];
      _resetViewFor(
        scenario,
        progress: scenarios.length > 1 ? '${i + 1} / ${scenarios.length}' : '',
      );
      final passed = await _runScenario(scenario);
      anyFailed = anyFailed || !passed;

      // Persist the outcome (best-effort) so the dashboard shows the last run.
      final history = this.history;
      if (history != null) {
        try {
          await history.record(scenario, passed: passed);
        } catch (_) {
          // Logging the result must never fail a run.
        }
      }
    }

    if (_cancelled) return;
    view.status = anyFailed ? QaRunStatus.failed : QaRunStatus.passed;
    view.finished = true;
    view.notify();
  }

  Future<bool> _runScenario(QaScenario scenario) async {
    late final LiveQaDriver driver;
    driver = LiveQaDriver(
      root: _rootProvider,
      isExcluded: QaChrome.matches,
      beforeStep: debug ? _awaitContinue : null,
      onUpdate: () {
        view.steps = List<QaStep>.of(driver.steps);
        view.notify();
      },
      onHighlight: (rect) {
        view.highlight = rect;
        view.notify();
      },
      stepDelay: () => stepDelay,
      pacer: pacer,
    );

    final harness = _harnessProvider();

    try {
      if (scenario.hasLive) {
        // Run the precondition check + setup inside a visible phase so a missing
        // app or missing credentials shows up as a red step with its reason.
        await driver.phase('prepare (reset + seed + sign in)', () async {
          if (harness == null) {
            throw QaHarnessUnavailable(
              'The intrst app is not running (or its QA harness has not '
              'registered yet), so this scenario cannot drive it.',
            );
          }
          // Start from a clean baseline so this scenario never inherits an open
          // dialog/drawer or a stray screen from the previous one.
          await harness.resetToBaseline();
          final setUp = scenario.liveSetUp;
          if (setUp != null) await setUp(harness);
        });
        await scenario.liveBody!(driver, harness!);
      } else {
        // Logic-only scenario: no app to drive, just evaluate its checks.
        await scenario.body(driver);
      }
      view.status = QaRunStatus.passed;
      view.notify();
      return true;
    } catch (_) {
      view.status = QaRunStatus.failed;
      view.notify();
      return false;
    } finally {
      view.highlight = null;
      // Cleanup always runs, even if the body threw or the user closed the PiP
      // mid-run, so seeded prod data is never left behind.
      final tearDown = scenario.liveTearDown;
      if (tearDown != null && harness != null) {
        try {
          await tearDown(harness);
        } catch (_) {
          // Cleanup is best-effort; QaSeeder already logs its own failures.
        }
      }
      view.notify();
    }
  }

  void _resetViewFor(QaScenario scenario, {required String progress}) {
    view.scenarioName = scenario.name;
    view.suite = scenario.suite;
    view.progress = progress;
    view.steps = const <QaStep>[];
    view.status = QaRunStatus.running;
    view.highlight = null;
    view.finished = false;
    view.notify();
  }

  /// Pauses a step-through run before a step until [continueRun] is called.
  Future<void> _awaitContinue() async {
    // Once the run is cancelled, stop gating so the scenario can run out and its
    // teardown (prod cleanup) still executes.
    if (_cancelled) return;
    final gate = Completer<void>();
    _continueGate = gate;
    view.awaitingContinue = true;
    view.notify();
    await gate.future;
    if (identical(_continueGate, gate)) _continueGate = null;
    view.awaitingContinue = false;
    view.notify();
  }

  /// Advances a paused debug run by one step (the PiP's Continue button).
  void continueRun() {
    final gate = _continueGate;
    _continueGate = null;
    view.awaitingContinue = false;
    view.notify();
    gate?.complete();
  }

  void _handleClose() {
    // Abort the loop between scenarios; an in-flight scenario still finishes so
    // its teardown runs. Release any debug pause so it isn't stranded waiting.
    _cancelled = true;
    final gate = _continueGate;
    _continueGate = null;
    view.awaitingContinue = false;
    _pip?.remove();
    _pip = null;
    gate?.complete();
  }

  void _handleBack() {
    _pip?.remove();
    _pip = null;
    onBackToDashboard();
  }
}
