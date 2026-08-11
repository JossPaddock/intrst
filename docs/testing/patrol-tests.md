# Patrol Testing Overview

This document is the high-level index of the [Patrol](https://patrol.leancode.co/)
scenarios in this repository: what each covers, where to find it, and the two
ways to run it.

## What "Patrol" means here

This project depends on **`patrol_finders`** (see [`pubspec.yaml`](../../pubspec.yaml)),
not the full `patrol` integration-test runner. In practice that means:

- Scenarios drive widgets through the `PatrolTester` (`$`) API — the same
  ergonomic finder/interaction layer Patrol provides — but they run as **Flutter
  widget tests**, in-process, with no device or emulator required.
- They run with the standard `flutter test` command (no `patrol` CLI needed).
- They mount real production widgets in a test `MaterialApp` harness and assert
  on what the user would see.

## One definition, two runners

Scenarios are defined once, in [`lib/qa/scenarios/`](../../lib/qa/scenarios), and
executed by two different runners:

| Runner | Where | What it is for |
|--------|-------|----------------|
| **Headless** | [`test/support/qa_scenario_bridge.dart`](../../test/support/qa_scenario_bridge.dart) | Turns every scenario into a `patrolWidgetTest`. This is what `flutter test`, `scripts/run_tests.sh` and CI execute. |
| **Live** | [`lib/qa/live_qa_driver.dart`](../../lib/qa/live_qa_driver.dart) + [`lib/qa/e2e/`](../../lib/qa/e2e) | Drives the **real running app** (real screens, real backend), paced so you can watch it, with results in a PiP overlay. This is what the admin dashboard uses. |

Both read the same catalogue, [`QaRegistry`](../../lib/qa/qa_registry.dart), so
**the dashboard's list of tests can never drift from the tests CI runs**.

Scenarios live under `lib/` (not `test/`) because the live runner is app code and
has to import them. Both the dashboard and its drawer entry are gated on
`kIsWeb && kDebugMode` — compile-time constants — so release builds tree-shake
the dashboard, the scenarios, and `fake_cloud_firestore` away.

### Why the live runner is not simply "running the tests"

A Flutter **web** app cannot shell out to `flutter test`, and `WidgetTester` only
exists under `TestWidgetsFlutterBinding`, which replaces the app's own binding at
startup — so a running app can never host a widget test. The live runner
therefore drives the real element tree directly: it locates widgets by walking
elements from the app root (pruning its own PiP chrome) and taps them by
dispatching genuine pointer events through `GestureBinding`, exactly as a finger
would. It reaches the running app through a small [`QaAppHarness`](../../lib/qa/e2e/qa_app_harness.dart)
that `_MyHomePageState` implements and registers (web + debug only), so it can
sign in, open a `Preview`, or open a conversation via the app's own code paths.
No test framework is pulled into the app.

The consequence worth knowing: **the dashboard is for watching and debugging a
scenario; `flutter test` is the source of truth for whether it passes.** Both
execute the same steps against the same widgets, but only the headless run is
what CI gates on.

## How to run

### From the command line (the source of truth)

```bash
flutter test                                           # whole suite
./scripts/run_tests.sh                                 # same, with the CI-style report
flutter test test/blocking_messages_patrol_test.dart   # one file
```

### From the admin dashboard (to watch it happen against the real app)

1. Run the app in a **web debug** build. To also run the scenarios that need an
   authenticated (or explicitly signed-out) session, supply a throwaway test
   account:
   ```bash
   flutter run -d chrome \
     --dart-define=QA_E2E_EMAIL=qa@example.com \
     --dart-define=QA_E2E_PASSWORD=•••••••
   ```
2. Open the drawer → **Admin Dashboard** → the **Patrol tests** tab.
3. Press ▶ to run a scenario, 🐞 to **debug** (step through) it, or **Run all**.

Unlike the headless run, the dashboard drives the **real running app**. Pressing
▶ closes the dashboard to reveal the live app, then drives production screens —
the real `Preview`, the real chat, the real login route — with genuine
hit-tested taps. Each target is highlighted, and a **draggable Picture-in-Picture
overlay** streams the step log and the pass/fail result on top of the app. When a
run finishes, use the PiP's **Back to dashboard** to return.

The PiP also has:
- **Debug (step-through):** pressing 🐞 instead of ▶ pauses the run *before every
  step* (the step shows as pending) and waits for you to press **Continue** in
  the PiP, so you can watch it play out at your own pace.
- **Copy logs:** the overlay text isn't selectable, so the header's copy button
  puts the whole run — scenario, status and every step (with any failure text) —
  on the clipboard as plain text.

Every run records its outcome (time + pass/fail) to the `qa_test_runs` Firestore
collection ([`qa_run_history.dart`](../../lib/qa/e2e/qa_run_history.dart), one
fixed doc per scenario), and each tile shows its **last run** — so you can see at
a glance when a scenario last ran and whether it passed. Use the header's refresh
button to re-read without leaving the tab.

Before every scenario the runner **resets the app to a baseline** (dismisses any
open dialog/drawer, returns to the map) via `QaAppHarness.resetToBaseline`, so a
scenario never inherits UI state a previous one left behind (e.g. an open
`Preview`). That makes **Run all** order-independent and not susceptible to
"the app wasn't on the right screen" faults.

Because it drives the real app, the live run seeds the **live** backend
(`intrst-1525412155568`). Everything it writes lives under the reserved
`qa_e2e_*` id namespace, and cleanup deletes only the exact documents it created
(see [`qa_seed.dart`](../../lib/qa/e2e/qa_seed.dart)) — never a query-and-delete —
so it cannot touch real data. Two of the scenarios open the `Preview` by invoking
the app's real `handleMarkerTap` in code, since a Google Maps marker (a platform
view) can't be tapped; everything the Preview then does is real.

Scenarios that assert on logic rather than UI (the `MessageBlockPolicy` checks)
are marked *"logic check — nothing to watch"*. There is nothing to drive, so
their ▶ **runs them in place in the dashboard** — no PiP, no leaving the tab —
and reports the result on the tile (and a brief snackbar). Only scenarios that
actually drive the app (▶ / 🐞) open the PiP. A scenario that needs a session it
can't get (no one signed in and no test credentials) fails gracefully with an
explanatory step rather than hanging.

## Test index

| Scenarios | Area | Defined in | Registered by |
|-----------|------|-----------|---------------|
| 2 widget + 6 logic | Messaging / blocking | [`blocking_scenarios.dart`](../../lib/qa/scenarios/blocking_scenarios.dart) | [`test/blocking_messages_patrol_test.dart`](../../test/blocking_messages_patrol_test.dart) |
| 2 widget | Map / preview | [`marker_preview_scenarios.dart`](../../lib/qa/scenarios/marker_preview_scenarios.dart) | [`test/marker_opens_preview_patrol_test.dart`](../../test/marker_opens_preview_patrol_test.dart) |
| 1 widget | Logged-out preview → login | [`preview_login_scenarios.dart`](../../lib/qa/scenarios/preview_login_scenarios.dart) | [`test/widgets/preview_logged_out_login_test.dart`](../../test/widgets/preview_logged_out_login_test.dart) |

---

## `blocking_scenarios.dart`

Covers the user blocking feature's messaging enforcement — both the UI the two
sides of a block see, and the underlying policy that decides when a 1:1
conversation is blocked.

### Suite — `Blocked messaging notice`

Mounts the production [`BlockedMessageNotice`](../../lib/widgets/BlockedMessageNotice.dart)
widget (rendered by `CollapsibleChatScreen` in place of the message input).

| Scenario | What it verifies |
|----------|------------------|
| `a blocked user sees "not accepting messages" and cannot send` | The **blocked** user (not the blocker) sees the neutral copy, the blocker-facing copy does **not** leak (which would reveal they were blocked), and no `TextField` is rendered — there is no way to type or send. |
| `the blocker sees the "you blocked them, unblock to continue" message` | The **blocker** sees the actionable unblock copy, the blocked-user copy is not shown, and no input affordance is rendered. |

### Suite — `MessageBlockPolicy (1:1 send enforcement)`

Exercises [`MessageBlockPolicy.isBlocked`](../../lib/utility/MessageBlockPolicy.dart),
the single predicate that gates both hiding the input and the hard stop inside
`_handleSendMessage`.

| Scenario | Expected |
|----------|----------|
| Viewer blocked the other user | blocked |
| Other user blocked the viewer | blocked |
| Both sides blocked each other | blocked |
| Neither side blocked | not blocked |
| Group conversation (more than one other participant) | not enforced / not blocked |
| No other participant | not blocked |

## `marker_preview_scenarios.dart`

Mirrors the two branches of `handleMarkerTap` (`lib/main/home_map_logic.dart`),
driving a real `google_maps` `Marker` and the real `Preview` widget. A
`GoogleMap` platform view cannot render in a widget test, so a proxy button
invokes the marker's own `onTap`.

| Scenario | What it verifies |
|----------|------------------|
| `tapping another user's marker opens the Preview for that user` | The Preview dialog opens showing the tapped person. |
| `tapping your own marker does not open a Preview` | The end drawer opens instead; no Preview appears. |

## `preview_login_scenarios.dart`

| Scenario | What it verifies |
|----------|------------------|
| `selecting an interest routes an unauthenticated visitor to the login/sign-up page` | A logged-out visitor tapping a link-free interest is routed to slot 1 (login/sign-up) and the preview is dismissed. |

---

## Adding a new scenario

1. Add it to a file under [`lib/qa/scenarios/`](../../lib/qa/scenarios) (new file
   or existing), returning `QaScenario`s.
2. Register the file's list in [`QaRegistry.all()`](../../lib/qa/qa_registry.dart).
3. If it is a new file, add a `test/<feature>_patrol_test.dart` that calls
   `registerQaScenarios(yourScenarios())`.
4. Add a row to the [Test index](#test-index) above.

It then appears in both `flutter test` and the dashboard automatically.

A scenario is a `build` (the widget tree, rebuilt fresh on every run) plus a
`body` written against [`QaDriver`](../../lib/qa/qa_scenario.dart):

```dart
QaScenario(
  suite: 'Blocked messaging notice',
  name: 'the blocker sees the unblock message',
  summary: 'Shown in the dashboard so the scope is readable without opening code.',
  build: () => _notice(viewerIsBlocker: true, otherName: 'User B'),
  body: (d) async {
    await d.expectVisible(
      qaText(BlockedMessageNotice.blockerMessage('User B')),
      count: 1,
    );
    await d.expectAbsent(qaType(TextField));
  },
);
```

`QaDriver` offers `tap`, `enterText`, `settle`, `expectVisible` (optionally with
an exact `count`), `expectAbsent`, `check` (for plain booleans) and `phase` for
grouping steps. Locators are `qaText(...)`, `qaType(...)` and `qaKey(...)`.

Omit `build` for a logic-only scenario. To assert on state captured during a run,
define the scenario in a small class whose `build` resets that state — see
`preview_login_scenarios.dart`.

### Making a scenario runnable against the live app

`build`/`body` are the CI source of truth and always run under `flutter test`.
To *also* let the dashboard drive it against the real app, add the optional live
hooks — they're ignored by `flutter test` and only used by the dashboard:

```dart
QaScenario(
  // ...headless build/body as above...
  liveSetUp: (harness) async {
    // Seed via QaSeeder (namespaced qa_e2e_* ids) and/or sign in:
    await seeder.seedUser(uid: QaSeeder.otherUid, firstName: 'Ada', lastName: 'Lovelace');
  },
  liveBody: (d, harness) async {
    await harness.openPreviewFor(QaSeeder.otherUid, 'Ada Lovelace'); // real code path
    await d.expectVisible(qaText('Ada Lovelace'));                    // drive the real widget
  },
  liveTearDown: (harness) => seeder.cleanup(),   // deletes only what it created
);
```

Share one [`QaSeeder`](../../lib/qa/e2e/qa_seed.dart) across a scenario's
`liveSetUp`/`liveTearDown` (hold it in a small class, like the `_…Live` holders
in the scenario files) so cleanup can delete exactly what setup created. The
[`QaAppHarness`](../../lib/qa/e2e/qa_app_harness.dart) methods
(`signInTestUser`, `openPreviewFor`, `openConversationWith`, `goHome`, …) each
delegate to a real app code path. A scenario with no `liveBody` still appears in
the dashboard and runs its `body` (used for the logic-only checks).

`phase` maps onto the existing [`phase()`](../../test/support/test_phase.dart)
helper under `flutter test`, so `tool/test_report.dart` still prints the phase
breakdown for failures, and onto a bold heading in the dashboard's step log.

## Tests covering the test tooling

Because the live runner only ever executes inside a running app, it has its own
coverage so it cannot rot unnoticed:

- [`test/qa_live_driver_test.dart`](../../test/qa_live_driver_test.dart) —
  element lookup, hit-tested pointer dispatch, polling assertions, `enterText`,
  ambiguity detection, failure recording, phases.
- [`test/qa_test_runner_panel_test.dart`](../../test/qa_test_runner_panel_test.dart) —
  the dashboard panel lists the whole registry, and pressing ▶ really mounts and
  drives a scenario to a green result.

Both work by swapping [`QaPacer`](../../lib/qa/live_qa_driver.dart) — the one part
of the driver that genuinely needs a running app (waiting on real frames and a
real clock) — for a tester-backed implementation.

## Related, non-Patrol tests

- [`test/DateTimeUtility_test.dart`](../../test/DateTimeUtility_test.dart) —
  exhaustive formatting cases for `DateTimeUtility.getFormattedTime`
  (today / yesterday / tomorrow / within 7 days / beyond 7 days / cross-year /
  time-formatting edge cases). Plain unit tests, not registered in `QaRegistry`.
