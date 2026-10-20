import 'package:firebase_auth/firebase_auth.dart';

/// Who counts as an admin, on the client.
///
/// This mirrors `_is_admin_caller` in [`functions/main.py`] exactly: a caller is
/// an admin if their auth token carries the custom claim `admin == true`, or if
/// their email is on the allowlist. Keeping one rule in one place is the point —
/// the previous gate on the dashboard was `kIsWeb && kDebugMode` alone, which
/// asks *what kind of build is this*, never *who is signed in*, so every user on
/// a web debug build could open it.
///
/// The server-side check in the Cloud Functions remains the real security
/// boundary: `admin_delete_user` and `admin_get_user_emails` are reachable by
/// anyone on the internet and must never trust this. What this class buys is
/// that the dashboard and its entry point stop appearing for people who are not
/// admins, and stop appearing the moment the signed-in user changes.
class AdminAccess {
  const AdminAccess._();

  /// Emails permitted to open the admin dashboard. Must stay in sync with
  /// `ADMIN_EMAILS` in `functions/main.py`; the server list is authoritative.
  static const Set<String> adminEmails = <String>{
    'joss.self@gmail.com',
    'josspaddock@hotmail.com',
  };

  /// The rule itself, as a pure function of an identity.
  ///
  /// Separated from the Firebase lookups so it can be exercised directly by
  /// unit tests — `getIdTokenResult` needs a live Firebase app, but the
  /// decision it feeds does not.
  ///
  /// [adminClaim] is compared against `true` identically to the server, so a
  /// stringly-typed `"true"` in a token grants nothing.
  static bool isAdminIdentity({String? email, Object? adminClaim}) {
    if (adminClaim == true) return true;
    final String normalized = (email ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return adminEmails.contains(normalized);
  }

  /// Whether [user] (defaulting to the currently signed-in user) is an admin.
  ///
  /// A failed token read falls back to the email allowlist rather than
  /// throwing: losing the network should not lock the admin out of a screen
  /// whose privileged operations are re-checked server-side anyway.
  static Future<bool> isAdmin({User? user, bool forceRefresh = false}) async {
    final User? current = user ?? FirebaseAuth.instance.currentUser;
    if (current == null) return false;

    Object? claim;
    try {
      final IdTokenResult token = await current.getIdTokenResult(forceRefresh);
      claim = token.claims?['admin'];
    } catch (e) {
      print('Admin claim lookup failed for ${current.uid}: $e');
    }

    return isAdminIdentity(email: current.email, adminClaim: claim);
  }

  /// Admin status, re-evaluated on every sign-in, sign-out and token refresh.
  ///
  /// `idTokenChanges` rather than `authStateChanges` because a custom claim can
  /// be granted or revoked without the signed-in user changing; it also fires
  /// for sign-in and sign-out, so this covers the case that prompted the fix —
  /// an admin signing out and a test user signing in must flip this to false
  /// without anything having to remember to clear a cached flag.
  static Stream<bool> changes() =>
      FirebaseAuth.instance.idTokenChanges().asyncMap((user) => isAdmin(user: user));
}
