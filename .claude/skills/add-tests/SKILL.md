---
name: add-tests
description: Add test coverage to the intrst Flutter app the project's way — one definition in lib/qa/, run by both `flutter test` and the admin dashboard, with docs/testing/ kept in sync. Use whenever asked to add, extend, or backfill tests, increase coverage, or "write a test for X".
---

# Adding tests to intrst

This project does **not** put test logic in `test/`. Every test is defined once
under `lib/qa/`, registered in a registry, and executed by two runners:

| Kind | Definition lives in | Registry | Headless bridge | In-app runner |
|------|--------------------|----------|-----------------|---------------|
| **Unit** (pure logic) | `lib/qa/unit/*_unit_tests.dart` | `lib/qa/unit/unit_test_registry.dart` | `test/support/unit_test_bridge.dart` | `lib/qa/unit/unit_test_runner.dart` → dashboard **Unit tests** tab |
| **Patrol scenario** (widget / flow) | `lib/qa/scenarios/*_scenarios.dart` | `lib/qa/qa_registry.dart` | `test/support/qa_scenario_bridge.dart` | `lib/qa/live_qa_driver.dart` + `lib/qa/e2e/` → dashboard **Patrol tests** tab |

Files in `test/` are **thin bridges only** (≈10 lines: import the definitions,
call `registerUnitTests(...)` / `registerQaScenarios(...)`). Never write
assertions there. The two exceptions are the tests that cover the QA tooling
itself (`test/qa_*_test.dart`, `test/unit_test_runner_panel_test.dart`), which
must use `testWidgets`; those get **read-only listings** instead (see step 5).

Definitions live under `lib/` because the in-app runner is app code and must
import them. The dashboard is gated on `kIsWeb && kDebugMode`, so release builds
tree-shake it all away — do not add non-debug-gated entry points.

`flutter test` is the source of truth for pass/fail. The dashboard is for
running/watching a test against the real app.

## Pick the kind

- Asserting on a **function's return value** with no widgets → **unit test**.
- Asserting on **what a user sees or does** (widgets, dialogs, routes) →
  **Patrol scenario** with `build` + `body`.
- A logic predicate that belongs conceptually with a UI feature (e.g.
  `MessageBlockPolicy`) may be a **logic-only scenario** — a `QaScenario` with no
  `build`, body of `d.check(...)`. It runs in place in the dashboard, no PiP.
- If the code under test isn't reachable as a pure function, extract the logic
  first (see `lib/main/marker_visibility.dart` as the pattern) rather than
  reaching into widget state.

## Recipe A — unit test

1. Add `UnitTest`s to an existing `lib/qa/unit/<area>_unit_tests.dart`, or create
   one exporting `List<UnitTest> <area>UnitTests()`.
2. Every test needs `suite`, `name`, `summary` (one line, shown on the dashboard
   tile), and `body`. Add `doc:` (lightweight markdown — `##`, `-`, `**bold**`,
   `` `code` ``) when the test deserves an explanation; it renders in the tile's
   expandable preview via `SimpleMarkdown`.
3. Body assertions use `UnitTestContext` only — **never** `package:flutter_test`,
   which the app runtime cannot import: `expectEqual` (deep/unordered),
   `expectClose`, `expectTrue`, `expectFalse`, `expectEmpty`,
   `expectLessOrEqual`, and `note(...)` to add a console line.
4. New file → add its list to `UnitTestRegistry.all()` **and** add a bridge
   `test/<area>_test.dart`:
   ```dart
   import 'package:intrst/qa/unit/<area>_unit_tests.dart';
   import 'support/unit_test_bridge.dart';

   // The tests themselves live in lib/qa/unit/… so the admin dashboard's Unit
   // tests tab can run them in-app. This file makes `flutter test` run the same
   // definitions headlessly.
   void main() => registerUnitTests(<area>UnitTests());
   ```
5. If you instead added a `testWidgets` test to one of the QA-tooling files, add
   a matching read-only listing in `lib/qa/unit/harness_only_unit_tests.dart`
   (`UnitTest` with no `body`, with `harnessOnlyReason`) so the tab still
   reflects the app's full scope.

## Recipe B — Patrol scenario

1. Add `QaScenario`s to an existing `lib/qa/scenarios/<area>_scenarios.dart`, or
   create one exporting `List<QaScenario> <area>Scenarios()`.
2. `suite`, `name`, `summary`, `build` (rebuilt fresh each run — mount the real
   production widget in a test `MaterialApp`), `body` against `QaDriver`:
   `tap`, `enterText`, `settle`, `expectVisible` (optional exact `count`),
   `expectAbsent`, `check`, `phase`. Locators: `qaText`, `qaType`, `qaKey`.
   Omit `build` for a logic-only scenario. To assert on state captured during a
   run, wrap the scenario in a small class whose `build` resets that state (see
   `preview_login_scenarios.dart`).
3. New file → add its list to `QaRegistry.all()` **and** add a bridge
   `test/<area>_patrol_test.dart` calling `registerQaScenarios(<area>Scenarios())`.
4. **Optional live hooks** (ignored by `flutter test`, used only by the
   dashboard) so it can be driven against the real running app:
   `liveSetUp(harness)`, `liveBody(driver, harness)`, `liveTearDown(harness)`.
   Rules that matter:
   - Seeding writes to **live prod**. Only ever create ids in the reserved
     `qa_e2e_*` namespace via `QaSeeder` (`lib/qa/e2e/qa_seed.dart`), share one
     seeder instance between `liveSetUp`/`liveTearDown`, and clean up by
     deleting the exact documents created — never query-and-delete.
   - Reach the app through `QaAppHarness` (`signInTestUser`, `openPreviewFor`,
     `openConversationWith`, `goHome`, `resetToBaseline`), which delegates to
     real app code paths. Don't poke widget internals.
   - A scenario needing a session it can't get must fail with an explanatory
     step, not hang.

## Always: documentation

A test isn't done until its doc is updated. This is non-negotiable in this repo —
the docs are the human-readable index of scope.

- Unit test → `docs/testing/unit-tests.md`
- Patrol scenario → `docs/testing/patrol-tests.md`

Update **all** of:
1. The **Test index** table — counts, area, definition file link, bridge file
   link. Recount rather than incrementing from memory.
2. For `patrol-tests.md`, the per-file section: a `### Suite — <name>` heading
   and a row per scenario in the "What it verifies" table.
3. Any prose that a new capability makes stale (e.g. a new harness method, a new
   assertion helper, a new gating rule).

Links are repo-relative (`../../lib/qa/...`) and must resolve.

## Always: verify

```bash
flutter test                                    # whole suite — must be green
flutter test test/<your>_test.dart              # just yours
./scripts/run_tests.sh                          # CI-style report (tool/test_report.dart)
flutter analyze                                 # definitions live in lib/, so they are app code
```

Then confirm the dashboard side, since that's half the point of the design:
- Read back `UnitTestRegistry.all()` / `QaRegistry.all()` and confirm the new
  list is wired in — an unregistered file silently tests nothing in the app.
- If asked to check it visually: `flutter run -d chrome` (add
  `--dart-define=QA_E2E_EMAIL=… --dart-define=QA_E2E_PASSWORD=…` for scenarios
  needing a session), then drawer → **Admin Dashboard** → the relevant tab, and
  press ▶. Each run records to the `qa_test_runs` Firestore collection keyed by
  test id (`lib/qa/e2e/qa_run_history.dart`), so tiles show a last-run stamp.

## Checklist

- [ ] Definition under `lib/qa/unit/` or `lib/qa/scenarios/` — not in `test/`
- [ ] Registered in `UnitTestRegistry.all()` / `QaRegistry.all()`
- [ ] Bridge file in `test/` exists (new definition files only), ~10 lines
- [ ] `summary` written for every test (it's dashboard-facing copy, not a comment)
- [ ] Live hooks, if any, seed only `qa_e2e_*` ids and clean up exactly those
- [ ] `docs/testing/*.md` index + per-suite tables updated
- [ ] `flutter test` and `flutter analyze` green; report what actually ran
