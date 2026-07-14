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
// Removed flutter_quill and dart:convert imports as they are unused

class Interests extends StatefulWidget {
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool signedIn;
  final void Function(int) onItemTapped;
  final bool shouldCreateInterest;
  final String initialInterestName;

  const Interests({
    super.key,
    required this.name,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
    this.shouldCreateInterest = false,
    this.initialInterestName = '',
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
    if (widget.shouldCreateInterest) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _cardListKey.currentState
            ?.createNewInterest(initialName: widget.initialInterestName);
      });
    }
  }

  @override
  void didUpdateWidget(covariant Interests oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldCreateInterest && !oldWidget.shouldCreateInterest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _cardListKey.currentState
            ?.createNewInterest(initialName: widget.initialInterestName);
      });
    }
  }

  // Moved your fetch logic here
  Future<List<Interest>> _fetchSortedInterestsForUser(String userUid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, userUid);
    interests.sort(Interest.compareForDisplay);
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
              shouldCreateInterest: widget.shouldCreateInterest,
              initialInterestName: widget.initialInterestName,
            );
          }
        },
      );
    });
  }
}
