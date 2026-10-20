import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_login/flutter_login.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intrst/login/signup/signup_submission.dart';
import 'package:intrst/login/signup/signup_wizard.dart';
import 'package:intrst/login/signup/signup_wizard_data.dart';
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
  late final SignupSubmission _signupSubmission =
      SignupSubmission(usersUtility: fu);
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

  /// Entry point for the "Sign up" button.
  ///
  /// The email and password are collected by `FlutterLogin`; everything else —
  /// name, age, first interest and marker location — is collected by the
  /// wizard, which runs *before* any account is created. Nothing is written
  /// anywhere until the user finishes all three parts, so an abandoned or
  /// underage sign-up leaves no account and no half-built profile behind.
  Future<String?> _signupUser(SignupData data) async {
    final String email = data.name?.trim() ?? '';
    final String password = data.password ?? '';
    if (email.isEmpty || password.isEmpty) {
      return 'Please enter an email address and password.';
    }

    // Resolves to null once the account exists, or to a message to show on
    // this screen if the user backed out or hit an error only fixable here.
    return SignupWizard.show(
      context,
      email: email,
      onSubmit: (result) => _createAccountFromWizard(email, password, result),
    );
  }

  /// Creates the Auth account and writes every answer the wizard collected.
  ///
  /// Safe to retry: if a previous attempt created the account but failed to
  /// write the profile, the existing session is reused rather than triggering
  /// an "email already in use" error the user cannot act on.
  Future<SignupSubmitError?> _createAccountFromWizard(
      String email, String password, SignupWizardResult result) async {
    User? user = FirebaseAuth.instance.currentUser;
    final bool reusingSession =
        user != null && (user.email?.toLowerCase() == email.toLowerCase());

    if (!reusingSession) {
      try {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        user = credential.user;
      } on FirebaseAuthException catch (e) {
        print('Sign-up error: ${e.code} ${e.message}');
        return _signupErrorFor(e);
      } catch (e) {
        print('Sign-up error: $e');
        return const SignupSubmitError(
            'Sign-up failed. Please check your connection and try again.');
      }
    }

    if (user == null) {
      return const SignupSubmitError(
          'Sign-up failed. Please try again.', fatal: true);
    }

    // The account exists at this point, so a failed verification email is
    // non-fatal: the "verify your email" screen offers a resend. Skipped in
    // debug, where the auth listener bypasses the verification gate anyway.
    if (!kDebugMode && !user.emailVerified) {
      try {
        await user.sendEmailVerification();
        print('Verification email sent to ${user.email}');
      } catch (e) {
        print('Failed to send verification email: $e');
      }
    }

    try {
      await _signupSubmission.submit(
        users: FirebaseFirestore.instance.collection('users'),
        userUid: user.uid,
        result: result,
      );
    } catch (e) {
      print('Failed to create user profile: $e');
      return const SignupSubmitError(
          "We couldn't save your profile. Check your connection and try "
          'again.');
    }

    askNotificationSetting(user.uid);

    // The user stays signed in even though they are unverified: the
    // authStateChanges listener shows the "verify your email" screen and logs
    // them straight in the moment they verify — no second sign-in.
    return null;
  }

  /// Maps a sign-up auth failure onto a wizard error. Failures the user can
  /// only fix back on the login form (the email or password itself) are fatal
  /// and close the wizard; transient ones keep their answers and let them
  /// retry in place.
  SignupSubmitError _signupErrorFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return const SignupSubmitError(
            'An account already exists for that email address.',
            fatal: true);
      case 'invalid-email':
        return const SignupSubmitError(
            "That email address doesn't look right.",
            fatal: true);
      case 'weak-password':
        return const SignupSubmitError(
            'Please choose a stronger password.',
            fatal: true);
      case 'network-request-failed':
        return const SignupSubmitError(
            'No connection. Check your network and try again.');
      default:
        return const SignupSubmitError(
            'Sign-up failed. Please try again.');
    }
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
    );
  }
}