import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intrst/utility/FirebaseMappers.dart';
import '../models/Interest.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:uuid/uuid.dart';

class FirebaseMessagesUtility {
  final CollectionReference messages =
      FirebaseFirestore.instance.collection('messages');

  Future<List<Map<DocumentReference, Map<String, dynamic>>>>
      getMessageDocumentsByUserUid(String userUid) async {
    QuerySnapshot querySnapshot =
        await messages.where('user_uids', arrayContains: userUid).get();
    List<Map<DocumentReference, Map<String, dynamic>>> message_data = [];
    for (var doc in querySnapshot.docs) {
      Map<DocumentReference, Map<String, dynamic>> myMap = {
        doc.reference: doc.data() as Map<String, dynamic>,
      };
      message_data.add(myMap);
    }
    return message_data;
  }

  Future<Map<DocumentReference, Map<String, dynamic>>?>
      getMessageDocumentsExclusivelyByUserUids(List<String> userUids) async {
    List<Map<DocumentReference, Map<String, dynamic>>> messages_data = [];
    QuerySnapshot querySnapshot =
        await messages.where('user_uids', arrayContainsAny: userUids).get();

    userUids.sort();
    for (var doc in querySnapshot.docs) {
      List<String> docUserUids = List<String>.from(doc["user_uids"] ?? []);
      docUserUids.sort();

      if (docUserUids.join(",") == userUids.join(",")) {
        print("Matched Message: ${doc.id}, Data: ${doc.data()}");
        Map<DocumentReference, Map<String, dynamic>> myMap = {
          doc.reference: doc.data() as Map<String, dynamic>,
        };
        messages_data.add(myMap);
      }
    }
    if (messages_data.length > 1) {
      print(
          "Warning, found more than one message document. Length: ${messages_data.length}. "
          "This should have been one, but was more because the user probably has more than "
          "one message with the same person!!!");
    }
    if (messages_data.isEmpty) {
      print("warning could not find any message documents");
      return null;
    }
    return messages_data[0];
  }

  Future<bool> userUidComboAlreadyExists(List<String> userUids) async {
    final inputKey = (userUids..sort()).join(',');
    final allMessages = await messages.get();
    return allMessages.docs.any((doc) =>
    ((doc['user_uids'] as List?)?.map((d) => d.toString()).toList()?..sort())?.join(',') == inputKey
    );
  }

  Future<bool> createMessageDocument(List<String> userUids) async {
    Map<String, Map<String, dynamic>> conversation = {};
    Map<String, dynamic> data = {
      'user_uids': userUids,
      'conversation': conversation,
      'created_at': FieldValue.serverTimestamp(),
    };
    final alreadyExists = await userUidComboAlreadyExists(userUids);
    if(alreadyExists) {
      print('the user tried creating a chat which already exists but was prevented');
      return false;
    } else {
      await messages.add(data);
      return true;
    }

  }

  Future<void> deleteMessageDocument(DocumentReference dr) async {
    try {
      await dr.delete();
    } catch (e) {
      print("Error deleting message document: $e");
    }
  }

  Future<void> sendMessage(
      String message, DocumentReference dr, String user_uid) async {
    try {
      final String messageId = const Uuid().v4();

      final Map<String, dynamic> newMessage = {
        'message_content': message,
        'timestamp': FieldValue.serverTimestamp(),
        'user_uid': user_uid,
      };

      await dr.set({
        'conversation': {
          messageId: newMessage,
        }
      }, SetOptions(merge: true));

      print("User has sent message successfully.");
    } catch (e) {
      print("Error sending message: $e");
    }
  }
}
