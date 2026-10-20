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

/// Stable prefixes the CI reporter looks for to detect a *step* line — one
/// scenario action or assertion — inside a test's captured output.
///
/// Steps are the headless counterpart of the step log the live runner paints in
/// its PiP overlay: under `flutter test` there is nothing to watch, so the same
/// trail is printed instead. Like phases, the reporter only surfaces these for
/// failing tests, so a green run stays quiet.
const String kStepMarker = 'STEP ›';
const String kStepFailMarker = 'STEP ✗';

/// Logs [label] as a step, runs [body], and logs again if it throws.
///
/// The step is printed *before* [body] runs, so a step that hangs or crashes
/// the runner still leaves its name in the output.
Future<T> logStep<T>(String label, FutureOr<T> Function() body) async {
  print('$kStepMarker $label');
  try {
    return await body();
  } catch (_) {
    print('$kStepFailMarker $label');
    rethrow;
  }
}
