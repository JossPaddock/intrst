import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:intrst/widgets/CollapsibleChatScreen.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/Interest.dart';
import '../models/UserModel.dart';
import '../utility/FirebaseMessagesUtility.dart';

class Preview extends StatefulWidget {
  const Preview({
    super.key,
    required this.uid,
    required this.alternateUid,
    required this.scaffoldKey,
    required this.onItemTapped,
    required this.signedIn,
    required this.onDrawerOpened,
  });
  final String uid;
  final String alternateUid;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final void Function(int) onItemTapped;
  final bool signedIn;
  final VoidCallback onDrawerOpened;

  @override
  _InterestAlertDialogState createState() => _InterestAlertDialogState();
}

class _InterestAlertDialogState extends State<Preview> {
  List<Interest> _previewInterests = [];
  String _name = '';
  FirebaseUsersUtility fuu = FirebaseUsersUtility();
  FirebaseMessagesUtility fmu = FirebaseMessagesUtility();
  bool chatOpen = false;
  CollectionReference messages =
      FirebaseFirestore.instance.collection('messages');
  CollectionReference users = FirebaseFirestore.instance.collection('users');
  Map<DocumentReference, Map<String, dynamic>>? initMessageData = null;
  bool hasNotification = false;
  int notificationCount = 0;
  bool _isFollowing = false;
  bool _followStateLoading = false;
  bool _followActionLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchNameAndButtonLabels();
    _loadNotificationCount();
    _loadFollowState();
  }

  void _loadNotificationCount() async {
    while (initMessageData == null) {
      await Future.delayed(Duration(milliseconds: 500));
    }
    print('attempting to load notification count');
    int count = await fuu.retrieveNotificationCount(
        users, widget.uid, initMessageData!.entries.first.key.path);
    print('the notification count was $count');
    setState(() {
      if (count > 0) {
        hasNotification = true;
        notificationCount = count;
      } else {
        hasNotification = false;
        notificationCount = 0;
      }
    });
  }

  void _handleAlternateUserModel(String value, String name) {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    userModel.changeAlternateUid(value);
    userModel.changeAlternateName(name);
  }

  String _handleLookUpViewerOfPreviewWidget() {
    UserModel userModel = Provider.of<UserModel>(context, listen: false);
    return userModel.currentUid;
  }

  Future<void> _fetchNameAndButtonLabels() async {
    List<Interest> interests =
        await fuu.pullInterestsForUser(users, widget.alternateUid);
    String name = await fuu.lookUpNameByUserUid(users, widget.alternateUid);
    setState(() {
      _previewInterests = interests;
      _name = name;
    });
  }

  Future<void> _fetchInitialMessageData() async {
    List<String> userUids = [widget.uid, widget.alternateUid];
    Map<DocumentReference, Map<String, dynamic>>? data =
        await fmu.getMessageDocumentsExclusivelyByUserUids(userUids);
    if (data == null) {
      await fmu.createMessageDocument([widget.uid, widget.alternateUid]);
      data = await fmu.getMessageDocumentsExclusivelyByUserUids(userUids);
    }
    setState(() {
      initMessageData = data;
    });
  }

  Future<void> _loadFollowState() async {
    if (!widget.signedIn ||
        widget.uid.isEmpty ||
        widget.alternateUid.isEmpty ||
        widget.uid == widget.alternateUid) {
      return;
    }

    setState(() {
      _followStateLoading = true;
    });

    final isFollowing =
        await fuu.isFollowingUser(users, widget.uid, widget.alternateUid);
    if (!mounted) return;

    setState(() {
      _isFollowing = isFollowing;
      _followStateLoading = false;
    });
  }

  Future<void> _toggleFollowState() async {
    if (!widget.signedIn) {
      Navigator.pop(context);
      widget.onItemTapped(1);
      return;
    }

    if (widget.uid == widget.alternateUid) return;

    setState(() {
      _followActionLoading = true;
    });

    final nowFollowing =
        await fuu.toggleFollowUser(users, widget.uid, widget.alternateUid);
    if (!mounted) return;

    setState(() {
      _isFollowing = nowFollowing;
      _followActionLoading = false;
    });
  }

  void _handlePreviewToInterestsWidgetFlow(
      {String highlightedInterestId = ''}) {
    if (widget.signedIn) {
      _handleAlternateUserModel(widget.alternateUid, _name);
      final userModel = Provider.of<UserModel>(context, listen: false);
      final sanitizedInterestId = highlightedInterestId.trim();
      if (sanitizedInterestId.isNotEmpty) {
        userModel.setFeedInterestHighlight(
          ownerUid: widget.alternateUid,
          interestId: sanitizedInterestId,
        );
      } else {
        userModel.clearFeedInterestHighlight();
      }
      widget.scaffoldKey.currentState?.openEndDrawer();
      widget.onDrawerOpened();
    } else {
      widget.onItemTapped(1);
      Navigator.of(context).pop(false);
    }
  }

  String formatTextByWords(String text, int wordsPerLine) {
    final words = text.split(' ');
    final buffer = StringBuffer();

    for (int i = 0; i < words.length; i++) {
      buffer.write(words[i]);
      if (i < words.length - 1) {
        if ((i + 1) % wordsPerLine == 0) {
          buffer.write('\n'); // Newline after every N words
        } else {
          buffer.write(' ');
        }
      }
    }

    return buffer.toString();
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
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
        side: BorderSide(
          color: Colors.grey, // Border color
          width: 1.0, // Border width
        ),
      ),
      title: Text(
        _name,
        textAlign: TextAlign.center, // Center the title text
        style: TextStyle(
          fontSize: 20, // Adjust font size as needed
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!chatOpen)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16.0,
              runSpacing: 8.0,
              children: _previewInterests
                  .map((interest) {
                    final interestLink = (interest.link ?? '').trim();
                    return ElevatedButton(
                      onPressed: () {
                        //_handlePreviewToInterestsWidgetFlow();
                      },
                      child: GestureDetector(
                        onTap: () {
                          if (interestLink.isEmpty) {
                            _handlePreviewToInterestsWidgetFlow(
                                highlightedInterestId: interest.id);
                          }
                          _launchUrl(interest.link);
                        },
                        child: Text(
                          formatTextByWords(interest.name, 3),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: interestLink.isEmpty
                                  ? Colors.black
                                  : Colors.blue,
                              decoration: interestLink.isEmpty
                                  ? TextDecoration.none
                                  : TextDecoration.underline),
                        ),
                      ),
                    );
                  })
                  .toList()
                  .take(5)
                  .toList(),
            ),
          if (!chatOpen) SizedBox(height: 16.0),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  if (widget.signedIn) {
                  } else {
                    Navigator.pop(context); // Close the dialog
                    widget.onItemTapped(1);
                  } //
                  if (widget.uid.isNotEmpty && widget.alternateUid.isNotEmpty) {
                    await _fetchInitialMessageData();
                  }
                  setState(() {
                    chatOpen = !chatOpen;
                  });
                },
                icon: Badge.count(
                    offset: Offset(9.0, -7.0),
                    isLabelVisible: hasNotification,
                    count: notificationCount,
                    child: const Icon(Icons.chat)),
                label: Text(chatOpen ? 'Close' : 'Chat',
                    style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _handlePreviewToInterestsWidgetFlow();
                },
                icon: Icon(Icons.add),
                label: Text('All interests', style: TextStyle(fontSize: 12)),
              ),
              if (widget.signedIn && widget.uid != widget.alternateUid)
                ElevatedButton.icon(
                  onPressed: (_followStateLoading || _followActionLoading)
                      ? null
                      : _toggleFollowState,
                  icon: _followActionLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_isFollowing
                          ? Icons.person_remove
                          : Icons.person_add),
                  label: Text(
                    _isFollowing ? 'Unfollow' : 'Follow',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          if (!chatOpen)
            ElevatedButton.icon(
              onPressed: () {
                widget.onItemTapped(3);
                Navigator.pop(context);
              },
              icon: Icon(Icons.chat),
              label: Text('Show all chats'),
            ),
          if (chatOpen && initMessageData != null)
            Column(
              children: [
                CollapsibleChatScreen(
                    autoOpen: true,
                    showNameAtTop: false,
                    uid: _handleLookUpViewerOfPreviewWidget(),
                    documentData: initMessageData!.entries.first.value,
                    documentReference: initMessageData!.entries.first.key),
              ],
            ),
          if (chatOpen && initMessageData == null)
            Text(
                'You have never had a chat with this person, we are creating that chat now ')
        ],
      ),
    );
  }
}
