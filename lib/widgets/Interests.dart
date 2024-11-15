import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/widgets/InterestInputForm.dart';
import 'package:intrst/utility/FirebaseUtility.dart';
import '../models/Interest.dart';

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
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            List<Interest> interests = snapshot.data ?? [];
            return CardList(
              name: user.alternateName,
              uid: user.currentUid,
              signedIn: signedIn,
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

class CardList extends StatefulWidget {
  const CardList({
    super.key,
    required this.name,
    required this.uid,
    required this.signedIn,
    required this.interests,
    required this.showInputForm,
    required this.editToggles,
  });

  final String name;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final bool showInputForm;
  final List<bool> editToggles;

  @override
  State<CardList> createState() => _CardListState();
}

class _CardListState extends State<CardList> with AutomaticKeepAliveClientMixin <CardList>{
  @override
  bool get wantKeepAlive => true;
  final FirebaseUtility fu = FirebaseUtility();

  List<TextEditingController> _titleControllers = [];
  List<TextEditingController> _linkControllers = [];
  List<TextEditingController> _subtitleControllers = [];

  @override
  void initState() {
    super.initState();
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

  void updateToggles(String interestId, bool toggle) {
    Provider.of<UserModel>(context, listen: false)
        .updateToggle(interestId, toggle);
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
    UserModel userModel = Provider.of<UserModel>(context);
    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.white,
            width: 2.0,
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: 250,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
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
              ListView.builder(
                shrinkWrap: true,
                physics: AlwaysScrollableScrollPhysics(),
                itemCount: widget.interests.length,
                itemBuilder: (context, index) {
                  Interest interest = widget.interests[index];
                  String interestId =
                      interest.name; // Or a unique ID for the interest
                  bool toggle = userModel.getToggle(interestId);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _launchUrl(interest.link!),
                              child: toggle
                                  ? TextField(
                                      controller: _titleControllers[index],
                                      decoration: InputDecoration(
                                        labelText: 'Edit title here',
                                        border: OutlineInputBorder(),
                                      ),
                                    )
                                  : Text(
                                      interest.name,
                                      style: TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                            ),
                            SizedBox(height: 8),
                            toggle
                                ? Column(
                                    children: [
                                      TextField(
                                        maxLines: 3,
                                        controller: _subtitleControllers[index],
                                        decoration: InputDecoration(
                                          labelText: 'Edit description here',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      TextField(
                                        controller: _linkControllers[index],
                                        decoration: InputDecoration(
                                          labelText: 'Edit link here',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(interest.description),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (widget.showInputForm)
                                  IconButton(
                                    icon:
                                        Icon(toggle ? Icons.save : Icons.edit),
                                    onPressed: () {
                                      if (toggle) {
                                        // Save changes logic
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
                                      updateToggles(interestId, !toggle);
                                    },
                                  ),
                                if (widget.showInputForm)
                                  IconButton(
                                    icon: Icon(Icons.delete),
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
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (widget.signedIn && widget.showInputForm) InterestInputForm(),
            ],
          ),
        ),
      ),
    );
  }
}
