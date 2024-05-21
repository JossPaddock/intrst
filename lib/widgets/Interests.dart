import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:name_app/widgets/InterestInputForm.dart';
import 'package:name_app/utility/FirebaseUtility.dart';
import '../models/Interest.dart';
import 'package:provider/provider.dart';
import 'package:name_app/models/UserModel.dart';

class Interests extends StatelessWidget {
  final String name;
  final bool signedIn;
  final FirebaseUtility fu = FirebaseUtility();

  Interests({super.key, required this.name, required this.signedIn});

  Future<List<Interest>> fetchInterestsForUser(String user_uid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, user_uid);
    return interests;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(builder: (context, user, child) {
      return FutureBuilder<List<Interest>>(
        future: fetchInterestsForUser(user.currentUid),
        builder: (context, object) {
          if (object.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (object.hasError) {
            return Center(child: Text('Error: ${object.error}'));
          } else {
            List<Interest> interests = object.data ?? [];
            return CardList(
              name: name,
              signedIn: signedIn,
              interests: interests,
            );
          }
        },
      );
    });
  }
}

// ignore: must_be_immutable
class CardList extends StatelessWidget {
  CardList(
      {super.key,
      required this.name,
      required this.signedIn,
      required this.interests});

  final String name;
  final bool signedIn;
  final List<Interest> interests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 100, 0, 0),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: interests.length,
            itemBuilder: (context, index) {
              Interest interest = interests[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(200, 5, 200, 5),
                child: Card(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                      maxHeight: 1200,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ListTile(
                          title: Text(interest.name),
                          subtitle: Text(interest.description),
                          trailing: Text(interest.created_timestamp.toString()),

                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              child: const Icon(Icons.link),
                              onPressed: () {/* ... */},
                            ),
                            const SizedBox(width: 0),
                            TextButton(
                              child: const Icon(Icons.edit),
                              onPressed: () {/* ... */},
                            ),
                            const SizedBox(width: 0),
                            TextButton(
                              child: const Icon(Icons.star),
                              onPressed: () {/* ... */},
                            ),
                            const SizedBox(width: 0),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (signedIn)
          Padding(
              padding: const EdgeInsets.fromLTRB(200, 5, 200, 80),
              child: InterestInputForm())
      ],
    );
  }
}
