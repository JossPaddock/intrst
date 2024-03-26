import 'package:flutter/material.dart';

class ButtonWidget extends StatelessWidget{
  void addUserToFirestore(){
   print("user clicked 'click me' button");
  }
  @override
  Widget build(BuildContext context){
    return TextButton(onPressed: () { addUserToFirestore(); }, child: Text('Click Me'),);
  }
}
