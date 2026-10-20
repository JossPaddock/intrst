import '../../login/signup/signup_wizard_data.dart';
import 'unit_test.dart';

/// Unit coverage for the rules behind the multi-part sign-up wizard.
///
/// These matter because the wizard runs *before* the Firebase Auth account is
/// created: whatever these functions allow through is what becomes a real
/// account, a real profile document and a real marker on the map. The age gate
/// in particular is the last line before account creation — if it passes an
/// underage sign-up, an account exists that should never have.
List<UnitTest> signupWizardUnitTests() {
  UnitTest check(
          String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'Signup wizard (validation)',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  // A fixed "now" so no test depends on the wall clock.
  final now = DateTime.utc(2026, 6, 15);

  return <UnitTest>[
    check(
      'parses a well-formed MM/DD/YYYY birthday',
      'The birthday field accepts the format it asks for, with or without '
          'leading zeros.',
      '''
## What it checks
`parseSignupBirthday` returns the right calendar date for `01/31/1990` and for
the unpadded `1/5/2000`.

## Why it matters
The parsed date is written straight to the profile document's `birthday` field
and drives the age gate. A parse that silently shifts a date would both
misstate the user's age and store the wrong value forever.

## Expected
`01/31/1990` → 1990-01-31, `1/5/2000` → 2000-01-05''',
      (t) {
        t.expectEqual(parseSignupBirthday('01/31/1990'), DateTime(1990, 1, 31));
        t.expectEqual(parseSignupBirthday('1/5/2000'), DateTime(2000, 1, 5));
      },
    ),
    check(
      'rejects dates that only look valid',
      'Out-of-range months and days are refused instead of rolling over into '
          'a different date.',
      '''
## What it checks
`parseSignupBirthday` returns null for `13/01/1990` (no 13th month),
`02/30/1991` (February has no 30th) and for anything not in `MM/DD/YYYY` shape.

## Why it matters
`DateTime` **normalizes** out-of-range parts rather than throwing — month 13
quietly becomes January of the next year. Without the round-trip check inside
the parser, a typo would be accepted as a real, wrong birthday.

## Expected
every malformed input → null''',
      (t) {
        t.expectTrue(parseSignupBirthday('13/01/1990') == null,
            reason: 'month 13 must not roll into the next year');
        t.expectTrue(parseSignupBirthday('02/30/1991') == null,
            reason: 'February 30th must not roll into March');
        t.expectTrue(parseSignupBirthday('1990-01-31') == null,
            reason: 'ISO format is not the format the field asks for');
        t.expectTrue(parseSignupBirthday('') == null,
            reason: 'empty input must not parse');
      },
    ),
    check(
      'counts age by whole years elapsed',
      "A birthday that hasn't come round yet this year does not count.",
      '''
## What it checks
`calculateSignupAge` against a fixed `now` of 2026-06-15: a birthday earlier in
the year has had its anniversary, one later in the year has not, and the
birthday itself counts on the day.

## Why it matters
Off-by-one here is the difference between admitting and refusing a
13-year-old on their birthday.

## Expected
2000-01-01 → 26, 2000-12-31 → 25, 2013-06-15 → 13''',
      (t) {
        t.expectEqual(calculateSignupAge(DateTime(2000, 1, 1), now: now), 26);
        t.expectEqual(calculateSignupAge(DateTime(2000, 12, 31), now: now), 25);
        t.expectEqual(calculateSignupAge(DateTime(2013, 6, 15), now: now), 13);
      },
    ),
    check(
      'holds the age gate at $kMinimumSignupAge',
      'A profile draft under the minimum age is refused; one exactly at it is '
          'allowed.',
      '''
## What it checks
`SignupProfileDraft.isOldEnough` for someone one day short of
$kMinimumSignupAge, exactly $kMinimumSignupAge today, and comfortably older.

## Why it matters
The wizard's first part is the **only** thing standing between an underage
sign-up and account creation — the account is created after part three, so a
draft that passes here becomes a real Firebase user.

## Expected
one day short → false, exactly $kMinimumSignupAge → true, older → true''',
      (t) {
        SignupProfileDraft draftBornOn(DateTime birthday) =>
            SignupProfileDraft(
                firstName: 'Ada', lastName: 'Lovelace', birthday: birthday);

        t.expectFalse(
          draftBornOn(DateTime(2013, 6, 16)).isOldEnough(now: now),
          reason: 'one day short of the minimum age must be refused',
        );
        t.expectTrue(
          draftBornOn(DateTime(2013, 6, 15)).isOldEnough(now: now),
          reason: 'turning $kMinimumSignupAge today must be allowed',
        );
        t.expectTrue(
          draftBornOn(DateTime(1990, 1, 1)).isOldEnough(now: now),
          reason: 'a clearly adult birthday must be allowed',
        );
      },
    ),
    check(
      'requires a first and last name',
      'Blank or whitespace-only names are refused, with the field named in '
          'the message.',
      '''
## What it checks
`validateSignupName` returns an error mentioning the field for null, empty and
whitespace-only input, and null (valid) for a real name.

## Why it matters
The name written here is what appears on the user's marker and profile for
everyone else. A whitespace-only name would produce a blank, unidentifiable
marker on the map.

## Expected
`''`, `'   '`, null → 'Please enter a First Name'; `'Ada'` → no error''',
      (t) {
        t.expectEqual(
            validateSignupName('', 'First Name'), 'Please enter a First Name');
        t.expectEqual(validateSignupName('   ', 'First Name'),
            'Please enter a First Name');
        t.expectEqual(
            validateSignupName(null, 'Last Name'), 'Please enter a Last Name');
        t.expectTrue(validateSignupName('Ada', 'First Name') == null,
            reason: 'a real name must validate');
      },
    ),
    check(
      'refuses a birthday in the future',
      'The birthday field rejects future dates before the age gate ever sees '
          'them.',
      '''
## What it checks
`validateSignupBirthdayField` against a fixed `now`: a future date and a
malformed date both produce an error, a past date does not.

## Why it matters
A future birthday yields a negative age, which the age gate would refuse
anyway — but with a confusing "you must be 13" dialog instead of pointing at
the field the user actually mistyped.

## Expected
future date → 'Birthday cannot be in the future'; `'not a date'` → format
error; past date → no error''',
      (t) {
        t.expectEqual(
          validateSignupBirthdayField('06/16/2026', now: now),
          'Birthday cannot be in the future',
        );
        t.expectEqual(
          validateSignupBirthdayField('not a date', now: now),
          'Please enter a valid date as MM/DD/YYYY',
        );
        t.expectEqual(
          validateSignupBirthdayField('', now: now),
          'Please enter your birthday',
        );
        t.expectTrue(
          validateSignupBirthdayField('01/31/1990', now: now) == null,
          reason: 'a valid past birthday must validate',
        );
      },
    ),
    check(
      'requires the first interest to be named but not described',
      'The interest name is mandatory; its description is optional.',
      '''
## What it checks
`validateSignupInterestName` refuses blank input and accepts a real name. The
description has no validator at all.

## Why it matters
The point of collecting an interest during sign-up is that the user reaches the
map with a non-empty list. A nameless interest would be an unlabelled card, so
the name is required — but demanding a description as well would be a wall
between the user and the app for no gain, since it is editable later.

## Expected
`''`, `'  '` → 'Please name your interest'; `'Astronomy'` → no error''',
      (t) {
        t.expectEqual(
            validateSignupInterestName(''), 'Please name your interest');
        t.expectEqual(
            validateSignupInterestName('   '), 'Please name your interest');
        t.expectTrue(validateSignupInterestName('Astronomy') == null,
            reason: 'a named interest must validate');
      },
    ),
    check(
      'a dragged pin becomes a manual placement',
      'Moving the marker rewrites the position and marks it as chosen by the '
          'user, keeping the zoom they settled on.',
      '''
## What it checks
`SignupLocationDraft.copyWith` applied the way the map step applies it when the
pin is dragged: latitude/longitude replaced, `source` switched to
`manual`, and the untouched `zoom` preserved.

## Why it matters
`source` is what the location part reads to caption the map ("we estimated your
area" vs "your marker will sit exactly here") and it is the difference between
a guessed position and one the user actually chose. Losing the zoom would open
the real map at a different scale than the one they placed the pin at.

## Expected
IP estimate at (10, 20) dragged to (51.5, -0.12) → manual, zoom unchanged''',
      (t) {
        const estimate = SignupLocationDraft(
          latitude: 10,
          longitude: 20,
          zoom: 9,
          source: SignupLocationSource.ipEstimate,
        );

        final dragged = estimate.copyWith(
          latitude: 51.5,
          longitude: -0.12,
          source: SignupLocationSource.manual,
        );

        t.expectClose(dragged.latitude, 51.5, 1e-9);
        t.expectClose(dragged.longitude, -0.12, 1e-9);
        t.expectClose(dragged.zoom, 9, 1e-9,
            reason: 'the zoom the user settled on must survive a drag');
        t.expectTrue(dragged.source == SignupLocationSource.manual,
            reason: 'a dragged pin is a manual placement');
      },
    ),
    check(
      'the wizard has exactly three parts, in order',
      'The progress indicator and the shell agree on how many parts there are '
          'and what each is called.',
      '''
## What it checks
`SignupWizardStep.values` is profile → interest → location, and
`SignupWizardStep.count` is 3.

## Why it matters
The progress header renders one dot per step and prints "Step N of
`count`", while the shell drives navigation off the same enum. Adding a part
without updating both would silently produce a header that disagrees with the
screens the user is actually walking through.

## Expected
3 steps: About you, Your interest, Your location''',
      (t) {
        t.expectEqual(SignupWizardStep.count, 3);
        t.expectEqual(
          SignupWizardStep.values.map((s) => s.label).toList(),
          <String>['About you', 'Your interest', 'Your location'],
        );
      },
    ),
  ];
}
