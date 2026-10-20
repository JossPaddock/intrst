import 'package:flutter/material.dart';

import '../../widgets/ChatBubble.dart';
import '../../widgets/EditMessageDialog.dart';
import '../e2e/qa_app_harness.dart';
import '../e2e/qa_seed.dart';
import '../qa_scenario.dart';

/// Coverage for message editing as the user meets it: which bubbles offer the
/// pencil, how an edited message is marked for everyone in the chat, and the
/// edit dialog's refusal to save a no-op.
///
/// The rules behind these affordances are asserted separately in
/// `lib/qa/unit/message_edit_unit_tests.dart`; these scenarios prove the widgets
/// honour them. Every scenario carries **both** definitions: `build` mounts the
/// production widget under `flutter test`, and the live hooks seed a real
/// conversation and drive the real chat from the dashboard.

const String _bubbleSuite = 'Chat bubble (editing)';
const String _dialogSuite = 'Edit message dialog';

const String _editedMarker = '(edited)';

// Message text used by both runners. Distinctive so an assertion can never
// match some other conversation's content in the live app.
const String _seededMessage = 'qa seeded message about hot air balloons';
const String _editedMessage = 'qa edited message about gliders';

/// Mounts [ChatBubble] the way `ChatScreen` renders one message.
Future<Widget> _bubble({
  required bool isSender,
  required bool isEdited,
  required bool editable,
}) async {
  return MaterialApp(
    home: Scaffold(
      body: ChatBubble(
        message: _seededMessage,
        isSender: isSender,
        isEdited: isEdited,
        onEdit: editable ? () {} : null,
      ),
    ),
  );
}

List<QaScenario> messageEditScenarios() {
  // One live holder per scenario, so each seeds and cleans up its own
  // conversation rather than inheriting the previous scenario's state.
  final pencilLive = _MessageEditLive();
  final receivedLive = _MessageEditLive(fromViewer: false);
  final markerLive = _MessageEditLive();
  final noMarkerLive = _MessageEditLive();
  final savesLive = _MessageEditLive();
  final cancelLive = _MessageEditLive();
  final inertLive = _MessageEditLive();

  final dialogRun = _EditDialogScenario();

  return <QaScenario>[
    QaScenario(
      suite: _bubbleSuite,
      name: 'your own editable message offers the pencil',
      summary:
          'A message you sent, still inside the edit window, shows an edit '
          'button next to it.',
      doc: '''
## What it checks
A sender-side bubble inside the edit window renders the edit button.

## Why it matters
The pencil is the only entry point to editing. `ChatScreen` passes `onEdit` only
when `MessageEditPolicy.canEdit` is true, so this is the visible half of that
rule.

## How it runs
- **Headless:** mounts the production `ChatBubble` the way `ChatScreen` renders
  one message.
- **Live:** seeds a 1:1 conversation containing a message the signed-in user
  sent moments ago, opens the real chat, and looks for the pencil on it.

## Expected
Visible: the message text, and the edit button.
''',
      build: () => _bubble(isSender: true, isEdited: false, editable: true),
      body: (d) async {
        await d.expectVisible(qaText(_seededMessage), count: 1);
        await d.expectVisible(qaKey(const Key('chat_bubble_edit_button')),
            count: 1);
      },
      liveSetUp: pencilLive.setUp,
      liveBody: (d, harness) async {
        await d.phase('your own recent message offers the pencil', () async {
          await pencilLive.openChat(d, harness);
          await d.expectVisible(qaText(_seededMessage));
          await d.expectVisible(qaKey(const Key('chat_bubble_edit_button')));
        });
      },
      liveTearDown: pencilLive.cleanup,
    ),
    QaScenario(
      suite: _bubbleSuite,
      name: 'a received message never offers the pencil',
      summary:
          'A message from the other participant shows no edit button, whatever '
          'else is passed to the bubble.',
      doc: '''
## What it checks
A bubble with `isSender: false` renders no edit button even when an `onEdit`
callback is supplied.

## Why it matters
Editing someone else's words is the worst thing this feature could allow. The
bubble refuses independently of its caller, so a wiring mistake in `ChatScreen`
still cannot surface an edit affordance on a received message. The write path
refuses too — see the `MessageEditPolicy` unit coverage.

## How it runs
- **Headless:** passes an `onEdit` callback to a received bubble anyway, and
  asserts the button is still absent.
- **Live:** seeds the conversation with a message sent by the **other** user and
  opens the real chat.

## Expected
Absent: the edit button.
''',
      build: () => _bubble(isSender: false, isEdited: false, editable: true),
      body: (d) async {
        await d.expectVisible(qaText(_seededMessage), count: 1);
        await d.expectAbsent(qaKey(const Key('chat_bubble_edit_button')));
      },
      liveSetUp: receivedLive.setUp,
      liveBody: (d, harness) async {
        await d.phase("the other user's message offers no pencil", () async {
          await receivedLive.openChat(d, harness);
          await d.expectVisible(qaText(_seededMessage));
          await d.expectAbsent(qaKey(const Key('chat_bubble_edit_button')));
        });
      },
      liveTearDown: receivedLive.cleanup,
    ),
    QaScenario(
      suite: _bubbleSuite,
      name: 'an edited message is marked "(edited)" for everyone',
      summary:
          'An edited message carries an "(edited)" marker, on the receiving '
          'side as well as the sender\'s.',
      doc: '''
## What it checks
A received bubble with `isEdited: true` shows the `(edited)` marker.

## Why it matters
Editing rewrites text the other person may already have read. The marker is what
keeps that honest — without it, a message could be changed silently after being
read.

## How it runs
- **Headless:** mounts a received bubble with `isEdited: true`.
- **Live:** actually edits a real seeded message through the chat UI, then
  asserts the new text is shown, the old text is gone, and the marker appeared.
  This is the end-to-end proof that `edited_at` is written and read back.

## Expected
Visible: the new text and the `(edited)` marker. Absent: the original text.
''',
      build: () => _bubble(isSender: false, isEdited: true, editable: false),
      body: (d) async {
        await d.expectVisible(qaKey(const Key('chat_bubble_edited_marker')),
            count: 1);
        await d.expectVisible(qaText(_editedMarker), count: 1);
      },
      liveSetUp: markerLive.setUp,
      liveBody: (d, harness) async {
        await markerLive.openChat(d, harness);

        await d.phase('editing a real message marks it', () async {
          await markerLive.openEditDialog(d);
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            _editedMessage,
          );
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();

          await d.expectVisible(qaText(_editedMessage));
          await d.expectAbsent(qaText(_seededMessage));
          await d.expectVisible(qaKey(const Key('chat_bubble_edited_marker')));
        });
      },
      liveTearDown: markerLive.cleanup,
    ),
    QaScenario(
      suite: _bubbleSuite,
      name: 'an unedited message shows no marker',
      summary:
          'A message that has never been edited carries no "(edited)" marker.',
      doc: '''
## What it checks
A bubble with `isEdited: false` renders neither the marker key nor the text.

## Why it matters
The marker only means something if it is absent on ordinary messages. This is
the negative half of the marker contract.

## How it runs
- **Headless:** mounts an un-edited bubble.
- **Live:** opens a real chat holding a freshly seeded, never-edited message and
  asserts the marker is absent — but only *after* asserting the message itself
  is on screen, so an empty screen can never pass this by default.

## Expected
Visible: the message. Absent: the `(edited)` marker.
''',
      build: () => _bubble(isSender: true, isEdited: false, editable: true),
      body: (d) async {
        // Assert the bubble is actually there first: a screen with nothing on
        // it would satisfy the two absence checks on its own.
        await d.expectVisible(qaText(_seededMessage), count: 1);
        await d.expectAbsent(qaKey(const Key('chat_bubble_edited_marker')));
        await d.expectAbsent(qaText(_editedMarker));
      },
      liveSetUp: noMarkerLive.setUp,
      liveBody: (d, harness) async {
        await d.phase('a never-edited message carries no marker', () async {
          await noMarkerLive.openChat(d, harness);
          await d.expectVisible(qaText(_seededMessage));
          await d.expectAbsent(qaKey(const Key('chat_bubble_edited_marker')));
        });
      },
      liveTearDown: noMarkerLive.cleanup,
    ),
    QaScenario(
      suite: _dialogSuite,
      name: 'saves a real change and returns the trimmed text',
      summary:
          'Typing new text and pressing Save stores the trimmed new message.',
      doc: '''
## What it checks
Opening the dialog, replacing the text with a padded `  …  ` version and
pressing **Save** yields the **trimmed** message.

## Why it matters
The value the dialog returns is written verbatim to Firestore. If it returned
the raw field text, stored messages would drift from what the dialog previewed
and from `MessageEditPolicy.normalize`.

## How it runs
- **Headless:** a host records what `EditMessageDialog` resolves to.
- **Live:** edits a real message to padded text, saves, and asserts the
  conversation renders the **trimmed** string (an exact-text match, so an
  untrimmed write would not satisfy it).

## Expected
Stored/rendered: the trimmed text. Absent: the padded text.
''',
      build: dialogRun.build,
      body: (d) async {
        await d.tap(qaKey(const Key('open_edit_dialog')));
        await d.settle();
        await d.expectVisible(qaKey(const Key('edit_message_dialog')), count: 1);

        await d.enterText(
          qaKey(const Key('edit_message_field')),
          '  $_editedMessage  ',
        );
        await d.settle();

        await d.tap(qaKey(const Key('edit_message_save')));
        await d.settle();

        await d.check(
          'dialog returned the trimmed new message',
          () => dialogRun.result == _editedMessage,
        );
      },
      liveSetUp: savesLive.setUp,
      liveBody: (d, harness) async {
        await savesLive.openChat(d, harness);

        await d.phase('a padded edit is stored trimmed', () async {
          await savesLive.openEditDialog(d);
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            '  $_editedMessage  ',
          );
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();

          await d.expectVisible(qaText(_editedMessage));
          await d.expectAbsent(qaText('  $_editedMessage  '));
        });
      },
      liveTearDown: savesLive.cleanup,
    ),
    QaScenario(
      suite: _dialogSuite,
      name: 'cancelling leaves the message alone',
      summary:
          'Editing the text then pressing Cancel changes nothing, so no write '
          'happens.',
      doc: '''
## What it checks
Text is changed in the field, then **Cancel** is pressed: nothing is written and
the original message stands.

## Why it matters
Cancel has to be a true escape hatch. A dialog that returned the typed text on
cancel would write an edit the user explicitly backed out of.

## How it runs
- **Headless:** asserts the dialog resolves to null.
- **Live:** types into the real dialog, cancels, and asserts the conversation
  still shows the original message, without the discarded text and without an
  `(edited)` marker.

## Expected
Visible: the original message. Absent: the typed text, and the marker.
''',
      build: dialogRun.build,
      body: (d) async {
        await d.tap(qaKey(const Key('open_edit_dialog')));
        await d.settle();

        await d.enterText(
          qaKey(const Key('edit_message_field')),
          _editedMessage,
        );
        await d.settle();

        await d.tap(qaKey(const Key('edit_message_cancel')));
        await d.settle();

        await d.check(
          'no edit was returned to the caller',
          () => dialogRun.result == null && dialogRun.closed,
        );
      },
      liveSetUp: cancelLive.setUp,
      liveBody: (d, harness) async {
        await cancelLive.openChat(d, harness);

        await d.phase('cancelling writes nothing', () async {
          await cancelLive.openEditDialog(d);
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            _editedMessage,
          );
          await d.tap(qaKey(const Key('edit_message_cancel')));
          await d.settle();

          await d.expectVisible(qaText(_seededMessage));
          await d.expectAbsent(qaText(_editedMessage));
          await d.expectAbsent(qaKey(const Key('chat_bubble_edited_marker')));
        });
      },
      liveTearDown: cancelLive.cleanup,
    ),
    QaScenario(
      suite: _dialogSuite,
      name: 'Save does nothing until the message actually changes',
      summary:
          'With the text untouched — or only re-spaced, or emptied — Save is '
          'inert, so no pointless "(edited)" is ever stamped on.',
      doc: '''
## What it checks
Pressing **Save** straight after opening, again after re-typing the original
text with different spacing, and again with the field emptied, leaves the dialog
open and writes nothing. Typing genuinely different text then saves normally.

## Why it matters
Every save stamps `(edited)` and rewrites the message. A no-op save would mark a
message as edited when nothing changed; an empty save would delete it by the
back door, which is not what this feature offers.
`MessageEditPolicy.isValidEdit` decides this — see its unit coverage — and the
dialog is where the user feels it.

## How it runs
- **Headless:** drives the production dialog and checks nothing is returned.
- **Live:** does the same against a real seeded message and finishes by saving a
  real change, so the run also proves the dialog is not simply stuck.

## Expected
- unchanged / re-spaced / emptied → dialog stays open, nothing written
- different text → dialog closes and the new message is shown
''',
      build: dialogRun.build,
      body: (d) async {
        await d.tap(qaKey(const Key('open_edit_dialog')));
        await d.settle();

        Future<void> saveIsInert(String label) async {
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();
          await d.expectVisible(qaKey(const Key('edit_message_dialog')),
              count: 1);
          await d.check(label, () => !dialogRun.closed);
        }

        await d.phase('an untouched message cannot be saved', () async {
          await saveIsInert('dialog still open, no edit returned');
        });

        await d.phase('re-spacing the same text cannot be saved', () async {
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            '   ${_EditDialogScenario.original}   ',
          );
          await d.settle();
          await saveIsInert('dialog still open, no edit returned');
        });

        await d.phase('an emptied message cannot be saved', () async {
          await d.enterText(qaKey(const Key('edit_message_field')), '   ');
          await d.settle();
          await saveIsInert('dialog still open, no edit returned');
        });

        await d.phase('a real change saves', () async {
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            _editedMessage,
          );
          await d.settle();
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();
          await d.expectAbsent(qaKey(const Key('edit_message_dialog')));
          await d.check(
            'the new message was returned',
            () => dialogRun.result == _editedMessage,
          );
        });
      },
      liveSetUp: inertLive.setUp,
      liveBody: (d, harness) async {
        await inertLive.openChat(d, harness);
        await inertLive.openEditDialog(d);

        Future<void> saveIsInert() async {
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();
          // The dialog is still up, so nothing was written.
          await d.expectVisible(qaKey(const Key('edit_message_dialog')));
        }

        await d.phase('an untouched message cannot be saved', saveIsInert);

        await d.phase('re-spacing the same text cannot be saved', () async {
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            '   $_seededMessage   ',
          );
          await saveIsInert();
        });

        await d.phase('an emptied message cannot be saved', () async {
          await d.enterText(qaKey(const Key('edit_message_field')), '   ');
          await saveIsInert();
        });

        await d.phase('a real change saves', () async {
          await d.enterText(
            qaKey(const Key('edit_message_field')),
            _editedMessage,
          );
          await d.tap(qaKey(const Key('edit_message_save')));
          await d.settle();
          await d.expectAbsent(qaKey(const Key('edit_message_dialog')));
          await d.expectVisible(qaText(_editedMessage));
        });
      },
      liveTearDown: inertLive.cleanup,
    ),
  ];
}

/// Live definition shared by the editing scenarios: seeds a 1:1 conversation
/// holding one message, opens it in the **real** app, and deletes exactly what
/// it created afterwards.
///
/// Everything it writes lives under the reserved `qa_e2e_*` namespace via
/// [QaSeeder], and the message is stamped with the current time so it is inside
/// `MessageEditPolicy.editWindow` when the scenario runs.
class _MessageEditLive {
  _MessageEditLive({this.fromViewer = true});

  /// Whether the seeded message was sent by the signed-in viewer (editable) or
  /// by the other participant (never editable).
  final bool fromViewer;

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
        'No signed-in user, so there is nobody to own the message being '
        'edited.',
      );
    }

    await _seeder.seedUser(
      uid: QaSeeder.otherUid,
      firstName: 'Ada',
      lastName: 'Lovelace',
    );
    final conversation = await _seeder.seedConversation(
      selfUid: _viewerUid,
      otherUid: QaSeeder.otherUid,
    );
    await _seeder.seedMessage(
      conversation: conversation,
      senderUid: fromViewer ? _viewerUid : QaSeeder.otherUid,
      content: _seededMessage,
    );
  }

  /// Opens the seeded conversation in the real app and waits for its messages.
  Future<void> openChat(QaDriver d, QaAppHarness harness) async {
    await harness.openConversationWith(QaSeeder.otherUid, _otherName);
    await d.settle();
  }

  /// Taps the pencil on the seeded message and waits for the dialog.
  Future<void> openEditDialog(QaDriver d) async {
    await d.tap(qaKey(const Key('chat_bubble_edit_button')));
    await d.settle();
    await d.expectVisible(qaKey(const Key('edit_message_dialog')));
  }

  Future<void> cleanup(QaAppHarness harness) => _seeder.cleanup();
}

/// Holds the per-run state the headless dialog scenarios assert on. [build]
/// resets it, so they are safe to re-run any number of times.
class _EditDialogScenario {
  static const String original = _seededMessage;

  /// What the dialog handed back, or null if it was cancelled.
  String? result;

  /// Whether the dialog has closed at all, so "cancelled" can be told apart
  /// from "still open".
  bool closed = false;

  Future<Widget> build() async {
    result = null;
    closed = false;

    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open_edit_dialog'),
              onPressed: () async {
                final updated = await EditMessageDialog.show(
                  context,
                  originalContent: original,
                );
                result = updated;
                closed = true;
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
  }
}
