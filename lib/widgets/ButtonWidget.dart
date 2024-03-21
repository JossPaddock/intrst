import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ButtonWidget extends StatelessWidget{
 String user_uid = '';

  void initState() {
    FirebaseAuth.instance
        .authStateChanges()
        .listen((User? user) {
      if (user != null) {
        print(user.uid);
        user_uid = user.uid;
      }
    });
  }
  void addUserToFirestore(){
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    Map<String, dynamic> userData = {
      'user_uid': user_uid,
      'first_name': 'John',
      'last_name': 'Doe',
      'interests': [],
      'location': GeoPoint(0,0),
    };
    users.add(userData)
        .then((value) => print("User added to Firestore"))
        .catchError((error) => print("Failed to add user: $error"));
  }
  Widget build(BuildContext context){
    return TextButton(onPressed: () { addUserToFirestore(); }, child: Text('Click Me'),);
  }
}
