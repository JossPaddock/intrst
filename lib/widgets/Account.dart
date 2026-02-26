import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';

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
  bool _didHydrateInitialValues = false;

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
