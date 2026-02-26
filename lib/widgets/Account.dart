import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';

// change this to true to show the admin controls to plus or minus profile stats, or false to hide.
const bool kShowProfileStatsAdminControls = false;

class Account extends StatefulWidget {
  const Account({
    super.key,
    required this.uid,
    required this.onNameChanged,
  });

  final String uid;
  final void Function(String value) onNameChanged;

  @override
  State<Account> createState() => _Account();
}

class _Account extends State<Account> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  bool _isSavingName = false;
  bool _isAdjustingProfileStatistics = false;
  bool _didHydrateInitialValues = false;
  final Set<String> _updatingFeedSettingKeys = <String>{};

  @override
  void didUpdateWidget(covariant Account oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _didHydrateInitialValues = false;
      _firstNameController.clear();
      _lastNameController.clear();
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _hydrateNameFields(Map<String, dynamic> userData) {
    if (_didHydrateInitialValues) return;
    _firstNameController.text = (userData['first_name'] ?? '').toString();
    _lastNameController.text = (userData['last_name'] ?? '').toString();
    _didHydrateInitialValues = true;
  }

  // maybe im being silly for adding this lol - but it works!
  String _daySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _formatProfileCreatedOn(Timestamp? createdAt) {
    if (createdAt == null) return 'Unknown';
    final value = createdAt.toDate().toLocal();
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final month = months[value.month - 1];
    final suffix = _daySuffix(value.day);
    return '$month ${value.day}$suffix, ${value.year}';
  }

  Future<void> _adjustProfileStatisticForDebug(
      Future<void> Function(CollectionReference users) action) async {
    if (!kDebugMode ||
        !kShowProfileStatsAdminControls ||
        _isAdjustingProfileStatistics ||
        widget.uid.trim().isEmpty) {
      return;
    }
    setState(() {
      _isAdjustingProfileStatistics = true;
    });
    try {
      final users = FirebaseFirestore.instance.collection('users');
      await action(users);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to adjust metric: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAdjustingProfileStatistics = false;
        });
      }
    }
  }

  Widget _buildProfileStatisticRow({
    required String label,
    required int value,
    required VoidCallback? onIncrement,
    required VoidCallback? onDecrement,
  }) {
    return Row(
      children: [
        Expanded(child: Text('$label: $value')),
        if (kDebugMode && kShowProfileStatsAdminControls)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Decrease',
                onPressed: _isAdjustingProfileStatistics ? null : onDecrement,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Increase',
                onPressed: _isAdjustingProfileStatistics ? null : onIncrement,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _saveName() async {
    if (_isSavingName || widget.uid.trim().isEmpty) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please provide both a first name and a last name.')),
      );
      return;
    }

    setState(() {
      _isSavingName = true;
    });

    try {
      final users = FirebaseFirestore.instance.collection('users');
      final updated =
          await fu.updateUserName(users, widget.uid, firstName, lastName);
      if (!mounted) return;

      if (!updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update name right now.')),
        );
      } else {
        final fullName = '$firstName $lastName';
        widget.onNameChanged(fullName);
        FocusManager.instance.primaryFocus?.unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name updated.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update name: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingName = false;
        });
      }
    }
  }

  Future<void> _updateFeedSetting(String settingKey, bool isEnabled) async {
    if (widget.uid.trim().isEmpty ||
        _updatingFeedSettingKeys.contains(settingKey)) {
      return;
    }

    setState(() {
      _updatingFeedSettingKeys.add(settingKey);
    });

    try {
      final users = FirebaseFirestore.instance.collection('users');
      final updated = await fu.updateFeedVisibilitySetting(
        users,
        widget.uid,
        settingKey,
        isEnabled,
      );
      if (!mounted) return;
      if (!updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update feed setting.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update feed setting: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingFeedSettingKeys.remove(settingKey);
        });
      }
    }
  }

  Widget _buildFeedSettingTile({
    required String settingKey,
    required String title,
    required String subtitle,
    required bool value,
  }) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _updatingFeedSettingKeys.contains(settingKey)
          ? null
          : (nextValue) => _updateFeedSetting(settingKey, nextValue),
    );
  }

  Future<void> _requestPushNotificationPermissions() async {
    await FirebaseMessaging.instance.requestPermission(provisional: true);

    final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    if (apnsToken != null) {
      print('APNs token is available: $apnsToken');
    } else {
      print('APNs token is NOT available');
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken != null) {
      print('fcm token is available: $fcmToken');
      fu.addFcmTokenForUser(widget.uid, fcmToken);
    } else {
      print('fcm token is NOT available');
    }

    NotificationSettings notifSettings = await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
    print('${notifSettings.authorizationStatus}');
    String permissionMessage = '';
    switch (notifSettings.authorizationStatus.name) {
      case 'authorized':
        permissionMessage =
            'Thank you, the intrst app can now send you notifications!';
      case 'denied':
        permissionMessage =
            'The intrst app is not authorized to create notifications.';
      case 'notDetermined':
        permissionMessage =
            'Your permission status for notifications is not determined yet';
      case 'provisional':
        permissionMessage =
            'The intrst app is currently authorized to post non-interrupting user notifications.';
      default:
        permissionMessage = 'There has been an error';
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Padding(
            padding: const EdgeInsets.symmetric(vertical: 66),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('the APNs token is: $apnsToken'),
                Text('the fcm token is: $fcmToken'),
                Text(permissionMessage),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.trim().isEmpty) {
      return const Center(child: Text('Sign in to manage your account.'));
    }

    final users = FirebaseFirestore.instance.collection('users');
    return StreamBuilder<QuerySnapshot>(
      stream:
          users.where('user_uid', isEqualTo: widget.uid).limit(1).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading account settings: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Could not find account profile.'));
        }

        final userData =
            snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final profileStatisticsRaw = userData['profile_statistics'];
        final profileStatistics = profileStatisticsRaw is Map
            ? Map<String, dynamic>.from(profileStatisticsRaw)
            : <String, dynamic>{};
        final feedSettingsRaw =
            userData[FirebaseUsersUtility.feedSettingsField];
        final feedSettings = feedSettingsRaw is Map
            ? Map<String, dynamic>.from(feedSettingsRaw)
            : <String, dynamic>{};
        final showPosts = FirebaseUsersUtility.readFeedSettingValue(
          feedSettings,
          FirebaseUsersUtility.feedSettingShowPosts,
        );
        final showMessages = FirebaseUsersUtility.readFeedSettingValue(
          feedSettings,
          FirebaseUsersUtility.feedSettingShowMessages,
        );
        final showInterestUpdates = FirebaseUsersUtility.readFeedSettingValue(
          feedSettings,
          FirebaseUsersUtility.feedSettingShowInterestUpdates,
        );
        final showStreaks = FirebaseUsersUtility.readFeedSettingValue(
          feedSettings,
          FirebaseUsersUtility.feedSettingShowStreaks,
        );
        final showMessageCounts = FirebaseUsersUtility.readFeedSettingValue(
          feedSettings,
          FirebaseUsersUtility.feedSettingShowMessageCounts,
        );
        final longestStreak =
            (profileStatistics['longest_app_usage_streak'] as num?)?.toInt() ??
                0;
        final sentMessageCount =
            (profileStatistics['messages_sent_count'] as num?)?.toInt() ?? 0;
        final receivedMessageCount =
            (profileStatistics['messages_received_count'] as num?)?.toInt() ??
                0;
        final profileCreatedAt =
            profileStatistics['profile_created_at'] as Timestamp?;
        final profileCreatedOnText = _formatProfileCreatedOn(profileCreatedAt);
        _hydrateNameFields(userData);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Profile',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'First name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Last name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isSavingName ? null : _saveName,
              icon: _isSavingName
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save name'),
            ),
            const SizedBox(height: 20),
            const Text(
              'Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildProfileStatisticRow(
              label: 'Longest Streak for using the Intrst App',
              value: longestStreak,
              onIncrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.incrementLongestStreakForDebug(users, widget.uid, 1));
              },
              onDecrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.decrementLongestStreakForDebug(users, widget.uid, 1));
              },
            ),
            const SizedBox(height: 4),
            _buildProfileStatisticRow(
              label: 'Number of messages sent',
              value: sentMessageCount,
              onIncrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.incrementSentMessageCount(users, widget.uid, 1));
              },
              onDecrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.decrementSentMessageCount(users, widget.uid, 1));
              },
            ),
            const SizedBox(height: 4),
            _buildProfileStatisticRow(
              label: 'Number of messages recieved',
              value: receivedMessageCount,
              onIncrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.incrementReceivedMessageCount(users, widget.uid, 1));
              },
              onDecrement: () {
                _adjustProfileStatisticForDebug((users) =>
                    fu.decrementReceivedMessageCount(users, widget.uid, 1));
              },
            ),
            const SizedBox(height: 4),
            Text('Profile created on $profileCreatedOnText'),
            const SizedBox(height: 20),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Advanced Feed Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              children: [
                _buildFeedSettingTile(
                  settingKey: FirebaseUsersUtility.feedSettingShowPosts,
                  title: 'Posts',
                  subtitle:
                      'Whenever someone you follow posts an interest with a message. Your own posts always stay visible.',
                  value: showPosts,
                ),
                _buildFeedSettingTile(
                  settingKey: FirebaseUsersUtility.feedSettingShowMessages,
                  title: 'Messages',
                  subtitle:
                      'Message reminders whenever someone sends you a new message.',
                  value: showMessages,
                ),
                _buildFeedSettingTile(
                  settingKey:
                      FirebaseUsersUtility.feedSettingShowInterestUpdates,
                  title: 'Interest Updates',
                  subtitle:
                      'Whenever someone creates or updates their interests.',
                  value: showInterestUpdates,
                ),
                _buildFeedSettingTile(
                  settingKey: FirebaseUsersUtility.feedSettingShowStreaks,
                  title: 'Streaks',
                  subtitle:
                      'Whenever you earn a new Longest Streak for using the Intrst App.',
                  value: showStreaks,
                ),
                _buildFeedSettingTile(
                  settingKey: FirebaseUsersUtility.feedSettingShowMessageCounts,
                  title: 'Messages Counts',
                  subtitle:
                      'Whenever you reach new milestones for large numbers of messages.',
                  value: showMessageCounts,
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                fu.showReauthAndDeleteDialog(context, widget.uid);
              },
              child: const Text('Delete my account'),
            ),
            if (!kIsWeb)
              TextButton(
                onPressed: _requestPushNotificationPermissions,
                child: const Text('Allow push notification permissions'),
              ),
          ],
        );
      },
    );
  }
}
