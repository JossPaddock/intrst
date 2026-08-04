import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intrst/widgets/Preview.dart';
import 'package:patrol_finders/patrol_finders.dart';

import '../support/test_phase.dart';

// The profile a logged-out visitor is previewing on the map.
const String _ownerUid = 'owner-123';

// A public, link-free interest map as Firestore stores it. Link-free is the
// case that matters here: an interest with a link opens that URL, while a
// link-free interest is one of the "up to 5 selectable" interests that should
// route an unauthenticated visitor to the login/sign-up page.
Map<String, dynamic> _publicInterest({
  required String id,
  required String name,
  required Timestamp ts,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'description': '',
    'link': '', // link-free -> selecting it navigates rather than opening a URL
    'favorite': false,
    'privacy': 4, // public, so it is visible to a logged-out visitor
    'created_timestamp': ts,
    'updated_timestamp': ts,
    'shared_with_uids': <String>[],
  };
}

void main() {
  patrolWidgetTest(
    'Preview (logged out): selecting an interest routes an unauthenticated '
    'visitor to the login/sign-up page',
    ($) async {
      // ---- Arrange -------------------------------------------------------
      // Seed an in-memory Firestore with a previewable profile that has two
      // public, selectable interests.
      final firestore = FakeFirebaseFirestore();
      final ts = Timestamp.now();
      await firestore.collection('users').add(<String, dynamic>{
        'user_uid': _ownerUid,
        'first_name': 'Ada',
        'last_name': 'Lovelace',
        'interests': <Map<String, dynamic>>[
          _publicInterest(id: 'interest-1', name: 'Rock Climbing', ts: ts),
          _publicInterest(id: 'interest-2', name: 'Jazz Piano', ts: ts),
        ],
      });

      // Captures the navigation index Preview requests. Index 1 is the
      // login/sign-up destination in the real app (see home_ui_logic.dart, the
      // IndexedStack whose slot 1 is LoginScreen).
      int? routedIndex;

      await $.pumpWidgetAndSettle(
        _PreviewHost(
          firestore: firestore,
          onRoute: (index) => routedIndex = index,
        ),
      );

      // ---- Act & Assert, phase by phase ---------------------------------
      await phase('a logged-out visitor opens the preview widget', () async {
        await $('Open preview').tap();
        await $.pumpAndSettle();

        // The preview lists the profile's (up to 5) selectable interests.
        expect($(Preview).exists, true);
        expect($('Rock Climbing').exists, true);
        expect($('Jazz Piano').exists, true);
      });

      await phase('the visitor selects one of the listed interests', () async {
        await $('Rock Climbing').tap();
        await $.pumpAndSettle();
      });

      await phase(
        'the visitor lands on the page asking them to log in / sign up',
        () async {
          // Routed to the login/sign-up destination...
          expect(routedIndex, 1);
          expect($(_kLoginSignupPrompt).exists, true);
          // ...and the preview dialog has been dismissed.
          expect($(Preview).exists, false);
        },
      );
    },
  );
}

const String _kLoginSignupPrompt = 'Log in or sign up to continue';

/// A minimal host that mirrors how the real app hangs together for this flow:
/// slot 0 shows the map/home surface (from which a [Preview] dialog opens), and
/// slot 1 is the login/sign-up page. Selecting an index is the same
/// `onItemTapped` contract Preview is wired to in production.
class _PreviewHost extends StatefulWidget {
  const _PreviewHost({required this.firestore, required this.onRoute});

  final FirebaseFirestore firestore;
  final ValueChanged<int> onRoute;

  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    widget.onRoute(index);
    setState(() => _selectedIndex = index);
  }

  void _openPreview(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => Preview(
        uid: '', // logged-out visitor has no uid
        alternateUid: _ownerUid,
        scaffoldKey: _scaffoldKey,
        onItemTapped: _onItemTapped,
        signedIn: false,
        onDrawerOpened: () {},
        onOpenMessages: (_, __) {},
        firestore: widget.firestore,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: <Widget>[
        Scaffold(
          key: _scaffoldKey,
          // Builder gives an inner context (below MaterialApp) so showDialog
          // can find MaterialLocalizations.
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => _openPreview(context),
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
        // Slot 1: stand-in for LoginScreen (which itself needs a live Firebase
        // app). What matters for this flow is that selecting an interest lands
        // the visitor on a page prompting them to authenticate.
        const Scaffold(
          body: Center(child: Text(_kLoginSignupPrompt)),
        ),
      ][_selectedIndex],
    );
  }
}
