# intrst
This is an open source project to connect people with similar interests.

## Testing

The suite is built on [Patrol](https://patrol.leancode.co/)'s finder framework
(`patrolWidgetTest` + the `$` API), so tests run under `flutter test` — no
emulator or device required.

### Running the full suite

```bash
./scripts/run_tests.sh
```

This is the **exact command the CI pipeline runs** on every push to `main`. It
wraps `flutter test --machine` and prints a report where each test shows as:

```
Test <name> passed ✅
Test <name> failed ❌
```

and ends with a `Passed X/Y tests` tally. It exits non-zero if anything fails,
so it's safe to gate CI on it.

Run a subset by passing paths through to `flutter test`:

```bash
./scripts/run_tests.sh test/widgets/preview_logged_out_login_test.dart
```

> The script uses the Dart SDK bundled with Flutter, so it works even if a
> different `dart` is first on your `PATH`. Under the hood it just runs
> `dart run tool/test_report.dart`.

### Failure output and phases

Passing tests print a single line. **Failing tests additionally print every
phase they ran plus the failure details**, so you can see which step broke:

```
Test Preview (logged out): ... failed ❌
    ▸ PHASE › a logged-out visitor opens the preview widget
    ▸ PHASE › the visitor selects one of the listed interests
    ▸ PHASE › the visitor lands on the page asking them to log in / sign up
    │ Expected: <1>
    │   Actual: <null>
    │ ...stack trace...
```

Declare phases in a test with the `phase()` helper from
`test/support/test_phase.dart`:

```dart
await phase('open the dialog', () async {
  await $('Open').tap();
  await $.pumpAndSettle();
});
```

Only failing tests surface their phase lines — green runs stay quiet.

### Writing a new test

Add a `*_test.dart` file under `test/` (widget/UI tests live in
`test/widgets/`). A minimal Patrol widget test:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

void main() {
  patrolWidgetTest('description', ($) async {
    await $.pumpWidgetAndSettle(const MyApp());
    await $('Some button').tap();
    expect($('Expected text').exists, true);
  });
}
```

`flutter test` (and therefore `./scripts/run_tests.sh`) picks it up
automatically.

### In CI

`.github/workflows/main.yml` runs `./scripts/run_tests.sh` as the **Run test
suite (Patrol)** step before building/deploying. A failure fails the job and
blocks the deploy, and the GitHub run summary shows the `Passed X/Y` tally and
any failing test names.
