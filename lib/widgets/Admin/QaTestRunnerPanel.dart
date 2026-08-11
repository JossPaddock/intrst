import 'package:flutter/material.dart';

import '../../qa/e2e/live_e2e_runner.dart';
import '../../qa/e2e/qa_run_history.dart';
import '../../qa/live_qa_driver.dart';
import '../../qa/qa_registry.dart';
import '../../qa/qa_scenario.dart';
import 'AdminDashboard.dart';

/// The admin dashboard's Patrol test panel.
///
/// Lists every scenario in [QaRegistry] — the same catalogue `flutter test`
/// runs, so the scope shown here is always the real scope — with each scenario's
/// **last run** (time + pass/fail, from [QaRunHistory]). On ▶ it replays a
/// scenario **against the real running app** (🐞 to step through it): the
/// dashboard closes, the live app is driven with real taps, and progress streams
/// into a draggable PiP results overlay (see [LiveE2eRunner]).
class QaTestRunnerPanel extends StatefulWidget {
  const QaTestRunnerPanel({
    super.key,
    this.pacer = const LiveQaPacer(),
    this.stepDelay = const Duration(milliseconds: 400),
    this.onLaunch,
    this.history,
  });

  /// How the run waits for the UI between steps. The default drives real frames
  /// on a real clock; the panel's test swaps in a tester-backed pacer.
  final QaPacer pacer;

  /// Deliberate pause before each step, so the run is watchable.
  final Duration stepDelay;

  /// Test seam. When set, it is called instead of launching a real run — the
  /// panel's own wiring can then be covered without a running app. Receives the
  /// scenarios the pressed control would have run.
  @visibleForTesting
  final void Function(List<QaScenario> scenarios)? onLaunch;

  /// Persists/reads the "last run" per scenario. Defaults to a live
  /// [QaRunHistory]; tests inject one backed by a fake Firestore.
  @visibleForTesting
  final QaRunHistory? history;

  @override
  State<QaTestRunnerPanel> createState() => _QaTestRunnerPanelState();
}

class _QaTestRunnerPanelState extends State<QaTestRunnerPanel> {
  static const Color _brand = Color(0xFF082D38);

  late final QaRunHistory _history = widget.history ?? QaRunHistory();
  Map<String, QaRunRecord> _records = const <String, QaRunRecord>{};

  // Scenario ids currently running inline (logic-only checks run in place,
  // without the PiP).
  final Set<String> _runningInline = <String>{};

  List<QaScenario> get _scenarios => QaRegistry.all();

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final records = await _history.loadAll();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      // No history yet (or Firebase unavailable, e.g. under test): the tiles
      // simply show "not run yet".
    }
  }

  void _launch(
    BuildContext context,
    List<QaScenario> scenarios, {
    bool debug = false,
  }) {
    final override = widget.onLaunch;
    if (override != null) {
      override(scenarios);
      return;
    }

    // Capture the overlay + navigator now: the runner outlives this panel, and
    // the dashboard route is popped immediately to reveal the app.
    final overlay = Overlay.of(context, rootOverlay: true);
    final navigator = Navigator.of(context);

    final runner = LiveE2eRunner(
      overlay: overlay,
      pacer: widget.pacer,
      stepDelay: widget.stepDelay,
      debug: debug,
      history: _history,
      onRevealApp: () {
        if (navigator.canPop()) navigator.pop();
      },
      onBackToDashboard: () {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const AdminDashboard(
              initialTabIndex: AdminDashboard.patrolTestsTabIndex,
            ),
          ),
        );
      },
    );
    // Fire and forget: the runner owns the PiP from here on.
    runner.run(scenarios);
  }

  /// Runs a logic-only scenario right here in the dashboard — no PiP, no leaving
  /// the tab. Its `check`s assert plain booleans, so there is nothing to drive
  /// or watch; we just report the result on the tile (and a brief snackbar).
  Future<void> _runInline(QaScenario scenario) async {
    final override = widget.onLaunch;
    if (override != null) {
      override(<QaScenario>[scenario]);
      return;
    }
    if (_runningInline.contains(scenario.id)) return;

    setState(() => _runningInline.add(scenario.id));
    var passed = false;
    try {
      final driver = LiveQaDriver(
        root: () => null, // logic checks don't touch the widget tree
        onUpdate: () {},
        onHighlight: (_) {},
        stepDelay: () => Duration.zero,
        pacer: widget.pacer,
      );
      await scenario.body(driver);
      passed = true;
    } catch (_) {
      passed = false;
    }

    try {
      await _history.record(scenario, passed: passed);
    } catch (_) {
      // Recording the result must never fail the run.
    }

    if (!mounted) return;
    setState(() {
      _runningInline.remove(scenario.id);
      _records = <String, QaRunRecord>{
        ..._records,
        scenario.id: QaRunRecord(lastRunAt: DateTime.now(), passed: passed),
      };
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${scenario.name} — ${passed ? 'passed' : 'failed'}'),
        backgroundColor:
            passed ? Colors.green.shade700 : Colors.red.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scenarios = _scenarios;
    final suites = scenarios.map((s) => s.suite).toSet().length;

    return Column(
      children: [
        _buildHeader(context, scenarios, suites),
        const Divider(height: 1),
        Expanded(child: _buildScenarioList(context, scenarios)),
      ],
    );
  }

  Widget _buildHeader(
      BuildContext context, List<QaScenario> scenarios, int suites) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${scenarios.length} scenarios across $suites suites',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'Runs against the live app; results appear in a PiP overlay.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh last-run status',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadRecords,
          ),
          OutlinedButton.icon(
            onPressed: () => _launch(context, scenarios),
            icon: const Icon(Icons.playlist_play, size: 18),
            label: const Text('Run all'),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioList(BuildContext context, List<QaScenario> scenarios) {
    final bySuite = <String, List<QaScenario>>{};
    for (final scenario in scenarios) {
      bySuite.putIfAbsent(scenario.suite, () => <QaScenario>[]).add(scenario);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final entry in bySuite.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
            child: Text(
              entry.key,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: _brand,
              ),
            ),
          ),
          for (final scenario in entry.value)
            _buildScenarioTile(context, scenario),
        ],
      ],
    );
  }

  Widget _buildScenarioTile(BuildContext context, QaScenario scenario) {
    final canDrive = scenario.hasLive;
    final running = _runningInline.contains(scenario.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: ListTile(
        dense: true,
        leading: running
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                canDrive ? Icons.play_circle_outline : Icons.rule,
                size: 20,
                color: canDrive ? _brand : Colors.grey.shade500,
              ),
        title: Text(scenario.name, style: const TextStyle(fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              scenario.summary,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            if (!canDrive && !scenario.hasUi)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'logic check — nothing to watch',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            _buildLastRun(scenario),
          ],
        ),
        trailing: canDrive
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip:
                        'Debug — pause at each step, advance with Continue',
                    icon: const Icon(Icons.bug_report_outlined),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _launch(context, <QaScenario>[scenario], debug: true),
                  ),
                  IconButton(
                    tooltip: 'Run this scenario against the live app',
                    icon: const Icon(Icons.play_arrow),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _launch(context, <QaScenario>[scenario]),
                  ),
                ],
              )
            // Logic-only: runs in place here, no PiP.
            : IconButton(
                tooltip: 'Run this check here in the dashboard',
                icon: const Icon(Icons.play_arrow),
                visualDensity: VisualDensity.compact,
                onPressed: running ? null : () => _runInline(scenario),
              ),
      ),
    );
  }

  Widget _buildLastRun(QaScenario scenario) {
    final record = _records[scenario.id];
    if (record == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Not run yet',
          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
        ),
      );
    }

    final passed = record.passed;
    final color = passed ? Colors.green.shade700 : Colors.red.shade700;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            size: 13,
            color: passed ? Colors.green.shade600 : Colors.red.shade600,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Last run ${_formatDateTime(record.lastRunAt)} · '
              '${passed ? 'passed' : 'failed'}',
              style: TextStyle(fontSize: 10.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
