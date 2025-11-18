import 'package:flutter/material.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/Interest.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'dart:convert';

class InterestInputForm extends StatefulWidget {
  const InterestInputForm({
    super.key,
  });

  @override
  InterestInputFormState createState() {
    return InterestInputFormState();
  }
}

class InterestInputFormState extends State<InterestInputForm> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseUsersUtility fu = FirebaseUsersUtility();

  late QuillController _quillController;

  Interest interest = Interest(
      name: '',
      description: '',
      link: '',
      created_timestamp: DateTime.now(),
      updated_timestamp: DateTime.now());

  @override
  void initState() {
    super.initState();
    _quillController = QuillController.basic();
  }

  bool hasValidUrl(String value) {
    String pattern =
        r'^\S*(https:\/\/www\.|http:\/\/www\.|https:\/\/|http:\/\/)?\S[a-zA-Z0-9\/\-]{2,}(\.[a-zA-Z0-9\/\-]{2,})(\.[a-zA-Z0-9\/\-]{2,})?$';
    RegExp regExp = RegExp(pattern);
    if (!regExp.hasMatch(value)) {
      return false;
    }
    return true;
  }

  String _getQuillJson(QuillController controller) {
    return jsonEncode(controller.document.toDelta().toJson());
  }

  @override
  void dispose() {
    _quillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(
      builder: (context, user, child) {
        return Card(
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: Size(MediaQuery.of(context).size.width - 33,
                  MediaQuery.of(context).size.height * .05),
            ),
            child: Text('Add Interest'),
            onPressed: () async {
              // Reset the quill controller for a new interest
              _quillController.dispose();
              _quillController = QuillController.basic();

              await showDialog<String>(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) => AlertDialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: EdgeInsets.all(0),
                  content: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 480,
                      minWidth: 999,
                      maxWidth: 1000,
                      maxHeight: 500,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Card(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 20, left: 20, right: 20, bottom: 0),
                                child: TextFormField(
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter some text';
                                    }
                                    interest.name = value;
                                    return null;
                                  },
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Add a new interest.',
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 20, right: 20, top: 10, bottom: 10),
                                child: GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: true,
                                      builder: (BuildContext dialogContext) {
                                        return Dialog(
                                          insetPadding: EdgeInsets.zero,
                                          child: Container(
                                            width: double.infinity,
                                            height: double.infinity,
                                            color: Colors.white,
                                            child: Column(
                                              children: [
                                                AppBar(
                                                  title: Text(
                                                      'Enter/edit description'),
                                                  automaticallyImplyLeading:
                                                      false,
                                                  actions: [
                                                    IconButton(
                                                      icon: Icon(Icons.check),
                                                      onPressed: () {
                                                        interest.description =
                                                            _getQuillJson(
                                                                _quillController);
                                                        Navigator.of(
                                                                dialogContext)
                                                            .pop();
                                                      },
                                                    ),
                                                  ],
                                                ),
                                                QuillSimpleToolbar(
                                                  controller: _quillController,
                                                  
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    padding: EdgeInsets.all(10),
                                                    child: QuillEditor.basic(
                                                      controller:
                                                          _quillController,
                                                      
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _quillController.document
                                                        .toPlainText()
                                                        .trim()
                                                        .isEmpty
                                                ? 'Enter a description of the interest.'
                                                : _quillController.document
                                                    .toPlainText()
                                                    .trim(),
                                            style: TextStyle(
                                              color: _quillController.document
                                                          .toPlainText()
                                                          .trim()
                                                          .isEmpty
                                                  ? Colors.grey[600]
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                        Icon(Icons.edit,
                                            color: Colors.grey[600]),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 0, left: 20, right: 20, bottom: 0),
                                child: TextFormField(
                                  validator: (value) {
                                    if (value != null && value.isNotEmpty) {
                                      if (!hasValidUrl(value)) {
                                        return 'Please make sure this is a valid link';
                                      }
                                    }
                                    interest.link = value;
                                    return null;
                                  },
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: '(Optional) Enter a link.',
                                  ),
                                ),
                              ),
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          // Validate returns true if the form is valid, or false otherwise.
                                          if (_formKey.currentState!
                                              .validate()) {
                                            // Save the description from quill
                                            interest.description = _getQuillJson(
                                                _quillController);

                                            // If the form is valid, display a snackbar for confirmation
                                            // Also make call to add interest for the given user uid (logged in user)
                                            CollectionReference users =
                                                FirebaseFirestore.instance
                                                    .collection('users');
                                            fu.addInterestForUser(
                                                users, interest, user.currentUid);

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Adding new interest')),
                                            );

                                            // todo: future state should not delay this synchronous process but instead manage a local set of interests against the ones stored in the database
                                            await Future.delayed(
                                                Duration(milliseconds: 500));

                                            UserModel userModel =
                                                Provider.of<UserModel>(context,
                                                    listen: false);
                                            userModel.notify();

                                            Navigator.pop(context, 'submit');
                                          }
                                        },
                                        child: const Text('Submit'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(context, 'cancel');
                                        },
                                        child: const Text('Cancel'),
                                      ),
                                    ],
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  actions: <Widget>[],
                ),
              );
            },
          ),
        );
      },
    );
  }
}