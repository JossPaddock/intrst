import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/DateTimeUtility.dart';
import 'package:intrst/widgets/ChatBubble.dart';

import '../utility/FirebaseMessagesUtility.dart';
import '../utility/FirebaseUsersUtility.dart';
import 'ChatScreen.dart';

class CollapsibleChatScreen extends StatefulWidget {
  final bool showNameAtTop;
  final bool autoOpen;
  final Map<String, dynamic> documentData;
  final String uid;
  final DocumentReference documentReference;
  const CollapsibleChatScreen({
    super.key,
    this.showNameAtTop = true,
    this.autoOpen = false,
    required this.uid,
    required this.documentData,
    required this.documentReference,
  });

  @override
  State<CollapsibleChatScreen> createState() =>
      _CollapsibleChatContainerState();
}

class _CollapsibleChatContainerState extends State<CollapsibleChatScreen> {
  final TextEditingController _send_message_controller =
      TextEditingController();
  final FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  bool _isExpanded = false;
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  Set<String> messagesWith = {};

  @override
  void initState() {
    super.initState();
    widget.documentData['user_uids'].forEach((value) async {
      if (value != widget.uid) {
        String name = await fuu.lookUpNameByUserUid(users, value);
        setState(() {
          messagesWith.add(name);
        });
      }
    });
    if (widget.autoOpen) {
      setState(() {
        _isExpanded = true;
      });
    }
  }
  void _showDeleteDialog(BuildContext context) {
    final TextEditingController _controller = TextEditingController();
    bool isCorrect = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Confirm Deletion"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Type 'delete for sure' to confirm."),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    onChanged: (value) {
                      setState(() {
                        isCorrect = value.trim().toLowerCase() == "delete for sure";
                      });
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "type here...",
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isCorrect
                      ? () {
                    Navigator.of(context).pop();
                    //put the call to delete the message document here!!!
                    fmu.deleteMessageDocument(widget.documentReference);
                    setState(() {
                    });
                  }
                      : null,
                  child: const Text("Really Delete!"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget build(BuildContext context) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
              IconButton(
                icon: const Icon(Icons.delete),
                color: Colors.brown,
                tooltip: 'Delete messages',
                onPressed: ()=>_showDeleteDialog(context),
              ),
              if (widget.showNameAtTop) Text(messagesWith.join(',')),
            if (!widget.autoOpen)
              IconButton(
                  icon:
                      Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  }),
            ],),
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000),
              height: _isExpanded ? 400 : 0,
              child: _isExpanded
                  ? StreamBuilder<DocumentSnapshot>(
                      stream: widget.documentReference
                          .snapshots(), // Listen to changes in the document
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Something went wrong :(');
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Text('Loading...');
                        }
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return Text('No messages found');
                        }

                        var data =
                            snapshot.data!.data() as Map<String, dynamic>;
                        return ChatScreen(
                          uid: widget.uid,
                          documentData: data,
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            if (_isExpanded)
              TextField(
                controller: _send_message_controller,
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
                    onPressed: () {
                      final text = _send_message_controller.text;
                      //todo: message input validation eg. make sure they don't send an empty message.
                      fmu.sendMessage(
                          text, widget.documentReference, widget.uid);
                    },
                  ),
                ),
              ),
          ])),
      SizedBox(
        height: 5,
      )
    ]);
  }
}
