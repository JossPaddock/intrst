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

  /// Blocking dialog shown to an authenticated-but-unverified user. Must be
  /// called while [user] is still signed in (before any signOut) so the
  /// "Resend email" action can use the live [User] object. Returns once the
  /// user dismisses it; the caller is responsible for signing out afterwards.
  Future<void> _showVerifyEmailDialog(User user) async {
    if (!mounted) return;
    final String emailLabel = user.email ?? 'your email address';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String? statusMessage;
        bool isError = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify your email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Please verify your email to continue using the intrst app.\n\n'
                    'We sent a verification link to $emailLabel. '
                    'Please check your inbox — and your junk/spam folder.',
                  ),
                  if (statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        statusMessage!,
                        style: TextStyle(
                          color: isError ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    try {
                      await user.sendEmailVerification();
                      setDialogState(() {
                        isError = false;
                        statusMessage = 'Verification email resent to $emailLabel.';
                      });
                    } catch (e) {
                      print('Failed to resend verification email: $e');
                      setDialogState(() {
                        isError = true;
                        statusMessage =
                            'Could not resend right now. Please try again shortly.';
                      });
                    }
                  },
                  child: const Text('Resend email'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
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

      // --- Email verification gate (skipped in debug mode) ---
      // Unverified users cannot enter the app. Show a blocking dialog (with a
      // "Resend email" action) while still signed in, then sign out so the
      // authStateChanges listener keeps the app in its signed-out state.
      if (!kDebugMode && user != null && !user.emailVerified) {
        await _showVerifyEmailDialog(user);
        await FirebaseAuth.instance.signOut();
        return null; // Dialog already informed the user; stay signed-out.
      }

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

  Future<String?> _signupUser(SignupData data) async {
    debugPrint('Signup Name: ${data.name}, Password: ${data.password}');

    if (data.name is String && data.password is String) {
      String email = data.name ?? '';
      String password = data.password ?? '';

      final credential = await _createNewUser(email, password);
      if (credential == null) {
        return 'Sign-up failed. The email may already be in use.';
      }

      final user = credential.user!;

      // Send verification email in production; skip in debug for convenience.
      // The account already exists at this point, so a send failure is
      // non-fatal: we log it and continue. The user can get a fresh link by
      // attempting to log in (the sign-in gate resends — see _signIn).
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

      // Safely access additional signup data to avoid crashes.
      var firstname = data.additionalSignupData?['firstname'] ?? 'Bob';
      var lastname = data.additionalSignupData?['lastname'] ?? 'Watkins';

      try {
        // MUST await this call before potential sign-out to ensure document creation.
        await fu.addUserToFirestore(
            users, user.uid, firstname, lastname, GeoPoint(0, 0));
      } catch (e) {
        print('Failed to create user doc: $e');
        return 'Failed to create user profile. Please try again.';
      }

      askNotificationSetting(user.uid);

      // In production, block the user behind the verification dialog and then
      // sign out so they must verify before entering the app. We deliberately
      // do NOT set _signedIn/_name/_uid: the user is not verified yet, and the
      // authStateChanges listener keeps the app in a clean signed-out state
      // until they verify and sign in.
      if (!kDebugMode) {
        await _showVerifyEmailDialog(user);
        await FirebaseAuth.instance.signOut();
      }
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
        // The verification instructions are delivered via the blocking dialog
        // (_showVerifyEmailDialog), so this just confirms account creation.
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
      ],
    );
  }
}