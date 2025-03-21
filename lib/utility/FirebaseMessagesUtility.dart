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
  Future<List<Map<DocumentReference, Map<String, dynamic>>>> getMessageDocumentsByUserUid(String userUid) async {
    QuerySnapshot querySnapshot =
        await messages.where('user_uids', arrayContains: userUid).get();
    List<Map<DocumentReference, Map<String, dynamic>>> message_data = [];
    for (var doc in querySnapshot.docs) {
      Map<DocumentReference, Map<String, dynamic>> myMap = {
      doc.reference: doc.data()as Map<String,dynamic>,
      };
      message_data.add(myMap);
    }
    return message_data;
  }

  Future<void> createMessageDocument(List<String> userUids) async {
    Map<String, Map<String, dynamic>> conversation = {};
    Map<String, dynamic> data = {
      'user_uids': userUids,
      'conversation': conversation,
      'created_at': FieldValue.serverTimestamp(),
    };
    await messages.add(data);
  }

  Future<void> sendMessage(String message, DocumentReference dr, String user_uid) async {
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
