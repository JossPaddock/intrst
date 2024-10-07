import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intrst/widgets/InterestInputForm.dart';
import 'package:intrst/utility/FirebaseUtility.dart';
import '../models/Interest.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';

class Interests extends StatelessWidget {
  final String name;
  final bool signedIn;
  final FirebaseUtility fu = FirebaseUtility();

  Interests({super.key, required this.name, required this.signedIn});

  Future<List<Interest>> fetchSortedInterestsForUser(String user_uid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, user_uid);
    interests
        .sort((x, y) => y.updated_timestamp.compareTo(x.updated_timestamp));
    return interests;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(builder: (context, user, child) {
      return FutureBuilder<List<Interest>>(
        future: fetchSortedInterestsForUser(user.alternateUid),
        builder: (context, object) {
          if (object.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (object.hasError) {
            return Center(child: Text('Error: ${object.error}'));
          } else {
            List<Interest> interests = object.data ?? [];
            return CardList(
              name: user.alternateName,
              signedIn: signedIn,
              interests: interests,
              showInputForm: user.alternateUid == user.currentUid,
              editToggles: []
            );
          }
        },
      );
    });
  }
}

// ignore: must_be_immutable
class CardList extends StatefulWidget {
  const CardList({super.key,
    required this.name,
    required this.signedIn,
    required this.interests,
    required this.showInputForm,
    required this.editToggles});

  final String name;
  final bool signedIn;
  final List<Interest> interests;
  final bool showInputForm;
  final List<bool> editToggles;

  @override
  State<CardList> createState() => _CardList();

}
class _CardList extends State<CardList> {
  late List<bool> _editToggles;
  @override
  void initState() {
    super.initState();
    _editToggles = widget.editToggles;
  }
  void updateToggles(int index, bool toggle) {
    List<bool> editTogglesCopy = _editToggles;
    editTogglesCopy[index] = toggle;
    setState(() {
      _editToggles = editTogglesCopy;
    });
  }
  Future<void> _launchUrl(String url) async {
    if (!url.startsWith('http://') &&
        !url.startsWith('https://')) {
      url = 'http://' + url;
    }
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }
  @override
  Widget build(BuildContext context) {
    _editToggles = [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 100, 0, 0),
              child: Text(
                widget.name,
                style: TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        Flexible(
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: 120.0 * widget.interests.length,

              ),
              child: ListView.builder(
                itemCount: widget.interests.length,
                itemBuilder: (context, index) {
                  _editToggles.add(false);
                  Interest interest = widget.interests[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                    child: Card(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 200,
                          maxHeight: 600,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ListTile(
                              title:GestureDetector(
                                  onTap: ()=> _launchUrl(interest.link!),
                                  child: _editToggles[index] ?
                                  TextField(
                                  ):Text(
                                    interest.name,
                                    style: TextStyle(
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                      ),
                              subtitle: _editToggles[index] ?
                              TextField(
                              ):Text(interest.description),
                              //trailing:
                                  //Text(interest.created_timestamp.toString()),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                /*TextButton(
                                  child: const Icon(Icons.link),
                                  onPressed: () {
                                    if (interest.link != null) {
                                      String url = interest.link!;
                                      if (!url.startsWith('http://') &&
                                          !url.startsWith('https://')) {
                                        url = 'http://' + url;
                                      }
                                      html.window.open(url, '_blank');
                                    }
                                  },
                                ),*/
                                const SizedBox(width: 0),
                                if (widget.showInputForm)
                                  TextButton(
                                    child: const Icon(Icons.edit),
                                    onPressed: () {
                                      //_editToggles[index] = !_editToggles[index];
                                      updateToggles(index, !_editToggles[index]);
                                      setState(() {});
                                      print(_editToggles);
                                      print(index);
                                      setState(() {});
                                    },
                                  ),
                                const SizedBox(width: 0),
                                if (widget.showInputForm)
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
          ),
        ),
        if (widget.signedIn)
          Padding(
              padding: const EdgeInsets.fromLTRB(200, 5, 200, 80),
              child: (widget.showInputForm) ? (InterestInputForm()) : Text(''))
      ],
    );
  }
}
