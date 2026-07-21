import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/Pick_GeneralUtility.dart';
import 'package:intrst/utility/GeneralUtility.dart';
import 'package:provider/provider.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import '../../models/Interest.dart';
import 'dart:convert';
import '../../rich_text_editor/rich_text_document.dart';
import '../../rich_text_editor/rich_text_editor_controller.dart';
import '../../rich_text_editor/rich_text_editor_widget.dart';
import '../../rich_text_editor/rich_text_op.dart';
import '../../utility/url_validator/url_validator.dart';

// CardListState is split across the files below (loaded as `part`s of this
// same library) to keep any single file from growing into a "mega file".
// A State class's members can't literally be declared across separate
// files, so the split works like this: every field lives on
// `_CardListStateBase` below, and any private helper that's called from a
// *different* part file is declared abstractly on `_CardListStateBase` and
// implemented by the relevant mixin. Everything that's only used within one
// part stays purely private to that part.
part 'card_list/card_list_data.dart';
part 'card_list/card_list_sharing.dart';
part 'card_list/card_list_dialogs.dart';
part 'card_list/card_list_description.dart';
part 'card_list/card_list_builders.dart';

class CardList extends StatefulWidget {
  static GlobalKey<CardListState> createGlobalKey() =>
      GlobalKey<CardListState>();

  final GlobalKey<CardListState> cardListKey;
  final String name;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final String uid;
  final bool signedIn;
  final List<Interest> interests;
  final void Function(int) onItemTapped;
  final bool showInputForm;
  final List<bool> editToggles;
  final bool shouldCreateInterest;
  final String initialInterestName;

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
    this.shouldCreateInterest = false,
    this.initialInterestName = '',
  });

  @override
  CardListState createState() => CardListState();
}

// Holds every field CardListState needs, plus the private-method "contract"
// that lets the mixins in the part files call into each other. Dart mixins
// may only call members declared on their `on` bound, so any private helper
// invoked from outside the part file where it's implemented has to be
// declared here (no body) and is then implemented by whichever mixin owns
// it.
abstract class _CardListStateBase extends State<CardList> {
  final FirebaseUsersUtility fu = FirebaseUsersUtility();
  bool get isEditingAny {
    final userModel = Provider.of<UserModel>(context, listen: false);
    return localInterests.any((i) => userModel.getToggle(i.id) == true);
  }

  final TextEditingController _searchController = TextEditingController();
  // FocusNode with skipTraversal: true prevents the OS/Flutter focus system
  // from auto-jumping to this field when the emoji keyboard triggers a focus
  // transition while the user is typing in the RichText description editor.
  final FocusNode _searchFocusNode = FocusNode(skipTraversal: true);
  // True while the search field has focus (keyboard is up). Used to hide the
  // title, link, and description fields so the search results have full room.
  bool _searchKeyboardActive = false;
  final Map<String, bool> _expandedDescriptions = {};
  // Whether the pinned "Favorites" section is expanded. The database already
  // enforces the 5-favorite cap, so this is purely a display constant.
  bool _favoritesExpanded = true;

  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _linkControllers = {};
  final Map<String, RichTextEditorController> _richTextControllers = {};
  bool _isFriend = false;
  bool _isFollowing = false;
  bool _relationshipsLoaded = false;

  // Load hardening: tracks how many retries have been attempted and whether
  // a retry is currently scheduled.
  int _interestLoadRetries = 0;

  TextEditingController _mobileTitleController = TextEditingController();
  TextEditingController _mobileLinkController = TextEditingController();
  late RichTextEditorController _mobileRichTextController;
  bool _isSearchingUsers = false;
  List<String> searchResults = <String>[];
  final FirebaseUsersUtility fuu = FirebaseUsersUtility();
  final CollectionReference users = FirebaseFirestore.instance.collection(
    'users',
  );
  final Set<String> selectedItems = <String>{};
  final Map<String, String> _userNameCache = <String, String>{};

  late List<Interest> localInterests = widget.interests;

  GeneralUtility gu = GeneralUtilityWeb();

  // --- Cross-part method contract ---
  // Implemented in card_list_data.dart:
  Future<void> createNewInterest({String? initialName});
  Future<void> editing(
    Interest interest,
    bool toggle,
    TextEditingController titleController,
    RichTextEditorController richTextController,
    TextEditingController linkController,
    int index,
    String id,
    String toggleKey,
  );
  String getStatusText(int statusId);
  RichTextEditorController _createRichTextController(String text);
  String _getRichTextPlainText(RichTextEditorController controller);
  void _disposeControllersForId(String id);
  Future<void> _launchUrl(String? url);
  Future<List<Interest>> refreshInterestsForUser(String user_uid);
  void _syncControllersWithInterests();
  Future<void> _handleReorderWithinGroup(
    List<Interest> group,
    bool isFavoriteGroup,
    int oldIndex,
    int newIndex,
  );

  // Implemented in card_list_dialogs.dart:
  Future<void> _showInvalidLinkDialog();
  Future<void> _showBlankInterestDialog();
  Future<String?> _showCreateInterestDialog({String? initialName});
  Future<bool?> _showSaveDialog(BuildContext context);
  Future<void> _showPostInterestToFeedDialog(Interest interest);
  Future<void> _openFullscreenRichTextEditor(
    RichTextEditorController richTextController,
  );

  // Implemented in card_list_description.dart:
  Widget _buildInlineDescription(
    BuildContext context,
    String id,
    RichTextEditorController richTextController, {
    bool canResize = false,
    Interest? interest,
  });

  // Implemented in card_list_sharing.dart:
  Widget _buildNewChatTab(Interest interest);
}

class CardListState extends _CardListStateBase
    with
        AutomaticKeepAliveClientMixin<CardList>,
        _CardListDataMixin,
        _CardListSharingMixin,
        _CardListDialogsMixin,
        _CardListDescriptionMixin,
        _CardListBuildersMixin {
  @override
  bool get wantKeepAlive => true;
}
