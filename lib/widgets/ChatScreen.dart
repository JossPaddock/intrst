import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/DateTimeUtility.dart';
import 'package:intrst/widgets/ChatBubble.dart';

import '../utility/FirebaseUsersUtility.dart';

class ChatScreen extends StatelessWidget {
  final Map<String, dynamic> documentData;
  final String uid;
  const ChatScreen({Key? key, required this.uid, required this.documentData})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final FirebaseUsersUtility fu = FirebaseUsersUtility();
    List<Map<String, dynamic>> messages = [];
    if (documentData['conversation'] != null) {
      documentData['conversation'].forEach((key, value) {
        messages.add({
          'message_content': value['message_content'],
          'timestamp': (value['timestamp'] as Timestamp).toDate(),
          'user_uid': value['user_uid'],
        });
      });

      // Sort messages by timestamp in the appropriate order
      messages.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
    }
    final DateTimeUtility dtu = DateTimeUtility();
    return Container(
        decoration:
            BoxDecoration(border: Border.all(color: Colors.black, width: 5)),
        child: SizedBox(
          height: 400,
          width: 200,
          child: ListView.builder(
            itemCount: messages.length,
            itemBuilder: (context, index) {
              var message = messages[index];
              CollectionReference users =
                  FirebaseFirestore.instance.collection('users');
              var isUserMessage = message['user_uid'] == uid;
              return FutureBuilder<String>(
                future: fu.lookUpNameByUserUid(users, message['user_uid']),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListTile(title: Text('Loading...'));
                  } else if (snapshot.hasError) {
                    return ListTile(title: Text('Error'));
                  } else {
                    return ListTile(
                      title: Padding(
                        padding: const EdgeInsets.only(left: 15, right: 15),
                        child: Text(
                          style: TextStyle(fontSize: 13.0),
                          snapshot.data == null ? 'unknown' : snapshot.data!,
                          textAlign:
                              isUserMessage ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                      subtitle: Tooltip(
                        message: dtu.getFormattedTime(
                          message['timestamp'],
                        ),
                        child: ChatBubble(
                          message: message['message_content'],
                          isSender: isUserMessage,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ));
  }
}
