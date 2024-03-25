import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ButtonWidget extends StatelessWidget{
  void addUserToFirestore(){
   print("user clicked 'click me' button");
  }
  Widget build(BuildContext context){
    return TextButton(onPressed: () { addUserToFirestore(); }, child: Text('Click Me'),);
  }
}
