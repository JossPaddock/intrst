import 'package:flutter/material.dart';

class UserModel extends ChangeNotifier {
  String _uid = '';

  String get currentUid => _uid;

  void changeUid(String newValue) {
    _uid = newValue;
    notifyListeners();
  }
  void notify() {
    notifyListeners();
  }
}