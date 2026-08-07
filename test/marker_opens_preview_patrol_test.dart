import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:intrst/widgets/Preview.dart';

const _viewerUid = 'viewer-uid';
const _otherUid = 'other-user-uid';

// Mirrors the two branches of `handleMarkerTap` (lib/main/home_map_logic.dart):
// tapping a marker whose uid is NOT the viewer's shows the Preview dialog;
// tapping the viewer's own marker opens the end drawer instead and shows no
// Preview. The real handler is a private extension method on the home page
// state, so the test reproduces its contract while driving the *real*
// google_maps `Marker` and the *real* `Preview` widget.
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
// button invokes the marker's own `onTap` callback — the test exercises the
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
  await firestore.collection('users').add({
    'user_uid': _otherUid,
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'interests': <dynamic>[],
  });
  return firestore;
}

void main() {
  group('Marker tap opens the Preview', () {
    // Scenario: the user taps another person's map marker. The marker's onTap
    // must open the Preview widget for that person.
    patrolWidgetTest(
      "tapping another user's marker opens the Preview for that user",
      ($) async {
        final firestore = await _seedUsers();

        await $.pumpWidgetAndSettle(
          _harness(markerUid: _otherUid, firestore: firestore),
        );

        // Nothing is shown until the marker is tapped.
        expect(find.byType(Preview), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);

        await $('tap marker').tap();
        await $.pumpAndSettle();

        // The real Preview widget is now on screen, showing the tapped user.
        expect(find.byType(Preview), findsOneWidget);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Ada Lovelace'), findsOneWidget);
      },
    );

    // Scenario: the user taps their OWN marker. Production opens the end drawer
    // (their profile), so no Preview dialog should appear.
    patrolWidgetTest(
      'tapping your own marker does not open a Preview',
      ($) async {
        final firestore = await _seedUsers();

        await $.pumpWidgetAndSettle(
          _harness(markerUid: _viewerUid, firestore: firestore),
        );

        await $('tap marker').tap();
        await $.pumpAndSettle();

        expect(find.byType(Preview), findsNothing);
      },
    );
  });
}
