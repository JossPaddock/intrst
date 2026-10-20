# Unit Testing Overview

This document is the index of the project's **unit tests** — the pure-logic
tests that assert on functions rather than UI — and the **Unit tests** tab in
the admin dashboard that runs them. It is the unit-level companion to
[`patrol-tests.md`](./patrol-tests.md); the two tabs work the same way and share
the same "one definition, two runners" design.

## One definition, two runners

Unit tests are defined once, in [`lib/qa/unit/`](../../lib/qa/unit), and executed
by two runners:

| Runner | Where | What it is for |
|--------|-------|----------------|
| **Headless** | [`test/support/unit_test_bridge.dart`](../../test/support/unit_test_bridge.dart) | Turns every runnable test into an ordinary `test(...)`. This is what `flutter test`, `scripts/run_tests.sh` and CI execute. |
| **In-app** | [`lib/qa/unit/unit_test_runner.dart`](../../lib/qa/unit/unit_test_runner.dart) | Runs the same body inside the live app and streams its console output into the admin dashboard's **Unit tests** tab. |

Both read the same catalogue,
[`UnitTestRegistry`](../../lib/qa/unit/unit_test_registry.dart), so **the
dashboard's list can never drift from the tests CI runs** — exactly as
`QaRegistry` guarantees for Patrol scenarios.

Tests live under `lib/` (not `test/`) because the in-app runner is app code and
has to import them. The dashboard and its drawer entry are gated on
`kIsWeb && kDebugMode`, so release builds tree-shake all of it away.

### Why "run in-app" is not just `flutter test`

A Flutter **web** app cannot shell out to `flutter test`, and it cannot import
the `test/*_test.dart` files (they depend on `package:flutter_test`, which is not
in the app runtime). So a runnable [`UnitTest`](../../lib/qa/unit/unit_test.dart)
carries its assertions as a plain, dependency-free body against a tiny
[`UnitTestContext`](../../lib/qa/unit/unit_test.dart) (`expectEqual`,
`expectClose`, `expectTrue`, `expectLessOrEqual`, …). The in-app runner executes
that body inside a `Zone` that captures anything the code under test `print`s,
turning a failed assertion into a red result instead of a thrown test. The bridge
runs the *same* body under `flutter test`, translating a failed assertion into a
normal `expect` failure.

The consequence worth knowing: **the dashboard is for running and reading a unit
test's output on a real device/browser; `flutter test` is the source of truth for
whether it passes.**

### Runnable vs. harness-only

Only **pure-logic** tests can run inside the app. Tests that pump widgets or need
the Flutter test binding (`testWidgets`) cannot — the binding replaces the app's
own binding at startup, so a running app can never host them. Those appear in the
tab as **read-only listings** (greyed, a lock icon, no ▶) purely so the tab
reflects the app's full test scope. They are declared in
[`harness_only_unit_tests.dart`](../../lib/qa/unit/harness_only_unit_tests.dart)
and mirror the real `testWidgets` files by hand — when you add a test to one of
those files, add a matching listing there.

## How to run

### From the command line (the source of truth)

```bash
flutter test                                      # whole suite
flutter test test/marker_visibility_test.dart     # one bridged file
flutter test test/DateTimeUtility_test.dart       # another
```

### From the admin dashboard (to run and read output in-app)

1. Run the app in a **web debug** build (`flutter run -d chrome`).
2. Open the drawer → **Admin Dashboard** → the **Unit tests** tab.
3. Press ▶ on a tile to run that test, or **Run all** to run every runnable test.

Unlike the Patrol tab, there is no PiP — a unit test has nothing on screen to
drive. Instead the tab has a docked **log reader** at the bottom: each run
appends a block (a PASS/FAIL header + everything the test `print`ed, captured via
a `Zone`) that you can scroll, select/copy, or clear. The reader collapses to its
header bar when you don't need it.

Every run records its outcome (time + pass/fail) to the same `qa_test_runs`
Firestore collection the Patrol tab uses
([`qa_run_history.dart`](../../lib/qa/e2e/qa_run_history.dart), keyed by test id),
so each tile shows its **last run** across sessions. Use the header's refresh
button to re-read without leaving the tab.

### Reading a test's docs

Every test carries its own documentation. Tap a tile (or its
**document** icon) to open a scrollable preview of that test's doc — rendered
from the test's [`UnitTest.doc`](../../lib/qa/unit/unit_test.dart) markdown by a
tiny in-house renderer ([`simple_markdown.dart`](../../lib/widgets/Admin/simple_markdown.dart),
no dependency). A test with no dedicated doc falls back to its one-line summary.
The docs live inline beside each test in `lib/qa/unit/`, so they can never drift
from the code they describe.

## Test index

| Tests | Area | Defined in | Bridged by |
|-------|------|-----------|------------|
| 6 | Admin dashboard access (`AdminAccess`) | [`admin_access_unit_tests.dart`](../../lib/qa/unit/admin_access_unit_tests.dart) | [`test/admin_access_test.dart`](../../test/admin_access_test.dart) |
| 23 | Date/time formatting (`DateTimeUtility.getFormattedTime`) | [`date_time_unit_tests.dart`](../../lib/qa/unit/date_time_unit_tests.dart) | [`test/DateTimeUtility_test.dart`](../../test/DateTimeUtility_test.dart) |
| 44 | Map marker visibility/labelling (`MarkerVisibility`) | [`marker_visibility_unit_tests.dart`](../../lib/qa/unit/marker_visibility_unit_tests.dart) | [`test/marker_visibility_test.dart`](../../test/marker_visibility_test.dart) |
| 8 | Map camera memory (`MapCameraSnapshot`) | [`map_camera_memory_unit_tests.dart`](../../lib/qa/unit/map_camera_memory_unit_tests.dart) | [`test/map_camera_memory_test.dart`](../../test/map_camera_memory_test.dart) |
| 7 | Search fly-to camera path (`MapFlyPath`) | [`map_fly_path_unit_tests.dart`](../../lib/qa/unit/map_fly_path_unit_tests.dart) | [`test/map_fly_path_test.dart`](../../test/map_fly_path_test.dart) |
| 9 | Declined-location placement (`IpLocationLookup`, `MapZoom`) | [`ip_placement_unit_tests.dart`](../../lib/qa/unit/ip_placement_unit_tests.dart) | [`test/ip_placement_test.dart`](../../test/ip_placement_test.dart) |
| 8 | Message editing rules (`MessageEditPolicy`) | [`message_edit_unit_tests.dart`](../../lib/qa/unit/message_edit_unit_tests.dart) | [`test/message_edit_test.dart`](../../test/message_edit_test.dart) |
| 9 | Sign-up wizard validation (`signup_wizard_data.dart`) | [`signup_wizard_unit_tests.dart`](../../lib/qa/unit/signup_wizard_unit_tests.dart) | [`test/signup_wizard_test.dart`](../../test/signup_wizard_test.dart) |
| 20 (read-only) | QA tooling (`LiveQaDriver`, `LiveE2eRunner`, `QaTestRunnerPanel`) | [`harness_only_unit_tests.dart`](../../lib/qa/unit/harness_only_unit_tests.dart) | run via their own `testWidgets` files |

`date_time_unit_tests.dart` and `marker_visibility_unit_tests.dart` cover the
same logic the old standalone `flutter test` files did; those files are now thin
bridges that call the shared definitions.

### Suite — `MessageEditPolicy (message editing)`

Guards **message editing** — the rules deciding when the pencil appears on a
chat bubble and when a rewrite is allowed to reach Firestore. The policy lives
in [`MessageEditPolicy`](../../lib/utility/MessageEditPolicy.dart) and is read
in two places: [`ChatScreen`](../../lib/widgets/ChatScreen.dart) uses it to
decide whether to pass an `onEdit` callback into a bubble, and
[`FirebaseMessagesUtility.editMessage`](../../lib/utility/FirebaseMessagesUtility.dart)
re-checks it against the stored message before writing, so a client that skipped
the UI check still cannot rewrite anything.

Editing rewrites text the other participant may already have read, so the tests
pin how narrow that is: only the author, only within the 15-minute window (the
boundary is asserted at 14/15/16 minutes), never while the conversation is
blocked, and never for a message whose server timestamp has not landed yet. A
send time slightly in the *future* — ordinary skew between the device clock and
`serverTimestamp()` — must not read as expired, or the pencil would vanish from
the message the user just sent.

The remaining tests cover what may be written: `isValidEdit` rejects an
unchanged message, one that differs only in surrounding whitespace, and an empty
one (emptying a message would be deletion by the back door, which this feature
deliberately does not offer), while `normalize` fixes the exact string stored so
the dialog's preview and the saved message cannot disagree.

The user-visible half — which bubbles offer the pencil, the `(edited)` marker,
and the dialog refusing to save a no-op — is covered by the **Chat bubble
(editing)** and **Edit message dialog** scenarios in
[`patrol-tests.md`](./patrol-tests.md).

### Suite — `MapCameraSnapshot`

Guards the **"the map reopens where you left it"** behaviour. The map's
`initialCameraPosition` is read exactly once, when the `GoogleMap` widget is
built, and it comes from a [`MapCameraSnapshot`](../../lib/main/map_camera_memory.dart)
decoded out of device preferences (see
[`home_map_bootstrap.dart`](../../lib/main/home_map_bootstrap.dart)). That makes
the snapshot's validation the only thing standing between a corrupt preference
and a map that opens somewhere the user has never been.

The tests cover both directions of that risk: a good camera must survive the
encode/decode round trip (including ints and numeric strings, so a JSON
representation detail never discards a real memory), and a bad one must decode
to `null` so the bootstrap falls back to its default — malformed JSON, partial
objects, impossible coordinates, NaN/infinity. Zoom is clamped rather than
rejected, because an out-of-range zoom still carries a usable location. The
`isSameViewAs` tests pin the write-throttling used by `onCameraIdle`, which
fires after every gesture: a sub-metre nudge is "the same view", and a `null`
previous camera never is, so the first camera of a session is always persisted.

### Suite — `MapFlyPath`

Guards the **smooth camera flight** the map makes when a search in the top bar
narrows down to exactly one person: `_focusSoleSearchResult` in
[`home_location_logic.dart`](../../lib/main/home_location_logic.dart) hands
their marker to `flyCameraTo`. On Android and iOS that is the SDK's own
`animateCamera`. On web the plugin implements `animateCamera` as a plain
`moveCamera`, which jumps, so the app steps the camera once per frame along a
[`MapFlyPath`](../../lib/main/map_fly_path.dart). That class is van Wijk &
Nuij's smooth zoom-and-pan curve, the same one d3 and Mapbox use.

The tests pin what a user would notice if the curve were wrong:

- The flight lands **exactly** on the target camera.
- A long hop **zooms out** mid-flight and keeps closing on the destination, so
  it never scrolls thousands of screens of tiles past at street zoom.
- A short hop **doesn't** zoom out.
- Tokyo → Honolulu goes across the Pacific, not the long way round.
- The duration scales with distance between `minDuration` and `maxDuration`.
- The same-centre zoom (the curve's special case) doesn't move the centre.
- Max zoom to the far side of the world stays **finite**. The map silently
  ignores a NaN camera, which would freeze the flight.

### Suites — `IpLocationLookup.parseResponse` and `MapZoom.forRadius`

The **decline-to-share** placement path. A new sign-up who declines location
sharing is placed from their IP address, once, from whatever these two pure
functions return — there is no retry and no second chance to get it right, which
is what makes them worth testing rather than the HTTP call around them.

The parser tests matter most for the *failure* shapes. Both providers answer
rate limiting with HTTP 200 and an error payload carrying coordinates of `0`,
and both use `0, 0` for reserved addresses — so a parser that only read
latitude/longitude would place the user in the Gulf of Guinea, report success,
and skip the fallback provider. The tests pin both provider shapes through the
single shared parser, so if those shapes ever diverge this fails rather than the
fallback chain silently never working.

The zoom tests assert the actual product requirement — that the marker we
guessed *and* the area the user is really in both fit on screen — by
re-deriving ground resolution from the returned zoom
(`156543.03392 * cos(lat) / 2^zoom`) instead of trusting the function's own
arithmetic. They also pin the two directions that are easy to invert: a vaguer
estimate must zoom *out*, never in, and a higher latitude must widen the view to
account for Mercator distortion. The clamp tests exist because this value goes
straight into `initialCameraPosition` during start-up, where a NaN would break
the one launch a user cannot skip.

### Suite — `MarkerVisibility.buildVisibleMarkers — zoom round-trips`

The **"swap to labels and back" regression guard**. The map rebuilds its whole
marker set on every camera move — `_onCameraMove` calls
[`MarkerVisibility.buildVisibleMarkers`](../../lib/main/marker_visibility.dart)
and hands the result straight to `setState` — so zooming in to swap crowded POI
dots for name labels and zooming back out must land on *exactly* the marker set
it started with.

Each test walks the builder through a zoom sweep, one call per zoom, and compares
the final `MarkerId`s against the initial ones:

| Test | Sweep | Guards |
|------|-------|--------|
| `zoom 10 -> 18 -> 10 …` (layered / original) | proximity threshold, 5479 m at zoom 10 → 21 m at zoom 18 | crowded markers gain labels and lose them again |
| `zoom 10 -> 1 -> 10 …` (layered / original) | the `minLabelZoom` (2.0) gate, crossed **downwards and back up** | labels dropped below the gate all come back |

The fixture is a crowded pair 110 m apart plus one isolated marker, chosen so
every waypoint is a genuinely different set:

| | zoom 1 | zoom 10 | zoom 18 |
|---|---|---|---|
| layered | `a`, `b`, `c` | `a`, `b`, `c`, `c_label` | `a`, `b`, `c` + all three labels |
| original | `a`, `b`, `c` | `a`, `b`, `c_label` | all three as labels |

Every test also asserts the **midpoint differs** from the start, so none can pass
vacuously; and each `note()`s the id set at each zoom, so a failure in the
dashboard's log reader shows the sweep step by step.

`MarkerVisibility` is pure today, so these round trips hold by construction —
which is exactly the property under guard. The moment anyone adds caching,
memoisation or accumulated state to the marker pipeline, a stale label or an
orphaned dot would survive the trip back and these fail. The same sweeps run at
scenario granularity in the Patrol tab's `Marker label zoom round-trips` suite
([`patrol-tests.md`](./patrol-tests.md)).

### Suite — `Signup wizard (validation)`

Guards the rules behind the **multi-part sign-up wizard**
([`lib/login/signup/`](../../lib/login/signup)), which collects name and age,
a first interest, and a marker location across three screens.

These rules carry unusual weight because the wizard runs **before** the Firebase
Auth account is created: whatever they let through becomes a real account, a real
profile document and a real marker on the map. The age gate in particular is the
last check before account creation, so the boundary is asserted on both sides —
one day short of 13 is refused, turning 13 today is allowed.

The birthday parser gets its own tests because `DateTime` *normalizes*
out-of-range parts instead of throwing (month 13 quietly becomes January of the
next year), so `13/01/1990` and `02/30/1991` have to be rejected by an explicit
round-trip check rather than by the constructor. The remaining tests pin the
field validators (names, birthday format, interest name), the drag-to-place
behaviour of [`SignupLocationDraft`](../../lib/login/signup/signup_wizard_data.dart)
— a dragged pin becomes a `manual` placement and keeps the zoom the user settled
on — and that the wizard's step enum still describes exactly three parts, which
is what the progress header counts.

The screens that enforce these rules are covered by the
`Signup wizard (…)` scenarios in
[`patrol-tests.md`](./patrol-tests.md#signup_wizard_scenariosdart).

### Suite — `AdminAccess (admin dashboard gate)`

Guards **who may open the admin dashboard**
([`AdminAccess`](../../lib/utility/AdminAccess.dart)).

The gate this replaced was `kIsWeb && kDebugMode` alone — it asked what kind of
build was running and never who was signed in, so on a debug web build any
signed-in user could open the dashboard from the drawer, test accounts included.
The rule now mirrors `_is_admin_caller` in `functions/main.py`: the custom claim
`admin == true`, **or** an email on the allowlist.

The tests pin the parts that are easy to get subtly wrong. Email comparison is
case- and whitespace-insensitive (Firebase reports the address as the user typed
it) but not a substring match, so `joss.self@gmail.com.attacker.tld` is refused.
The claim must be the boolean `true` — `'true'` and `1` grant nothing, matching
the server's `is True`. The two conditions are independent, so a missing or
`false` claim never vetoes the allowlist: [`AdminAccess.isAdmin`] falls back to
the email when a token read fails, and a dropped connection must not lock the
admin out of a screen whose privileged actions are re-checked server-side.
Everything else — no email, an empty email, an ordinary user — fails closed.

**Keep [`AdminAccess.adminEmails`] in sync with `ADMIN_EMAILS` in
`functions/main.py`.** The server list is authoritative and is the actual
security boundary; these tests cover the client mirror only.

## Adding a new unit test

1. Add it to a file under [`lib/qa/unit/`](../../lib/qa/unit) (new file or
   existing), returning `UnitTest`s.
2. Register the file's list in
   [`UnitTestRegistry.all()`](../../lib/qa/unit/unit_test_registry.dart).
3. If it is a new file, add a `test/<feature>_test.dart` that calls
   `registerUnitTests(yourTests())`.
4. Add a row to the [Test index](#test-index) above.

It then appears in both `flutter test` and the dashboard automatically.

A `UnitTest` is a `name`/`summary` plus a `body` written against
[`UnitTestContext`](../../lib/qa/unit/unit_test.dart):

```dart
UnitTest(
  suite: 'MarkerVisibility.buildVisibleMarkers — layered',
  name: 'at zoom 2.0 exactly, labels become eligible again',
  summary: 'The 2.0 boundary is inclusive: labels appear for isolated markers.',
  body: (t) => t.expectEqual(
    idsOf(buildLayered(zoom: MarkerVisibility.minLabelZoom)),
    {'a', 'b', 'c', 'a_label', 'b_label', 'c_label'},
  ),
);
```

Give each test a `doc:` — lightweight markdown (`##` headings, `-` bullets,
`**bold**`, `` `code` ``) shown in the tile's tap-to-open preview. Keep it to a
few short sections (what it checks / why it matters / expected). It's optional:
a test with no `doc` falls back to its one-line `summary` in the preview.

`UnitTestContext` offers `expectEqual` (deep/unordered equality),
`expectClose`, `expectTrue`, `expectFalse`, `expectEmpty`, `expectLessOrEqual`,
and `note(...)` to add a line to the console output. Each failed assertion throws
`UnitTestFailure`, which the bridge turns into a normal `expect` failure and the
in-app runner paints red.

Omit `body` (and set `harnessOnlyReason`) for a **read-only listing** of a test
that can only run under the `flutter test` harness.
