// Runs the project's test suite and prints a compact, CI-friendly report.
//
// It wraps `flutter test --machine`, parses the JSON event stream, and prints:
//   * one line per test:  `Test <name> passed ✅`  /  `Test <name> failed ❌`
//   * for FAILING tests only, the phase breakdown + failure details, so it is
//     clear which step broke and why (passing tests stay quiet);
//   * a final `Passed X/Y tests` tally.
//
// Exit code is non-zero if any test failed or the runner itself failed, so it
// is safe to gate a CI pipeline on this command.
//
// Usage:
//   dart run tool/test_report.dart [extra flutter-test args...]
//   dart run tool/test_report.dart test/widgets/preview_logged_out_login_test.dart
//
// See scripts/run_tests.sh for the convenience wrapper the pipeline invokes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _pass = '✅';
const String _fail = '❌';
const String _skip = '⊘';
const String _phaseMarker = 'PHASE ›';
const String _rule =
    '────────────────────────────────────────────────────────────';

class _TestRecord {
  _TestRecord(this.name);
  final String name;
  final List<String> messages = <String>[]; // captured print() output, in order
  final List<String> errors = <String>[]; // failure error + stack blocks
  String? result; // success | failure | error
  bool skipped = false;
  bool hidden = false;
}

Future<void> main(List<String> args) async {
  final command = <String>['test', '--machine', ...args];
  stdout.writeln('▶ Running test suite: flutter ${command.join(' ')}\n');

  final Process process;
  try {
    process = await Process.start(
      'flutter',
      command,
      workingDirectory: Directory.current.path,
    );
  } on ProcessException catch (e) {
    stderr.writeln('Failed to start flutter: ${e.message}');
    exitCode = 127;
    return;
  }

  final records = <int, _TestRecord>{};
  final orderedFailures = <String>[];
  var runnerReportedSuccess = true;
  var sawDoneEvent = false;

  // Surface anything flutter writes to stderr (compile errors, tool crashes).
  final stderrBuffer = StringBuffer();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach(stderrBuffer.writeln);

  void handleEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>?;
        if (test == null) return;
        final id = test['id'] as int;
        final record = _TestRecord((test['name'] as String?)?.trim() ?? '');
        // A test with no url is a synthetic harness test (loading/tearDown).
        if (test['url'] == null) record.hidden = true;
        records[id] = record;
      case 'print':
        final id = event['testID'] as int?;
        final message = event['message'] as String?;
        if (id != null && message != null) {
          records[id]?.messages.add(message);
        }
      case 'error':
        final id = event['testID'] as int?;
        if (id == null) break;
        final buffer = StringBuffer();
        final error = (event['error'] as String?)?.trimRight();
        final stack = (event['stackTrace'] as String?)?.trimRight();
        if (error != null && error.isNotEmpty) buffer.writeln(error);
        if (stack != null && stack.isNotEmpty) buffer.write(stack);
        records[id]?.errors.add(buffer.toString());
      case 'testDone':
        final id = event['testID'] as int?;
        if (id == null) break;
        final record = records[id];
        if (record == null) break;
        record
          ..result = event['result'] as String?
          ..skipped = event['skipped'] == true
          ..hidden = record.hidden || event['hidden'] == true;
        _printRecord(record, orderedFailures);
      case 'done':
        sawDoneEvent = true;
        runnerReportedSuccess = event['success'] == true;
    }
  }

  await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed[0] != '{' && trimmed[0] != '[') return;
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return; // non-JSON noise (e.g. "Resolving dependencies...")
    }
    if (decoded is Map<String, dynamic>) {
      handleEvent(decoded);
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) handleEvent(item);
      }
    }
  });

  final runnerExitCode = await process.exitCode;
  await stderrDone;

  // ---- Tally ---------------------------------------------------------------
  var passed = 0;
  var failed = 0;
  var skipped = 0;
  for (final record in records.values) {
    if (record.hidden) continue;
    if (record.skipped) {
      skipped++;
    } else if (record.result == 'success') {
      passed++;
    } else {
      failed++;
    }
  }
  final total = passed + failed;

  stdout.writeln('\n$_rule');
  final skipNote = skipped > 0 ? '   ($skipped skipped)' : '';
  stdout.writeln(' Passed $passed/$total tests$skipNote');
  if (failed > 0) {
    stdout.writeln(' $failed failed $_fail');
    stdout.writeln('\nFailing tests:');
    for (final name in orderedFailures) {
      stdout.writeln('  $_fail $name');
    }
  } else if (total > 0) {
    stdout.writeln(' All tests passed $_pass');
  }
  stdout.writeln(_rule);

  if (!sawDoneEvent) {
    stdout.writeln(
        '\n⚠ The test runner did not finish cleanly. flutter stderr:');
    stdout.writeln(stderrBuffer.toString().trimRight());
  }

  _writeGithubSummary(
    passed: passed,
    failed: failed,
    skipped: skipped,
    total: total,
    failures: orderedFailures,
  );

  final ok = sawDoneEvent && runnerReportedSuccess && failed == 0;
  exitCode = ok ? 0 : (runnerExitCode != 0 ? runnerExitCode : 1);
}

void _printRecord(_TestRecord record, List<String> orderedFailures) {
  if (record.hidden) return;
  if (record.skipped) {
    stdout.writeln('Test ${record.name} skipped $_skip');
    return;
  }
  if (record.result == 'success') {
    stdout.writeln('Test ${record.name} passed $_pass');
    return;
  }

  // Failure: name + every phase that ran + the failure details.
  orderedFailures.add(record.name);
  stdout.writeln('Test ${record.name} failed $_fail');
  for (final message in record.messages) {
    for (final rawLine in const LineSplitter().convert(message)) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final label = line.startsWith(_phaseMarker) ? '▸' : '·';
      stdout.writeln('    $label $line');
    }
  }
  for (final block in record.errors) {
    for (final line in const LineSplitter().convert(block)) {
      stdout.writeln('    │ ${line.trimRight()}');
    }
  }
}

void _writeGithubSummary({
  required int passed,
  required int failed,
  required int skipped,
  required int total,
  required List<String> failures,
}) {
  final path = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (path == null || path.isEmpty) return;
  final buffer = StringBuffer()
    ..writeln('## Test suite')
    ..writeln()
    ..writeln('**Passed $passed/$total tests**'
        '${skipped > 0 ? ' · $skipped skipped' : ''}'
        '${failed > 0 ? ' · $failed failed ❌' : ' ✅'}')
    ..writeln();
  if (failures.isNotEmpty) {
    buffer.writeln('### Failing tests');
    for (final name in failures) {
      buffer.writeln('- ❌ $name');
    }
  }
  try {
    File(path).writeAsStringSync(buffer.toString(), mode: FileMode.append);
  } catch (_) {
    // A summary write failure must never fail the build.
  }
}
