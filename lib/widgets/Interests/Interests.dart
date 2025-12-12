import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:intrst/widgets/Interests/CardList.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../../models/Interest.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';

class Interests extends StatefulWidget {
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool signedIn;
  final void Function(int) onItemTapped;

  const Interests({
    super.key,
    required this.name,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
  });

  @override
  State<Interests> createState() => _InterestsState();
}

class _InterestsState extends State<Interests> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();

  final GlobalKey<CardListState> _cardListKey = GlobalKey<CardListState>();
  
  // 1. Store these in State so they don't reset on rebuilds
  Future<List<Interest>>? _interestsFuture;
  String? _lastUid; // To track if the user changed

  @override
  void initState() {
    super.initState();
  }

  // Moved your fetch logic here
  Future<List<Interest>> _fetchSortedInterestsForUser(String userUid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, userUid);
    interests.sort((x, y) => y.updated_timestamp.compareTo(x.updated_timestamp));
    return interests;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(builder: (context, user, child) {
      
      // 2. Only create a NEW future if the User ID has actually changed.
      // Otherwise, keep using the existing loaded data.
      if (_interestsFuture == null || _lastUid != user.alternateUid) {
        _lastUid = user.alternateUid;
        _interestsFuture = _fetchSortedInterestsForUser(_lastUid!);
      }

      return FutureBuilder<List<Interest>>(
        future: _interestsFuture, // Use the CACHED future
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            List<Interest> interests = snapshot.data ?? [];

            return CardList(
              key: _cardListKey, // Use the CACHED key
              cardListKey: _cardListKey,
              name: user.alternateName,
              scaffoldKey: widget.scaffoldKey,
              uid: user.currentUid,
              signedIn: widget.signedIn,
              onItemTapped: widget.onItemTapped,
              interests: interests,
              showInputForm: user.alternateUid == user.currentUid,
              editToggles: [],
            );
          }
        },
      );
    });
  }
}