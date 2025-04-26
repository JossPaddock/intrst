import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/widgets/CollapsibleChatScreen.dart';
import 'package:provider/provider.dart';

import '../models/Interest.dart';
import '../models/UserModel.dart';
import '../utility/FirebaseMessagesUtility.dart';

class Preview extends StatefulWidget {
  const Preview({
    super.key,
    required this.uid,
    required this.alternateUid,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
    required this.onDrawerOpened,
  });
  final String uid;
  final String alternateUid;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final void Function(int) onItemTapped;
  final bool signedIn;
  final VoidCallback onDrawerOpened;

  @override
  _InterestAlertDialogState createState() => _InterestAlertDialogState();
}

class _InterestAlertDialogState extends State<Preview> {
  List<String> _buttonLabels = [];
  String _name = '';
  FirebaseUsersUtility fuu = FirebaseUsersUtility();
  FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  bool chatOpen = false;
  CollectionReference messages =
      FirebaseFirestore.instance.collection('messages');
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  Map<DocumentReference, Map<String, dynamic>>? initMessageData = null;
  bool hasNotification = false;
  int notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchNameAndButtonLabels();
    _fetchInitialMessageData();
    _loadNotificationCount();
  }

  void _loadNotificationCount() async{
    while(initMessageData == null) {
      await Future.delayed(Duration(milliseconds: 500));
    }
    print('attempting to load notification count');
    int count = await fuu.retrieveNotificationCount(users, widget.uid, initMessageData!.entries.first.key.path);
    print('the notification count was $count');
    setState(() {
      if(count > 0 ) {
        hasNotification = true;
        notificationCount = count;
      }
      else{
        hasNotification = false;
        notificationCount = 0;
      }
    });
  }
  
  void _handleAlternateUserModel(String value, String name) {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeAlternateUid(value);
    userModel.changeAlternateName(name);
  }

  String _handleLookUpViewerOfPreviewWidget() {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    return userModel.currentUid;
  }

  Future<void> _fetchNameAndButtonLabels() async {
    List<Interest> interests =
        await fuu.pullInterestsForUser(users, widget.alternateUid);
    String name = await fuu.lookUpNameByUserUid(users, widget.alternateUid);
    List<String> labels = interests.map((interest) => interest.name).toList();
    setState(() {
      _buttonLabels = labels;
      _name = name;
    });
  }

  Future<void> _fetchInitialMessageData() async {
    List<String> userUids = [widget.uid, widget.alternateUid];
    Map<DocumentReference, Map<String, dynamic>>? data =
        await fmu.getMessageDocumentsExclusivelyByUserUids(userUids);
    if (data == null) {
      await fmu.createMessageDocument([widget.uid, widget.alternateUid]);
      data = await fmu.getMessageDocumentsExclusivelyByUserUids(userUids);
    }
    setState(() {
      initMessageData = data;
    });
  }

  void _handlePreviewToInterestsWidgetFlow() {
    if (widget.signedIn) {
      _handleAlternateUserModel(widget.alternateUid, _name);
      widget.scaffoldKey.currentState?.openEndDrawer();
      widget.onDrawerOpened();
    } else {
      widget.onItemTapped(1);
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(
          color: Colors.grey, // Border color
          width: 1.0, // Border width
        ),
      ),
      title: Text(
        _name,
        textAlign: TextAlign.center, // Center the title text
        style: TextStyle(
          fontSize: 20, // Adjust font size as needed
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16.0,
            runSpacing: 8.0,
            children: _buttonLabels
                .map((label) {
                  return ElevatedButton(
                    onPressed: () {
                      _handlePreviewToInterestsWidgetFlow();
                    },
                    child: Text(label),
                  );
                })
                .toList()
                .take(5)
                .toList(),
          ),
          SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  if (widget.signedIn) {
                  } else {
                    widget.onItemTapped(1);
                  } //
                  //Navigator.pop(context); // Close the dialog
                  setState(() {
                    chatOpen = !chatOpen;
                  });
                },
                icon: Badge.count(
                    offset: Offset(9.0, -7.0), isLabelVisible: hasNotification,
                  count: notificationCount, child: const Icon(Icons.chat)),
                  label: Text(chatOpen ? 'Close' : 'Chat'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _handlePreviewToInterestsWidgetFlow();
                },
                icon: Icon(Icons.add),
                label: Text('List all interests'),
              ),
            ],
          ),
          if (chatOpen && initMessageData != null)
            Column(
              children: [
                CollapsibleChatScreen(
                    autoOpen: true,
                    showNameAtTop: false,
                    uid: _handleLookUpViewerOfPreviewWidget(),
                    documentData: initMessageData!.entries.first.value,
                    documentReference: initMessageData!.entries.first.key),
                ElevatedButton.icon(
                  onPressed: () {
                    widget.onItemTapped(3);
                    Navigator.pop(context);
                  },
                  icon: Icon(Icons.chat),
                  label: Text('Show all chats'),
                )
              ],
            ),
          if (chatOpen && initMessageData == null)
            Text('we tried creating a conversation with this person but failed')
        ],
      ),
    );
  }
}
