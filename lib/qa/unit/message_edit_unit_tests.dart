import '../../utility/MessageEditPolicy.dart';
import 'unit_test.dart';

/// Unit coverage for [MessageEditPolicy] — the rules behind the pencil on a
/// chat bubble and behind the write in `FirebaseMessagesUtility.editMessage`.
///
/// These matter because editing rewrites history in a conversation the other
/// person has already read. The rules are what keep that narrow: only your own
/// message, only for a short window, never in a blocked conversation, and never
/// a write that changes nothing or empties the message.
List<UnitTest> messageEditUnitTests() {
  UnitTest edit(String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'MessageEditPolicy (message editing)',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  // A fixed "now" so no test depends on the wall clock.
  final now = DateTime.utc(2026, 1, 1, 12, 0);
  DateTime agoMinutes(int minutes) => now.subtract(Duration(minutes: minutes));

  bool canEdit({
    String senderUid = 'me',
    String viewerUid = 'me',
    bool blocked = false,
    DateTime? sentAt,
  }) =>
      MessageEditPolicy.canEdit(
        senderUid: senderUid,
        viewerUid: viewerUid,
        conversationBlocked: blocked,
        sentAt: sentAt ?? agoMinutes(1),
        now: now,
      );

  return <UnitTest>[
    edit(
      'lets the author edit their own recent message',
      'The pencil is offered on your own message inside the edit window.',
      '''
## What it checks
`canEdit` is true when the viewer is the sender, the conversation is not
blocked, and the message was sent a minute ago.

## Why it matters
This is the whole feature's happy path — the condition the chat bubble reads to
decide whether to render the edit affordance at all.

## Expected
sender == viewer, 1 minute old, not blocked → editable''',
      (t) {
        t.expectTrue(canEdit(), reason: 'own recent message should be editable');
      },
    ),
    edit(
      'never lets a viewer edit someone else\'s message',
      "You can only edit your own messages — never the other participant's.",
      '''
## What it checks
`canEdit` is false when the message's `senderUid` is not the viewer, even for a
brand new message in an unblocked conversation.

## Why it matters
Putting words in someone else's mouth is the worst failure this feature could
have. The same check runs again server-side in
`FirebaseMessagesUtility.editMessage` against stored data, so a client that
skipped this one still cannot write.

## Expected
sender `them` / viewer `me` → not editable''',
      (t) {
        t.expectFalse(
          canEdit(senderUid: 'them'),
          reason: "another user's message must never be editable",
        );
      },
    ),
    edit(
      'closes the edit window once it has elapsed',
      'A message older than the 15-minute window can no longer be edited.',
      '''
## What it checks
`canEdit` and `isExpired` at the boundary: just inside the window, exactly at
it, and past it.

## Why it matters
The window is what stops a conversation the other person has already read and
replied to from being rewritten underneath them. An off-by-one at the boundary
would either cut editing short or leave old messages mutable forever.

## Expected
- 14 min old → editable
- exactly 15 min old → still editable (the window is inclusive)
- 16 min old → not editable''',
      (t) {
        t.expectTrue(canEdit(sentAt: agoMinutes(14)), reason: '14 min');
        t.expectTrue(canEdit(sentAt: agoMinutes(15)), reason: '15 min (boundary)');
        t.expectFalse(canEdit(sentAt: agoMinutes(16)), reason: '16 min');

        t.expectFalse(
          MessageEditPolicy.isExpired(sentAt: agoMinutes(15), now: now),
        );
        t.expectTrue(
          MessageEditPolicy.isExpired(sentAt: agoMinutes(16), now: now),
        );
      },
    ),
    edit(
      'treats a not-yet-confirmed message as uneditable',
      'A message with no server timestamp yet cannot be edited.',
      '''
## What it checks
A null `sentAt` — a message written locally whose `serverTimestamp()` has not
resolved — yields `canEdit == false`.

## Why it matters
Without a send time there is no way to tell whether the window has closed.
Refusing is the safe direction, and the message becomes editable a moment later
once the stream delivers the server timestamp.

## Expected
`sentAt: null` → not editable''',
      (t) {
        t.expectFalse(
          MessageEditPolicy.canEdit(
            senderUid: 'me',
            viewerUid: 'me',
            conversationBlocked: false,
            sentAt: null,
            now: now,
          ),
        );
      },
    ),
    edit(
      'refuses to edit inside a blocked conversation',
      'When messaging is blocked, existing messages are frozen too.',
      '''
## What it checks
`canEdit` is false for your own recent message when the conversation is blocked.

## Why it matters
`MessageBlockPolicy` already makes a blocked conversation read-only for sending.
Editing is another write into the same conversation, so it has to be shut off by
the same condition — otherwise blocking could be worked around by editing an
older message into a new one.

## Expected
own message, 1 minute old, `conversationBlocked: true` → not editable''',
      (t) {
        t.expectFalse(canEdit(blocked: true));
      },
    ),
    edit(
      'tolerates a send time in the future',
      'Clock skew between device and server never locks editing out.',
      '''
## What it checks
A `sentAt` five minutes ahead of `now` is not treated as expired, and
`remainingWindow` never goes negative.

## Why it matters
`timestamp` is a server timestamp while `now` is the device clock, so a message
can legitimately look like it was sent slightly in the future. Reading that as
"expired" would hide the pencil on the message the user just sent.

## Expected
- future `sentAt` → not expired
- `remainingWindow` for a long-expired message → `Duration.zero`''',
      (t) {
        final future = now.add(const Duration(minutes: 5));
        t.expectFalse(MessageEditPolicy.isExpired(sentAt: future, now: now));
        t.expectTrue(canEdit(sentAt: future));

        t.expectEqual(
          MessageEditPolicy.remainingWindow(sentAt: agoMinutes(60), now: now),
          Duration.zero,
        );
        t.expectEqual(
          MessageEditPolicy.remainingWindow(sentAt: agoMinutes(5), now: now),
          const Duration(minutes: 10),
        );
      },
    ),
    edit(
      'rejects empty, unchanged and whitespace-only edits',
      'Save stays disabled unless the text is a real change worth writing.',
      '''
## What it checks
`isValidEdit` against the original `hello`:
identical text, text differing only in surrounding whitespace, empty text and
whitespace-only text are all rejected; genuinely different text is accepted.

## Why it matters
This is what disables **Save** in the edit dialog and what makes the write path
reject a no-op. Without it, a user could stamp `(edited)` on a message without
changing it, or empty a message — deleting by the back door, which is a separate
action this feature deliberately does not provide.

## Expected
`hello` → `hello`, `  hello  `, ``, `   ` all invalid; `hello there` valid''',
      (t) {
        bool valid(String edited) =>
            MessageEditPolicy.isValidEdit(original: 'hello', edited: edited);

        t.expectFalse(valid('hello'), reason: 'identical');
        t.expectFalse(valid('  hello  '), reason: 'whitespace-only difference');
        t.expectFalse(valid(''), reason: 'empty');
        t.expectFalse(valid('   '), reason: 'whitespace only');
        t.expectTrue(valid('hello there'), reason: 'real change');
        t.expectTrue(valid('  hello there  '), reason: 'real change, padded');
      },
    ),
    edit(
      'normalizes stored text and caps its length',
      'What gets written is the trimmed text, and an over-long edit is refused.',
      '''
## What it checks
`normalize` trims surrounding whitespace and newlines, and `isValidEdit`
rejects text longer than `maxLength` (${MessageEditPolicy.maxLength}).

## Why it matters
`normalize` decides the exact string written to Firestore, so the dialog's
preview and the stored message agree. The length cap keeps an edit from
producing a message the composer itself would never have allowed.

## Expected
- `'  hi\\n\\n'` → `'hi'`
- ${MessageEditPolicy.maxLength} characters → valid
- ${MessageEditPolicy.maxLength} + 1 characters → invalid''',
      (t) {
        t.expectEqual(MessageEditPolicy.normalize('  hi\n\n'), 'hi');
        t.expectEqual(MessageEditPolicy.normalize('hi'), 'hi');

        final atLimit = 'x' * MessageEditPolicy.maxLength;
        final overLimit = 'x' * (MessageEditPolicy.maxLength + 1);
        t.expectTrue(
          MessageEditPolicy.isValidEdit(original: 'hello', edited: atLimit),
        );
        t.expectFalse(
          MessageEditPolicy.isValidEdit(original: 'hello', edited: overLimit),
        );
      },
    ),
  ];
}
