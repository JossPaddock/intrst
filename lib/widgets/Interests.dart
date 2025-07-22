import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/widgets/InterestInputForm.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../models/Interest.dart';

class Interests extends StatelessWidget {
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final bool signedIn;
  final void Function(int) onItemTapped;
  final FirebaseUsersUtility fu = FirebaseUsersUtility();

  Interests({
    super.key,
    required this.name,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
  });

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
              scaffoldKey: scaffoldKey,
              uid: user.currentUid,
              signedIn: signedIn,
              onItemTapped: onItemTapped,
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
    required this.scaffoldKey,
    required this.uid,
    required this.signedIn,
    required this.interests,
    required this.onItemTapped,
    required this.showInputForm,
    required this.editToggles,
  });

  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final void Function(int) onItemTapped;
  final bool showInputForm;
  final List<bool> editToggles;

  @override
  State<CardList> createState() => _CardListState();
}

class _CardListState extends State<CardList>
    with AutomaticKeepAliveClientMixin<CardList> {
  @override
  bool get wantKeepAlive => true;
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  List<TextEditingController> _titleControllers = [];
  List<TextEditingController> _linkControllers = [];
  List<TextEditingController> _subtitleControllers = [];

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  TextEditingController _mobileSubtitleController = TextEditingController();
  late List<Interest> localInterests = widget.interests;
  GeneralUtility gu = GeneralUtilityWeb();

  Future<List<Interest>> refreshInterestsForUser(String user_uid) async {
    return Interests(
      name: widget.name,
      scaffoldKey: widget.scaffoldKey,
      signedIn: widget.signedIn,
      onItemTapped: widget.onItemTapped,
    ).fetchSortedInterestsForUser(user_uid);
  }

  @override
  void initState() {
    super.initState();
    _titleControllers = List.generate(
        localInterests.length, (index) => TextEditingController());
    _linkControllers = List.generate(
        localInterests.length, (index) => TextEditingController());
    _subtitleControllers = List.generate(
        localInterests.length, (index) => TextEditingController());

    for (int i = 0; i < localInterests.length; i++) {
      _titleControllers[i].text = localInterests[i].name;
      _linkControllers[i].text = localInterests[i].link ?? '';
      _subtitleControllers[i].text = localInterests[i].description;
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
    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white,
          width: 2.0,
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: 700,
      ),
      child: Stack(children: [
        SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Spacer(flex: 1),
                    Text(
                      widget.name,
                      style: TextStyle(
                        color: Colors.white,
                        backgroundColor: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(flex: 1),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        widget.scaffoldKey.currentState?.closeEndDrawer();
                      },
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: localInterests.length,
                itemBuilder: (context, index) {
                  Interest interest = localInterests[index];
                  String interestId =
                      interest.name; // Or a unique ID for the interest
                  bool toggle = userModel.getToggle(interestId);

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 8.0),
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
                                      icon: Icon(Icons.star,
                                          color: interest.favorite
                                              ? Colors.orange
                                              : Colors.blueGrey),
                                      onPressed: () async {
                                        CollectionReference users =
                                            FirebaseFirestore.instance
                                                .collection('users');
                                        bool favorited = !interest.favorite;
                                        Interest newInterest =
                                            interest.copyWith(
                                                favorite: !interest.favorite,
                                                favorited_timestamp: favorited
                                                    ? DateTime.now()
                                                    : interest
                                                        .favorited_timestamp);
                                        //apply this to the local state of favorite interests to update immediately
                                        //on the interest widget update before the database updates.
                                        setState(() {
                                          localInterests[index] = newInterest;
                                        });
                                        await fu.updateEditedInterest(users,
                                            interest, newInterest, widget.uid);
                                        List<Interest> updatedInterests =
                                            await refreshInterestsForUser(
                                                widget.uid);
                                        setState(() {
                                          //localInterests[index] = newInterest;
                                          localInterests = updatedInterests;
                                        });
                                      }),
                                IconButton(
                                  icon: Icon(toggle ? Icons.save : Icons.edit),
                                  onPressed: () async {
                                    if (!gu.isMobileBrowser(context)) {
                                      if (toggle) {
                                        // Save changes logic
                                        CollectionReference users =
                                            FirebaseFirestore.instance
                                                .collection('users');
                                        Interest newInterest =
                                            interest.copyWith(
                                          name: _titleControllers[index].text,
                                          description:
                                              _subtitleControllers[index].text,
                                          link: _linkControllers[index].text,
                                          created_timestamp:
                                              interest.created_timestamp,
                                          updated_timestamp: DateTime.now(),
                                        );
                                        await fu.updateEditedInterest(users,
                                            interest, newInterest, widget.uid);
                                        setState(() {
                                          localInterests[index] = newInterest;
                                        });
                                      }
                                      updateToggles(interestId, !toggle);
                                    } else {
                                      _mobileTitleController.text =
                                          _titleControllers[index].text;
                                      _mobileSubtitleController.text =
                                          _subtitleControllers[index].text;
                                      _mobileLinkController.text =
                                          _linkControllers[index].text;
                                      Interest dialogueInterest = Interest(
                                          created_timestamp: DateTime.now(),
                                          updated_timestamp: DateTime.now());
                                      bool editCancelled = false;
                                      await showDialog<String>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (BuildContext context) =>
                                            AlertDialog(
                                          content: Column(children: [
                                            TextField(
                                              controller:
                                                  _mobileTitleController,
                                              decoration: InputDecoration(
                                                labelText: 'Edit title here',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            SizedBox(height: 10),
                                            TextField(
                                              maxLines: 2,
                                              controller:
                                                  _mobileSubtitleController,
                                              decoration: InputDecoration(
                                                labelText:
                                                    'Edit description here',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            SizedBox(height: 10),
                                            TextField(
                                              controller: _mobileLinkController,
                                              decoration: InputDecoration(
                                                labelText: 'Edit link here',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ]),
                                          actions: <Widget>[
                                            Center(
                                              child: Row(children: <Widget>[
                                                IconButton(
                                                    icon: Icon(Icons.save),
                                                    onPressed: () {
                                                      print(
                                                          'attempting to save');
                                                      // Save changes logic
                                                      CollectionReference
                                                          users =
                                                          FirebaseFirestore
                                                              .instance
                                                              .collection(
                                                                  'users');
                                                      Interest newInterest =
                                                          interest.copyWith(
                                                        name:
                                                            _mobileTitleController
                                                                .text,
                                                        description:
                                                            _mobileSubtitleController
                                                                .text,
                                                        link:
                                                            _mobileLinkController
                                                                .text,
                                                        created_timestamp: interest
                                                            .created_timestamp,
                                                        updated_timestamp:
                                                            DateTime.now(),
                                                      );
                                                      dialogueInterest =
                                                          newInterest;
                                                      //setState(() {
                                                      //widget.interests[index] = newInterest;
                                                      //});
                                                      fu.updateEditedInterest(
                                                          users,
                                                          interest,
                                                          newInterest,
                                                          widget.uid);
                                                      _titleControllers[index]
                                                              .text =
                                                          _mobileTitleController
                                                              .text;
                                                      _subtitleControllers[
                                                                  index]
                                                              .text =
                                                          _mobileSubtitleController
                                                              .text;
                                                      _linkControllers[index]
                                                              .text =
                                                          _mobileLinkController
                                                              .text;
                                                      Navigator.pop(
                                                          context, 'saving');
                                                    }),
                                                IconButton(
                                                    icon: Icon(Icons.cancel),
                                                    onPressed: () {
                                                      editCancelled = true;
                                                      Navigator.pop(
                                                          context, 'cancel');
                                                    }),
                                              ]),
                                            ),
                                          ],
                                        ),
                                      );
                                      //await Future.delayed(Duration(milliseconds: 1000));
                                      setState(() {
                                        if (!editCancelled) {
                                          localInterests[index] =
                                              dialogueInterest;
                                        }
                                      });
                                    }
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
                                            'This will permanently delete\nthe interest \"${interest.name}\"',
                                            textAlign: TextAlign.center),
                                        actions: <Widget>[
                                          Center(
                                            child: Column(children: <Widget>[
                                              TextButton(
                                                onPressed: () {
                                                  CollectionReference users =
                                                      FirebaseFirestore.instance
                                                          .collection('users');
                                                  Interest oldInterest =
                                                      Interest(
                                                    id: interest.id,
                                                    nextInterestId:
                                                        interest.nextInterestId,
                                                    active: interest.active,
                                                    name: interest.name,
                                                    description:
                                                        interest.description,
                                                    link: interest.link,
                                                    favorite: interest.favorite,
                                                    favorited_timestamp: interest
                                                        .favorited_timestamp,
                                                    created_timestamp: interest
                                                        .created_timestamp,
                                                    updated_timestamp: interest
                                                        .updated_timestamp,
                                                  );
                                                  print(oldInterest.mapper());
                                                  fu.removeInterest(users,
                                                      oldInterest, widget.uid);
                                                  setState(() {
                                                    localInterests
                                                        .removeAt(index);
                                                  });
                                                  Navigator.pop(
                                                      context, 'Delete');
                                                },
                                                child: const Text('Yes'),
                                              ),
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, 'Never mind'),
                                                child: const Text('No'),
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
            ],
          ),
        ),
        if (!widget.signedIn)
          Align(
            alignment: Alignment.center,
            child: Card(
              margin: EdgeInsets.all(16),
              child: SizedBox(
                  width: 300,
                  height: 150,
                  child: Column(children: [
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: ElevatedButton(
                          onPressed: () {
                            print('button pressed navigates to the sign in page');
                            Navigator.pop(context);
                            widget.onItemTapped(1);
                          }, //navigate to signup page
                          child: Text("Sign in or Sign Up"))
                    ),
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Center(
                        child: Text(
                          'to access your interests page.',
                          style: TextStyle(
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ]))),),
        if (widget.signedIn && widget.showInputForm)
          Align(
            alignment: Alignment.bottomCenter,
            child: InterestInputForm(),
          ),
      ]),
    );
  }
}
