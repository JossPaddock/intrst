part of 'package:intrst/main.dart';

extension _HomeNotificationLogic on _MyHomePageState {
  /// Call once from initState. Registers all three FCM lifecycle handlers:
  ///   1. onMessageOpenedApp  — app was backgrounded, user tapped notification
  ///   2. onMessage           — app is foregrounded, show a snackbar with "View"
  ///   3. getInitialMessage   — app was terminated, user tapped notification (cold start)
  void _initNotifications() {
    // ── 1. Background tap ──────────────────────────────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationDeepLink(message);
    });

    // ── 2. Foreground message ──────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotificationBanner(message);
    });

    // ── 3. Cold start ──────────────────────────────────────────────────────
    // getInitialMessage() must be awaited after the widget is mounted.
    // Auth may still be settling, so we poll for _signedIn before navigating.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage == null) return;

      // Wait up to 5 s for Firebase Auth to restore the session.
      for (int i = 0; i < 10; i++) {
        if (_signedIn && _uid.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (mounted && _signedIn && _uid.isNotEmpty) {
        await _handleNotificationDeepLink(initialMessage);
      }
    });
  }

  // ── Deep-link router ────────────────────────────────────────────────────

  Future<void> _handleNotificationDeepLink(RemoteMessage message) async {
    if (!mounted || !_signedIn) return;

    final data = message.data;
    final activityType = data['activity_type'] ?? '';
    final actorUid    = (data['actor_uid']  ?? '').trim();
    final interestId  = (data['interest_id'] ?? '').trim();
    final senderUid   = (data['sender_uid']  ?? '').trim();

    // ── Message notification ───────────────────────────────────────────────
    // activity_type is absent; sender_uid is set (requires main.py change below).
    if (activityType.isEmpty) {
      if (senderUid.isNotEmpty) {
        // Open the specific conversation.
        String senderName = '';
        try {
          senderName = await fu.lookUpNameByUserUid(
            FirebaseFirestore.instance.collection('users'),
            senderUid,
          );
        } catch (_) {}
        _openMessagesForUserFromFeed(senderUid, senderName.trim());
      } else {
        // Fallback: just open the Messages tab.
        _onItemTapped(3);
      }
      return;
    }

    // ── Activity notification (interest_created / interest_updated) ────────
    if ((activityType == 'interest_created' ||
        activityType == 'interest_updated') &&
        actorUid.isNotEmpty) {
      String actorName = '';
      try {
        actorName = await fu.lookUpNameByUserUid(
          FirebaseFirestore.instance.collection('users'),
          actorUid,
        );
      } catch (e) {
        print('notification deep-link: could not look up actor name: $e');
      }
      if (actorName.trim().isEmpty) actorName = 'User';

      // Reuses the exact same flow as tapping a post in FollowingFeed:
      //   • sets alternateUid / alternateName on UserModel
      //   • calls setFeedInterestHighlight so the card glows
      //   • navigates to map tab (index 0) then opens the end drawer
      await _openInterestsForUserFromFeed(actorUid, actorName, interestId);
    }
  }

  // ── Foreground banner ────────────────────────────────────────────────────

  void _showForegroundNotificationBanner(RemoteMessage message) {
    if (!mounted) return;
    final notification = message.notification;
    if (notification == null) return;

    final title = (notification.title ?? '').trim();
    final body  = (notification.body  ?? '').trim();
    if (title.isEmpty && body.isEmpty) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              if (body.isNotEmpty) Text(body),
            ],
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _handleNotificationDeepLink(message),
          ),
        ),
      );
  }
}