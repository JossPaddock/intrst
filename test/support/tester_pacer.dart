import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/live_qa_driver.dart';

/// Advances the faked clock and frames that `flutter test` runs on, standing in
/// for the real frames and real delays [LiveQaPacer] uses inside the running
/// app.
///
/// This is what lets the dashboard's live runner — which otherwise only ever
/// executes in a running app — be covered by ordinary widget tests.
class TesterPacer implements QaPacer {
  TesterPacer(this.tester);

  final WidgetTester tester;

  /// Pumps a fixed handful of frames rather than calling `pumpAndSettle`.
  /// The dashboard panel shows a progress spinner while a run is in flight, so
  /// there is a continuously scheduled animation and `pumpAndSettle` would
  /// never return. This mirrors what [LiveQaPacer] does in the real app, which
  /// also just lets a few frames go by.
  @override
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  @override
  Future<void> pause(Duration duration) => tester.pump(duration);
}
