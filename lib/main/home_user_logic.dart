part of 'package:intrst/main.dart';

extension _HomeUserLogic on _MyHomePageState {
  void loadFCMToken() async {
    // You may set the permission requests to "provisional" which allows the user to choose what type
    // of notifications they would like to receive once the user receives a notification.
    final notificationSettings =
        await FirebaseMessaging.instance.requestPermission(provisional: true);

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
      fu.addFcmTokenForUser(_uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }
  }

  Future<void> loadUserContext() async {
    if (_uid.trim().isNotEmpty) {
      try {
        await fu.ensureProfileStatisticsDefaults(
            FirebaseFirestore.instance.collection('users'), _uid);
      } catch (e) {
        print('Failed to initialize profile statistics defaults: $e');
      }
    }
    _loadNotificationCount();
    _notificationLoading = Timer.periodic(Duration(seconds: 10), (timer) {
      print(
          'Attempting to load user notifications timestamp: ${DateTime.now()}');
      _loadNotificationCount();
    });
  }

  Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      name: 'intrst',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await captureInitialMessage();
    // The Firebase auth listener is the SINGLE source of truth for sign-in
    // state. Nothing else (LoginScreen callbacks, animation completion, etc.)
    // should set `_signedIn`/`_name`/`_uid` — doing so previously let the UI
    // and the real auth state diverge into a "half signed-in" state.
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      // Bump the generation for every event. Any continuation that awaits
      // before committing state must re-check this to discard stale events.
      final int generation = ++_authStateGeneration;

      // Truly signed out.
      if (user == null) {
        _enterSignedOutState();
        return;
      }

      // Authenticated but email not verified (bypassed in debug): hold the user
      // on the "verify your email" screen and poll until they verify, then log
      // them in automatically — no second sign-in required.
      if (!kDebugMode && !user.emailVerified) {
        _enterPendingVerificationState(user);
        return;
      }

      // Authenticated and verified — enter the app.
      await _enterSignedInState(user, generation);
    });
  }

  /// Resets all session state to signed-out. Single place that clears identity.
  void _enterSignedOutState() {
    print('User is currently signed out!');
    _notificationLoading?.cancel();
    _emailVerificationPoll?.cancel();
    _emailVerificationPoll = null;
    _hasPerformedInitialSignedInMapSetup = false;
    _pendingMapFocusUserUid = null;
    _lastTrackedUsageDayKey = '';
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _awaitingEmailVerification = false;
      _uid = '';
      _name = '';
      _selectedIndex = 0;
    });
    _handleUserModel('');
  }

  /// Holds an authenticated-but-unverified user on the verification screen and
  /// begins polling for verification. We intentionally keep their Firebase
  /// session alive (no signOut) so that verifying logs them straight in.
  void _enterPendingVerificationState(User user) {
    print('User signed in but email not verified; awaiting verification.');
    _notificationLoading?.cancel();
    _hasPerformedInitialSignedInMapSetup = false;
    _pendingMapFocusUserUid = null;
    _lastTrackedUsageDayKey = '';
    if (mounted) {
      setState(() {
        _signedIn = false;
        _awaitingEmailVerification = true;
        _uid = '';
        _name = '';
        _selectedIndex = 0;
      });
    }
    _handleUserModel('');
    _startEmailVerificationPolling(user);
  }

  /// Periodically reloads [user] until their email is verified, then enters the
  /// signed-in state. `reload()` does not fire authStateChanges, so we drive the
  /// transition ourselves here.
  void _startEmailVerificationPolling(User user) {
    _emailVerificationPoll?.cancel();
    _emailVerificationPoll =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        await user.reload();
      } catch (e) {
        print('Verification reload failed: $e');
        return;
      }
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed == null) {
        timer.cancel();
        return;
      }
      if (refreshed.emailVerified) {
        timer.cancel();
        _emailVerificationPoll = null;
        await _enterSignedInState(refreshed, ++_authStateGeneration);
      }
    });
  }

  /// Commits the verified, signed-in session. [generation] is checked after the
  /// async name lookup so a newer auth event can cancel this stale continuation.
  Future<void> _enterSignedInState(User user, int generation) async {
    print('User is signed in!');
    _emailVerificationPoll?.cancel();
    _emailVerificationPoll = null;
    final CollectionReference users =
        FirebaseFirestore.instance.collection('users');
    final String localUid = user.uid;

    String name;
    try {
      name = await fu.lookUpNameByUserUid(users, localUid);
    } catch (e) {
      print('Failed to look up user name: $e');
      name = '';
    }

    if (!mounted || generation != _authStateGeneration) {
      print('Stale auth event ($generation); skipping signed-in commit.');
      return;
    }

    _hasPerformedInitialSignedInMapSetup = false;
    _lastTrackedUsageDayKey = '';
    setState(() {
      _signedIn = true;
      _awaitingEmailVerification = false;
      _name = name;
      _uid = localUid;
      _selectedIndex = 0;
    });
    _handleUserModel(localUid);
    loadUserContext();
    await flushInitialMessage();
  }

  /// Resends the verification email to the currently pending user. Used by the
  /// verify-email screen's "Resend email" action.
  Future<void> _resendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
      _showTemporaryBottomMessage(
          'Verification email resent. Check your inbox and junk folder.');
    } catch (e) {
      print('Resend verification failed: $e');
      _showTemporaryBottomMessage(
          'Could not resend right now. Please try again shortly.');
    }
  }

  void _loadNotificationCount() async {
    print('attempting to load notification count');
    await fu.updateUnreadNotificationCounts('users');
    int count = await fu.retrieveNotificationCount(
        FirebaseFirestore.instance.collection('users'), _uid);
    print('the notification count was $count');
    if (notificationCount != count) {
      setState(() {
        FlutterAppBadger.updateBadgeCount(count);
        if (count > 0) {
          hasNotification = true;
          notificationCount = count;
        } else {
          hasNotification = false;
          notificationCount = 0;
          FlutterAppBadger.removeBadge();
        }
      });
    }
  }

  void _handleSignInChanged(bool newValue) {
    setState(() {
      _signedIn = newValue;
      if (!newValue) {
        _hasPerformedInitialSignedInMapSetup = false;
        _pendingMapFocusUserUid = null;
        _lastTrackedUsageDayKey = '';
      }
    });
    if (newValue) {
      _hasPerformedInitialSignedInMapSetup = false;
      loadUserContext();
    }
  }

  void _handleNameChanged(String newValue) {
    setState(() {
      _name = newValue;
    });
  }

  void _handleUidChanged(String newValue) {
    setState(() {
      _uid = newValue;
    });
    // this gets the global instance of usermodel and allows us to access methods
    _handleUserModel(newValue);
  }

  void _handleUserModel(String value) {
    UserModel().changeUid(value);
  }

  bool _retrieveDraggabilityUserModel() {
    return UserModel().draggability;
  }

  Future<void> _setDraggabilityUserModel(bool value) async {
    print('Changing draggability $value');
    UserModel().changeDraggability(value);
  }

  void _handleAlternateUserModel(String value, String name) {
    UserModel().changeAlternateUid(value);
    UserModel().changeAlternateName(name);
  }

  Future<void> _openInterestsForUserFromFeed(
      String targetUid, String targetName, String targetInterestId) async {
    _handleAlternateUserModel(targetUid, targetName);
    final sanitizedInterestId = targetInterestId.trim();
    if (sanitizedInterestId.isNotEmpty) {
      UserModel().setFeedInterestHighlight(
        ownerUid: targetUid,
        interestId: sanitizedInterestId,
      );
    } else {
      UserModel().clearFeedInterestHighlight();
    }
    _onItemTapped(0);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _openMessagesForUserFromFeed(String targetUid, String targetName) {
    _handleAlternateUserModel(targetUid, targetName);
    setState(() {
      _openMessagesWithUserUid = targetUid;
      _selectedIndex = 3;
    });
    _trackSignedInUsageAction();
  }

  Future<void> _openUserOnMapFromFeed(
      String targetUid, String targetName) async {
    _handleAlternateUserModel(targetUid, targetName);
    setState(() {
      _pendingMapFocusUserUid = targetUid;
    });
    _onItemTapped(0);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 3) {
        _openMessagesWithUserUid = null;
      }
      if (index != 0) {
        _pendingMapFocusUserUid = null;
      }
    });
    _trackSignedInUsageAction();
  }

  Future<void> _trackSignedInUsageAction() async {
    if (!_signedIn || _uid.trim().isEmpty) return;
    final now = DateTime.now().toLocal();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final dayKey = '${now.year}-$month-$day';
    if (_lastTrackedUsageDayKey == dayKey) return;

    _lastTrackedUsageDayKey = dayKey;
    try {
      await fu.recordAppUsageAction(
          FirebaseFirestore.instance.collection('users'), _uid);
    } catch (_) {
      _lastTrackedUsageDayKey = '';
    }
  }

  void _showLoadingIndicator() {
    setState(() {
      _isLoading = true;
    });
    Future.delayed(Duration(seconds: 5), () {
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _showTemporaryBottomMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
