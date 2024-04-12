import 'package:flutter/material.dart';

class UserModel extends ChangeNotifier {
  /// Internal, private state of the cart.
  String _uid = '';

  String get currentUid => _uid;

  void changeUid(String newValue) {
    _uid = newValue;
    print("IN THE CHANGEUID METHOD INSIDE OF USERMODEL newValue: $newValue");
    // This call tells the widgets that are listening to this model to rebuild.
    notifyListeners();
  }
}