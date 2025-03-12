import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final bool isSender;

  ChatBubble({required this.message, required this.isSender});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
        decoration: BoxDecoration(
          color: isSender ? Colors.blue : Colors.red,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: isSender ? Radius.circular(20) : Radius.zero,
            bottomRight: isSender ? Radius.zero : Radius.circular(20),
          ),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isSender ? Colors.white : Colors.black,
            fontSize: 17.0,
          ),
        ),
      ),
    );
  }
}