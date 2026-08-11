import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../login/LoginScreen.dart';
import '../../widgets/Preview.dart';
import '../e2e/qa_app_harness.dart';
import '../e2e/qa_seed.dart';
import '../qa_scenario.dart';

/// Coverage for the logged-out visitor path: selecting someone's interest from
/// the map preview must route the visitor to log in / sign up.

const String _suite = 'Preview (logged out)';

// The profile a logged-out visitor is previewing on the map.
const String _ownerUid = 'owner-123';

const String _kLoginSignupPrompt = 'Log in or sign up to continue';

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

/// Holds the per-run state this scenario asserts on (the navigation index the
/// Preview requested). [build] resets it, so the scenario is safe to re-run
/// from the dashboard as many times as you like.
class _PreviewLoginScenario {
  int? routedIndex;

  Future<Widget> build() async {
    routedIndex = null;

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

    return _PreviewHost(
      firestore: firestore,
      onRoute: (index) => routedIndex = index,
    );
  }

  // ---- Live (real running app) -------------------------------------------
  // Shares one seeder across setUp/teardown of the live run.
  final QaSeeder _seeder = QaSeeder();

  /// Live setup: sign the current session out (a logged-out visitor is the
  /// whole point of this flow — no test credentials are required to sign out)
  /// and seed a public profile with two selectable interests.
  Future<void> liveSetUp(QaAppHarness harness) async {
    await harness.signOutTestUser();
    final ts = Timestamp.now();
    await _seeder.seedUser(
      uid: QaSeeder.otherUid,
      firstName: 'Ada',
      lastName: 'Lovelace',
      interests: <Map<String, dynamic>>[
        _publicInterest(id: 'interest-1', name: 'Rock Climbing', ts: ts),
        _publicInterest(id: 'interest-2', name: 'Jazz Piano', ts: ts),
      ],
    );
  }

  Future<void> liveTearDown(QaAppHarness harness) => _seeder.cleanup();

  /// Live body: opens the seeded profile's real Preview from the map handler,
  /// selects an interest, and asserts the visitor lands on the real
  /// [LoginScreen] and the Preview closes.
  Future<void> liveRun(QaDriver d, QaAppHarness harness) async {
    await d.phase('a logged-out visitor opens the real preview', () async {
      await harness.goHome();
      await harness.openPreviewFor(QaSeeder.otherUid, 'Ada Lovelace');
      await d.expectVisible(qaType(Preview));
      await d.expectVisible(qaText('Rock Climbing'));
      await d.expectVisible(qaText('Jazz Piano'));
    });

    await d.phase('selecting an interest routes them to log in / sign up',
        () async {
      await d.tap(qaText('Rock Climbing'));
      // The real login/sign-up screen is now shown, and the preview is gone.
      await d.expectVisible(qaType(LoginScreen));
      await d.expectAbsent(qaType(Preview));
    });
  }

  Future<void> run(QaDriver d) async {
    await d.phase('a logged-out visitor opens the preview widget', () async {
      await d.tap(qaText('Open preview'));

      // The preview lists the profile's (up to 5) selectable interests.
      await d.expectVisible(qaType(Preview));
      await d.expectVisible(qaText('Rock Climbing'));
      await d.expectVisible(qaText('Jazz Piano'));
    });

    await d.phase('the visitor selects one of the listed interests', () async {
      await d.tap(qaText('Rock Climbing'));
    });

    await d.phase(
      'the visitor lands on the page asking them to log in / sign up',
      () async {
        // Routed to the login/sign-up destination...
        await d.check(
          'Preview routed the visitor to the login/sign-up destination (index 1)',
          () => routedIndex == 1,
        );
        await d.expectVisible(qaText(_kLoginSignupPrompt));
        // ...and the preview dialog has been dismissed.
        await d.expectAbsent(qaType(Preview));
      },
    );
  }
}

List<QaScenario> previewLoginScenarios() {
  final scenario = _PreviewLoginScenario();
  return <QaScenario>[
    QaScenario(
      suite: _suite,
      name: 'selecting an interest routes an unauthenticated visitor to the '
          'login/sign-up page',
      summary:
          'The sign-up funnel: a logged-out visitor viewing someone\'s profile '
          'Preview from the map who taps one of their interests is routed to the '
          'log-in / sign-up page, and the Preview closes.',
      build: scenario.build,
      body: scenario.run,
      liveSetUp: scenario.liveSetUp,
      liveBody: scenario.liveRun,
      liveTearDown: scenario.liveTearDown,
    ),
  ];
}

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
