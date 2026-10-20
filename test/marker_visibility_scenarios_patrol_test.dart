import 'package:intrst/qa/scenarios/marker_visibility_scenarios.dart';

import 'support/qa_scenario_bridge.dart';

// The scenarios themselves live in lib/qa/scenarios/marker_visibility_scenarios.dart
// so that the admin dashboard can replay them. This file is what makes
// `flutter test` run them headlessly.
void main() {
  registerQaScenarios(markerVisibilityScenarios());
}
