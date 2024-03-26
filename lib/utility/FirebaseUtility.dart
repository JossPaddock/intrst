import 'package:cloud_firestore/cloud_firestore.dart';


class FirebaseUtility {
  void addUserToFirestore(CollectionReference users, String userUid, String firstName, String lastName, GeoPoint geoPoint){

    Map<String, dynamic> userData = {
      'user_uid': userUid,
      'first_name': firstName,
      'last_name': lastName,
      'interests': [],
      'location': geoPoint,
    };
    users.add(userData)
        .then((value) => print("User added to Firestore"))
        .catchError((error) => print("Failed to add user: $error"));
  }

}
