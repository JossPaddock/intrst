import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_login/flutter_login.dart';
//this is for Firebase
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
    required this.onSignInChanged,
    required this.onNameChanged,
    required this.onUidChanged,
    required this.onSelectedIndexChanged,
  });

  final bool signedIn;
  final ValueChanged<bool> onSignInChanged;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onUidChanged;
  final ValueChanged<int> onSelectedIndexChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  Duration get loginTime => const Duration(milliseconds: 2250);

  void askNotificationSetting(String uid) async{
    final notificationSettings = await FirebaseMessaging.instance
        .requestPermission(provisional: true);

// For apple platforms, ensure the APNS token is available before making any FCM plugin API calls
    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken != null) {
      // APNS token is available, make FCM plugin API requests...
      print('APNs token is available: ${apnsToken}');
    } else {
      print('APNs token is NOT available');
    }
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('fcm token is available: ${fcmToken}');
      fu.addFcmTokenForUser(uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }
    NotificationSettings notifSettings = await FirebaseMessaging
        .instance
        .requestPermission(alert: true, badge: true, sound: true);
    String permissionMessage = '';
    switch(notifSettings.authorizationStatus.name) {
      case 'authorized' : permissionMessage = "Thank you, the intrst app can now send you notifications!";
      case 'denied' : permissionMessage = "The intrst app is not authorized to create notifications.";
      case 'notDetermined' : permissionMessage = "Your permission status for notifications is not determined yet";
      case 'provisional' : permissionMessage = "The intrst app is currently authorized to post non-interrupting user notifications.";
      default: permissionMessage = "There has been an error";

    };
    print(permissionMessage);
  }

  Future<String?> _signInUser(LoginData data) {
    debugPrint('Name: ${data.name}, Password: ${data.password}');
    return Future.delayed(loginTime).then((_) async {
      String email = data.name ?? "";
      String password = data.password ?? "";
      bool result = await _signIn(email, password);
      if (result == false) {
        if (!users.containsKey(data.name) &&
            users[data.name] != data.password) {
          return 'User does not exist or password does not match';
        }
      }
      return null;
    });
  }

  Future<bool> _signIn(String email, String password) async {
    var result = false;
    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      result = true;
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        print('Web persistence set to LOCAL');
      } else {
        print('Skipping setPersistence on non-web platform');
      }
      print(FirebaseAuth.instance.currentUser?.uid);
      CollectionReference users =
          FirebaseFirestore.instance.collection('users');
      String localUid = FirebaseAuth.instance.currentUser!.uid;
      String name = await fu.lookUpNameByUserUid(users, localUid);
      print(name);
      widget.onNameChanged(name);
      widget.onUidChanged(localUid);
      askNotificationSetting(localUid);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        print('No user found for that email.');
      } else if (e.code == 'wrong-password') {
        print('Wrong password provided for that user.');
      } else {
        print(
            'some login error has occured e.code: ${e.code} and e.detailMessage: ${e.message} and e.stackTrace: ${e.stackTrace.toString()}');
      }
      result = false;
    }
    return result;
  }

  Future<String?> _signupUser(SignupData data) async {
    debugPrint('Signup Name: ${data.name}, Password: ${data.password}');
    if (data.name is String && data.password is String) {
      String email = data.name ?? "";
      String password = data.password ?? "";
      await _createNewUser(email, password);
      CollectionReference users =
          FirebaseFirestore.instance.collection('users');
      User? userSnapshot;
      if (FirebaseAuth.instance.currentUser != null) {
        print(FirebaseAuth.instance.currentUser?.uid);
        userSnapshot = FirebaseAuth.instance.currentUser;
      } else {
        print('the current user is null');
      }
      var firstname = data.additionalSignupData?.entries
              .firstWhere((element) => element.key == 'firstname')
              .value ??
          'Bob';
      var lastname = data.additionalSignupData?.entries
              .firstWhere((element) => element.key == 'lastname')
              .value ??
          'Watkins';
      fu.addUserToFirestore(
          users, userSnapshot!.uid, firstname, lastname, GeoPoint(0, 0));
      widget.onNameChanged('$firstname $lastname');
      widget.onUidChanged(userSnapshot.uid);
      askNotificationSetting(userSnapshot.uid);
    }
    return Future.delayed(loginTime).then((_) {
      return null;
    });
  }

  Future<UserCredential?> _createNewUser(String email, String password) async {
    var credential = null;
    try {
      credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        print('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        print('The account already exists for that email.');
      }
    } catch (e) {
      print(e);
    }
    return credential;
  }

  Future<String?> _recoverPassword(String email) async {
    debugPrint('Email: $email');
    bool result = await _sendPasswordResetEmail(email);
    return Future.delayed(loginTime).then((_) {
      return "sent reset email to $email";
    });
  }

  Future<bool> _sendPasswordResetEmail(String email) async {
    var result = false;
    try {
      final credential = await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );
      result = true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        print('No user found for that email.');
      } else if (e.code == 'invalid-email') {
        print('This is not a valid email');
      }
      result = false;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FlutterLogin(
      headerWidget: kDebugMode
          ? ElevatedButton(
              onPressed: () {
                _signInUser(LoginData(name: 'permanent@test.com', password: 'password'));
                widget.onSignInChanged(true);
                widget.onSelectedIndexChanged(0);
              },
              child: Text('auto login : ${FirebaseAuth.instance.currentUser?.uid}'))
          : null,
      title: '',
      //if you want a logo above the login widget, add the path to a png, eg below:
      logo: const AssetImage('assets/intrstlogo2.20White.png'),
      onLogin: _signInUser,
      onSignup: _signupUser,
      messages: LoginMessages(signUpSuccess: 'You have signed up'),
      theme: LoginTheme(
        primaryColor: Color(0xFF082D38), // Overall primary color
        accentColor: Colors
            .amber, // Secondary color (e.g., for title text, loading icon)
        errorColor: Colors.red, // Color for input validation errors
        pageColorLight:
            Color(0xFF082D38), // Light background color for the page
        pageColorDark:
            Colors.blueGrey[900], // Dark background color for the page
      ),
      onSubmitAnimationCompleted: () {
        debugPrint("onSubmitAnimationCompleted: User logged in");
        widget.onSignInChanged(true);
        widget.onSelectedIndexChanged(0);
      },
      onRecoverPassword: _recoverPassword,
      additionalSignupFields: [
        UserFormField(
          keyName: 'firstname',
          displayName: 'First Name',
          userType: LoginUserType.firstName,
          fieldValidator: (value) {
            if (value == null) {
              return "Value was null!";
            } else {
              if (value.isEmpty) {
                return "Please enter a First Name";
              } else {
                return null;
              }
            }
          },
        ),
        UserFormField(
          keyName: 'lastname',
          displayName: 'Last Name',
          userType: LoginUserType.lastName,
          fieldValidator: (value) {
            if (value == null) {
              return "Value was null!";
            } else {
              if (value.isEmpty) {
                return "Please enter a Last Name";
              } else {
                return null;
              }
            }
          },
        ),
      ],
    );
  }
}
