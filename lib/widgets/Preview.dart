import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUtility.dart';
import 'package:provider/provider.dart';

import '../models/Interest.dart';
import '../models/UserModel.dart';

class Preview extends StatefulWidget {
  const Preview({
    super.key,
    required this.uid,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
    required this.onDrawerOpened,
  });
  final String uid;
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
  FirebaseUtility fu = FirebaseUtility();

  @override
  void initState() {
    super.initState();
    _fetchNameAndButtonLabels();
  }

  void _handleAlternateUserModel(String value, String name) {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeAlternateUid(value);
    userModel.changeAlternateName(name);
  }

  Future<void> _fetchNameAndButtonLabels() async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, widget.uid);
    String name = await fu.lookUpNameByUserUid(users, widget.uid);
    List<String> labels = interests.map((interest) => interest.name).toList();
    setState(() {
      _buttonLabels = labels;
      _name = name;
    });
  }

  void _handlePreviewToInterestsWidgetFlow() {
    if (widget.signedIn) {
      _handleAlternateUserModel(widget.uid, _name);
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
            children: _buttonLabels.map((label) {
              return ElevatedButton(
                onPressed: () {
                  _handlePreviewToInterestsWidgetFlow();
                },
                child: Text(label),
              );
            }).toList().take(5).toList(),
          ),
          SizedBox(height: 16.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (widget.signedIn) {
                  } else {
                    widget.onItemTapped(1);
                  } //
                  Navigator.pop(context); // Close the dialog
                },
                icon: Icon(Icons.chat),
                label: Text('Chat'),
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
        ],
      ),
    );
  }
}
