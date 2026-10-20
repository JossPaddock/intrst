import '../../utility/AdminAccess.dart';
import 'unit_test.dart';

/// Unit coverage for [AdminAccess.isAdminIdentity] — the rule that decides who
/// may open the admin dashboard.
///
/// This exists because the dashboard's original gate was `kIsWeb && kDebugMode`
/// alone: it asked what kind of build was running and never who was signed in,
/// so on a debug web build any user — a test account included — could open it.
/// The rule below replaces that, and mirrors `_is_admin_caller` in
/// `functions/main.py` so the client and the server cannot disagree about what
/// "admin" means.
///
/// The server remains the security boundary: `admin_delete_user` and
/// `admin_get_user_emails` re-check every caller. These tests are about the
/// screen not being offered to, or rendered for, the wrong person.
List<UnitTest> adminAccessUnitTests() {
  UnitTest check(
          String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'AdminAccess (admin dashboard gate)',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  return <UnitTest>[
    check(
      'admits an allowlisted email',
      'An email on the allowlist is an admin, whatever its casing or '
          'surrounding whitespace.',
      '''
## What it checks
`isAdminIdentity` is true for every address in [AdminAccess.adminEmails], and
stays true when that address arrives upper-cased or padded with whitespace.

## Why it matters
Firebase reports `user.email` as the user typed it at sign-up, so an admin who
registered with mixed casing must not be locked out by an exact-string compare.
The server lowercases both sides for the same reason.

## Expected
each allowlisted address, and `' JOSS.SELF@GMAIL.COM '` → admin''',
      (t) {
        for (final email in AdminAccess.adminEmails) {
          t.expectTrue(AdminAccess.isAdminIdentity(email: email),
              reason: '$email is on the allowlist');
        }
        t.expectTrue(
          AdminAccess.isAdminIdentity(email: ' JOSS.SELF@GMAIL.COM '),
          reason: 'casing and whitespace must not matter',
        );
      },
    ),
    check(
      'refuses everyone else',
      'A signed-in user who is not on the allowlist and holds no admin claim '
          'is not an admin.',
      '''
## What it checks
`isAdminIdentity` is false for an ordinary user's email, for the project's own
test accounts, and for an email that merely *contains* an allowlisted one.

## Why it matters
This is the exact failure that prompted the gate: signing out of the admin
account and back in as `permanent@test.com` left the dashboard reachable.
The substring case matters separately — `joss.self@gmail.com.attacker.tld` must
not pass a sloppy `contains` check.

## Expected
`permanent@test.com`, `someone@example.com`,
`joss.self@gmail.com.attacker.tld` → not admin''',
      (t) {
        t.expectFalse(AdminAccess.isAdminIdentity(email: 'permanent@test.com'),
            reason: 'the permanent test account is not an admin');
        t.expectFalse(AdminAccess.isAdminIdentity(email: 'someone@example.com'),
            reason: 'an ordinary user is not an admin');
        t.expectFalse(
          AdminAccess.isAdminIdentity(email: 'joss.self@gmail.com.attacker.tld'),
          reason: 'an allowlisted address as a prefix must not match',
        );
      },
    ),
    check(
      'treats a signed-out identity as not an admin',
      'No email and no claim is never an admin — the gate fails closed.',
      '''
## What it checks
`isAdminIdentity` is false for a null email, an empty email and a
whitespace-only email, with no claim present.

## Why it matters
[AdminAccess.isAdmin] returns false before ever calling this when there is no
signed-in user, but the rule itself must fail closed too: a token read that
comes back without an email must not be able to grant access by default.

## Expected
null, `''`, `'   '` → not admin''',
      (t) {
        t.expectFalse(AdminAccess.isAdminIdentity(),
            reason: 'no identity at all is not an admin');
        t.expectFalse(AdminAccess.isAdminIdentity(email: ''),
            reason: 'an empty email is not an admin');
        t.expectFalse(AdminAccess.isAdminIdentity(email: '   '),
            reason: 'a whitespace-only email is not an admin');
      },
    ),
    check(
      'honours the admin custom claim',
      'A token carrying `admin: true` is an admin regardless of its email.',
      '''
## What it checks
`isAdminIdentity` is true when `adminClaim` is the boolean `true`, even for an
email that is not on the allowlist.

## Why it matters
The custom claim is how an admin is granted without an app release, and the
server accepts it the same way. A client that ignored it would hide the
dashboard from someone the server considers an admin.

## Expected
`someone@example.com` + `admin: true` → admin''',
      (t) {
        t.expectTrue(
          AdminAccess.isAdminIdentity(
              email: 'someone@example.com', adminClaim: true),
          reason: 'the admin custom claim grants access on its own',
        );
      },
    ),
    check(
      'accepts only a boolean true claim',
      'A truthy-looking claim that is not the boolean `true` grants nothing.',
      '''
## What it checks
`isAdminIdentity` is false when `adminClaim` is the string `'true'`, the number
`1`, or `false`, for a non-allowlisted email.

## Why it matters
Custom claims are arbitrary JSON, so the value's *type* is not guaranteed. The
server compares with `is True`, which rejects `"true"` and `1`; the client
compares against the boolean for the same reason, so the two can never disagree
about a malformed claim.

## Expected
`'true'`, `1`, `false` → not admin''',
      (t) {
        t.expectFalse(
          AdminAccess.isAdminIdentity(
              email: 'someone@example.com', adminClaim: 'true'),
          reason: 'a string claim must not be treated as boolean true',
        );
        t.expectFalse(
          AdminAccess.isAdminIdentity(
              email: 'someone@example.com', adminClaim: 1),
          reason: 'a numeric claim must not be treated as boolean true',
        );
        t.expectFalse(
          AdminAccess.isAdminIdentity(
              email: 'someone@example.com', adminClaim: false),
          reason: 'an explicitly false claim must not grant access',
        );
      },
    ),
    check(
      'an allowlisted admin stays one without a claim',
      'The two conditions are independent: either alone is enough, and a '
          'false claim does not veto the allowlist.',
      '''
## What it checks
An allowlisted email with `adminClaim: null` is an admin, and so is one with
`adminClaim: false`.

## Why it matters
[AdminAccess.isAdmin] falls back to the email alone when the token read fails
(no network, expired session). If a missing or false claim vetoed the
allowlist, a dropped connection would lock the admin out of a screen whose
privileged actions are re-checked server-side anyway.

## Expected
allowlisted email + no claim → admin; + `false` claim → admin''',
      (t) {
        t.expectTrue(
          AdminAccess.isAdminIdentity(email: 'joss.self@gmail.com'),
          reason: 'the allowlist works without any claim',
        );
        t.expectTrue(
          AdminAccess.isAdminIdentity(
              email: 'joss.self@gmail.com', adminClaim: false),
          reason: 'a false claim must not veto the allowlist',
        );
      },
    ),
  ];
}
