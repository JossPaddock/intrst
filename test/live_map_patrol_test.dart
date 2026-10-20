import 'package:intrst/qa/scenarios/live_map_scenarios.dart';

import 'support/qa_scenario_bridge.dart';

// The scenarios themselves live in lib/qa/scenarios/live_map_scenarios.dart so
// the admin dashboard can drive them against the real running app. This file is
// what makes `flutter test` run their headless bodies.
void main() {
  registerQaScenarios(liveMapScenarios());
}
