import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_login/flutter_login.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const users = {
  'test@test.com': 'password',
};

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.signedIn = false,
    required this.onSelectedIndexChanged,
  });

  // Sign-in state (_signedIn/_name/_uid) is owned entirely by the
  // authStateChanges listener in home_user_logic. LoginScreen only needs to
  // request navigation once an auth flow completes, hence the lone callback.
  final bool signedIn;
  final ValueChanged<int> onSelectedIndexChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  Duration get loginTime => const Duration(milliseconds: 2250);

  void askNotificationSetting(String uid) async {
    final notificationSettings =
    await FirebaseMessaging.instance.requestPermission(provisional: true);

    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken != null) {
      print('APNs token is available: $apnsToken');
    } else {
      print('APNs token is NOT available');
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('fcm token is available: $fcmToken');
      fu.addFcmTokenForUser(uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }

    NotificationSettings notifSettings =
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String permissionMessage = switch (notifSettings.authorizationStatus.name) {
      'authorized' =>
      'Thank you, the intrst app can now send you notifications!',
      'denied' => 'The intrst app is not authorized to create notifications.',
      'notDetermined' =>
      'Your permission status for notifications is not determined yet',
      'provisional' =>
      'The intrst app is currently authorized to post non-interrupting user notifications.',
      _ => 'There has been an error',
    };
    print(permissionMessage);
  }

  Future<String?> _signInUser(LoginData data) {
    debugPrint('Name: ${data.name}, Password: ${data.password}');
    return Future.delayed(loginTime).then((_) async {
      String email = data.name ?? '';
      String password = data.password ?? '';
      return await _signIn(email, password);
    });
  }

  /// Returns null on success, or an error string to display to the user.
  Future<String?> _signIn(String email, String password) async {
    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      // No verification gate here: the authStateChanges listener decides what
      // to do. A verified user enters the app; an unverified one is routed to
      // the "verify your email" screen and auto-logged-in once they verify.

      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        print('Web persistence set to LOCAL');
      } else {
        print('Skipping setPersistence on non-web platform');
      }

      // NOTE: Do NOT set _signedIn/_name/_uid here. The authStateChanges
      // listener in home_user_logic is the single source of truth and will
      // populate them once it observes this verified sign-in.
      final localUid = user!.uid;
      askNotificationSetting(localUid);

      return null; // success
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No account found for that email.';
        case 'wrong-password':
          return 'Incorrect password.';
        case 'invalid-credential':
          return 'Invalid email or password.';
        default:
          print(
              'Login error — code: ${e.code}, message: ${e.message}, stack: ${e.stackTrace}');
          return 'An error occurred. Please try again.';
      }
    }
  }

  /// Parses a birthday entered as `MM/DD/YYYY`. Returns null if the string
  /// isn't a valid calendar date in that format.
  DateTime? _parseBirthday(String input) {
    final match =
    RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(input.trim());
    if (match == null) return null;

    final month = int.parse(match.group(1)!);
    final day = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);

    final date = DateTime(year, month, day);
    // DateTime normalizes out-of-range values (e.g. month 13) instead of
    // throwing, so confirm the parts round-trip to catch invalid dates.
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  int _calculateAge(DateTime birthday) {
    final now = DateTime.now();
    int age = now.year - birthday.year;
    if (now.month < birthday.month ||
        (now.month == birthday.month && now.day < birthday.day)) {
      age--;
    }
    return age;
  }

  Future<void> _showUnderageDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Age Restriction'),
          content: const Text(
              'You must be at least 13 years of age to use the intrst app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _signupUser(SignupData data) async {
    debugPrint('Signup Name: ${data.name}, Password: ${data.password}');

    if (data.name is String && data.password is String) {
      String email = data.name ?? '';
      String password = data.password ?? '';

      // Safely access additional signup data to avoid crashes.
      var firstname = data.additionalSignupData?['firstname'] ?? 'Bob';
      var lastname = data.additionalSignupData?['lastname'] ?? 'Watkins';
      final birthdayInput = data.additionalSignupData?['birthday'];
      final birthday =
      birthdayInput is String ? _parseBirthday(birthdayInput) : null;

      if (birthday == null) {
        return 'Please enter a valid birthday as MM/DD/YYYY.';
      }

      // Enforce the age gate before creating the Firebase Auth account so
      // no account is ever created for an underage signup attempt.
      if (_calculateAge(birthday) < 13) {
        if (mounted) {
          await _showUnderageDialog();
        }
        return 'You must be at least 13 years of age to use the intrst app.';
      }

      final credential = await _createNewUser(email, password);
      if (credential == null) {
        return 'Sign-up failed. The email may already be in use.';
      }

      final user = credential.user!;

      // Send verification email in production; skip in debug for convenience.
      // The account already exists at this point, so a send failure is
      // non-fatal: we log it and continue. The user is kept signed in and the
      // authStateChanges listener routes them to the "verify your email"
      // screen, which also offers a resend.
      if (!kDebugMode) {
        try {
          await user.sendEmailVerification();
          print('Verification email sent to ${user.email}');
        } catch (e) {
          print('Failed to send verification email: $e');
        }
      } else {
        print('Debug mode: skipping email verification for ${user.email}');
      }

      CollectionReference users =
      FirebaseFirestore.instance.collection('users');

      try {
        // MUST await this call before potential sign-out to ensure document creation.
        await fu.addUserToFirestore(
            users, user.uid, firstname, lastname, GeoPoint(0, 0), birthday);
      } catch (e) {
        print('Failed to create user doc: $e');
        return 'Failed to create user profile. Please try again.';
      }

      askNotificationSetting(user.uid);

      // We deliberately keep the user signed in (no signOut) even though they
      // are unverified. The authStateChanges listener sees the unverified
      // session and shows the "verify your email" screen, then polls and logs
      // them in automatically the moment they verify — no second sign-in.
    }

    return Future.delayed(loginTime).then((_) => null);
  }

  Future<UserCredential?> _createNewUser(
      String email, String password) async {
    try {
      return await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'weak-password':
          print('The password provided is too weak.');
        case 'email-already-in-use':
          print('The account already exists for that email.');
        default:
          print('Sign-up error: ${e.code}');
      }
    } catch (e) {
      print(e);
    }
    return null;
  }

  Future<String?> _recoverPassword(String email) async {
    debugPrint('Email: $email');
    await _sendPasswordResetEmail(email);
    return Future.delayed(loginTime).then((_) {
      return 'Sent reset email to $email';
    });
  }

  Future<bool> _sendPasswordResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return true;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          print('No user found for that email.');
        case 'invalid-email':
          print('This is not a valid email.');
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlutterLogin(
      headerWidget: kDebugMode
          ? ElevatedButton(
          onPressed: () {
            // The authStateChanges listener flips _signedIn once Firebase
            // reports the signed-in user; we only handle navigation here.
            _signInUser(LoginData(
                name: 'permanent@test.com', password: 'password'));
            widget.onSelectedIndexChanged(0);
          },
          child: Text(
              'auto login : ${FirebaseAuth.instance.currentUser?.uid}'))
          : null,
      title: '',
      logo: const AssetImage('assets/intrstlogo2.20White.png'),
      onLogin: _signInUser,
      onSignup: _signupUser,
      messages: LoginMessages(
        // After sign-up the app routes straight to the "verify your email"
        // screen (driven by the auth listener), so this just confirms creation.
        signUpSuccess: 'Account created!',
      ),
      theme: LoginTheme(
        primaryColor: Color(0xFF082D38),
        accentColor: Colors.amber,
        errorColor: Colors.red,
        pageColorLight: Color(0xFF082D38),
        pageColorDark: Colors.blueGrey[900],
      ),
      onSubmitAnimationCompleted: () {
        debugPrint('onSubmitAnimationCompleted: animation finished');
        // Do NOT force _signedIn=true here. After a production sign-up the
        // user has been signed out for verification, and forcing signed-in
        // was the cause of the "half signed-in" state. Sign-in state is
        // owned solely by the authStateChanges listener; we only navigate.
        widget.onSelectedIndexChanged(0);
      },
      onRecoverPassword: _recoverPassword,
      additionalSignupFields: [
        UserFormField(
          keyName: 'firstname',
          displayName: 'First Name',
          userType: LoginUserType.firstName,
          fieldValidator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a First Name';
            }
            return null;
          },
        ),
        UserFormField(
          keyName: 'lastname',
          displayName: 'Last Name',
          userType: LoginUserType.lastName,
          fieldValidator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a Last Name';
            }
            return null;
          },
        ),
        UserFormField(
          keyName: 'birthday',
          displayName: 'Birthday (MM/DD/YYYY)',
          userType: LoginUserType.text,
          fieldValidator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your birthday';
            }
            final birthday = _parseBirthday(value);
            if (birthday == null) {
              return 'Please enter a valid date as MM/DD/YYYY';
            }
            if (birthday.isAfter(DateTime.now())) {
              return 'Birthday cannot be in the future';
            }
            return null;
          },
        ),
      ],
    );
  }
}