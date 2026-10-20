import 'package:intrst/qa/scenarios/signup_wizard_scenarios.dart';

import 'support/qa_scenario_bridge.dart';

// The scenarios themselves live in lib/qa/scenarios/signup_wizard_scenarios.dart
// so the admin dashboard can replay them; this file is what makes
// `flutter test` run the same definitions headlessly.
void main() {
  registerQaScenarios(signupWizardScenarios());
}
