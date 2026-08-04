import 'dart:async';

/// Stable prefix the CI reporter (tool/test_report.dart) looks for to detect a
/// phase boundary inside a test's captured output.
const String kPhaseMarker = 'PHASE ›'; // "PHASE ›"

/// Runs [body] as a named [name] phase of a test.
///
/// The phase name is `print`ed, which the machine test reporter captures and
/// attaches to the running test. The reporter only surfaces these phase lines
/// for *failing* tests, so a green run stays quiet while a red run shows every
/// phase that ran (and therefore which one broke).
///
/// Example:
/// ```dart
/// await phase('open the dialog', () async {
///   await $('Open').tap();
/// });
/// ```
Future<void> phase(String name, FutureOr<void> Function() body) async {
  print('$kPhaseMarker $name');
  await body();
}
