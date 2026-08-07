# Patrol Testing Overview

This document is the high-level index of the [Patrol](https://patrol.leancode.co/)
tests in this repository. It describes what each test covers, where to find it,
and how to run it.

## What "Patrol" means here

This project depends on **`patrol_finders`** (see [`pubspec.yaml`](../../pubspec.yaml)),
not the full `patrol` integration-test runner. In practice that means:

- Tests are written with `patrolWidgetTest(...)` and drive widgets through the
  `PatrolTester` (`$`) API — the same ergonomic finder/interaction layer Patrol
  provides — but they run as **Flutter widget tests**, in-process, with no device
  or emulator required.
- They run with the standard `flutter test` command (no `patrol` CLI needed).
- Because they are widget tests, they mount real production widgets in a test
  `MaterialApp` harness and assert on what the user would see.

## How to run the Patrol tests

Run the entire test suite:

```bash
flutter test
```

Run a single Patrol test file:

```bash
flutter test test/blocking_messages_patrol_test.dart
```

## Test index

| Test file | Area | Type | Scenarios |
|-----------|------|------|-----------|
| [`test/blocking_messages_patrol_test.dart`](../../test/blocking_messages_patrol_test.dart) | Messaging / blocking | `patrolWidgetTest` + unit | 2 widget scenarios, 6 policy unit tests |
| [`test/marker_opens_preview_patrol_test.dart`](../../test/marker_opens_preview_patrol_test.dart) | Map / preview | `patrolWidgetTest` | 2 widget scenarios |

---

## `blocking_messages_patrol_test.dart`

**Location:** [`test/blocking_messages_patrol_test.dart`](../../test/blocking_messages_patrol_test.dart)

Covers the user blocking feature's messaging enforcement — both the UI the two
sides of a block see, and the underlying policy that decides when a 1:1
conversation is blocked.

### Patrol widget tests — `Blocked messaging notice`

Mounts the production [`BlockedMessageNotice`](../../lib/widgets/BlockedMessageNotice.dart)
widget (rendered by `CollapsibleChatScreen` in place of the message input) inside
a `MaterialApp` harness.

| Scenario | What it verifies |
|----------|------------------|
| `a blocked user sees "not accepting messages" and cannot send` | The **blocked** user (not the blocker) sees the neutral "This person is not accepting messages right now." copy, the blocker-facing copy does **not** leak (which would reveal they were blocked), and no `TextField` is rendered — there is no way to type or send. |
| `the blocker sees the "you blocked them, unblock to continue" message` | The **blocker** sees the actionable "You have blocked …, unblock them to continue messaging this user." copy, the blocked-user copy is not shown, and no input affordance is rendered. |

### Unit tests — `MessageBlockPolicy.isBlocked (1:1 send enforcement)`

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

---

## `marker_opens_preview_patrol_test.dart`

**Location:** [`test/marker_opens_preview_patrol_test.dart`](../../test/marker_opens_preview_patrol_test.dart)

Covers the map interaction where tapping a user's map marker opens the
[`Preview`](../../lib/widgets/Preview.dart) card for that user — the
`Marker.onTap` → `showDialog(Preview(...))` flow implemented by `handleMarkerTap`
in [`lib/main/home_map_logic.dart`](../../lib/main/home_map_logic.dart).

### Patrol widget tests — `Marker tap opens the Preview`

| Scenario | What it verifies |
|----------|------------------|
| `tapping another user's marker opens the Preview for that user` | Before tapping, no `Preview`/`AlertDialog` is shown. Invoking the marker's `onTap` opens the **real** `Preview` widget, which renders the tapped user's name (`Ada Lovelace`) loaded from Firestore. |
| `tapping your own marker does not open a Preview` | When the tapped marker's uid is the viewer's own uid, `handleMarkerTap` opens the end drawer instead, so **no** `Preview` dialog appears. |

### How it works (test design notes)

Two production realities shape this test, and it's worth understanding them
before editing it:

- **Google Maps markers are platform views** and cannot be rendered or tapped in
  an in-process widget test. The test therefore constructs a **real**
  `google_maps_flutter` `Marker` (the same data type production builds) with the
  same `onTap` wiring, and invokes that `onTap` through a proxy button. It
  exercises the marker's real tap handler, standing in only for Google Maps'
  internal tap dispatch. The private `handleMarkerTap` extension method's
  two-branch contract (other user → dialog, own marker → end drawer) is mirrored
  in the test harness.
- **`Preview` reads from Firestore in `initState`.** To mount the real widget
  without a live Firebase app, `Preview` exposes an optional `usersCollection`
  injection seam (it defaults to `FirebaseFirestore.instance.collection('users')`
  in production). The test injects a
  [`fake_cloud_firestore`](https://pub.dev/packages/fake_cloud_firestore)-backed
  collection seeded with one user, so the opened `Preview` loads a real name and
  interest list through the production `FirebaseUsersUtility` code paths.

> **Dependency:** this test uses `fake_cloud_firestore` (a `dev_dependency`).

---

## Adding a new Patrol test

1. Create the test file under `test/` with a `_patrol_test.dart` suffix
   (e.g. `test/<feature>_patrol_test.dart`).
2. Import `package:patrol_finders/patrol_finders.dart` and write scenarios with
   `patrolWidgetTest('...', ($) async { ... })`.
3. Mount the real production widget in a small `MaterialApp` harness so the test
   exercises production code, not a re-implementation.
4. Add a row to the [Test index](#test-index) above and a matching section
   describing the scenarios.

## Related, non-Patrol tests

For completeness, the suite also contains plain `flutter_test` unit tests that
are **not** Patrol tests:

- [`test/DateTimeUtility_test.dart`](../../test/DateTimeUtility_test.dart) —
  exhaustive formatting cases for `DateTimeUtility.getFormattedTime`
  (today / yesterday / tomorrow / within 7 days / beyond 7 days / cross-year /
  time-formatting edge cases).
