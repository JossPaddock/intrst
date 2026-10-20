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

  // One-shot request for the interests drawer to open [interestId] already
  // expanded (e.g. the user tapped a notification about it). CardList
  // consumes it via [takeInterestFocusRequest] once that interest is loaded.
  String _focusRequestInterestId = '';
  String _focusRequestOwnerUid = '';

  void requestInterestFocus({
    required String ownerUid,
    required String interestId,
  }) {
    _focusRequestOwnerUid = ownerUid.trim();
    _focusRequestInterestId = interestId.trim();
  }

  // Returns the pending focus request for [ownerUid]'s interests if it names
  // one of [availableIds], clearing it so it only applies once. Doesn't
  // notify: it's called from build.
  String? takeInterestFocusRequest(
    String ownerUid,
    Iterable<String> availableIds,
  ) {
    if (_focusRequestInterestId.isEmpty ||
        _focusRequestOwnerUid != ownerUid ||
        !availableIds.contains(_focusRequestInterestId)) {
      return null;
    }
    final id = _focusRequestInterestId;
    _focusRequestInterestId = '';
    _focusRequestOwnerUid = '';
    return id;
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
