import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:intrst/utility/MessageBlockPolicy.dart';
import 'package:intrst/widgets/BlockedMessageNotice.dart';

// Wraps the notice the way CollapsibleChatScreen renders it (in place of the
// message input) so the test exercises the real production widget.
Widget _harness({required bool viewerIsBlocker, required String otherName}) {
  return MaterialApp(
    home: Scaffold(
      body: BlockedMessageNotice(
        viewerIsBlocker: viewerIsBlocker,
        otherDisplayName: otherName,
      ),
    ),
  );
}

void main() {
  group('Blocked messaging notice', () {
    // Scenario: User A blocked User B. User B opens the conversation and tries
    // to message A. B is NOT the blocker, so B must see the neutral notice and
    // have no way to send.
    patrolWidgetTest(
      'a blocked user sees "not accepting messages" and cannot send',
      ($) async {
        await $.pumpWidgetAndSettle(
          _harness(viewerIsBlocker: false, otherName: 'User A'),
        );

        expect(
          find.text('This person is not accepting messages right now.'),
          findsOneWidget,
        );

        // The blocker-facing copy must not leak to the blocked user (it would
        // reveal that they were blocked).
        expect(
          find.text(BlockedMessageNotice.blockerMessage('User A')),
          findsNothing,
        );

        // No input affordance is rendered, so there is nothing to type into
        // or send with.
        expect(find.byType(TextField), findsNothing);
      },
    );

    // Scenario: User A blocked User B and then opens the conversation to try to
    // message B. A IS the blocker, so A sees the actionable "unblock" copy.
    patrolWidgetTest(
      'the blocker sees the "you blocked them, unblock to continue" message',
      ($) async {
        await $.pumpWidgetAndSettle(
          _harness(viewerIsBlocker: true, otherName: 'User B'),
        );

        expect(
          find.text(
            'You have blocked User B, unblock them to continue messaging this user.',
          ),
          findsOneWidget,
        );

        // The blocked-user copy must not be shown to the blocker.
        expect(
          find.text(BlockedMessageNotice.blockedMessage),
          findsNothing,
        );

        expect(find.byType(TextField), findsNothing);
      },
    );
  });

  // The same predicate gates both hiding the input and the hard stop inside
  // _handleSendMessage, so this is the coverage for "cannot send even if they
  // try" in either block direction.
  group('MessageBlockPolicy.isBlocked (1:1 send enforcement)', () {
    bool blocked({
      int otherCount = 1,
      bool iBlockedThem = false,
      bool theyBlockedMe = false,
    }) =>
        MessageBlockPolicy.isBlocked(
          otherParticipantCount: otherCount,
          iBlockedThem: iBlockedThem,
          theyBlockedMe: theyBlockedMe,
        );

    test('blocks when the viewer blocked the other user', () {
      expect(blocked(iBlockedThem: true), isTrue);
    });

    test('blocks when the other user blocked the viewer', () {
      expect(blocked(theyBlockedMe: true), isTrue);
    });

    test('blocks when both sides blocked each other', () {
      expect(blocked(iBlockedThem: true, theyBlockedMe: true), isTrue);
    });

    test('does not block when neither side blocked', () {
      expect(blocked(), isFalse);
    });

    test('does not enforce blocking in group conversations', () {
      expect(blocked(otherCount: 2, iBlockedThem: true), isFalse);
      expect(blocked(otherCount: 3, theyBlockedMe: true), isFalse);
    });

    test('does not block when there is no other participant', () {
      expect(blocked(otherCount: 0, iBlockedThem: true), isFalse);
    });
  });
}
