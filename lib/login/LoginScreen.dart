import 'package:flutter/material.dart';
import 'package:flutter_login/flutter_login.dart';
//this is for Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:name_app/utility/FirebaseUtility.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
const users =  {
  'test@test.com': 'password',
};

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.signedIn = false,
    required this.onSignInChanged,
    required this.onSelectedIndexChanged,
  });

  final bool signedIn;
  final ValueChanged<bool> onSignInChanged;
  final ValueChanged<int> onSelectedIndexChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseUtility fu = FirebaseUtility();
  final FirebaseAuth firebaseAuth = FirebaseAuth.instance;
  Duration get loginTime => const Duration(milliseconds: 2250);

  Future<String?> _signInUser(LoginData data) {
    debugPrint('Name: ${data.name}, Password: ${data.password}');
    return Future.delayed(loginTime).then((_) async {
      String email = data.name??"";
      String password = data.password??"";
      bool result = await _signIn(email, password);
      if (result == false) {
        if (!users.containsKey(data.name) && users[data.name] != data.password) {
          return 'User does not exist or password does not match';
        }
      }
      return null;
    });
  }

  Future<bool> _signIn(String email, String password) async {
    var result = false;
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password
      );
      result = true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        print('No user found for that email.');
      } else if (e.code == 'wrong-password') {
        print('Wrong password provided for that user.');
      }
      result = false;
    }
    return result;
  }

  Future<String?> _signupUser(SignupData data) async {
    debugPrint('Signup Name: ${data.name}, Password: ${data.password}');
    if(data.name is String && data.password is String) {
      String email = data.name??"";
      String password = data.password??"";
      await _createNewUser(email, password);
      CollectionReference users = FirebaseFirestore.instance.collection('users');
      User? userSnapshot;
      if (FirebaseAuth.instance.currentUser != null) {
        print(FirebaseAuth.instance.currentUser?.uid);
        userSnapshot = FirebaseAuth.instance.currentUser;
      }
      fu.addUserToFirestore(users, userSnapshot!.uid, data.additionalSignupData?.entries.firstWhere((element) => element.key == 'firstname').value ?? 'Bob', data.additionalSignupData?.entries.firstWhere((element) => element.key == 'lastname').value ?? 'Watkins', GeoPoint(0,0) );
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
      title: 'intrst',
      //if you want a log above the login widget, add the path to a png, eg below:
      //logo: const AssetImage('assets/images/ecorp-lightblue.png'),
      onLogin: _signInUser,
      onSignup: _signupUser,
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
                if(value == null) {
                  return "Value was null!";
                } else {
                  if(value.isEmpty) {
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
                if(value == null) {
                  return "Value was null!";
                } else {
                  if(value.isEmpty) {
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