import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/widgets/ChatScreen.dart';

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
  CollectionReference users =
  FirebaseFirestore.instance.collection('users');
  Set<String> selectedItems = {};
  List<String> searchResults = [];
  List<Map<String, dynamic>> messageData = [];
  @override
  void initState() {
    super.initState();
    getMessages();
  }

  Future<void> getMessages() async {
    List<Map<String, dynamic>> data =
        await fmu.getMessageDocumentsByUserUid(widget.user_uid);
    setState(() {
      messageData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextField(
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
              setState(() {
                searchResults = results;
              });
            },
          ),
          Text(searchResults.join(",")),
          Wrap(
            spacing: 20.0,
            children: searchResults.map((item) {
              final isSelected = selectedItems.contains(item);
              return isSelected ? SizedBox.shrink(): ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? Colors.green : Colors.grey,
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
                    }
                  );
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
          Container(
            width: 300,
            height: 500,
            child: ListView.builder(
              itemCount: messageData.length,
              itemBuilder: (context, index) {
                return ChatScreen(
                    uid: widget.user_uid, documentData: messageData[index]);
              },
            ),
          )
        ],
      ),
    );
  }
}
