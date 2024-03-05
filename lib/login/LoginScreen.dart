import 'package:flutter/material.dart';
import 'package:flutter_login/flutter_login.dart';

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

  Duration get loginTime => const Duration(milliseconds: 2250);

  Future<String?> _authUser(LoginData data) {
    debugPrint('Name: ${data.name}, Password: ${data.password}');
    return Future.delayed(loginTime).then((_) {
      if (!users.containsKey(data.name)) {
        return 'User does not exist';
      }
      if (users[data.name] != data.password) {
        return 'Password does not match';
      }
      return null;
    });
  }

  Future<String?> _signupUser(SignupData data) {
    debugPrint('Signup Name: ${data.name}, Password: ${data.password}');
    return Future.delayed(loginTime).then((_) {
      return null;
    });
  }

  Future<String?> _recoverPassword(String name) {
    debugPrint('Name: $name');
    return Future.delayed(loginTime).then((_) {
      if (!users.containsKey(name)) {
        return 'User not exists';
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FlutterLogin(
      title: 'intrst',
      //if you want a log above the login widget, add the path to a png, eg below:
      //logo: const AssetImage('assets/images/ecorp-lightblue.png'),
      onLogin: _authUser,
      onSignup: _signupUser,
      onSubmitAnimationCompleted: () {
        debugPrint("onSubmitAnimationCompleted: User logged in");
        widget.onSignInChanged(true);
        widget.onSelectedIndexChanged(0);
      },
      onRecoverPassword: _recoverPassword,
    );
  }
}