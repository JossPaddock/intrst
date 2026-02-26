import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../../login/LoginScreen.dart';
import '../../models/Interest.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';
import '../../utility/url_validator/url_validator.dart';

class CardList extends StatefulWidget {
  //static GlobalKey<_CardListState> createGlobalKey() => GlobalKey<_CardListState>();

  // FIX 2: Update your helper method if you use it
  static GlobalKey<CardListState> createGlobalKey() =>
      GlobalKey<CardListState>();

  const CardList({
    super.key,
    required this.cardListKey,
    required this.name,
    required this.scaffoldKey,
    required this.uid,
    required this.signedIn,
    required this.interests,
    required this.onItemTapped,
    required this.showInputForm,
    required this.editToggles,
  });

  final GlobalKey<CardListState> cardListKey;
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final void Function(int) onItemTapped;
  final bool showInputForm;
  final List<bool> editToggles;

  @override
  //State<CardList> createState() => _CardListState();
  //fix 1
  CardListState createState() => CardListState();
}

class CardListState extends State<CardList>
    with AutomaticKeepAliveClientMixin<CardList> {
  @override
  bool get wantKeepAlive => true;

  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  bool get isEditingAny {
    final userModel = Provider.of<UserModel>(context, listen: false);
    return localInterests.any(
      (i) => userModel.getToggle(i.id) == true,
    );
  }

  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _linkControllers = {};
  final Map<String, QuillController> _quillControllers = {};

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  late QuillController _mobileQuillController;

  late List<Interest> localInterests = widget.interests;

  GeneralUtility gu = GeneralUtilityWeb();

  Future<void> _deleteInterestSilently(Interest interest) async {
    final users = FirebaseFirestore.instance.collection('users');

    final Interest oldInterest = Interest(
      id: interest.id,
      nextInterestId: interest.nextInterestId,
      active: interest.active,
      name: interest.name,
      description: interest.description,
      link: interest.link,
      favorite: interest.favorite,
      favorited_timestamp: interest.favorited_timestamp,
      created_timestamp: interest.created_timestamp,
      updated_timestamp: interest.updated_timestamp,
    );

    await fu.removeInterest(users, oldInterest, widget.uid);

    setState(() {
      _disposeControllersForId(interest.id);
      localInterests.removeWhere((i) => i.id == interest.id);
    });

    updateToggles(interest.id, false);
  }

  Future<void> _showBlankInterestDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Missing content'),
        content: const Text('This interest will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  bool _isInterestBlank({
    required TextEditingController titleController,
    required QuillController quillController,
  }) {
    final title = titleController.text.trim();
    final description = _getQuillPlainText(quillController);

    return title.isEmpty && description.isEmpty;
  }

  void editTopMostInterest() {
    if (localInterests.isEmpty) return;
    final Interest top = localInterests.first;
    final String id = top.id;
    Provider.of<UserModel>(context, listen: false).updateToggle(id, true);
    setState(() {});
  }

  Future<List<Interest>> fetchSortedInterestsForUser(String userUid) async {
    CollectionReference users = FirebaseFirestore.instance.collection('users');
    List<Interest> interests = await fu.pullInterestsForUser(users, userUid);
    interests
        .sort((x, y) => y.updated_timestamp.compareTo(x.updated_timestamp));
    return interests;
  }

  Future<List<Interest>> refreshInterestsForUser(String user_uid) async {
    return fetchSortedInterestsForUser(user_uid);
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
    final currentIds = localInterests.map((i) => i.id).toSet();
    final keysToRemove = <String>[];

    for (final existingId in _titleControllers.keys) {
      if (!currentIds.contains(existingId)) {
        keysToRemove.add(existingId);
      }
    }

    for (final id in keysToRemove) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _titleControllers[id]?.dispose();
      });
      _titleControllers.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _quillControllers[id]?.dispose();
      });
      _quillControllers.remove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _linkControllers[id]?.dispose();
      });
      _linkControllers.remove(id);
    }

    for (final interest in localInterests) {
      final id = interest.id;

      if (!_titleControllers.containsKey(id)) {
        _titleControllers[id] = TextEditingController(text: interest.name);
      }

      if (!_quillControllers.containsKey(id)) {
        _quillControllers[id] = _createQuillController(interest.description);
      }

      if (!_linkControllers.containsKey(id)) {
        _linkControllers[id] = TextEditingController(text: interest.link ?? '');
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

  Future<void> forceRefresh() async {
    List<Interest> updated = await refreshInterestsForUser(widget.uid);
    setState(() {
      localInterests = updated;
      _syncControllersWithInterests();
    });
  }

  Future<void> _showInvalidLinkDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid link'),
        content: const Text(
          'The link you entered does not appear to be reachable. '
          'Please try fix it before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPostInterestToFeedDialog(Interest interest) async {
    if (widget.uid.trim().isEmpty) return;

    final TextEditingController postMessageController = TextEditingController();
    bool isPosting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Post "${interest.name}" to your feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: postMessageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Say something about this interest...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isPosting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isPosting
                      ? null
                      : () async {
                          final message = postMessageController.text.trim();
                          if (message.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Please add a message before posting.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isPosting = true;
                          });

                          try {
                            await fu.createInterestPostedActivity(
                              actorUid: widget.uid,
                              interest: interest,
                              message: message,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Posted to feed.')),
                            );
                          } catch (e) {
                            setDialogState(() {
                              isPosting = false;
                            });
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Could not post: $e')),
                            );
                          }
                        },
                  child: isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Post to my Feed'),
                ),
              ],
            );
          },
        );
      },
    );

    postMessageController.dispose();
  }

  String normalizeUrl(String input) {
    String url = input.trim();

    if (url.isEmpty) return url;

    // If user entered google.com
    if (!url.startsWith('http://www.') && !url.startsWith('https://www.')) {
      url = 'https://www.$url';
    }

    return url;
  }

  Future<void> editing(
      Interest interest,
      bool toggle,
      TextEditingController titleController,
      QuillController quillController,
      TextEditingController linkController,
      int index,
      String id,
      String toggleKey) async {
    if (toggle) {
      CollectionReference users =
          FirebaseFirestore.instance.collection('users');
      Interest newInterest = interest.copyWith(
        name: titleController.text,
        description: _getQuillJson(quillController),
        link: linkController.text,
        created_timestamp: interest.created_timestamp,
        updated_timestamp: DateTime.now(),
      );
      final isBlank = _isInterestBlank(
        titleController: titleController,
        quillController: quillController,
      );
      if (!kIsWeb) {
        final isValid =
            await isUrlResolvable(normalizeUrl(linkController.text));
        if (!isValid) {
          await _showInvalidLinkDialog();
          return;
        }
      }
      fu.updateEditedInterest(users, interest, newInterest, widget.uid);

      if (isBlank) {
        await _showBlankInterestDialog();
        await _deleteInterestSilently(interest);
        //return;
      }

      final updated = await refreshInterestsForUser(widget.uid);

      setState(() {
        localInterests = updated;
        _syncControllersWithInterests();
      });

      updateToggles(toggleKey, false);
    }
    updateToggles(toggleKey, !toggle);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    UserModel userModel = Provider.of<UserModel>(context);
    double deviceScreenHeight = MediaQuery.of(context).size.height;
    double maxHeight = deviceScreenHeight * 0.88;
    final editingEntry = userModel.editToggles.entries.firstWhere(
      (e) => e.value == true,
      orElse: () => MapEntry('', false),
    );

    final editingId = editingEntry.key;

// show only the card being edited, or full list if none are being edited
    final visibleInterests = editingId.isEmpty
        ? localInterests
        : localInterests.where((i) => (i.id) == editingId).toList();
    //_syncControllersWithInterests();

    return Container(
      alignment: Alignment.topCenter,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.transparent, width: 5.0),
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
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
                icon: Icon(Icons.close, color: Colors.white),
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
                  itemCount: visibleInterests.length,
                  itemBuilder: (context, index) {
                    final interest = visibleInterests[index];
                    //Interest interest = localInterests[index];
                    final String id = interest.id;
                    final String toggleKey = id;
                    bool toggle = userModel.getToggle(toggleKey);
                    final shouldHighlightFromFeed =
                        userModel.feedHighlightedInterestOwnerUid ==
                                userModel.alternateUid &&
                            userModel.feedHighlightedInterestId == id;

                    final titleController =
                        _titleControllers[id] ?? TextEditingController();
                    final quillController = _quillControllers[id] ??
                        _createQuillController(interest.description);
                    final linkController =
                        _linkControllers[id] ?? TextEditingController();

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 8.0),
                      child: Card(
                        key: ValueKey(id),
                        color: shouldHighlightFromFeed
                            ? const Color(0xFFFFF3CD)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: shouldHighlightFromFeed
                                ? const Color(0xFFF0AD4E)
                                : Colors.transparent,
                            width: shouldHighlightFromFeed ? 2 : 0,
                          ),
                        ),
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
                                            color: interest.link == ""
                                                ? Colors.black
                                                : Colors.blue,
                                            decoration: interest.link == ""
                                                ? TextDecoration.none
                                                : TextDecoration.underline),
                                      ),
                              ),
                              SizedBox(height: 4),
                              toggle
                                  ? Column(
                                      children: [
                                        TextField(
                                          controller: linkController,
                                          decoration: InputDecoration(
                                            labelText: 'Edit link here',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            border:
                                                Border.all(color: Colors.grey),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Column(
                                            children: [
                                              QuillSimpleToolbar(
                                                controller: quillController,
                                                config:
                                                    const QuillSimpleToolbarConfig(
                                                  showFontFamily:
                                                      false, // Hide to save space
                                                  showFontSize:
                                                      false, // Hide to save space
                                                  showBoldButton: true,
                                                  showItalicButton: true,
                                                  showUnderLineButton: true,
                                                  showListBullets: true,
                                                  showListNumbers: true,
                                                  // Disable others to prevent clutter/overflow
                                                  showStrikeThrough: false,
                                                  showAlignmentButtons: false,
                                                  showBackgroundColorButton:
                                                      false,
                                                  showCenterAlignment: false,
                                                  showClearFormat: false,
                                                  showClipboardCopy: false,
                                                  showClipboardCut: false,
                                                  showClipboardPaste: false,
                                                  showCodeBlock: false,
                                                  showColorButton: false,
                                                  showDirection: false,
                                                  showDividers: false,
                                                  showHeaderStyle: false,
                                                  showIndent: false,
                                                  showInlineCode: false,
                                                  showJustifyAlignment: false,
                                                  showLeftAlignment: false,
                                                  showLineHeightButton: false,
                                                  showLink: true,
                                                  showListCheck: false,
                                                  showQuote: false,
                                                  showRedo: false,
                                                  showRightAlignment: false,
                                                  showSearchButton: false,
                                                  showSmallButton: false,
                                                  showSubscript: false,
                                                  showSuperscript: false,
                                                  showUndo: false,
                                                ),
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
                                      ],
                                    )
                                  : Container(
                                      padding: EdgeInsets.all(8),
                                      child: QuillEditor.basic(
                                        focusNode:
                                            FocusNode(canRequestFocus: false),
                                        controller: quillController,
                                        config: QuillEditorConfig(
                                            showCursor: false),
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
                                            localInterests[index] = newInterest;
                                            final nid = newInterest.id;
                                            _titleControllers[nid]?.text =
                                                newInterest.name;
                                            _linkControllers[nid]?.text =
                                                newInterest.link ?? '';
                                          });

                                          await fu.updateEditedInterest(
                                              users,
                                              interest,
                                              newInterest,
                                              widget.uid);
                                          List<Interest> updatedInterests =
                                              await refreshInterestsForUser(
                                                  widget.uid);

                                          setState(() {
                                            localInterests = updatedInterests;
                                            _syncControllersWithInterests();
                                          });
                                        }),
                                  if (widget.showInputForm && !toggle)
                                    IconButton(
                                      tooltip: 'Post to my feed',
                                      icon: const Icon(Icons.share),
                                      onPressed: () {
                                        _showPostInterestToFeedDialog(interest);
                                      },
                                    ),
                                  if (widget.showInputForm)
                                    IconButton(
                                      icon: Icon(
                                          toggle ? Icons.save : Icons.edit),
                                      onPressed: () async {
                                        await editing(
                                            interest,
                                            toggle,
                                            titleController,
                                            quillController,
                                            linkController,
                                            index,
                                            id,
                                            toggleKey);
                                      },
                                    ),
                                  if (widget.showInputForm && !toggle)
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
                                                        FirebaseFirestore
                                                            .instance
                                                            .collection(
                                                                'users');
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
                                                      favorited_timestamp: interest
                                                          .favorited_timestamp,
                                                      created_timestamp: interest
                                                          .created_timestamp,
                                                      updated_timestamp: interest
                                                          .updated_timestamp,
                                                    );

                                                    fu.removeInterest(
                                                        users,
                                                        oldInterest,
                                                        widget.uid);

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
        if (widget.signedIn && widget.showInputForm && !isEditingAny)
          Column(
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: TextButton(
                    onPressed: () async {
                      CollectionReference users =
                          FirebaseFirestore.instance.collection('users');
                      Interest interest = Interest(
                          name: '',
                          description: '',
                          link: '',
                          created_timestamp: DateTime.now(),
                          updated_timestamp: DateTime.now());

                      await fu.addInterestForUser(users, interest, widget.uid);
                      await refreshInterestsForUser(widget.uid)
                          .then((updatedInterests) {
                        setState(() {
                          localInterests = updatedInterests;
                          _syncControllersWithInterests();
                        });
                      });
                      widget.cardListKey.currentState?.editTopMostInterest();
                    },
                    child: Text("Add Interest")),
              ),
              SizedBox(height: 20)
            ],
          )
      ]),
    );
  }
}
