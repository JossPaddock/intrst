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
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';

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

  // Controllers keyed by interest id (fallback to name if id is null)
  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _linkControllers = {};
  final Map<String, QuillController> _quillControllers = {};

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  late QuillController _mobileQuillController;

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
    _mobileQuillController = QuillController.basic();
    _syncControllersWithInterests();
  }

  @override
  void didUpdateWidget(covariant CardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interests != oldWidget.interests) {
      setState(() {
        localInterests = widget.interests;
        _syncControllersWithInterests();
      });
    }
  }

  void _syncControllersWithInterests() {
    final currentIds = localInterests.map((i) => i.id ?? i.name).toSet();
    final keysToRemove = <String>[];

    for (final existingId in _titleControllers.keys) {
      if (!currentIds.contains(existingId)) {
        keysToRemove.add(existingId);
      }
    }

    for (final id in keysToRemove) {
      _titleControllers[id]?.dispose();
      _titleControllers.remove(id);
      _quillControllers[id]?.dispose();
      _quillControllers.remove(id);
      _linkControllers[id]?.dispose();
      _linkControllers.remove(id);
    }

    for (final interest in localInterests) {
      final id = interest.id ?? interest.name;

      if (!_titleControllers.containsKey(id)) {
        _titleControllers[id] = TextEditingController(text: interest.name);
      } else {
        final t = _titleControllers[id]!;
        if (t.text != interest.name) t.text = interest.name;
      }

      // Quill controller for description
      if (!_quillControllers.containsKey(id)) {
        _quillControllers[id] = _createQuillController(interest.description);
      } else {
        final currentText = _quillControllers[id]!.document.toPlainText();
        if (currentText != interest.description) {
          _quillControllers[id]!.dispose();
          _quillControllers[id] = _createQuillController(interest.description);
        }
      }

      // link
      if (!_linkControllers.containsKey(id)) {
        _linkControllers[id] =
            TextEditingController(text: interest.link ?? '');
      } else {
        final l = _linkControllers[id]!;
        final linkText = interest.link ?? '';
        if (l.text != linkText) l.text = linkText;
      }
    }
  }

  QuillController _createQuillController(String text) {
    try {
      final doc = Document.fromJson(jsonDecode(text));
      return QuillController(
        document: doc,
        selection: TextSelection.collapsed(offset: 0),
      );
    } catch (e) {
      // If it's not JSON, treat as plain text
      final doc = Document()..insert(0, text);
      return QuillController(
        document: doc,
        selection: TextSelection.collapsed(offset: 0),
      );
    }
  }

  String _getQuillPlainText(QuillController controller) {
    return controller.document.toPlainText().trim();
  }

  String _getQuillJson(QuillController controller) {
    return jsonEncode(controller.document.toDelta().toJson());
  }

  void _disposeControllersForId(String id) {
    _titleControllers[id]?.dispose();
    _titleControllers.remove(id);
    _quillControllers[id]?.dispose();
    _quillControllers.remove(id);
    _linkControllers[id]?.dispose();
    _linkControllers.remove(id);
  }

  @override
  void dispose() {
    for (var controller in _titleControllers.values) {
      controller.dispose();
    }
    for (var controller in _linkControllers.values) {
      controller.dispose();
    }
    for (var controller in _quillControllers.values) {
      controller.dispose();
    }
    _mobileTitleController.dispose();
    _mobileLinkController.dispose();
    _mobileQuillController.dispose();
    super.dispose();
  }

  void updateToggles(String interestId, bool toggle) {
    Provider.of<UserModel>(context, listen: false)
        .updateToggle(interestId, toggle);
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;
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
    super.build(context);
    UserModel userModel = Provider.of<UserModel>(context);

    double deviceScreenHeight = MediaQuery.of(context).size.height;
    double maxHeight = deviceScreenHeight * 0.88;

    _syncControllersWithInterests();

    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.transparent,
          width: 5.0,
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: maxHeight,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(width: 45),
              Container(
                padding: EdgeInsets.all(3),
                color: Color.fromRGBO(6, 28, 39, 1.0),
                child: Text(
                  widget.name,
                  style: TextStyle(
                    color: Colors.white,
                    backgroundColor: Color.fromRGBO(6, 28, 39, 1.0),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                iconSize: 20,
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
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: localInterests.length,
                  itemBuilder: (context, index) {
                    Interest interest = localInterests[index];
                    final String id = interest.id ?? interest.name;
                    final String toggleKey = id;
                    bool toggle = userModel.getToggle(toggleKey);

                    final titleController = _titleControllers[id] ??
                        TextEditingController();
                    final quillController = _quillControllers[id] ??
                        _createQuillController(interest.description);
                    final linkController = _linkControllers[id] ??
                        TextEditingController();

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 8.0),
                      child: Card(
                        key: ValueKey(id),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _launchUrl(interest.link),
                                child: toggle
                                    ? TextField(
                                        controller: titleController,
                                        decoration: InputDecoration(
                                          labelText: 'Edit title here',
                                          border: OutlineInputBorder(),
                                        ),
                                      )
                                    : Text(
                                        interest.name,
                                        style: TextStyle(
                                          color: Colors.blue,
                                          decoration:
                                              TextDecoration.underline,
                                        ),
                                      ),
                              ),
                              SizedBox(height: 8),
                              toggle
                                  ? Column(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Column(
                                            children: [
                                              QuillSimpleToolbar(
                                                controller: quillController,
                                         
                                              ),
                                              Container(
                                                height: 150,
                                                padding: EdgeInsets.all(8),
                                                child: QuillEditor.basic(
                                                  controller: quillController,
                                          
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        TextField(
                                          controller: linkController,
                                          decoration: InputDecoration(
                                            labelText: 'Edit link here',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Container(
                                      padding: EdgeInsets.all(8),
                                      child: QuillEditor.basic(
                                        controller: quillController,
                                        
                                      ),
                                    ),
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

                                          setState(() {
                                            localInterests[index] =
                                                newInterest;
                                            final nid = newInterest.id ??
                                                newInterest.name;
                                            _titleControllers[nid]?.text =
                                                newInterest.name;
                                            _linkControllers[nid]?.text =
                                                newInterest.link ?? '';
                                          });

                                          await fu.updateEditedInterest(users,
                                              interest, newInterest, widget.uid);
                                          List<Interest> updatedInterests =
                                              await refreshInterestsForUser(
                                                  widget.uid);

                                          setState(() {
                                            localInterests = updatedInterests;
                                            _syncControllersWithInterests();
                                          });
                                        }),
                                  if (widget.showInputForm)
                                    IconButton(
                                      icon: Icon(
                                          toggle ? Icons.save : Icons.edit),
                                      onPressed: () async {
                                        if (!gu.isMobileBrowser(context)) {
                                          if (toggle) {
                                            CollectionReference users =
                                                FirebaseFirestore.instance
                                                    .collection('users');
                                            Interest newInterest =
                                                interest.copyWith(
                                              name: titleController.text,
                                              description:
                                                  _getQuillJson(quillController),
                                              link: linkController.text,
                                              created_timestamp:
                                                  interest.created_timestamp,
                                              updated_timestamp: DateTime.now(),
                                            );

                                            await fu.updateEditedInterest(
                                                users,
                                                interest,
                                                newInterest,
                                                widget.uid);

                                            setState(() {
                                              localInterests[index] =
                                                  newInterest;
                                              final String oldId = id;
                                              final String newId =
                                                  newInterest.id ??
                                                      newInterest.name;

                                              if (oldId != newId) {
                                                final t = _titleControllers
                                                    .remove(oldId);
                                                final q = _quillControllers
                                                    .remove(oldId);
                                                final l = _linkControllers
                                                    .remove(oldId);

                                                if (t != null) {
                                                  _titleControllers[newId] =
                                                      t..text = newInterest.name;
                                                } else {
                                                  _titleControllers[newId] =
                                                      TextEditingController(
                                                          text: newInterest.name);
                                                }

                                                if (q != null) {
                                                  _quillControllers[newId] = q;
                                                } else {
                                                  _quillControllers[newId] =
                                                      _createQuillController(
                                                          newInterest.description);
                                                }

                                                if (l != null) {
                                                  _linkControllers[newId] =
                                                      l..text = newInterest.link ?? '';
                                                } else {
                                                  _linkControllers[newId] =
                                                      TextEditingController(
                                                          text: newInterest.link ?? '');
                                                }
                                              } else {
                                                _titleControllers[id]?.text =
                                                    newInterest.name;
                                                _linkControllers[id]?.text =
                                                    newInterest.link ?? '';
                                              }
                                            });
                                          }
                                          updateToggles(toggleKey, !toggle);
                                        } else {
                                          // mobile path
                                          _mobileTitleController.text =
                                              titleController.text;
                                          _mobileLinkController.text =
                                              linkController.text;

                                          _mobileQuillController.dispose();
                                          _mobileQuillController =
                                              _createQuillController(
                                                  _getQuillJson(quillController));

                                          Interest dialogueInterest = Interest(
                                              created_timestamp: DateTime.now(),
                                              updated_timestamp: DateTime.now());
                                          bool editCancelled = false;

                                          await showDialog<String>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext context) =>
                                                AlertDialog(
                                              content: SingleChildScrollView(
                                                child: Column(children: [
                                                  TextField(
                                                    controller:
                                                        _mobileTitleController,
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          'Edit title here',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                  ),
                                                  SizedBox(height: 10),
                                                  Container(
                                                    height: 250,
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: Colors.grey),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        QuillSimpleToolbar(
                                                          controller:
                                                              _mobileQuillController,
                                                          
                                                        ),
                                                        Expanded(
                                                          child: Container(
                                                            padding:
                                                                EdgeInsets.all(
                                                                    8),
                                                            child: QuillEditor
                                                                .basic(
                                                              controller:
                                                                  _mobileQuillController,
                                                              
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  SizedBox(height: 10),
                                                  TextField(
                                                    controller:
                                                        _mobileLinkController,
                                                    decoration: InputDecoration(
                                                      labelText:
                                                          'Edit link here',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                  ),
                                                ]),
                                              ),
                                              actions: <Widget>[
                                                Center(
                                                  child: Row(children: <Widget>[
                                                    IconButton(
                                                      icon: Icon(Icons.save),
                                                      onPressed: () {
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
                                                          description: _getQuillJson(
                                                              _mobileQuillController),
                                                          link:
                                                              _mobileLinkController
                                                                  .text,
                                                          created_timestamp:
                                                              interest
                                                                  .created_timestamp,
                                                          updated_timestamp:
                                                              DateTime.now(),
                                                        );

                                                        dialogueInterest =
                                                            newInterest;
                                                        fu.updateEditedInterest(
                                                            users,
                                                            interest,
                                                            newInterest,
                                                            widget.uid);

                                                        _titleControllers[id]
                                                                ?.text =
                                                            _mobileTitleController
                                                                .text;
                                                        _linkControllers[id]
                                                                ?.text =
                                                            _mobileLinkController
                                                                .text;

                                                        Navigator.pop(
                                                            context, 'saving');
                                                      }),
                                                    IconButton(
                                                        icon:
                                                            Icon(Icons.cancel),
                                                        onPressed: () {
                                                          editCancelled = true;
                                                          Navigator.pop(context,
                                                              'cancel');
                                                        }),
                                                  ]),
                                                ),
                                              ],
                                            ),
                                          );

                                          setState(() {
                                            if (!editCancelled) {
                                              localInterests[index] =
                                                  dialogueInterest;
                                              _syncControllersWithInterests();
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
                                              child:
                                                  Column(children: <Widget>[
                                                TextButton(
                                                  onPressed: () {
                                                    CollectionReference users =
                                                        FirebaseFirestore
                                                            .instance
                                                            .collection('users');
                                                    Interest oldInterest =
                                                        Interest(
                                                      id: interest.id,
                                                      nextInterestId: interest
                                                          .nextInterestId,
                                                      active: interest.active,
                                                      name: interest.name,
                                                      description:
                                                          interest.description,
                                                      link: interest.link,
                                                      favorite:
                                                          interest.favorite,
                                                      favorited_timestamp:
                                                          interest
                                                              .favorited_timestamp,
                                                      created_timestamp: interest
                                                          .created_timestamp,
                                                      updated_timestamp: interest
                                                          .updated_timestamp,
                                                    );

                                                    fu.removeInterest(users,
                                                        oldInterest, widget.uid);

                                                    setState(() {
                                                      _disposeControllersForId(
                                                          id);
                                                      localInterests
                                                          .removeAt(index);
                                                    });

                                                    Navigator.pop(
                                                        context, 'Delete');
                                                  },
                                                  child: const Text('Yes'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context,
                                                          'Never mind'),
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
                              Navigator.pop(context);
                              widget.onItemTapped(1);
                            },
                            child: Text("Sign in or Sign Up"))),
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
                  ])),
            ),
          ),
        if (widget.signedIn && widget.showInputForm)
          Column(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: InterestInputForm(),
              ),
              SizedBox(height: 20)
            ],
          )
      ]),
    );
  }
}