import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../login/signup/signup_progress_header.dart';
import '../../login/signup/signup_step_interest.dart';
import '../../login/signup/signup_step_profile.dart';
import '../../login/signup/signup_submission.dart';
import '../../login/signup/signup_wizard_data.dart';
import '../../models/Interest.dart';
import '../../utility/FirebaseUsersUtility.dart';
import '../e2e/qa_app_harness.dart';
import '../qa_scenario.dart';

/// Coverage for the multi-part sign-up wizard as the user meets it.
///
/// The wizard runs *before* the Firebase Auth account is created, so these
/// scenarios are checking the gates that decide whether an account gets made
/// at all — an underage birthday, a missing name, a nameless interest — plus
/// the progress indicator that tells the user where they are in the flow.
///
/// The rules themselves are asserted in
/// `lib/qa/unit/signup_wizard_unit_tests.dart`; these prove the screens honour
/// them. The final suite is logic-only: it drives [SignupSubmission] against an
/// in-memory Firestore to prove that finishing the wizard really does leave a
/// complete profile — marker placed, interest seeded — behind.
///
/// Every screen scenario carries **both** definitions: `build` mounts the
/// production step widget under `flutter test`, and the live hooks walk the
/// real wizard in the running app via [QaAppHarness.openSignupWizard]. Account
/// creation is disabled for the live wizard, so a dashboard run never writes
/// to prod — which is also why the live assertions check that the flow did or
/// did not *advance* rather than inspecting a captured draft.
const String _profileSuite = 'Signup wizard (about you)';
const String _interestSuite = 'Signup wizard (your interest)';
const String _progressSuite = 'Signup wizard (progress)';
const String _submissionSuite = 'Signup submission';

const Key _firstName = Key('signup_first_name');
const Key _lastName = Key('signup_last_name');
const Key _birthday = Key('signup_birthday');
const Key _profileContinue = Key('signup_profile_continue');
const Key _interestName = Key('signup_interest_name');
const Key _interestDescription = Key('signup_interest_description');
const Key _interestContinue = Key('signup_interest_continue');

/// A birthday string [years] years and [days] days before today, in the
/// `MM/DD/YYYY` format the field asks for. Relative to today rather than
/// hard-coded so these scenarios never expire.
String _birthdayAged({required int years, int days = 0}) {
  final DateTime now = DateTime.now();
  final DateTime date =
      DateTime(now.year - years, now.month, now.day).add(Duration(days: days));
  return '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/${date.year}';
}

/// Hosts [SignupStepProfile] and records the draft it hands back. [build]
/// resets that, so the scenario can be replayed from the dashboard.
class _ProfileStepHost {
  SignupProfileDraft? accepted;

  Future<Widget> build() async {
    accepted = null;
    return MaterialApp(
      home: Scaffold(
        body: SignupStepProfile(onContinue: (draft) => accepted = draft),
      ),
    );
  }
}

/// Hosts [SignupStepInterest] and records the draft it hands back.
class _InterestStepHost {
  SignupInterestDraft? accepted;

  Future<Widget> build() async {
    accepted = null;
    return MaterialApp(
      home: Scaffold(
        body: SignupStepInterest(
          onContinue: (draft) => accepted = draft,
          onBack: () {},
        ),
      ),
    );
  }
}

/// A [FirebaseUsersUtility] whose two write paths are recorded instead of
/// reaching the network.
///
/// `addInterestForUser` and the activity-feed write behind it both resolve
/// `FirebaseFirestore.instance` internally, which cannot be pointed at a fake,
/// so the submission is verified by recording what it *asks* the utility to
/// write while the profile document itself is written for real into an
/// in-memory Firestore.
class _RecordingUsersUtility extends FirebaseUsersUtility {
  final List<Interest> interests = <Interest>[];
  final List<bool> firstRunFlags = <bool>[];

  @override
  Future<void> addUserToFirestore(
    CollectionReference users,
    String userUid,
    String firstName,
    String lastName,
    GeoPoint geoPoint,
    DateTime birthday, {
    bool firstRunExperienceComplete = false,
  }) async {
    firstRunFlags.add(firstRunExperienceComplete);
    await users.add(<String, dynamic>{
      'user_uid': userUid,
      'first_name': firstName,
      'last_name': lastName,
      'birthday': Timestamp.fromDate(birthday),
      'location': geoPoint,
      'interests': <Map<String, dynamic>>[],
      'first_run_experience': firstRunExperienceComplete,
    });
  }

  @override
  Future<void> addInterestForUser(
      CollectionReference users, Interest interest, String uid) async {
    interests.add(interest);
  }
}

/// A completed wizard, as the location step hands it to the login screen.
SignupWizardResult _completedWizard() => SignupWizardResult(
      profile: SignupProfileDraft(
        firstName: 'Ada',
        lastName: 'Lovelace',
        birthday: DateTime(1990, 1, 31),
      ),
      interest: const SignupInterestDraft(
        name: 'Astronomy',
        description: 'Been hooked since the last eclipse.',
      ),
      location: const SignupLocationDraft(
        latitude: 51.5,
        longitude: -0.12,
        zoom: 15,
        source: SignupLocationSource.manual,
      ),
    );

/// Opens the real wizard before a live run, and closes it afterwards.
///
/// One instance per scenario, matching the rest of the repo: each live run gets
/// a freshly pushed wizard rather than inheriting whatever part the previous
/// scenario left it on.
class _SignupWizardLive {
  Future<void> setUp(QaAppHarness harness) => harness.openSignupWizard();

  // Pops the pushed wizard route and returns the app to the map. Always runs,
  // so a failed scenario never strands the next one inside a half-filled
  // wizard.
  Future<void> tearDown(QaAppHarness harness) => harness.resetToBaseline();
}

/// Fills part one of the live wizard.
Future<void> _liveFillProfile(QaDriver d, {required String birthday}) async {
  await d.enterText(qaKey(_firstName), 'Ada');
  await d.enterText(qaKey(_lastName), 'Lovelace');
  await d.enterText(qaKey(_birthday), birthday);
}

/// Gets the live wizard from part one to part two with a valid profile.
Future<void> _liveAdvanceToInterest(QaDriver d) async {
  await d.phase('complete part one', () async {
    await _liveFillProfile(d, birthday: _birthdayAged(years: 30));
    await d.tap(qaKey(_profileContinue));
    await d.expectVisible(qaText('Step 2 of 3'));
  });
}

List<QaScenario> signupWizardScenarios() {
  // One host per scenario, so each starts from a freshly built screen rather
  // than inheriting the previous run's captured draft.
  final underageHost = _ProfileStepHost();
  final blankNameHost = _ProfileStepHost();
  final validProfileHost = _ProfileStepHost();
  final promptHost = _InterestStepHost();
  final namelessInterestHost = _InterestStepHost();
  final validInterestHost = _InterestStepHost();

  // One live holder per scenario, for the same reason: each opens its own
  // wizard rather than inheriting the part the previous run left it on.
  final underageLive = _SignupWizardLive();
  final blankNameLive = _SignupWizardLive();
  final validProfileLive = _SignupWizardLive();
  final promptLive = _SignupWizardLive();
  final namelessInterestLive = _SignupWizardLive();
  final validInterestLive = _SignupWizardLive();
  final progressLive = _SignupWizardLive();

  return <QaScenario>[
    QaScenario(
      suite: _profileSuite,
      name: 'refuses an underage sign-up before any account is created',
      summary: 'A birthday under 13 raises the age restriction dialog and the '
          'wizard does not advance.',
      build: underageHost.build,
      liveSetUp: underageLive.setUp,
      liveTearDown: underageLive.tearDown,
      liveBody: (d, h) async {
        await d.expectVisible(qaText('Step 1 of 3'));
        await _liveFillProfile(d, birthday: _birthdayAged(years: 12));
        await d.tap(qaKey(_profileContinue));
        await d.expectVisible(qaText('Age Restriction'));
        await d.tap(qaText('OK'));
        // The live run has no captured draft to inspect, so "did not advance"
        // is checked the way the user would see it: still on part one.
        await d.expectVisible(qaText('Step 1 of 3'));
      },
      body: (d) async {
        await d.phase('fill in an underage profile', () async {
          await d.enterText(qaKey(_firstName), 'Ada');
          await d.enterText(qaKey(_lastName), 'Lovelace');
          await d.enterText(
              qaKey(_birthday), _birthdayAged(years: 12));
        });
        await d.phase('attempt to continue', () async {
          await d.tap(qaKey(_profileContinue));
          await d.expectVisible(qaText('Age Restriction'));
          await d.check(
            'the wizard did not accept the underage profile',
            () => underageHost.accepted == null,
          );
        });
      },
    ),
    QaScenario(
      suite: _profileSuite,
      name: 'requires a first and last name',
      summary: 'Continuing with empty name fields shows both field errors '
          'rather than advancing.',
      build: blankNameHost.build,
      liveSetUp: blankNameLive.setUp,
      liveTearDown: blankNameLive.tearDown,
      liveBody: (d, h) async {
        await d.tap(qaKey(_profileContinue));
        await d.expectVisible(qaText('Please enter a First Name'));
        await d.expectVisible(qaText('Please enter a Last Name'));
        await d.expectVisible(qaText('Step 1 of 3'));
      },
      body: (d) async {
        await d.tap(qaKey(_profileContinue));
        await d.expectVisible(qaText('Please enter a First Name'));
        await d.expectVisible(qaText('Please enter a Last Name'));
        await d.check(
          'the wizard did not accept an empty profile',
          () => blankNameHost.accepted == null,
        );
      },
    ),
    QaScenario(
      suite: _profileSuite,
      name: 'carries a valid profile forward and shows the age it read',
      summary: "A complete, old-enough profile advances and the field's helper "
          'text confirms the age the app calculated.',
      build: validProfileHost.build,
      liveSetUp: validProfileLive.setUp,
      liveTearDown: validProfileLive.tearDown,
      liveBody: (d, h) async {
        await _liveFillProfile(d, birthday: _birthdayAged(years: 30));
        await d.expectVisible(qaText('That makes you 30 years old.'));
        await d.tap(qaKey(_profileContinue));
        await d.expectVisible(qaText('Step 2 of 3'));
      },
      body: (d) async {
        await d.phase('fill in a valid profile', () async {
          await d.enterText(qaKey(_firstName), 'Ada');
          await d.enterText(qaKey(_lastName), 'Lovelace');
          await d.enterText(qaKey(_birthday), _birthdayAged(years: 30));
          // The live age caption is how the user checks they typed the date
          // they meant, so it is part of the contract of this screen.
          await d.expectVisible(qaText('That makes you 30 years old.'));
        });
        await d.phase('continue', () async {
          await d.tap(qaKey(_profileContinue));
          await d.check(
            'the profile was handed to the next part',
            () =>
                validProfileHost.accepted?.firstName == 'Ada' &&
                validProfileHost.accepted?.lastName == 'Lovelace',
          );
        });
      },
    ),
    QaScenario(
      suite: _interestSuite,
      name: 'shows the inspiration prompt',
      summary: 'The second part asks the prompt the flow is built around.',
      build: promptHost.build,
      liveSetUp: promptLive.setUp,
      liveTearDown: promptLive.tearDown,
      liveBody: (d, h) async {
        await _liveAdvanceToInterest(d);
        await d.expectVisible(qaText(SignupStepInterest.prompt));
      },
      body: (d) async {
        await d.expectVisible(qaText(SignupStepInterest.prompt));
      },
    ),
    QaScenario(
      suite: _interestSuite,
      name: 'requires the interest to be named',
      summary: 'Continuing without a name shows the field error and does not '
          'advance.',
      build: namelessInterestHost.build,
      liveSetUp: namelessInterestLive.setUp,
      liveTearDown: namelessInterestLive.tearDown,
      liveBody: (d, h) async {
        await _liveAdvanceToInterest(d);
        await d.enterText(
            qaKey(_interestDescription), 'A description with no name.');
        await d.tap(qaKey(_interestContinue));
        await d.expectVisible(qaText('Please name your interest'));
        await d.expectVisible(qaText('Step 2 of 3'));
      },
      body: (d) async {
        await d.enterText(
            qaKey(_interestDescription), 'A description with no name.');
        await d.tap(qaKey(_interestContinue));
        await d.expectVisible(qaText('Please name your interest'));
        await d.check(
          'the wizard did not accept a nameless interest',
          () => namelessInterestHost.accepted == null,
        );
      },
    ),
    QaScenario(
      suite: _interestSuite,
      name: 'carries the name and description forward',
      summary: 'Both fields reach the next part, so the account is created '
          'with the interest the user actually typed.',
      build: validInterestHost.build,
      liveSetUp: validInterestLive.setUp,
      liveTearDown: validInterestLive.tearDown,
      liveBody: (d, h) async {
        await _liveAdvanceToInterest(d);
        await d.enterText(qaKey(_interestName), 'Astronomy');
        await d.enterText(
            qaKey(_interestDescription), 'Been hooked since the last eclipse.');
        await d.tap(qaKey(_interestContinue));
        // Reaching part three is what proves both fields were accepted.
        await d.expectVisible(qaText('Step 3 of 3'));
        await d.expectVisible(qaText('Where are you?'));
      },
      body: (d) async {
        await d.enterText(qaKey(_interestName), 'Astronomy');
        await d.enterText(
            qaKey(_interestDescription), 'Been hooked since the last eclipse.');
        await d.tap(qaKey(_interestContinue));
        await d.check(
          'the interest was handed to the next part intact',
          () =>
              validInterestHost.accepted?.name == 'Astronomy' &&
              validInterestHost.accepted?.description ==
                  'Been hooked since the last eclipse.',
        );
      },
    ),
    QaScenario(
      suite: _progressSuite,
      name: 'names the current part and how many are left',
      summary: 'The header on part two reads "Step 2 of 3" and labels every '
          'part of the flow.',
      build: () async => const MaterialApp(
        home: Scaffold(
          body: SignupProgressHeader(currentStep: SignupWizardStep.interest),
        ),
      ),
      liveSetUp: progressLive.setUp,
      liveTearDown: progressLive.tearDown,
      liveBody: (d, h) async {
        // The header is mounted by the wizard shell, so the live run watches
        // the counter actually change as the user advances.
        await d.expectVisible(qaText('Step 1 of 3'));
        for (final step in SignupWizardStep.values) {
          await d.expectVisible(qaText(step.label));
        }
        await _liveAdvanceToInterest(d);
      },
      body: (d) async {
        await d.expectVisible(qaText('Step 2 of 3'));
        for (final step in SignupWizardStep.values) {
          await d.expectVisible(qaText(step.label));
        }
      },
    ),
    QaScenario(
      suite: _submissionSuite,
      name: 'writes a complete profile with the marker already placed',
      summary: 'Finishing the wizard stores the name, birthday and chosen '
          'location, and marks the first-run experience done.',
      // Logic-only: this drives the submission directly, no screen involved.
      body: (d) async {
        final firestore = FakeFirebaseFirestore();
        final utility = _RecordingUsersUtility();
        final users = firestore.collection('users');

        await SignupSubmission(usersUtility: utility).submit(
          users: users,
          userUid: 'signup-uid-1',
          result: _completedWizard(),
        );

        final snapshot =
            await users.where('user_uid', isEqualTo: 'signup-uid-1').get();
        final data = snapshot.docs.single.data();
        final GeoPoint location = data['location'] as GeoPoint;

        await d.check(
          'the profile document carries the name from part one',
          () => data['first_name'] == 'Ada' && data['last_name'] == 'Lovelace',
        );
        await d.check(
          'the marker sits where part three placed it',
          () =>
              (location.latitude - 51.5).abs() < 1e-9 &&
              (location.longitude + 0.12).abs() < 1e-9,
        );
        await d.check(
          'the first-run location onboarding will not run again',
          () => data['first_run_experience'] == true,
        );
      },
    ),
    QaScenario(
      suite: _submissionSuite,
      name: 'seeds the interest from part two',
      summary: 'The interest the user typed is written for the new account, so '
          'their list is populated the first time they open it.',
      body: (d) async {
        final firestore = FakeFirebaseFirestore();
        final utility = _RecordingUsersUtility();

        final Interest written =
            await SignupSubmission(usersUtility: utility).submit(
          users: firestore.collection('users'),
          userUid: 'signup-uid-2',
          result: _completedWizard(),
        );

        await d.check(
          'exactly one interest was seeded',
          () => utility.interests.length == 1,
        );
        await d.check(
          'it is the interest the user typed',
          () =>
              utility.interests.single.name == 'Astronomy' &&
              utility.interests.single.description ==
                  'Been hooked since the last eclipse.',
        );
        await d.check(
          'the seeded interest is the one handed back to the caller',
          () => utility.interests.single.id == written.id,
        );
      },
    ),
    QaScenario(
      suite: _submissionSuite,
      name: 'a retry does not create a second profile document',
      summary: 'Re-running the submission after a partial failure reuses the '
          'existing profile instead of duplicating it.',
      body: (d) async {
        final firestore = FakeFirebaseFirestore();
        final utility = _RecordingUsersUtility();
        final users = firestore.collection('users');
        final submission = SignupSubmission(usersUtility: utility);

        await submission.submit(
          users: users,
          userUid: 'signup-uid-3',
          result: _completedWizard(),
        );
        // The wizard offers "try again" on a non-fatal failure, which replays
        // the whole submission against an account that may already be
        // half-written.
        await submission.submit(
          users: users,
          userUid: 'signup-uid-3',
          result: _completedWizard(),
        );

        final snapshot =
            await users.where('user_uid', isEqualTo: 'signup-uid-3').get();

        await d.check(
          'still exactly one profile document',
          () => snapshot.docs.length == 1,
        );
        await d.check(
          'the profile was only written once',
          () => utility.firstRunFlags.length == 1,
        );
      },
    ),
  ];
}
