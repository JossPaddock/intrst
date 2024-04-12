import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:name_app/utility/FirebaseUtility.dart';
import '../models/Interest.dart';

class ButtonWidget extends StatelessWidget{
  final FirebaseUtility fu = FirebaseUtility();
  void addUserToFirestore(){
   print("user clicked 'click me' button");
   CollectionReference users = FirebaseFirestore.instance.collection('users');
   Interest interest = Interest();
   fu.addInterestForUser(users, interest, "RGKsufgcDWRaEqyYBh4aLjV8TV32");
  }
  @override
  Widget build(BuildContext context){
    return TextButton(onPressed: () { addUserToFirestore(); }, child: Text('Click Me'),);
  }
}
