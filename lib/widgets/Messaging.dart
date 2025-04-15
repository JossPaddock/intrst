import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/widgets/CollapsibleChatScreen.dart';
import '../utility/FirebaseMessagesUtility.dart';
import '../utility/FirebaseUsersUtility.dart';

class Messaging extends StatefulWidget {
  const Messaging({
    super.key,
    required this.user_uid,
  });
  final String user_uid;

  @override
  _MessagingState createState() => _MessagingState();
}

class _MessagingState extends State<Messaging> {
  final FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  Set<String> selectedItems = {};
  List<String> searchResults = [];
  List<Map<String, dynamic>> messageData = [];
  List<DocumentReference> messageDocumentReference = [];

  late final StreamSubscription _subscription;
  @override
  void initState() {
    super.initState();
    _subscription = FirebaseFirestore.instance
        .collection('messages')
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      getMessages();
    });
    getMessages();
  }
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> getMessages() async {
    //clear out stale message data
    setState(() {
      messageData = [];
      messageDocumentReference = [];
    });
    print('attempting to get messages');
    List<Map<DocumentReference, Map<String, dynamic>>> data =
        await fmu.getMessageDocumentsByUserUid(widget.user_uid);
    List<Map<String, dynamic>> extractedList =
        data.map((entry) => entry.values.first).toList();
    List<DocumentReference> extractedDocumentReference =
        data.map((entry) => entry.keys.first).toList();
    print(extractedList);
    print(extractedDocumentReference);
    setState(() {
      messageData = extractedList;
      messageDocumentReference = extractedDocumentReference;
    });
    reorderMessagesByLatestMessageFirst();
  }

  Future<void> reorderMessagesByLatestMessageFirst() async {
    // instead of sorting 1 by 1, lets put what we want to sort into the same pairs
    // then do the sorting operations
    List<MapEntry<Map<String, dynamic>, DocumentReference>> combinedList = List.generate(
      messageData.length,
          (index) => MapEntry(messageData[index], messageDocumentReference[index]),
    );

    DateTime getLatestMessageTimestamp(Map<String, dynamic> conversation) {
      if (conversation.isEmpty) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      var messageTimestamps = conversation.values
          .map((message) => message['timestamp']?.toDate())
          .whereType<DateTime>()
          .toList();

      messageTimestamps.sort((a, b) => b.compareTo(a));
      return messageTimestamps.isEmpty ? DateTime.fromMillisecondsSinceEpoch(0) : messageTimestamps.first;
    }

    // dry principles
    combinedList.sort((a, b) {
      DateTime timestampA = getLatestMessageTimestamp(a.key['conversation']);
      DateTime timestampB = getLatestMessageTimestamp(b.key['conversation']);
      return timestampB.compareTo(timestampA); // Latest first
    });

    // but the data still needs to be seperated
    setState(() {
      messageData = combinedList.map((e) => e.key).toList();
      messageDocumentReference = combinedList.map((e) => e.value).toList();
    });

    print("Success: messages reordered by the latest message first.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SizedBox(
            width: 350,
            child: TextField(
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                fillColor: Colors.white,
                filled: true,
                hintText: 'find someone to message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0), // Adjust as needed
                ),
              ),
              onChanged: (value) async {
                List<String> results =
                    await fuu.searchForPeopleAndInterests(users, value, false);
                if (results.contains(widget.user_uid)) {
                  results.remove(widget.user_uid);
                }
                setState(() {
                  searchResults = results;
                });
              },
            ),
          ),
          Wrap(
            spacing: 20.0,
            children: searchResults.map((item) {
              final isSelected = selectedItems.contains(item);
              return isSelected
                  ? SizedBox.shrink()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isSelected ? Colors.green : Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isSelected) {
                            selectedItems.remove(item);
                          } else {
                            selectedItems.add(item);
                          }
                        });
                      },
                      child: FutureBuilder<String>(
                        future: fuu.lookUpNameByUserUid(users, item),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Text('');
                          } else if (snapshot.hasError) {
                            return const Text("Could Not Load Users Name");
                          } else {
                            return Text(snapshot.data ?? 'No Name');
                          }
                        },
                      ),
                    );
            }).toList(),
          ),
          Wrap(
            spacing: 20.0,
            children: selectedItems.map((item) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                onPressed: () {
                  setState(() {
                    selectedItems.remove(item);
                  });
                },
                child: FutureBuilder<String>(
                  future: fuu.lookUpNameByUserUid(users, item),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text('');
                    } else if (snapshot.hasError) {
                      return const Text("Could Not Load Users Name");
                    } else {
                      return Text(snapshot.data ?? 'No Name');
                    }
                  },
                ),
              );
            }).toList(),
          ),
          if (selectedItems.isNotEmpty)
            TextButton(
                onPressed: () async {
                  List<String> conversationParticipants =
                      selectedItems.toList();
                  conversationParticipants.add(widget.user_uid);
                  await fmu.createMessageDocument(conversationParticipants);
                  await getMessages();
                },
                child: Text('create new chat')),
          Container(
            width: 300,
            height: 600,
            child: ListView.builder(
              itemCount: messageData.length,
              itemBuilder: (context, index) {
                return CollapsibleChatScreen(
                  getMessages: getMessages,
                  uid: widget.user_uid,
                  documentData: messageData[index],
                  documentReference: messageDocumentReference[index],
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
