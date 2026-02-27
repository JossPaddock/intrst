import 'package:flutter/material.dart';
import 'dart:async';

class UserModel extends ChangeNotifier {
  static final UserModel _instance = UserModel._internal();
  factory UserModel() => _instance;
  UserModel._internal();

  String _uid = '';
  String _alternateUid = '';
  String _alternateName = '';
  String _feedHighlightedInterestId = '';
  String _feedHighlightedInterestOwnerUid = '';
  Timer? _feedHighlightTimer;
  String get alternateName => _alternateName;
  String get alternateUid => _alternateUid;
  String get currentUid => _uid;
  String get feedHighlightedInterestId => _feedHighlightedInterestId;
  String get feedHighlightedInterestOwnerUid =>
      _feedHighlightedInterestOwnerUid;
  Map<String, bool> _editToggles = {};
  Map<String, bool> get editToggles => _editToggles;
  bool draggability = false;
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

  void setFeedInterestHighlight({
    required String ownerUid,
    required String interestId,
    Duration duration = const Duration(seconds: 15),
  }) {
    _feedHighlightTimer?.cancel();
    final sanitizedOwnerUid = ownerUid.trim();
    final sanitizedInterestId = interestId.trim();
    if (sanitizedOwnerUid.isEmpty || sanitizedInterestId.isEmpty) {
      _feedHighlightedInterestId = '';
      _feedHighlightedInterestOwnerUid = '';
      notifyListeners();
      return;
    }

    _feedHighlightedInterestOwnerUid = sanitizedOwnerUid;
    _feedHighlightedInterestId = sanitizedInterestId;
    notifyListeners();

    _feedHighlightTimer = Timer(duration, () {
      if (_feedHighlightedInterestOwnerUid == sanitizedOwnerUid &&
          _feedHighlightedInterestId == sanitizedInterestId) {
        _feedHighlightedInterestOwnerUid = '';
        _feedHighlightedInterestId = '';
        notifyListeners();
      }
    });
  }

  void clearFeedInterestHighlight() {
    _feedHighlightTimer?.cancel();
    _feedHighlightedInterestId = '';
    _feedHighlightedInterestOwnerUid = '';
    notifyListeners();
  }

  void notify() {
    notifyListeners();
  }

  void changeDraggability(bool value) {
    print('Changing draggability to $value');
    draggability = value;
  }

  @override
  void dispose() {
    _feedHighlightTimer?.cancel();
    super.dispose();
  }
}
