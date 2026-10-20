import 'package:intrst/qa/scenarios/message_edit_scenarios.dart';

import 'support/qa_scenario_bridge.dart';

// The scenarios themselves live in lib/qa/scenarios/message_edit_scenarios.dart
// so the admin dashboard's Patrol tests tab can list and replay the same
// entries. This file is what makes `flutter test` run them headlessly.
void main() {
  registerQaScenarios(messageEditScenarios());
}
