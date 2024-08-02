import 'package:flutter/material.dart';

class UserModel extends ChangeNotifier {
  String _uid = '';
  String _alternateUid = '';
  String _alternateName = '';
  String get alternateName => _alternateName;
  String get alternateUid => _alternateUid;
  String get currentUid => _uid;

  void changeUid(String newValue) {
    _uid = newValue;
    notifyListeners();
  }
  void changeAlternateUid(String newValue) {
    _alternateUid = newValue;
  }
  void changeAlternateName(String newValue) {
    _alternateName = newValue;
  }
  void notify() {
    notifyListeners();
  }
}