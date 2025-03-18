import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intrst/utility/FirebaseMappers.dart';
import '../models/Interest.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

class FirebaseMessagesUtility {
  final CollectionReference messages =
      FirebaseFirestore.instance.collection('messages');
  Future<List<Map<String,dynamic>>> getMessageDocumentsByUserUid(String userUid) async {
    QuerySnapshot querySnapshot =
        await messages.where('user_uids', arrayContains: userUid).get();
    List<Map<String,dynamic>> message_data = [];
    for (var doc in querySnapshot.docs) {
      message_data.add(doc.data() as Map<String,dynamic>);
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
}
