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
sign in, open a `Preview`, open a conversation, open the sign-up wizard, or
drive the map via the app's own code paths. No test framework is pulled into the
app.

The map is the one surface the element walk cannot see at all: a `GoogleMap` is a
**platform view**, so its markers are neither in the element tree nor tappable.
The harness therefore also exposes the map's own state and controls —
`visibleMarkerIds()`, `currentMapZoom` / `initialMapZoom` / `rememberedCameraZoom()`,
`applyMapZoom`, `reloadMarkers`, `enterSearch` / `clearSearch`,
`setRelationshipFilters` and `openPreviewForMarkerId` — each delegating to the
production path (`_onCameraMove`, `loadMarkers`, the real search controller, the
real filter-chip handler, `handleMarkerTap`). A live map scenario asserts on the
marker ids the app actually handed Google Maps.

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

### Reading a scenario's docs

Every scenario carries its own documentation. Tap a tile (or its **document**
icon) to open a scrollable preview of that scenario's doc — what it checks, why it
matters, and how it runs headless vs. live. It's rendered from the scenario's
[`QaScenario.doc`](../../lib/qa/qa_scenario.dart) markdown by the same in-house
renderer the Unit tests tab uses
([`simple_markdown.dart`](../../lib/widgets/Admin/simple_markdown.dart)) via the
shared [`test_doc_sheet.dart`](../../lib/widgets/Admin/test_doc_sheet.dart), so the
two tabs present docs identically. A scenario with no dedicated doc falls back to
its one-line summary. The docs live inline beside each scenario in
`lib/qa/scenarios/`, so they can't drift from the code.

Before every scenario the runner **resets the app to a baseline** (dismisses any
open dialog/drawer, returns to the map) via `QaAppHarness.resetToBaseline`, so a
scenario never inherits UI state a previous one left behind (e.g. an open
`Preview`). That makes **Run all** order-independent and not susceptible to
"the app wasn't on the right screen" faults.

Because it drives the real app, the live run seeds the **live** backend
(`intrst-1525412155568`). Everything it writes lives under the reserved
`qa_e2e_*` id namespace, and cleanup deletes only the exact documents it created
(see [`qa_seed.dart`](../../lib/qa/e2e/qa_seed.dart)) — never a query-and-delete —
so it cannot touch real data. The scenarios that open a `Preview` do so by
invoking the app's real `handleMarkerTap` in code, since a Google Maps marker (a
platform view) can't be tapped; everything the Preview then does is real. The
live map scenarios seed their fixture user at a deliberately remote point in the
South Atlantic, so its marker is isolated from every real user and its label is
decided by the zoom rather than by whoever happens to live nearby.

Scenarios that assert on logic rather than UI (the `MessageBlockPolicy` checks)
are marked *"logic check — nothing to watch"*. There is nothing to drive, so
their ▶ **runs them in place in the dashboard** — no PiP, no leaving the tab —
and reports the result on the tile (and a brief snackbar). Only scenarios that
actually drive the app (▶ / 🐞) open the PiP. A widget scenario that has no live
definition is marked *"widget test — runs under `flutter test` only"* and fails
with an explanatory step if run here, rather than being evaluated against the
wrong widget tree. A scenario that needs a session it
can't get (no one signed in and no test credentials) fails gracefully with an
explanatory step rather than hanging.

## Test index

| Scenarios | Area | Defined in | Registered by |
|-----------|------|-----------|---------------|
| 2 widget + 6 logic | Messaging / blocking | [`blocking_scenarios.dart`](../../lib/qa/scenarios/blocking_scenarios.dart) | [`test/blocking_messages_patrol_test.dart`](../../test/blocking_messages_patrol_test.dart) |
| 2 widget | Map / preview | [`marker_preview_scenarios.dart`](../../lib/qa/scenarios/marker_preview_scenarios.dart) | [`test/marker_opens_preview_patrol_test.dart`](../../test/marker_opens_preview_patrol_test.dart) |
| 6 live (logic headless) | Map / live search, relationship filters, label tap, camera zoom, IP placement | [`live_map_scenarios.dart`](../../lib/qa/scenarios/live_map_scenarios.dart) | [`test/live_map_patrol_test.dart`](../../test/live_map_patrol_test.dart) |
| 21 logic | Map / marker labels, search + relationship filtering, POI/label invariants | [`marker_visibility_scenarios.dart`](../../lib/qa/scenarios/marker_visibility_scenarios.dart) | [`test/marker_visibility_scenarios_patrol_test.dart`](../../test/marker_visibility_scenarios_patrol_test.dart) |
| 1 widget | Logged-out preview → login | [`preview_login_scenarios.dart`](../../lib/qa/scenarios/preview_login_scenarios.dart) | [`test/widgets/preview_logged_out_login_test.dart`](../../test/widgets/preview_logged_out_login_test.dart) |
| 7 widget + live | Messaging / message editing | [`message_edit_scenarios.dart`](../../lib/qa/scenarios/message_edit_scenarios.dart) | [`test/message_edit_patrol_test.dart`](../../test/message_edit_patrol_test.dart) |
| 7 widget + live + 3 logic | Sign-up wizard / profile, interest, progress, submission | [`signup_wizard_scenarios.dart`](../../lib/qa/scenarios/signup_wizard_scenarios.dart) | [`test/signup_wizard_patrol_test.dart`](../../test/signup_wizard_patrol_test.dart) |

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

Both branches now open the **same** Preview dialog; what differs is the action
row, because `onMoveMarker` is passed only for your own marker (and `Preview`
drops the social actions when `uid == alternateUid`). "All interests" is the
Preview's wording for the list-every-interest action and appears in both.

| Scenario | What it verifies |
|----------|------------------|
| `tapping another user's marker opens their Preview with Chat` | Their Preview opens showing their name, **Chat** and **All interests** — no **Move marker**. |
| `tapping your own marker opens your Preview with Move marker` | Your own Preview opens showing **Move marker** and **All interests** — no **Chat**. |

## `live_map_scenarios.dart`

The map's marker pipeline **driven through the real running app**. Every other
marker test asserts at the [`MarkerVisibility`](../../lib/main/marker_visibility.dart)
layer, where the inputs are hand-built sets; these close the loop — they seed a
real user, let the real app load it, then drive the real search field, the real
relationship filters and the real `_onCameraMove`, and assert on the marker ids
the app actually handed the map (`QaAppHarness.visibleMarkerIds()`).

Each scenario also carries a **headless `body`** that pins the same rule at the
pure-logic layer, so `flutter test` — the source of truth — still gates on it
with no app, no Firebase and no network. In the dashboard they run as live
scenarios (▶ drives the app, PiP and all).

Marker sets are compared **as people, not as raw ids**, wherever the comparison
spans a filter change: narrowing the map also re-decides which survivors are
isolated enough to be labelled, so `uid` legitimately becomes `uid_label` on the
way. Comparisons within one filter state (search → clear, filter on → off) are
exact id comparisons.

### Suite — `Chat bubble (editing)`

Mounts the production [`ChatBubble`](../../lib/widgets/ChatBubble.dart) the way
[`ChatScreen`](../../lib/widgets/ChatScreen.dart) renders one message. Whether a
bubble is *given* an `onEdit` callback is decided by
[`MessageEditPolicy`](../../lib/utility/MessageEditPolicy.dart) — covered in
[`unit-tests.md`](./unit-tests.md); these scenarios pin what the user sees.

Each also carries a **live** definition: it seeds a `qa_e2e_*` 1:1 conversation
holding one message stamped with the current time (so it is inside the edit
window), opens the real chat via `openConversationWith`, and deletes exactly what
it seeded afterwards.

| Scenario | What it verifies |
|----------|------------------|
| `your own editable message offers the pencil` | A sender-side bubble inside the edit window renders the edit button — the only entry point to editing. Live: the pencil appears on a real message the signed-in user just sent. |
| `a received message never offers the pencil` | A bubble with `isSender: false` renders **no** edit button even when an `onEdit` callback is passed, so a wiring mistake in `ChatScreen` still cannot surface an edit affordance on someone else's message. Live: seeds the message as the *other* user. |
| `an edited message is marked "(edited)" for everyone` | An edited message carries the `(edited)` marker on the **receiving** side too, so text cannot be changed silently after it has been read. Live: performs a real edit end to end, then asserts the new text is shown, the old text is gone, and the marker appeared — the proof `edited_at` is written and read back. |
| `an unedited message shows no marker` | The negative half of the marker contract. Asserts the message **is** on screen before asserting the marker is not, so an empty screen cannot satisfy it by default. |

### Suite — `Edit message dialog`

Drives the production [`EditMessageDialog`](../../lib/widgets/EditMessageDialog.dart).
Headless, a host records what the dialog resolves to (the value
`FirebaseMessagesUtility.editMessage` writes verbatim); live, the dialog is
opened from the pencil on a real seeded message and the assertion is made
against the conversation itself.

| Scenario | What it verifies |
|----------|------------------|
| `saves a real change and returns the trimmed text` | Replacing the text with a padded new message and pressing **Save** yields the **trimmed** text, so the stored message matches what the dialog previewed. Live, the assertion is an exact-text match on the conversation, which an untrimmed write would not satisfy. |
| `cancelling leaves the message alone` | Changing the text then pressing **Cancel** writes nothing — Cancel is a true escape hatch. Live: the original message still stands, without the typed text and without an `(edited)` marker. |
| `Save does nothing until the message actually changes` | Save is inert for an untouched message, for one that differs only in spacing, and for an emptied field (deleting is not what this feature offers); the dialog stays open in each case, and a genuine change saves and closes. |

### Suite — `Live map — search`

| Scenario | What it verifies |
|----------|------------------|
| `searching narrows the visible marker set on the real map` | Typing the fixture's name into the **real** search field leaves strictly fewer people on the map, all of whom were already on it, including the person searched for. This is the only coverage that the real autocomplete → Firestore search → `_onCameraMove` chain actually reaches `buildVisibleMarkers`. |
| `clearing the search restores the full marker set` | Emptying the field restores **exactly** the previous marker ids — the state users hit constantly. Guards the separate "search cleared" branch of the production `optionsBuilder`, where a stale result list surviving the clear would leave the map permanently narrowed behind an empty search box. |

### Suite — `Live map — relationship filters`

| Scenario | What it verifies |
|----------|------------------|
| `toggling the Friends filter updates the markers live and flips back` | Flipping **Friends** on narrows the map to the allow-set (the seeded non-friend disappears); flipping it off restores exactly the previous set. The logic suites pin the tri-state `null` / populated / empty contract; this pins that the real chip handler (`_onMarkerFilterChanged`) moves between those states and back. Signs in first — the filter is meaningless signed out. |

### Suite — `Live map — marker tap`

| Scenario | What it verifies |
|----------|------------------|
| `a label-rendered marker opens the Preview for the user behind it` | At a zoom where the fixture is drawn as its name label, handing the app the **`<uid>_label` id** — the id it actually put on the map — opens that user's real `Preview` with their name on it. |

Above `minLabelZoom` the label is the marker on top, so at any useful zoom the
label is what a user taps. Pass the raw `<uid>_label` through as a uid and the
Preview queries a user that does not exist: a blank dialog for the marker people
tap the most. The existing `marker_preview_scenarios.dart` pair only covers the
bare-uid path, so nothing else pinned `uidFromLabelMarkerId` being applied at the
tap.

### Suite — `Live map — camera and zoom`

| Scenario | What it verifies |
|----------|------------------|
| `the restored camera zoom produces the same markers as zooming to it by hand` | The zoom [`MapCameraMemory`](../../lib/main/map_camera_memory.dart) restores builds the same marker set as pinching to it: apply it, detour to the world view, come back, compare. Also that the restored zoom survives a `MapCameraSnapshot.create` round-trip unchanged — i.e. it is already inside the clamp range it is about to be re-persisted into. |
| `an IP-estimated placement lands at a zoom where its own marker is labelled` | The zoom [`MapZoom.forRadius`](../../lib/main/map_zoom.dart) picks for an IP estimate leaves the estimated marker **named**: both `<uid>` and `<uid>_label` reach the map, and the zoom is at or above `minLabelZoom`. |

These two are the crossovers nothing else covers. `map_camera_memory.dart`
decides *where* the map opens and `marker_visibility.dart` decides *what is on
it*; the only thing tying them together is the zoom handed across, so a
restoration that produced a zoom the marker pipeline treats differently would
reopen the app to a map that looks nothing like the one the user left.
`MapZoom.forRadius` likewise knows nothing about `MarkerVisibility`: it is
derived from the uncertainty radius alone and could legitimately return a zoom
below the label gate — leaving someone who declined location sharing looking at
an anonymous dot they are supposed to recognise as themselves and drag.

## `marker_visibility_scenarios.dart`

Logic-only coverage of which markers reach the map and which of them are
labelled, asserting on
[`MarkerVisibility`](../../lib/main/marker_visibility.dart) — the pure marker
selection extracted out of `_onCameraMove`. There is nothing on screen to watch;
the scenarios still run and report in the dashboard like any other.

### Suite — `Marker label zoom boundary`

`MarkerVisibility.minLabelZoom` (2.0) is a hard gate: below it the builder emits
no label markers at all, whatever the proximity maths says.

| Scenario | What it verifies |
|----------|------------------|
| `below the boundary (zoom 1.9) shows only POI dots — layered` | A hair under the gate, the default layered mode renders POI dots and no labels. |
| `below the boundary (zoom 1.9) shows only POI dots — original` | Same rule in the mutually-exclusive mode. |
| `at the boundary (zoom 2.0) labels become eligible — layered` | The gate is inclusive: isolated markers gain their labels at exactly 2.0. |
| `at the boundary (zoom 2.0) labels become eligible — original` | Inclusive in the mutually-exclusive mode too, where the dot flips to a label. |

### Suite — `Marker label zoom round-trips`

The **"swap to labels and back" regression guard**. The map rebuilds its entire
marker set on every camera move (`_onCameraMove` → `buildVisibleMarkers` →
`setState`), so zooming in to swap crowded POI dots for name labels and zooming
back out must land on *exactly* the marker set it started with.

Each scenario walks the builder through a zoom sweep and compares the final
`MarkerId`s against the initial ones. The fixture is a crowded pair 110 m apart
plus one isolated marker, chosen so every waypoint really differs:

| | zoom 1 | zoom 10 | zoom 18 |
|---|---|---|---|
| layered | `a`, `b`, `c` | `a`, `b`, `c`, `c_label` | `a`, `b`, `c` + all three labels |
| original | `a`, `b`, `c` | `a`, `b`, `c_label` | all three as labels |

Each scenario also asserts the **midpoint differs** from the start, so it can
never pass vacuously — a builder that returned the same thing at every zoom
fails here instead of sailing through.

| Scenario | What it verifies |
|----------|------------------|
| `zoom 10 -> 18 -> 10 restores the original marker ids — layered` | Zooming past the proximity threshold (5479 m at zoom 10 → 21 m at zoom 18) so the crowded pair gains labels, then back out, restores the zoom-10 set. |
| `zoom 10 -> 18 -> 10 restores the original marker ids — original` | The same sweep where markers change identity between `uid` and `uid_label` rather than layering. |
| `zoom 10 -> 1 -> 10 restores the original marker ids — layered` | Crossing `minLabelZoom` **downwards and back up** returns every dropped label, with no orphaned or duplicated markers. |
| `zoom 10 -> 1 -> 10 restores the original marker ids — original` | The boundary crossing where every label becomes a POI dot below 2.0 and must turn back on the way up. |

The two sweeps guard different branches: `10 → 18 → 10` exercises the proximity
threshold, `10 → 1 → 10` exercises the zoom gate. A bug that dropped labels
permanently after zooming out past the gate would leave the map label-less for
the rest of the session and would be invisible to the proximity-only sweep.

`MarkerVisibility` is pure today, so these round trips hold by construction —
which is the point. The moment anyone adds caching, memoisation or accumulated
state to the marker pipeline, a stale label or an orphaned dot would survive the
trip back and these fail. The same sweeps run at unit granularity in
[`marker_visibility_unit_tests.dart`](../../lib/qa/unit/marker_visibility_unit_tests.dart);
see [`unit-tests.md`](./unit-tests.md).

### Suite — `Marker search filtering`

The search branch of `buildVisibleMarkers`, which the zoom suites never reach. An
active search term narrows the map to `searchFilteredResults`, **suppresses the
relationship filter**, and narrows the input to the label proximity computation
so labels are recomputed against what is actually on screen. Every scenario runs
in both marker behaviours.

| Scenario | What it verifies |
|----------|------------------|
| `search hides every non-matching marker` | With `searchFilteredResults: ['a']`, only **a** is on the map; `b` and `c` and their labels are gone. |
| `search suppresses the relationship filter` | A relationship filter of `{'b'}` does not intersect with the search — **a** still shows and **b** does not. Search wins outright, deliberately. |
| `an empty search term ignores a stale result list` | Clearing the search box restores every marker even while the previous result list is still in state. |
| `a search that matches nobody yields an empty marker set` | A non-empty term with zero results empties the map instead of falling back to showing everyone. |
| `labels are recomputed against the filtered set` | Filtering away a crowded neighbour lets the survivor gain its name label, because label spacing is computed over the visible markers only. |

The last two guard the same trap from opposite sides: `markersToShowAsLabels`
treats an empty `filteredUids` as "no filter, use every marker", and that reading
must never leak into the visibility check — a search matching nobody would then
show *everybody*.

### Suite — `Marker relationship filtering`

The relationship branch, reached whenever the search box is empty. The filter is
**tri-state**, not a boolean — `_relationshipFilterUids()`
([`home_map_logic.dart:101`](../../lib/main/home_map_logic.dart)) returns `null`
when no friends/followers/following toggle is on, and otherwise a set that may
well be empty. Each scenario runs in both marker behaviours.

| Scenario | What it verifies |
|----------|------------------|
| `the relationship filter shows only the allowed uids` | `relationshipUids: {'a', 'c'}` leaves **a** and **c** on the map and drops **b**, dot and label alike. |
| `a null relationship filter shows everyone` | `null` — no toggle on — means no filtering at all: a, b and c all show. This is the map's default state. |
| `an empty relationship set hides every marker` | A toggle that resolves to zero uids empties the map. Distinct from `null`: it must **not** collapse back onto "show everyone". |

The `null` and empty cases are the pair worth holding apart. Merging them — as a
"simplify the nullable away" refactor naturally would — either blanks the default
map or inverts a filter that matches nobody into one that shows everybody, and
both failures look plausible on screen.

### Suite — `Marker POI/label invariants`

The structural rules the marker set has to satisfy at **every** zoom, rather than
which markers appear at a chosen one. Each scenario walks a full **1.0 → 21.0
sweep in half-zoom steps** (41 builds), so a rule cannot hold at the zooms the
other suites sample and break in between. These are the properties the two marker
behaviours are *defined* by, and none of them was asserted anywhere before.

| Scenario | What it verifies |
|----------|------------------|
| `layered mode always keeps a POI dot under every label` | For every `x_label` in the result, `x` is in it too — at all 41 zooms. This is what "layered" means, and it is the defining difference from the original mode. |
| `original mode never emits both forms of the same uid` | `x` and `x_label` are mutually exclusive at all 41 zooms — the label branch and the POI branch are guarded by complementary predicates over `showAsLabels`. |
| `no label is emitted without a POI marker behind it` | A stale `ghost_label` with no POI marker never reaches the map — across both modes, all 41 zooms, and four filter configurations including **search + relationship combined** (328 marker sets). |
| `the 1000 km isolation rule labels below the zoom gate` | `markersToShowAsLabels` labels a 1056 km-isolated pair at zoom **1.5**, below `minLabelZoom`; a 890 km pair at the same zoom labels nothing. |
| `buildVisibleMarkers still withholds those labels below zoom 2.0` | End to end the gate wins: the same 1056 km pair renders as two bare dots at zoom 1.5 in both modes, even though `showAsLabels` picked both. |

The first two are exact mirror images, and running both is the point: layered mode
must emit `x` *and* `x_label`, original mode must emit exactly one of them. Each is
also guarded against passing vacuously — the sweep must actually produce a label
(and, in original mode, a bare dot) somewhere along the way.

The `ghost_label` case is worth its filter matrix because orphan suppression is
**implicit**: the label branch is filtered by `visible(uid)`, which knows about
the search and relationship sets and nothing about which uids have POI markers.
Labels stay tied to dots only because `showAsLabels` is computed from
`poiMarkers`. An orphan label is a name floating over empty map with no tap
target — and under a relationship filter, a name the user explicitly filtered
away.

#### The two halves of the 1000 km rule

`alwaysLabelDistance` (`marker_visibility.dart:120`) is the only selection rule
with no zoom term at all:

```dart
if (minDistanceToAnyMarker > alwaysLabelDistance) {
  showAsLabels.add(markerPositions[i].key);
} else if (currentZoom >= minLabelZoom && minDistanceToAnyMarker >= proximityThreshold) {
```

so it reads as "always label, whatever the zoom" — and at the
`markersToShowAsLabels` layer it is. **End to end it is not.** `buildVisibleMarkers`
gates both of its branches on `zoom >= minLabelZoom`, so below zoom 2.0 the
isolation rule's result is computed and then discarded. The two scenarios pin one
layer each, which is what makes the interaction visible instead of something the
next person rediscovers.

The fixture is 9.5° of latitude (**1056 km**) rather than something larger on
purpose: `markersToShowAsLabels` skips any pair more than 10° apart before
measuring, leaving `minDistanceToAnyMarker` at `infinity`, which satisfies the
1000 km test trivially. Staying inside the window makes the branch fire on a real
measured distance. The 890 km control — over the sub-zoom-3 proximity threshold of
701 km, under the isolation rule — is what stops a build that ignored zoom
entirely from passing.

If the product intent is that a genuinely isolated marker *should* be named at
world zoom, the second scenario is the one that will fail when that is fixed, and
it should be updated rather than deleted.

### Suite — `Marker move mode`

The `soloUid` branch. Tapping your own marker opens **your** preview, whose
`Move marker` button puts the map into move mode: `_enterMarkerMoveMode`
([`home_ui_logic.dart`](../../lib/main/home_ui_logic.dart)) makes your POI
draggable and `_onCameraMove` then passes `soloUid: _uid`, which short-circuits
`buildVisibleMarkers` to your dot alone. Everything else — other users' dots,
every name label including your own, the search term, the relationship filters —
is suppressed, so the only things on screen are the dot you are dragging and the
`Done` button that leaves the mode. Each scenario runs in both marker
behaviours.

| Scenario | What it verifies |
|----------|------------------|
| `move mode shows the moving user's POI dot and nothing else` | `soloUid: 'b'` at a zoom where all three markers would normally be labelled yields exactly `{b}` — no other uid, and not even `b_label`. |
| `move mode overrides the search term and the relationship filters` | A search term and an allow-set that between them exclude `b` still yield `{b}`: you can always see the marker you are moving. |
| `leaving move mode restores the full marker set` | `soloUid: null` before and after produce the same ids, while the build in between differs — so the round trip cannot pass vacuously. |

The suppression of your **own label** is deliberate, not an oversight: the label
marker is not draggable and sits directly over the POI dot, so leaving it up
would swallow the drag gesture on web. The override scenario guards the opposite
mistake — a refactor that ran move mode through the normal filter chain instead
of ahead of it would let a stale search term hide the very marker the user is
trying to reposition, leaving an empty map with a `Done` button on it.

## `preview_login_scenarios.dart`

| Scenario | What it verifies |
|----------|------------------|
| `selecting an interest routes an unauthenticated visitor to the login/sign-up page` | A logged-out visitor tapping a link-free interest is routed to slot 1 (login/sign-up) and the preview is dismissed. |

---

## `signup_wizard_scenarios.dart`

Covers the **multi-part sign-up wizard** ([`lib/login/signup/`](../../lib/login/signup)) —
the three screens a new user walks through after entering an email and password:
name and age, a first interest, and where their marker goes.

The ordering is what these scenarios are really protecting. The wizard runs
**before** the Firebase Auth account is created, so a gate that fails open here
produces a real account that should never have existed; and the whole point of
collecting an interest and a location up front is that the user reaches the map
with a populated list and a placed marker, with nothing deferred to a later
screen. The rules themselves are asserted in
[`unit-tests.md`](./unit-tests.md#suite--signup-wizard-validation); these
scenarios prove the screens honour them.

The location part is not mounted here: its map is a `GoogleMap` platform view,
which a widget test cannot render or interact with. Its placement logic is
covered at the unit level instead (`SignupLocationDraft`, and the declined-location
`IpLocationLookup`/`MapZoom` tests it reuses).

### Live runs

Every screen scenario also carries live hooks, so the dashboard walks the real
wizard rather than reporting "cannot run in the app". `liveSetUp` calls
[`QaAppHarness.openSignupWizard`](../../lib/qa/e2e/qa_app_harness.dart), which
pushes the production `SignupWizard` directly — the wizard normally opens from
`FlutterLogin`'s sign-up submit, and driving that third-party form live would be
asserting on someone else's widget internals.

**Account creation is disabled for the live wizard**: the `onSubmit` the harness
passes always refuses, so a dashboard run against prod can walk all three parts,
and even press "Create my account", without ever creating an account. That is
also why the live assertions are phrased as *did the flow advance* — there is no
captured draft to inspect, so "still on Step 1 of 3" is how a rejected part is
verified, exactly as the user would see it. The write itself is covered by the
`Signup submission` scenarios below. `liveTearDown` calls `resetToBaseline`,
which pops the pushed wizard so the next scenario starts from the map.

### Suite — `Signup wizard (about you)`

Mounts the production [`SignupStepProfile`](../../lib/login/signup/signup_step_profile.dart)
and records the draft it hands forward.

| Scenario | What it verifies |
|----------|------------------|
| `refuses an underage sign-up before any account is created` | A birthday 12 years ago raises the **Age Restriction** dialog and the step hands nothing forward — so the flow cannot reach account creation. The date is computed relative to today, so the scenario never expires. |
| `requires a first and last name` | Continuing with both name fields empty shows both field errors and does not advance. |
| `carries a valid profile forward and shows the age it read` | A complete, old-enough profile advances with its name intact, and the field's helper text reports the age the app calculated — the user's only way to confirm they typed the date they meant. |

### Suite — `Signup wizard (your interest)`

Mounts the production [`SignupStepInterest`](../../lib/login/signup/signup_step_interest.dart).

| Scenario | What it verifies |
|----------|------------------|
| `shows the inspiration prompt` | The exact prompt the part is built around ("What has inspired you lately…") is on screen. |
| `requires the interest to be named` | A description with no name shows the field error and does not advance — a nameless interest would be an unlabelled card in the user's list. |
| `carries the name and description forward` | Both fields reach the next part, so the account is created with the interest the user actually typed. |

### Suite — `Signup wizard (progress)`

Mounts the production [`SignupProgressHeader`](../../lib/login/signup/signup_progress_header.dart).

| Scenario | What it verifies |
|----------|------------------|
| `names the current part and how many are left` | On part two the header reads **Step 2 of 3** and every part is labelled, so the header can never disagree with the number of screens the flow actually has. |

### Suite — `Signup submission`

Logic-only (no `build`): drives
[`SignupSubmission`](../../lib/login/signup/signup_submission.dart) directly
against a `FakeFirebaseFirestore` and a recording `FirebaseUsersUtility`.
`addInterestForUser` and the activity-feed write behind it resolve
`FirebaseFirestore.instance` internally and cannot be pointed at a fake, so the
interest write is verified by recording what the submission *asks* the utility to
write, while the profile document is written for real into the in-memory
Firestore.

| Scenario | What it verifies |
|----------|------------------|
| `writes a complete profile with the marker already placed` | The profile document carries the name from part one, the marker sits at the coordinates part three chose, and `first_run_experience` is already `true` — so the in-app location onboarding screen does not run again for an account that just placed its marker. |
| `seeds the interest from part two` | Exactly one interest is written, with the name and description the user typed, and it is the same interest handed back to the caller. |
| `a retry does not create a second profile document` | Replaying the submission — what the wizard's "try again" does after a non-fatal failure — reuses the existing profile instead of duplicating it. `addUserToFirestore` uses `add()`, so this guard lives in `SignupSubmission`. |

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

> **A scenario with a `build` needs live hooks to appear in the app.** `build` is
> mounted only by the `flutter test` bridge; the dashboard has no tree to mount
> it into. Running such a scenario there fails with an explanatory step rather
> than evaluating its `body` — which would assert against the *real app's* tree
> and let any absence-only check pass vacuously. Add `liveBody` (below) to give
> it a live definition, or expect it to be **`flutter test`-only**.

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
(`signInTestUser`, `openPreviewFor`, `openConversationWith`, `goHome`,
`openSignupWizard`, and the
map surface: `visibleMarkerIds`, `applyMapZoom`, `reloadMarkers`, `enterSearch`,
`clearSearch`, `setRelationshipFilters`, `openPreviewForMarkerId`,
`rememberedCameraZoom`, …) each delegate to a real app code path. `QaSeeder` also
offers `seedMessage`, which drops one message into a seeded conversation (stamped
now by default, so it lands inside `MessageEditPolicy.editWindow`).

A **logic-only** scenario — no `build`, no `liveBody` — still appears in the
dashboard and runs its `body` in place. A scenario that has a `build` but no
`liveBody` is `flutter test`-only and is reported as such (see the note above).

`phase` maps onto the existing [`phase()`](../../test/support/test_phase.dart)
helper under `flutter test`, so `tool/test_report.dart` still prints the phase
breakdown for failures, and onto a bold heading in the dashboard's step log.

### What a run logs

Both runners keep a step trail, so a scenario that breaks says *which step* broke
without anyone re-reading the scenario source.

**Headless (`flutter test`).** Every `QaDriver` call the bridge makes prints one
line before it runs — `STEP › tap text "Login"` — and prints `STEP ✗ …` if it
throws. `tool/test_report.dart` (and therefore `./scripts/run_tests.sh`) replays
those lines under a failing test, marking phases with `▸`, steps with `·` and the
step that failed with `❌`, followed by the usual error and stack:

```
Test blocking a blocked user cannot send a message failed ❌
    ▸ PHASE › open the conversation
    · STEP › tap text "Messages"
    · STEP › expect a TextField widget to be visible
    ❌ STEP ✗ expect a TextField widget to be visible
      ══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══════════════════
      Expected: at least one matching candidate
        Actual: _TextWidgetFinder:<Found 0 widgets ...>
```

Passing tests print nothing — the reporter only surfaces captured output for
failures — so a green run stays as quiet as it was before.

**Live (dashboard).** Each step is already painted in the PiP overlay; it is now
also `debugPrint`ed with the shared `[QA]` prefix (as `QaSeeder` does), so the
browser console holds a copy of the run — including `[QA] FAILED: <step> — <why>`
— after the overlay is gone.

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

## Related: unit tests and the Unit tests tab

The pure-logic unit tests (date/time formatting, map marker visibility) have
their own catalogue and their own dashboard tab, built on the same
"one definition, two runners" design as the Patrol scenarios — see
[`unit-tests.md`](./unit-tests.md). The **Unit tests** tab sits beside this one
in the admin dashboard; it runs the runnable tests **in-app** and shows their
console output inline (no PiP, since there is nothing on screen to drive), and
lists the `testWidgets`-based QA tooling tests read-only for completeness.
