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
                uid: user.currentUid,
                signedIn: signedIn,
                interests: interests,
                showInputForm: user.alternateUid == user.currentUid,
                editToggles: []);
          }
        },
      );
    });
  }
}

// ignore: must_be_immutable
class CardList extends StatefulWidget {
  const CardList(
      {super.key,
      required this.name,
      required this.uid,
      required this.signedIn,
      required this.interests,
      required this.showInputForm,
      required this.editToggles});

  final String name;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final bool showInputForm;
  final List<bool> editToggles;

  @override
  State<CardList> createState() => _CardList();
}

class _CardList extends State<CardList> {
  late List<bool> _editToggles;
  final FirebaseUtility fu = FirebaseUtility();

  List<TextEditingController> _titleControllers = [];
  List<TextEditingController> _linkControllers = [];
  List<TextEditingController> _subtitleControllers = [];

  @override
  void initState() {
    super.initState();
    _editToggles = List<bool>.filled(widget.interests.length, false);
    _titleControllers = List.generate(
        widget.interests.length, (index) => TextEditingController());
    _linkControllers = List.generate(
        widget.interests.length, (index) => TextEditingController());
    _subtitleControllers = List.generate(
        widget.interests.length, (index) => TextEditingController());

    for (int i = 0; i < widget.interests.length; i++) {
      _titleControllers[i].text = widget.interests[i].name;
      _linkControllers[i].text = widget.interests[i].link ?? '';
      _subtitleControllers[i].text = widget.interests[i].description;
    }
  }

  @override
  void dispose() {
    // Dispose of the controllers when the widget is disposed.
    for (var controller in _titleControllers) {
      controller.dispose();
    }
    for (var controller in _linkControllers) {
      controller.dispose();
    }
    for (var controller in _subtitleControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void updateToggles(int index, bool toggle) {
    setState(() {
      _editToggles[index] = toggle;
    });
  }

  Future<void> _launchUrl(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
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
                              title: GestureDetector(
                                onTap: () => _launchUrl(interest.link!),
                                child: _editToggles[index]
                                    ? Column(children: [
                                        SizedBox(height: 10),
                                        TextField(
                                          controller: _titleControllers[index],
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(),
                                            labelText: 'Edit title here',
                                          ),
                                        ),
                                      ])
                                    : Text(
                                        interest.name,
                                        style: TextStyle(
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                              ),
                              subtitle: _editToggles[index]
                                  ? Column(children: [
                                      SizedBox(height: 20),
                                      TextField(
                                        controller: _subtitleControllers[index],
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Edit description here',
                                        ),
                                      ),
                                      SizedBox(height: 20),
                                      TextField(
                                        controller: _linkControllers[index],
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(),
                                          labelText: 'Edit link here',
                                        ),
                                      ),
                                    ])
                                  : Text(interest.description),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                if (widget.showInputForm)
                                  TextButton(
                                    child: !_editToggles[index]
                                        ? const Icon(Icons.edit)
                                        : const Icon(Icons.save),
                                    onPressed: () {
                                      if (_editToggles[index]) {
                                        // Save the new interest details
                                        CollectionReference users =
                                            FirebaseFirestore.instance
                                                .collection('users');
                                        Interest oldInterest = Interest(
                                          name: interest.name,
                                          description: interest.description,
                                          link: interest.link,
                                          created_timestamp:
                                              interest.created_timestamp,
                                          updated_timestamp:
                                              interest.updated_timestamp,
                                        );
                                        Interest newInterest = Interest(
                                          name: _titleControllers[index].text,
                                          description:
                                              _subtitleControllers[index].text,
                                          link: _linkControllers[index].text,
                                          created_timestamp:
                                              interest.created_timestamp,
                                          updated_timestamp: DateTime.now(),
                                        );
                                        setState(() {
                                          widget.interests[index] = newInterest;
                                        });
                                        fu.updateEditedInterest(
                                            users,
                                            oldInterest,
                                            newInterest,
                                            widget.uid);
                                      }
                                      updateToggles(
                                          index, !_editToggles[index]);
                                      setState(() {});
                                    },
                                  ),
                                if (widget.showInputForm)
                                  TextButton(
                                    child: const Icon(Icons.delete),
                                    onPressed: () => showDialog<String>(
                                      context: context,
                                      builder: (BuildContext context) =>
                                          AlertDialog(
                                        title: const Text(
                                            'Are you sure you want\nto delete this interest?'),
                                        content: Text(
                                            'This will permanently delete\nthe interest ${interest.name}',
                                            textAlign: TextAlign.center),
                                        actions: <Widget>[
                                           Center(
                                            child: Column(children: <Widget>[
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, 'Never mind'),
                                                child: const Text('Never mind'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  CollectionReference users =
                                                      FirebaseFirestore.instance
                                                          .collection('users');
                                                  Interest oldInterest =
                                                      Interest(
                                                    name: interest.name,
                                                    description:
                                                        interest.description,
                                                    link: interest.link,
                                                    created_timestamp: interest
                                                        .created_timestamp,
                                                    updated_timestamp: interest
                                                        .updated_timestamp,
                                                  );
                                                  fu.removeInterest(users,
                                                      oldInterest, widget.uid);
                                                  setState(() {
                                                    widget.interests
                                                        .removeAt(index);
                                                  });
                                                  Navigator.pop(
                                                      context, 'Delete');
                                                },
                                                child: const Text('Delete'),
                                              ),
                                            ]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
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
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: (widget.showInputForm) ? (InterestInputForm()) : Text(''))
      ],
    );
  }
}
