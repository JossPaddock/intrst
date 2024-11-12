import 'package:flutter/material.dart';

class UserModel extends ChangeNotifier {
  String _uid = '';
  String _alternateUid = '';
  String _alternateName = '';
  String get alternateName => _alternateName;
  String get alternateUid => _alternateUid;
  String get currentUid => _uid;
  Map<String, bool> _editToggles = {};
  Map<String, bool> get editToggles => _editToggles;
  bool getToggle(String interestId) {
    return _editToggles[interestId] ?? false;
  }
  void updateToggle(String interestId, bool toggle) {
    _editToggles[interestId] = toggle;
    notifyListeners();
  }
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