import 'package:intrst/qa/unit/signup_wizard_unit_tests.dart';

import 'support/unit_test_bridge.dart';

// The tests themselves live in lib/qa/unit/signup_wizard_unit_tests.dart so the
// admin dashboard's Unit tests tab can run them in-app. This file is what makes
// `flutter test` run the same definitions headlessly.
void main() {
  registerUnitTests(signupWizardUnitTests());
}
