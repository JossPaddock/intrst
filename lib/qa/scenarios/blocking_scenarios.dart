import 'package:flutter/material.dart';

import '../../utility/MessageBlockPolicy.dart';
import '../../widgets/BlockedMessageNotice.dart';
import '../e2e/qa_app_harness.dart';
import '../e2e/qa_seed.dart';
import '../qa_scenario.dart';

/// Coverage for the user-blocking feature's messaging enforcement: the UI each
/// side of a block sees, and the policy that decides when a 1:1 conversation is
/// blocked.

const String _noticeSuite = 'Blocked messaging notice';
const String _policySuite = 'MessageBlockPolicy (1:1 send enforcement)';

/// Wraps the notice the way `CollapsibleChatScreen` renders it — in place of the
/// message input — so the scenario exercises the real production widget.
Future<Widget> _notice({
  required bool viewerIsBlocker,
  required String otherName,
}) async {
  return MaterialApp(
    home: Scaffold(
      body: BlockedMessageNotice(
        viewerIsBlocker: viewerIsBlocker,
        otherDisplayName: otherName,
      ),
    ),
  );
}

List<QaScenario> blockingScenarios() {
  // One live holder per scenario, so each seeds/cleans its own conversation.
  final blockedLive = _BlockingLive(otherBlocksViewer: true);
  final blockerLive = _BlockingLive(otherBlocksViewer: false);
  return <QaScenario>[
    QaScenario(
      suite: _noticeSuite,
      name: 'a blocked user sees "not accepting messages" and cannot send',
      summary:
          "When someone blocks you and you open the chat, you see a neutral "
          "\"not accepting messages\" notice — never wording that reveals you "
          "were blocked — and the message box is gone, so you can't type or send.",
      doc: '''
## What it checks
When the **other** person has blocked you and you open the chat, you see the
neutral *"not accepting messages"* notice, the input box is gone, and the
blocker-facing wording is **not** shown.

## Why it matters
Blocking must not be observable to the blocked user. If the blocker-facing copy
("you blocked them") leaked here, it would reveal you'd been blocked — a privacy
leak. The neutral copy plus a removed input is the whole contract of the blocked
side.

## How it runs
- **Headless:** mounts the production `BlockedMessageNotice` the way
  `CollapsibleChatScreen` renders it (in place of the input).
- **Live:** seeds a 1:1 conversation with the other user blocking the viewer,
  opens the real chat, and asserts the neutral notice.

## Expected
- Visible: the neutral "not accepting messages" notice.
- Absent: the blocker-facing copy, and any `TextField` (no way to type/send).
''',
      build: () => _notice(viewerIsBlocker: false, otherName: 'User A'),
      body: (d) async {
        await d.expectVisible(
          qaText(BlockedMessageNotice.blockedMessage),
          count: 1,
        );

        // The blocker-facing copy must not leak to the blocked user (it would
        // reveal that they were blocked).
        await d.expectAbsent(qaText(BlockedMessageNotice.blockerMessage('User A')));

        // No input affordance is rendered, so there is nothing to type into
        // or send with.
        await d.expectAbsent(qaType(TextField));
      },
      liveSetUp: blockedLive.setUp,
      liveBody: blockedLive.body,
      liveTearDown: blockedLive.cleanup,
    ),
    QaScenario(
      suite: _noticeSuite,
      name: 'the blocker sees the "you blocked them, unblock to continue" message',
      summary:
          "When you block someone and reopen the chat, you see a clear "
          "\"you blocked them — unblock to continue\" message with a way to "
          "undo it, and the message box is removed so you can't send.",
      doc: '''
## What it checks
When **you** have blocked the other person and reopen the chat, you see the clear
*"you blocked them — unblock to continue"* message (with a way to undo), the input
box is removed, and the blocked-user copy is not shown.

## Why it matters
The blocker needs an actionable, honest message and a path to unblock — the
opposite of the neutral copy the blocked side sees. This guards that the two
sides of a block render their **own** copy and neither can send.

## How it runs
- **Headless:** mounts `BlockedMessageNotice` with `viewerIsBlocker: true`.
- **Live:** seeds the conversation and places the block on the real signed-in
  account, opens the real chat, and asserts the unblock message (cleanup removes
  the block afterwards).

## Expected
- Visible: the "you blocked them — unblock to continue" message.
- Absent: the neutral blocked-user copy, and any `TextField`.
''',
      build: () => _notice(viewerIsBlocker: true, otherName: 'User B'),
      body: (d) async {
        await d.expectVisible(
          qaText(BlockedMessageNotice.blockerMessage('User B')),
          count: 1,
        );

        // The blocked-user copy must not be shown to the blocker.
        await d.expectAbsent(qaText(BlockedMessageNotice.blockedMessage));
        await d.expectAbsent(qaType(TextField));
      },
      liveSetUp: blockerLive.setUp,
      liveBody: blockerLive.body,
      liveTearDown: blockerLive.cleanup,
    ),

    // The same predicate gates both hiding the input and the hard stop inside
    // _handleSendMessage, so these are the coverage for "cannot send even if
    // they try" in either block direction. They assert on logic, not UI, so
    // there is nothing to watch — they still run and report here.
    ..._policyScenarios(),
  ];
}

/// Drives the **real** blocked-messaging UI: seeds a 1:1 conversation and the
/// block, opens the production chat, and asserts the correct notice.
///
/// [otherBlocksViewer] chooses the direction:
///  - true  → the other user blocked the viewer (viewer sees the neutral copy);
///  - false → the viewer blocked the other user (viewer sees the unblock copy).
///
/// Uses whoever is signed in as the viewer (falling back to the QA test account
/// if signed out), so it needs no credentials as long as a session exists.
class _BlockingLive {
  _BlockingLive({required this.otherBlocksViewer});

  final bool otherBlocksViewer;
  final QaSeeder _seeder = QaSeeder();
  static const String _otherName = 'Ada Lovelace';

  String _viewerUid = '';

  Future<void> setUp(QaAppHarness harness) async {
    if (!harness.signedIn) {
      // Throws QaHarnessUnavailable (surfaced in the PiP) when no test account
      // is configured and nobody is signed in.
      await harness.signInTestUser();
    }
    _viewerUid = harness.currentUid;
    if (_viewerUid.isEmpty) {
      throw QaHarnessUnavailable(
        'No signed-in user, so there is nobody to host the conversation.',
      );
    }

    // The other participant. When they are the blocker, the block lives on
    // their own (namespaced, fully-deleted-on-cleanup) doc.
    await _seeder.seedUser(
      uid: QaSeeder.otherUid,
      firstName: 'Ada',
      lastName: 'Lovelace',
      blockedUids: otherBlocksViewer ? <String>[_viewerUid] : const <String>[],
    );
    await _seeder.seedConversation(
      selfUid: _viewerUid,
      otherUid: QaSeeder.otherUid,
    );
    if (!otherBlocksViewer) {
      // Viewer is the blocker: the block goes on the real signed-in account and
      // is removed again on cleanup.
      await _seeder.addBlockOnRealUser(
        ownerUid: _viewerUid,
        targetUid: QaSeeder.otherUid,
      );
    }
  }

  Future<void> body(QaDriver d, QaAppHarness harness) async {
    await d.phase(
      otherBlocksViewer
          ? 'the blocked user sees the neutral notice'
          : 'the blocker sees the actionable unblock notice',
      () async {
        await harness.openConversationWith(QaSeeder.otherUid, _otherName);
        await d.settle();

        // The notice renders in place of the message input, so its presence is
        // the proof the input is gone (an app-wide TextField check would match
        // Messaging's always-mounted "new chat" search field).
        await d.expectVisible(qaType(BlockedMessageNotice));
        if (otherBlocksViewer) {
          await d.expectVisible(qaText(BlockedMessageNotice.blockedMessage));
          await d.expectAbsent(
            qaText(BlockedMessageNotice.blockerMessage(_otherName)),
          );
        } else {
          await d.expectVisible(
            qaText(BlockedMessageNotice.blockerMessage(_otherName)),
          );
          await d.expectAbsent(qaText(BlockedMessageNotice.blockedMessage));
        }
      },
    );
  }

  Future<void> cleanup(QaAppHarness harness) => _seeder.cleanup();
}

bool _blocked({
  int otherCount = 1,
  bool iBlockedThem = false,
  bool theyBlockedMe = false,
}) =>
    MessageBlockPolicy.isBlocked(
      otherParticipantCount: otherCount,
      iBlockedThem: iBlockedThem,
      theyBlockedMe: theyBlockedMe,
    );

List<QaScenario> _policyScenarios() {
  QaScenario policy(
      String name, String summary, String doc, bool Function() condition) {
    return QaScenario(
      suite: _policySuite,
      name: name,
      summary: summary,
      doc: doc,
      body: (d) => d.check(name, condition),
    );
  }

  const about = '''
## About this suite
`MessageBlockPolicy.isBlocked` is the single predicate that decides whether a 1:1
conversation is blocked. It gates **both** hiding the message input and the hard
stop inside `_handleSendMessage`, so these checks are the coverage for "can't
send even if they try", in either block direction.

These are **logic checks**: they assert on the function directly, so there's
nothing to watch — the dashboard runs them in place and reports pass/fail.
''';

  return <QaScenario>[
    policy(
      'blocks when the viewer blocked the other user',
      'The send rule: if you have blocked the other person, the 1:1 '
          'conversation counts as blocked and your outgoing messages are stopped.',
      '''
## What it checks
If **you** blocked the other person, the 1:1 conversation counts as blocked.

## Expected
`isBlocked(others: 1, iBlockedThem: true)` -> **blocked**
$about''',
      () => _blocked(iBlockedThem: true) == true,
    ),
    policy(
      'blocks when the other user blocked the viewer',
      'The send rule works both ways: if the other person has blocked you, the '
          '1:1 conversation is blocked and your messages are stopped.',
      '''
## What it checks
The rule is symmetric: if the **other** person blocked you, the 1:1 conversation
is blocked too.

## Expected
`isBlocked(others: 1, theyBlockedMe: true)` -> **blocked**
$about''',
      () => _blocked(theyBlockedMe: true) == true,
    ),
    policy(
      'blocks when both sides blocked each other',
      'When both people have blocked each other, the conversation stays '
          'blocked — messaging remains stopped for both.',
      '''
## What it checks
When both people have blocked each other, the conversation stays blocked (the two
blocks don't cancel out).

## Expected
`isBlocked(others: 1, iBlockedThem: true, theyBlockedMe: true)` -> **blocked**
$about''',
      () => _blocked(iBlockedThem: true, theyBlockedMe: true) == true,
    ),
    policy(
      'does not block when neither side blocked',
      'The normal case: with no block in either direction, the 1:1 conversation '
          'is not blocked and messaging works as usual.',
      '''
## What it checks
The normal case: with no block in either direction, the conversation is not
blocked and messaging works.

## Why it matters
The negative case guards against `isBlocked` being over-eager and blocking normal
conversations.

## Expected
`isBlocked(others: 1)` -> **not blocked**
$about''',
      () => _blocked() == false,
    ),
    policy(
      'does not enforce blocking in group conversations',
      'Blocking is a 1:1-only rule: in a group chat (more than one other '
          'person) a block does not stop the conversation, in either direction.',
      '''
## What it checks
Blocking is a **1:1-only** rule: in a group (more than one other participant) a
block does not stop the conversation, in either direction.

## Why it matters
Group semantics differ — one member blocking another shouldn't silence a whole
group thread. The `otherParticipantCount > 1` guard is what enforces that.

## Expected
`isBlocked(others: 2, iBlockedThem: true)` -> not blocked; and
`isBlocked(others: 3, theyBlockedMe: true)` -> not blocked
$about''',
      () =>
          _blocked(otherCount: 2, iBlockedThem: true) == false &&
          _blocked(otherCount: 3, theyBlockedMe: true) == false,
    ),
    policy(
      'does not block when there is no other participant',
      'Edge case: a conversation with no other participant can\'t be blocked, '
          'so the rule reports it as not blocked.',
      '''
## What it checks
Edge case: a conversation with **no** other participant can't be blocked, so the
rule reports "not blocked".

## Why it matters
Guards the degenerate `otherParticipantCount == 0` case (e.g. a not-yet-populated
or malformed conversation) against a false positive.

## Expected
`isBlocked(others: 0, iBlockedThem: true)` -> **not blocked**
$about''',
      () => _blocked(otherCount: 0, iBlockedThem: true) == false,
    ),
  ];
}
