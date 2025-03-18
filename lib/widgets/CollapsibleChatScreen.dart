import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/DateTimeUtility.dart';
import 'package:intrst/widgets/ChatBubble.dart';

import '../utility/FirebaseUsersUtility.dart';
import 'ChatScreen.dart';

class CollapsibleChatScreen extends StatefulWidget {
  final Map<String, dynamic> documentData;
  final String uid;
  const CollapsibleChatScreen({
    Key? key,
    required this.uid,
    required this.documentData,
  }) : super(key: key);

  @override
  State<CollapsibleChatScreen> createState() =>
      _CollapsibleChatContainerState();
}

class _CollapsibleChatContainerState extends State<CollapsibleChatScreen> {
  bool _isExpanded = false;
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  Set<String> messagesWith = {};

  @override
  Widget build(BuildContext context) {
    widget.documentData['user_uids'].forEach((value) async {
      if (value != widget.uid) {
        messagesWith.add(await fuu.lookUpNameByUserUid(users, value));
      }
    });
    return Column(children: [
      Container(
        width: 400,
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.black,
              width: 3.0,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(children: [
            Text('Chat with ${messagesWith.join(',')}'),
            IconButton(
                icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                }),
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000),
              height: _isExpanded ? 400 : 0,
              child: _isExpanded
                  ? ChatScreen(
                      uid: widget.uid,
                      documentData: widget.documentData,
                    )
                  : const SizedBox.shrink(),
            ),
            if (_isExpanded)
              TextField(
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  hintText: 'send message',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12.0), // Adjust as needed
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.send),
                    onPressed: () {},
                  ),
                ),
              ),
          ])),
      SizedBox(
        height: 5,)
    ]);
  }
}
