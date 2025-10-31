import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/widgets/CollapsibleChatScreen.dart';
import 'package:provider/provider.dart';

import '../models/Interest.dart';
import '../models/UserModel.dart';
import '../utility/FirebaseMessagesUtility.dart';

class Account extends StatefulWidget {
  const Account({
    super.key,
    required this.uid,
  });

  final String uid;

  @override
  _Account createState() => _Account();
}

class _Account extends State<Account> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextButton(
          onPressed: () {
            fu.showReauthAndDeleteDialog(context, widget.uid);
          },
          child: Text('Delete my account')),
      kIsWeb? SizedBox.shrink():TextButton(
          onPressed: () async {
            // You may set the permission requests to "provisional" which allows the user to choose what type
// of notifications they would like to receive once the user receives a notification.
            final notificationSettings = await FirebaseMessaging.instance
                .requestPermission(provisional: true);

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
              fu.addFcmTokenForUser(widget.uid, fcmToken);
            } else {
              print('fcm token is NOT available');
            }
            NotificationSettings notifSettings = await FirebaseMessaging
                .instance
                .requestPermission(alert: true, badge: true, sound: true);
            print('${notifSettings.authorizationStatus}');
            String permissionMessage = '';
            switch(notifSettings.authorizationStatus.name) {
              case 'authorized' : permissionMessage = "Thank you, the intrst app can now send you notifications!";
              case 'denied' : permissionMessage = "The intrst app is not authorized to create notifications.";
              case 'notDetermined' : permissionMessage = "Your permission status for notifications is not determined yet";
              case 'provisional' : permissionMessage = "The intrst app is currently authorized to post non-interrupting user notifications.";
              default: permissionMessage = "There has been an error";

            };
            await showDialog<void>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                      content: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 66),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              //if (kDebugMode)
                                Text('the APNs token is: ${apnsToken}'),
                              //if (kDebugMode)
                                Text('the fcm token is: ${fcmToken}'),
                              Text(permissionMessage)
                            ],
                          )));
                });
          },
          child: Text('Allow push notification permissions')),
    ]);
  }
}
