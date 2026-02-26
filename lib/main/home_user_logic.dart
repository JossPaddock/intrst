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
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        print('User is currently signed out!');
        _notificationLoading?.cancel();
        _hasPerformedInitialSignedInMapSetup = false;
        _pendingMapFocusUserUid = null;
        _lastTrackedUsageDayKey = '';
      } else {
        CollectionReference users =
            FirebaseFirestore.instance.collection('users');
        print('User is signed in!');
        _signedIn = true;
        _hasPerformedInitialSignedInMapSetup = false;
        _lastTrackedUsageDayKey = '';
        _selectedIndex = 0;
        String localUid = FirebaseAuth.instance.currentUser!.uid;
        setState(() {});
        String name = await fu.lookUpNameByUserUid(users, localUid);
        _name = name;
        _uid = localUid;
        _handleUserModel(localUid);
        setState(() {});
        loadUserContext();
      }
    });
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
      String targetUid, String targetName) async {
    _handleAlternateUserModel(targetUid, targetName);
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
