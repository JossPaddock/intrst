import 'package:flutter/material.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUsersUtility.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/Interest.dart';

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
  TextEditingController _descriptionController = TextEditingController();
  Interest interest = Interest(
      name: '',
      description: '',
      link: '',
      created_timestamp: DateTime.now(),
      updated_timestamp: DateTime.now());

  bool hasValidUrl(String value) {
    String pattern =
        r'^\S*(https:\/\/www\.|http:\/\/www\.|https:\/\/|http:\/\/)?\S[a-zA-Z0-9\/\-]{2,}(\.[a-zA-Z0-9\/\-]{2,})(\.[a-zA-Z0-9\/\-]{2,})?$';
    RegExp regExp = RegExp(pattern);
    if (!regExp.hasMatch(value)) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    //_descriptionController.dispose(); // Clean up
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(
      builder: (context, user, child) {
        return Card(
          child: TextButton(
              child: Text('Add Interest'),
              onPressed: () async {
                await showDialog<String>(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) => AlertDialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.all(0),
                    content: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 380,
                        minWidth: 999,
                        maxWidth: 1000,
                        maxHeight: 400,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Card(
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
                                //child: Expanded(
                                child: TextFormField(
                                  maxLines: 1,
                                  readOnly: true,
                                  controller: _descriptionController,
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: true,
                                      builder: (BuildContext context) {
                                        TextEditingController dialogController =
                                            TextEditingController(
                                                text: _descriptionController
                                                    .text);
                                        final FocusNode _focusNode =
                                            FocusNode();
                                        return StatefulBuilder(
                                          builder: (context, setState) {
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              if (!_focusNode.hasFocus) {
                                                _focusNode.requestFocus();
                                              }
                                            });
                                            return Dialog(
                                              insetPadding: EdgeInsets.zero,
                                              child: Container(
                                                width: double.infinity,
                                                height: double.infinity,
                                                color: Colors.white,
                                                child: Column(
                                                  children: [
                                                    AppBar(
                                                        title: Text(''
                                                            'Enter/edit description'),
                                                        automaticallyImplyLeading:
                                                            false,
                                                        actions: [
                                                          IconButton(
                                                              icon: Icon(
                                                                  Icons.check),
                                                              onPressed: () {
                                                                _descriptionController
                                                                        .text =
                                                                    dialogController
                                                                        .text;
                                                                interest.description =
                                                                    dialogController
                                                                        .text;
                                                                Navigator.of(
                                                                        context)
                                                                    .pop();
                                                              }),
                                                        ]),
                                                    //Expanded(
                                                    //child:
                                                    TextField(
                                                      focusNode: _focusNode,
                                                      controller:
                                                          dialogController,
                                                      maxLines: null,
                                                      decoration:
                                                          InputDecoration(
                                                        border: InputBorder
                                                            .none, // No visible border
                                                        contentPadding:
                                                            EdgeInsets
                                                                .symmetric(
                                                                    horizontal:
                                                                        10.0),
                                                      ),
                                                    ),
                                                    //),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                  /*validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter some text';
                                      }
                                      interest.description = value;
                                      return null;
                                    },*/
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText:
                                        'Enter a description of the interest.',
                                  ),
                                ),
                                //),
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
                                            // If the form is valid, display a snackbar for confirmation
                                            // Also make call to add interest for the given user uid (logged in user)
                                            CollectionReference users =
                                                FirebaseFirestore.instance
                                                    .collection('users');
                                            fu.addInterestForUser(users,
                                                interest, user.currentUid);

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
                    actions: <Widget>[],
                  ),
                );
              }),
        );
        ;
      },
    );
  }
}
