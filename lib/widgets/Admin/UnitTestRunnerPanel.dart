import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../qa/e2e/qa_run_history.dart';
import '../../qa/unit/unit_test.dart';
import '../../qa/unit/unit_test_registry.dart';
import '../../qa/unit/unit_test_runner.dart';
import 'test_doc_sheet.dart';

/// The admin dashboard's **Unit tests** panel.
///
/// Lists every [UnitTest] in [UnitTestRegistry] — the same catalogue
/// `flutter test` runs via the unit-test bridge, so the scope shown here is
/// always the real scope. Runnable (pure-logic) tests carry a ▶ and execute
/// **inside the app**; because there is nothing on screen to drive, their
/// console output streams into a docked **log reader** at the bottom of the tab
/// instead of a PiP. Harness-only tests (`testWidgets`) are listed greyed for
/// completeness.
///
/// Last-run time + pass/fail is shared with the Patrol tab through
/// [QaRunHistory] (the same `qa_test_runs` store, keyed by test id).
class UnitTestRunnerPanel extends StatefulWidget {
  const UnitTestRunnerPanel({super.key, this.history});

  /// Persists/reads the "last run" per test. Defaults to a live [QaRunHistory];
  /// tests inject one backed by a fake Firestore.
  @visibleForTesting
  final QaRunHistory? history;

  @override
  State<UnitTestRunnerPanel> createState() => _UnitTestRunnerPanelState();
}

/// One run's worth of console output, shown as a block in the log reader.
class _LogEntry {
  _LogEntry({
    required this.name,
    required this.passed,
    required this.at,
    required this.lines,
  });

  final String name;
  final bool passed;
  final DateTime at;
  final List<String> lines;
}

class _UnitTestRunnerPanelState extends State<UnitTestRunnerPanel> {
  static const Color _brand = Color(0xFF082D38);

  late final QaRunHistory _history = widget.history ?? QaRunHistory();
  Map<String, QaRunRecord> _records = const <String, QaRunRecord>{};

  final Set<String> _running = <String>{};

  // The log reader's scrollback — appended to on every run.
  final List<_LogEntry> _log = <_LogEntry>[];
  final ScrollController _logScroll = ScrollController();
  bool _readerOpen = true;

  List<UnitTest> get _tests => UnitTestRegistry.all();

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    try {
      final records = await _history.loadAll();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      // No history yet (or Firebase unavailable under test): tiles show
      // "not run yet".
    }
  }

  /// Runs one test in-app, records its result, and appends its output to the
  /// log reader. Yields to the event loop first so the spinner paints before
  /// the (synchronous) run.
  Future<void> _run(UnitTest test) async {
    if (!test.runnable || _running.contains(test.id)) return;
    setState(() => _running.add(test.id));
    await Future<void>.delayed(Duration.zero);

    final result = UnitTestRunner.run(test);

    try {
      await _history.recordById(
        id: test.id,
        suite: test.suite,
        name: test.name,
        passed: result.passed,
      );
    } catch (_) {
      // Recording must never fail the run.
    }

    if (!mounted) return;
    setState(() {
      _running.remove(test.id);
      _records = <String, QaRunRecord>{
        ..._records,
        test.id: QaRunRecord(lastRunAt: DateTime.now(), passed: result.passed),
      };
      _readerOpen = true;
      _log.add(_LogEntry(
        name: test.name,
        passed: result.passed,
        at: DateTime.now(),
        lines: result.output,
      ));
    });
    _scrollLogToEnd();
  }

  Future<void> _runAll() async {
    for (final test in _tests.where((t) => t.runnable)) {
      await _run(test);
    }
    if (!mounted) return;
    final passed = _log.where((e) => e.passed).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$passed/${_log.length} unit tests passed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollLogToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  void _clearLog() => setState(_log.clear);

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _logAsText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Console output copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  String _logAsText() => _log
      .map((e) => '${e.passed ? 'PASS' : 'FAIL'}  ${e.name} '
          '(${_formatTime(e.at)})\n${e.lines.join('\n')}')
      .join('\n\n');

  @override
  Widget build(BuildContext context) {
    final tests = _tests;
    final runnable = tests.where((t) => t.runnable).length;
    final suites = tests.map((t) => t.suite).toSet().length;

    return Column(
      children: [
        _buildHeader(context, tests.length, runnable, suites),
        const Divider(height: 1),
        Expanded(child: _buildList(tests)),
        _buildLogReader(),
      ],
    );
  }

  Widget _buildHeader(
      BuildContext context, int total, int runnable, int suites) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total unit tests across $suites suites',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'Runnable tests execute in-app; output streams to the console below.',
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
            onPressed: runnable == 0 ? null : _runAll,
            icon: const Icon(Icons.playlist_play, size: 18),
            label: const Text('Run all'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<UnitTest> tests) {
    final bySuite = <String, List<UnitTest>>{};
    for (final test in tests) {
      bySuite.putIfAbsent(test.suite, () => <UnitTest>[]).add(test);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final entry in bySuite.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
            child: Text(
              entry.key,
              style: const TextStyle(fontWeight: FontWeight.bold, color: _brand),
            ),
          ),
          for (final test in entry.value) _buildTile(test),
        ],
      ],
    );
  }

  Widget _buildTile(UnitTest test) {
    final running = _running.contains(test.id);
    final runnable = test.runnable;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: ListTile(
        dense: true,
        onTap: () => _showDoc(test),
        leading: running
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                runnable ? Icons.play_circle_outline : Icons.lock_outline,
                size: 20,
                color: runnable ? _brand : Colors.grey.shade500,
              ),
        title: Text(test.name, style: const TextStyle(fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              test.summary,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            if (!runnable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  test.harnessOnlyReason ??
                      'Runs under the flutter test harness only.',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            _buildLastRun(test),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Read this test\'s docs',
              icon: const Icon(Icons.description_outlined),
              visualDensity: VisualDensity.compact,
              onPressed: () => _showDoc(test),
            ),
            if (runnable)
              IconButton(
                tooltip: 'Run this unit test here in the dashboard',
                icon: const Icon(Icons.play_arrow),
                visualDensity: VisualDensity.compact,
                onPressed: running ? null : () => _run(test),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens a scrollable preview of [test]'s documentation (its [UnitTest.doc],
  /// or its summary when no doc is written) as a draggable bottom sheet.
  void _showDoc(UnitTest test) {
    showTestDocSheet(
      context,
      suite: test.suite,
      name: test.name,
      doc: test.docText,
      note: test.runnable
          ? null
          : 'Runs under the flutter test harness only',
      noteIcon: test.runnable ? null : Icons.lock_outline,
    );
  }

  // ── Log reader ─────────────────────────────────────────────────────────

  Widget _buildLogReader() {
    return Material(
      elevation: 6,
      color: const Color(0xFF1E1E1E),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLogHeader(),
          if (_readerOpen)
            SizedBox(
              height: 220,
              child: _log.isEmpty
                  ? const Center(
                      child: Text(
                        'No output yet — run a test to see its console output.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : _buildLogBody(),
            ),
        ],
      ),
    );
  }

  Widget _buildLogHeader() {
    return InkWell(
      onTap: () => setState(() => _readerOpen = !_readerOpen),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black26)),
        ),
        child: Row(
          children: [
            Icon(_readerOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                size: 18, color: Colors.white70),
            const SizedBox(width: 6),
            const Icon(Icons.terminal, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              'Console${_log.isEmpty ? '' : ' · ${_log.length} run${_log.length == 1 ? '' : 's'}'}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Copy console output',
              icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
              visualDensity: VisualDensity.compact,
              onPressed: _log.isEmpty ? null : _copyLog,
            ),
            IconButton(
              tooltip: 'Clear console',
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white70),
              visualDensity: VisualDensity.compact,
              onPressed: _log.isEmpty ? null : _clearLog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogBody() {
    return Scrollbar(
      controller: _logScroll,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _logScroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _log.length,
        itemBuilder: (context, index) => _buildLogBlock(_log[index]),
      ),
    );
  }

  Widget _buildLogBlock(_LogEntry entry) {
    final statusColor =
        entry.passed ? const Color(0xFF7FD18C) : const Color(0xFFF08A8A);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(entry.passed ? Icons.check_circle : Icons.cancel,
                  size: 13, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${entry.passed ? 'PASS' : 'FAIL'}  ${entry.name}  ·  ${_formatTime(entry.at)}',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          if (entry.lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 19, top: 2),
              child: SelectableText(
                entry.lines.join('\n'),
                style: const TextStyle(
                  color: Color(0xFFD6D6D6),
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 19, top: 2),
              child: Text(
                '(no console output)',
                style: TextStyle(
                  color: Colors.white30,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLastRun(UnitTest test) {
    final record = _records[test.id];
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

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
