import 'unit_test.dart';

/// Read-only listings for tests that exercise widgets or the Flutter test
/// binding (`testWidgets`) and therefore **cannot run inside the app** — they
/// need the `flutter test` harness. They appear in the dashboard's Unit tests
/// tab (greyed, no ▶) purely so the tab reflects the app's full test scope.
///
/// These mirror `test/qa_live_driver_test.dart`,
/// `test/qa_live_e2e_runner_test.dart` and `test/qa_test_runner_panel_test.dart`.
/// They have no [UnitTest.body]; nothing here runs. When a test is added to one
/// of those files, add a matching entry here so the listing stays honest.
List<UnitTest> harnessOnlyUnitTests() {
  const reason =
      'Runs under the `flutter test` harness only (uses testWidgets / the '
      'Flutter test binding), so it can\'t run inside the app.';

  UnitTest listing(String suite, String name, String summary, String doc) =>
      UnitTest(
        suite: suite,
        name: name,
        summary: summary,
        doc: doc,
        harnessOnlyReason: reason,
      );

  const driver = 'LiveQaDriver (test-harness only)';
  const runner = 'LiveE2eRunner (test-harness only)';
  const panel = 'QaTestRunnerPanel (test-harness only)';

  const harnessNote = '''
> **Harness-only.** This test uses `testWidgets` / the Flutter test binding,
> which replaces the app's own binding at startup — so it can't run inside the
> app. Run it with `flutter test`. It's listed here only so the tab reflects the
> full test scope.
''';

  return <UnitTest>[
    listing(
        driver,
        'finds widgets by text and by type, scoped to the stage',
        'The live driver resolves widgets by text and type within its scope.',
        '''
## What it checks
`LiveQaDriver` locates widgets by their visible text and by their runtime type,
restricted to the subtree it was scoped to.

## Why it matters
Element lookup is the foundation the whole live runner stands on — every tap and
assertion starts by finding a widget. Scoping keeps a scenario from matching
chrome outside its stage.

$harnessNote'''),
    listing(
        driver,
        'taps a real button with hit-tested pointer events',
        'Taps dispatch real hit-tested pointer events to the widget.',
        '''
## What it checks
A tap dispatches genuine, hit-tested pointer events through `GestureBinding`,
exactly as a finger would — not a synthetic callback shortcut.

## Why it matters
Driving the *real* app means the tap has to survive hit-testing, so a widget
covered by an overlay is correctly untappable. This proves the driver taps like
a user, not like a test stub.

$harnessNote'''),
    listing(
        driver,
        'a tap that changes state is observed by the next assertion',
        'State changes from a tap are visible to the following assertion.',
        '''
## What it checks
After a tap triggers a `setState`, the driver's next assertion sees the updated
UI.

## Why it matters
Steps must compose: a scenario taps, then checks the result. If the frame from
the tap weren't settled before the assertion ran, tests would be racy.

$harnessNote'''),
    listing(
        driver,
        'assertions poll, so async work does not need a fixed wait',
        'Assertions poll for a match, so async work needs no fixed delay.',
        '''
## What it checks
`expectVisible`-style assertions poll for a match over a short window rather than
checking exactly once.

## Why it matters
Real screens settle after async work (a Firestore read, an animation). Polling
lets scenarios stay free of brittle `Future.delayed` guesses — the assertion
simply waits until the widget appears or times out.

$harnessNote'''),
    listing(
        driver,
        'types into a field through the wrapping TextField',
        'Text entry reaches the underlying TextField.',
        '''
## What it checks
`enterText` reaches the real `TextField` (through whatever wraps it) and updates
its value.

## Why it matters
Scenarios that search or fill forms depend on text actually landing in the
field, not just on the controller being poked.

$harnessNote'''),
    listing(
        driver,
        'a failed assertion throws and marks the step failed',
        'A failed assertion throws and the step is recorded as failed.',
        '''
## What it checks
When an assertion doesn't hold, the driver throws and the current step is
recorded as failed (rather than silently continuing).

## Why it matters
A live run's whole value is its pass/fail verdict and the red step that shows
*where* it broke. This proves failures are surfaced, not swallowed.

$harnessNote'''),
    listing(
        driver,
        'an ambiguous target fails instead of guessing',
        'An ambiguous locator fails rather than picking one match.',
        '''
## What it checks
When a locator matches more than one widget, the driver fails with an ambiguity
error instead of arbitrarily tapping one.

## Why it matters
Guessing would make scenarios pass or fail based on widget order — a silent
source of flakiness. Failing loudly forces the author to write a precise
locator.

$harnessNote'''),
    listing(
        driver,
        'phases wrap their steps and record failure',
        'Phases group steps and surface a failure within them.',
        '''
## What it checks
`phase(...)` groups a block of steps under a heading and correctly attributes a
failure inside it to that phase.

## Why it matters
Phases are how both the PiP log and `tool/test_report.dart` show *which stage*
of a scenario failed, so the breakdown has to be accurate.

$harnessNote'''),
    listing(
        driver,
        'check() reports plain boolean conditions',
        'check() evaluates and reports a plain boolean condition.',
        '''
## What it checks
`check(label, condition)` evaluates a plain boolean and reports it as a
pass/fail step.

## Why it matters
This is the primitive the logic-only scenarios (and the unit-test tab's
in-app runs) are built on — asserting a value with nothing on screen to drive.

$harnessNote'''),
    listing(
        driver,
        'a root-scoped driver skips QaChrome subtrees',
        'A root-scoped driver prunes the QaChrome (PiP) subtree.',
        '''
## What it checks
A driver scoped to the app root walks the whole element tree **except** the
`QaChrome` subtree (the PiP overlay).

## Why it matters
The live runner drives the real app from its root, but the PiP it paints on top
is part of that same tree. Without pruning, a scenario could match its own
results overlay and tap itself.

$harnessNote'''),
    listing(
        driver,
        'beforeStep is awaited before each step',
        'The beforeStep gate is awaited ahead of every step.',
        '''
## What it checks
The `beforeStep` gate is awaited before every step runs.

## Why it matters
This gate is what powers **debug / step-through**: pausing on a `Completer`
before each step until the user presses Continue. It has to be honoured for
every step, or debugging would skip past some.

$harnessNote'''),
    listing(
        runner,
        'drives the live app and reports a pass in the PiP',
        'The runner drives the app and reports a passing run in the PiP.',
        '''
## What it checks
`LiveE2eRunner` runs a scenario end to end against the app and reports a passing
result in the PiP overlay.

## Why it matters
This is the happy path of the whole live-runner feature: setUp → body →
tearDown, with the outcome shown on screen. If it regressed, the dashboard's ▶
would stop working.

$harnessNote'''),
    listing(
        runner,
        'fails gracefully, and still tears down, with no app harness',
        'With no harness it fails gracefully and still runs teardown.',
        '''
## What it checks
When no `QaAppHarness` is registered (nothing to drive), the run fails with a
clear message **and still executes teardown**.

## Why it matters
Teardown deletes seeded `qa_e2e_*` data. It must run even on failure, or a
broken run would leak test data into the live backend.

$harnessNote'''),
    listing(
        runner,
        'a logic-only scenario (no liveBody) still runs its checks',
        'A logic-only scenario runs its checks without a live body.',
        '''
## What it checks
A scenario with no `liveBody` still runs its `body` checks through the runner.

## Why it matters
The logic-only scenarios (e.g. `MessageBlockPolicy`) have nothing to drive on
screen but still need to run and report — this is the path that lets them.

$harnessNote'''),
    listing(
        runner,
        'a widget scenario with no liveBody fails instead of running against '
            'the real app',
        'A headless-only widget scenario is refused in-app rather than '
            'silently misrun.',
        '''
## What it checks
A scenario that carries a `build` (its own widget tree) but **no** `liveBody`
fails with an explanatory step when run from the dashboard, and its `body` never
executes.

## Why it matters
`build` is only mounted by the `flutter test` bridge. In the app there is nothing
to mount it into, so running the body here would assert against the **real app's**
tree instead — and any check that merely looks for *absence* would pass
vacuously, reporting coverage that never happened. Failing loudly is what makes
the gap visible.

$harnessNote'''),
    listing(
        panel,
        'lists the whole registry, so the dashboard cannot drift',
        'The panel lists every registered scenario, preventing drift.',
        '''
## What it checks
`QaTestRunnerPanel` renders every scenario in `QaRegistry` — the header count and
each suite heading match the registry.

## Why it matters
The dashboard is only trustworthy if it shows the *same* tests CI runs. This test
is the guard against the panel silently omitting a scenario.

$harnessNote'''),
    listing(
        panel,
        'a scenario\'s play button launches just that scenario',
        'A scenario\'s ▶ launches only that scenario.',
        '''
## What it checks
Pressing a single scenario's ▶ launches exactly that one scenario (verified via
the panel's `onLaunch` test seam).

## Why it matters
Per-tile run has to be surgical — running one scenario, not the whole suite,
when you press its button.

$harnessNote'''),
    listing(
        panel,
        'Run all launches every scenario in the registry',
        'Run all launches every scenario in the registry.',
        '''
## What it checks
The **Run all** control launches every scenario in the registry, not a subset.

## Why it matters
"Run all" is the one-click regression pass; missing any scenario would give false
confidence.

$harnessNote'''),
    listing(
        panel,
        'a logic-only scenario is labelled as having nothing to watch',
        'Logic-only scenarios are labelled as having nothing to watch.',
        '''
## What it checks
A logic-only scenario's tile shows the *"logic check — nothing to watch"* label
and runs in place (no PiP).

## Why it matters
It sets the right expectation: pressing ▶ on these runs them inline rather than
launching the on-screen driver.

$harnessNote'''),
    listing(
        panel,
        'shows each scenario\'s last-run time and status',
        'Each tile shows the scenario\'s last-run time and pass/fail.',
        '''
## What it checks
Each tile reads its last run from `QaRunHistory` (backed by a fake Firestore in
the test) and shows the time and pass/fail — with "Not run yet" for the rest.

## Why it matters
The last-run line is how you tell at a glance what has been exercised recently;
this proves it reflects the stored record.

$harnessNote'''),
  ];
}
