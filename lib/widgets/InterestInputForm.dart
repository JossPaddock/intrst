import 'package:flutter/material.dart';
import 'package:intrst/models/UserModel.dart';
import 'package:intrst/utility/FirebaseUtility.dart';
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
  final FirebaseUtility fu = FirebaseUtility();
  Interest interest = Interest(
      name: '',
      description: '',
      link: '',
      created_timestamp: DateTime.now(),
      updated_timestamp: DateTime.now());

  bool hasValidUrl(String value) {
    String pattern =
        r'^\S*(https:\/\/www\.|http:\/\/www\.|https:\/\/|http:\/\/)?\S[a-zA-Z0-9]{2,}(\.[a-zA-Z0-9]{2,})(\.[a-zA-Z0-9]{2,})?$';
    RegExp regExp = RegExp(pattern);
    if (!regExp.hasMatch(value)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(
      builder: (context, user, child) {
        return Form(
          key: _formKey,
          child: Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
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
                TextFormField(
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter some text';
                    }
                    interest.description = value;
                    return null;
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter a description of the interest.',
                  ),
                ),
                TextFormField(
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
                    hintText: '(Optional) Enter a link for the interest.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: ElevatedButton(
                    onPressed: () async {
                      // Validate returns true if the form is valid, or false otherwise.
                      if (_formKey.currentState!.validate()) {
                        // If the form is valid, display a snackbar for confirmation
                        // Also make call to add interest for the given user uid (logged in user)
                        CollectionReference users =
                            FirebaseFirestore.instance.collection('users');
                        fu.addInterestForUser(users, interest, user.currentUid);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Adding new interest')),
                        );
                        // todo: future state should not delay this synchronous process but instead manage a local set of interests against the ones stored in the database
                        await Future.delayed(Duration(milliseconds: 500));
                        UserModel userModel =
                        Provider.of<UserModel>(context, listen: false);
                        userModel.notify();
                      }
                    },
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
        );
        ;
      },
    );
  }
}
