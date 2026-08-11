import 'package:intrst/qa/scenarios/preview_login_scenarios.dart';

import '../support/qa_scenario_bridge.dart';

// Scenarios live in lib/qa/scenarios/preview_login_scenarios.dart; see
// test/support/qa_scenario_bridge.dart for why.
void main() {
  registerQaScenarios(previewLoginScenarios());
}
