import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
import 'package:intrst/models/Interest.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';

/// Writes a completed [SignupWizardResult] to Firestore.
///
/// The wizard runs *before* the Firebase Auth account exists, so by the time
/// this runs every answer is already in hand and the profile document can be
/// created complete: name and birthday from part one, the seeded interest from
/// part two, and the marker location from part three. That is what lets a new
/// user reach the map with their interest already in the list and their marker
/// already placed — nothing is deferred to a later screen.
///
/// Split out from the widget so it can be driven directly by tests against a
/// fake Firestore instance.
class SignupSubmission {
  SignupSubmission({FirebaseUsersUtility? usersUtility})
      : fu = usersUtility ?? FirebaseUsersUtility();

  final FirebaseUsersUtility fu;

  /// Creates the profile document and its first interest for [userUid].
  ///
  /// Returns the interest that was written so callers can log or surface it.
  /// The profile document is created first and awaited, because
  /// [FirebaseUsersUtility.addInterestForUser] looks the document up by
  /// `user_uid` and silently does nothing when it isn't there yet.
  Future<Interest> submit({
    required CollectionReference users,
    required String userUid,
    required SignupWizardResult result,
  }) async {
    // A retry after a partially-failed attempt must not produce a second
    // profile document: `addUserToFirestore` uses `add()`, so the guard has to
    // live here rather than inside it.
    final QuerySnapshot existing =
        await users.where('user_uid', isEqualTo: userUid).limit(1).get();
    if (existing.docs.isEmpty) {
      await fu.addUserToFirestore(
        users,
        userUid,
        result.profile.firstName,
        result.profile.lastName,
        GeoPoint(result.location.latitude, result.location.longitude),
        result.profile.birthday,
        // The wizard already placed the marker, so the in-app location
        // onboarding screen must not run for this account.
        firstRunExperienceComplete: true,
      );
    }

    final DateTime now = DateTime.now();
    final Interest interest = Interest(
      name: result.interest.name,
      description: result.interest.description,
      link: '',
      created_timestamp: now,
      updated_timestamp: now,
    );

    await fu.addInterestForUser(users, interest, userUid);
    return interest;
  }
}
