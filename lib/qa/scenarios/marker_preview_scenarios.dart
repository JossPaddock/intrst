import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../widgets/Preview.dart';
import '../e2e/qa_app_harness.dart';
import '../e2e/qa_seed.dart';
import '../qa_scenario.dart';

/// Coverage for the map's marker → Preview handoff.

const String _suite = 'Marker tap opens the Preview';
const String _viewerUid = 'viewer-uid';
const String _otherUid = 'other-user-uid';
const String _viewerName = 'Grace Hopper';
const String _otherName = 'Ada Lovelace';

// Button labels inside the real Preview (lib/widgets/Preview.dart). "All
// interests" is the widget's wording for the list-every-interest action, and is
// offered on both your own and someone else's preview; the pair that *does*
// differ is Move marker (yours) vs Chat (theirs).
const String _moveMarker = 'Move marker';
const String _chat = 'Chat';
const String _allInterests = 'All interests';

// Mirrors `handleMarkerTap` (lib/main/home_map_logic.dart): every marker tap
// opens the same `Preview` dialog — your own marker included. The only
// difference is that your own marker passes `onMoveMarker`, which is what makes
// the Preview swap its social actions for "Move marker". This reproduces that
// contract while driving the *real* google_maps `Marker` and the *real*
// `Preview` widget.
Future<void> _handleMarkerTap(
  BuildContext context, {
  required String markerUid,
  required FirebaseFirestore firestore,
}) async {
  final bool isOwnMarker = markerUid == _viewerUid;
  await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Preview(
      uid: _viewerUid,
      alternateUid: markerUid,
      scaffoldKey: GlobalKey<ScaffoldState>(),
      onItemTapped: (_) {},
      // Signed in, as the production "is this me?" check requires.
      signedIn: true,
      onDrawerOpened: () => Navigator.of(dialogContext).pop(true),
      onOpenMessages: (_, __) {},
      // Exactly the production wiring: supplied only for your own marker.
      onMoveMarker: isOwnMarker ? () {} : null,
      // Inject a fake Firestore so Preview mounts without a live Firebase app
      // (see Preview.firestore).
      firestore: firestore,
    ),
  );
}

// Builds a real google_maps `Marker` wired exactly like the production markers
// in `addMarker`/`loadMarkers`: its `onTap` is what triggers the Preview.
// Because a GoogleMap platform view cannot render in a widget test, a proxy
// button invokes the marker's own `onTap` callback — this exercises the
// marker's real tap handler, only standing in for Google Maps' internal tap
// dispatch.
Widget _harness({
  required String markerUid,
  required FirebaseFirestore firestore,
}) {
  return MaterialApp(
    home: Scaffold(
      endDrawer: const Drawer(child: SizedBox.shrink()),
      body: Builder(
        builder: (context) {
          final marker = Marker(
            markerId: MarkerId(markerUid),
            position: const LatLng(0, 0),
            onTap: () => _handleMarkerTap(
              context,
              markerUid: markerUid,
              firestore: firestore,
            ),
          );
          return Center(
            child: ElevatedButton(
              onPressed: () => marker.onTap?.call(),
              child: const Text('tap marker'),
            ),
          );
        },
      ),
    ),
  );
}

// Seeds a fake Firestore with both the viewer and the "other" user, so whichever
// marker is tapped the opened Preview has a name and interests to load.
Future<FirebaseFirestore> _seedUsers() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').add(<String, dynamic>{
    'user_uid': _viewerUid,
    'first_name': 'Grace',
    'last_name': 'Hopper',
    'interests': <dynamic>[],
  });
  await firestore.collection('users').add(<String, dynamic>{
    'user_uid': _otherUid,
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'interests': <dynamic>[],
  });
  return firestore;
}

List<QaScenario> markerPreviewScenarios() {
  final otherUserLive = _MarkerPreviewLive();
  final ownMarkerLive = _OwnMarkerPreviewLive();
  return <QaScenario>[
    QaScenario(
      suite: _suite,
      name: "tapping another user's marker opens their Preview with Chat",
      summary:
          "Tapping another person's marker opens their profile Preview with "
          "the Chat and All interests actions — and no Move marker.",
      doc: '''
## What it checks
Tapping a marker that belongs to **another** user opens the real `Preview`
dialog for that person, showing their name (Ada Lovelace) and the actions that
apply to someone else: **Chat** and **All interests**. **Move marker** is not
offered — you can only move your own.

## Why it matters
The marker -> Preview handoff is the map's primary interaction: it's how you go
from a dot on the map to someone's profile, and Chat is how you go from their
profile into a conversation. This is `handleMarkerTap`'s "not me" branch, where
`onMoveMarker` is null.

## How it runs
- **Headless (`flutter test`):** mounts a real `google_maps` `Marker` and the
  real `Preview` in a test harness. A `GoogleMap` platform view can't render in a
  widget test, so a proxy button invokes the marker's own `onTap` — the same
  callback Google Maps would fire.
- **Live (dashboard ▶):** seeds one profile under `qa_e2e_*`, then invokes the
  app's real `handleMarkerTap` (the platform-view marker still isn't tappable) and
  drives the real Preview on screen.

## Expected
Before tap: no `Preview`, no `AlertDialog`. After tap: `Preview` + `AlertDialog`
on screen, showing **Ada Lovelace**, **Chat** and **All interests**, with no
**Move marker**.
''',
      build: () async =>
          _harness(markerUid: _otherUid, firestore: await _seedUsers()),
      body: (d) async {
        // Nothing is shown until the marker is tapped.
        await d.expectAbsent(qaType(Preview));
        await d.expectAbsent(qaType(AlertDialog));

        await d.tap(qaText('tap marker'));

        // The real Preview widget is now on screen, showing the tapped user.
        await d.expectVisible(qaType(Preview), count: 1);
        await d.expectVisible(qaType(AlertDialog), count: 1);
        await d.expectVisible(qaText(_otherName), count: 1);

        // Someone else's preview: chat with them, browse their interests, but
        // no marker to move.
        await d.expectVisible(qaText(_chat), count: 1);
        await d.expectVisible(qaText(_allInterests), count: 1);
        await d.expectAbsent(qaText(_moveMarker));
      },
      // Live: seed one profile, then drive the real map handler → real Preview.
      liveSetUp: otherUserLive.seed,
      liveBody: (d, h) async {
        await d.phase("open the tapped user's real Preview", () async {
          await h.goHome();
          await d.expectAbsent(qaType(Preview));
          // The marker itself can't be tapped (platform view), so invoke the
          // real handler; everything the Preview then does is real.
          await h.openPreviewFor(QaSeeder.otherUid, _otherName);
          await d.expectVisible(qaType(Preview), count: 1);
          await d.expectVisible(qaText(_otherName));
          await d.expectVisible(qaText(_chat), count: 1);
          await d.expectVisible(qaText(_allInterests), count: 1);
          await d.expectAbsent(qaText(_moveMarker));
        });
      },
      liveTearDown: otherUserLive.cleanup,
    ),
    QaScenario(
      suite: _suite,
      name: 'tapping your own marker opens your Preview with Move marker',
      summary:
          "Tapping your own marker opens your own Preview with the Move marker "
          "and All interests actions — and no Chat with yourself.",
      doc: '''
## What it checks
Tapping **your own** marker opens the same real `Preview` dialog everyone else
gets, but with the actions that apply to yourself: **Move marker** (which
enters marker move mode on the map) and **All interests**. **Chat** is not
offered — there is nobody to message.

## Why it matters
This is the other branch of `handleMarkerTap`. Your own marker used to be a
shortcut to the account drawer; it now opens your preview, so the guard worth
testing is no longer "does a Preview appear" but **which actions it offers**:
`onMoveMarker` is passed only for your own marker, and the social actions
(Chat, Follow, Add friend, Block — all no-ops on yourself) are dropped.

## How it runs
- **Headless:** the proxy button fires the marker's `onTap` with the viewer's own
  uid, so the real `Preview` mounts with `uid == alternateUid`, `signedIn: true`
  and a non-null `onMoveMarker` — exactly what production passes.
- **Live:** signs in, then calls the real handler with the signed-in user's own
  uid and asserts on the real Preview the app puts on screen.

## Expected
After tapping your own marker: `Preview` on screen showing **Grace Hopper**
(your own name), with **Move marker** and **All interests**, and no **Chat**.
''',
      build: () async =>
          _harness(markerUid: _viewerUid, firestore: await _seedUsers()),
      body: (d) async {
        await d.expectAbsent(qaType(Preview));

        await d.tap(qaText('tap marker'));

        // Your own preview opens, just like anyone else's.
        await d.expectVisible(qaType(Preview), count: 1);
        await d.expectVisible(qaType(AlertDialog), count: 1);
        await d.expectVisible(qaText(_viewerName), count: 1);

        // ...but with the self actions in place of the social ones.
        await d.expectVisible(qaText(_moveMarker), count: 1);
        await d.expectVisible(qaText(_allInterests), count: 1);
        await d.expectAbsent(qaText(_chat));
      },
      // Live: no data to seed — your own marker previews the real signed-in
      // account. It does need a session, since the "is this me?" check is
      // `signedIn && uid == _uid`.
      liveSetUp: ownMarkerLive.setUp,
      liveBody: (d, h) async {
        await d.phase('your own marker opens your Preview', () async {
          await h.goHome();
          await d.expectAbsent(qaType(Preview));
          await h.openPreviewFor(h.currentUid, 'You');
          await d.expectVisible(qaType(Preview), count: 1);
          await d.expectVisible(qaText(_moveMarker), count: 1);
          await d.expectVisible(qaText(_allInterests), count: 1);
          await d.expectAbsent(qaText(_chat));
        });
      },
    ),
  ];
}

/// Holds the seeded profile for the live marker→Preview run so setUp and
/// teardown share one [QaSeeder].
class _MarkerPreviewLive {
  final QaSeeder _seeder = QaSeeder();

  Future<void> seed(QaAppHarness harness) async {
    await _seeder.seedUser(
      uid: QaSeeder.otherUid,
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
  }

  Future<void> cleanup(QaAppHarness harness) => _seeder.cleanup();
}

/// Live setup for the own-marker run: nothing to seed, but the preview is only
/// "yours" when somebody is signed in, so make sure somebody is.
class _OwnMarkerPreviewLive {
  Future<void> setUp(QaAppHarness harness) async {
    if (!harness.signedIn) {
      // Throws QaHarnessUnavailable (surfaced in the PiP) when no test account
      // is configured and nobody is signed in.
      await harness.signInTestUser();
    }
    if (harness.currentUid.isEmpty) {
      throw QaHarnessUnavailable(
        'No signed-in user, so there is no own marker to preview.',
      );
    }
  }
}
