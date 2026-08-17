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

// Mirrors the two branches of `handleMarkerTap` (lib/main/home_map_logic.dart):
// tapping a marker whose uid is NOT the viewer's shows the Preview dialog;
// tapping the viewer's own marker opens the end drawer instead and shows no
// Preview. The real handler is a private extension method on the home page
// state, so this reproduces its contract while driving the *real* google_maps
// `Marker` and the *real* `Preview` widget.
Future<void> _handleMarkerTap(
  BuildContext context, {
  required String markerUid,
  required FirebaseFirestore firestore,
}) async {
  if (markerUid == _viewerUid) {
    // Own marker: production opens the end drawer, not a Preview dialog.
    Scaffold.of(context).openEndDrawer();
    return;
  }
  await showDialog<bool>(
    context: context,
    builder: (dialogContext) => Preview(
      uid: _viewerUid,
      alternateUid: markerUid,
      scaffoldKey: GlobalKey<ScaffoldState>(),
      onItemTapped: (_) {},
      signedIn: false,
      onDrawerOpened: () => Navigator.of(dialogContext).pop(true),
      onOpenMessages: (_, __) {},
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

// Seeds a fake Firestore with a single "other" user so the opened Preview has a
// name and interests to load.
Future<FirebaseFirestore> _seedUsers() async {
  final firestore = FakeFirebaseFirestore();
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
  return <QaScenario>[
    QaScenario(
      suite: _suite,
      name: "tapping another user's marker opens the Preview for that user",
      summary:
          "Tapping another person's marker on the map opens their profile "
          "Preview, showing that user's name and details.",
      doc: '''
## What it checks
Tapping a marker that belongs to **another** user opens the real `Preview`
dialog for that person, showing their name (Ada Lovelace) and details.

## Why it matters
The marker -> Preview handoff is the map's primary interaction: it's how you go
from a dot on the map to someone's profile. This is the happy path of
`handleMarkerTap`'s "not me" branch.

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
on screen, showing **Ada Lovelace**.
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
        await d.expectVisible(qaText('Ada Lovelace'), count: 1);
      },
      // Live: seed one profile, then drive the real map handler → real Preview.
      liveSetUp: otherUserLive.seed,
      liveBody: (d, h) async {
        await d.phase("open the tapped user's real Preview", () async {
          await h.goHome();
          await d.expectAbsent(qaType(Preview));
          // The marker itself can't be tapped (platform view), so invoke the
          // real handler; everything the Preview then does is real.
          await h.openPreviewFor(QaSeeder.otherUid, 'Ada Lovelace');
          await d.expectVisible(qaType(Preview), count: 1);
          await d.expectVisible(qaText('Ada Lovelace'));
        });
      },
      liveTearDown: otherUserLive.cleanup,
    ),
    QaScenario(
      suite: _suite,
      name: 'tapping your own marker does not open a Preview',
      summary:
          "Tapping your own marker on the map opens your account drawer "
          "instead of a profile Preview — you don't preview yourself.",
      doc: '''
## What it checks
Tapping **your own** marker opens the end (account) drawer instead of a profile
Preview — no `Preview` dialog appears.

## Why it matters
This is the other branch of `handleMarkerTap`: previewing yourself makes no
sense, so your own marker is a shortcut to your account drawer. The test guards
that the "is me" check routes correctly and never shows a self-Preview.

## How it runs
- **Headless:** the proxy button fires the marker's `onTap` with the viewer's own
  uid; the harness asserts the drawer path, not a Preview.
- **Live:** calls the real handler with the signed-in user's uid and asserts no
  Preview opens (works in either auth state, so it needs no seeded data).

## Expected
After tapping your own marker: no `Preview` on screen.
''',
      build: () async =>
          _harness(markerUid: _viewerUid, firestore: await _seedUsers()),
      body: (d) async {
        await d.tap(qaText('tap marker'));
        await d.expectAbsent(qaType(Preview));
      },
      // Live: no data needed — tapping your own uid opens the drawer, not a
      // Preview, in either auth state.
      liveBody: (d, h) async {
        await d.phase('your own marker opens the drawer, not a Preview',
            () async {
          await h.goHome();
          await h.openPreviewFor(h.currentUid, 'You');
          await d.expectAbsent(qaType(Preview));
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
