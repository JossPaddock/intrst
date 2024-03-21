import 'package:cloud_firestore/cloud_firestore.dart';


class FirebaseUtility {
  void addUserToFirestore(CollectionReference users, String user_uid, String first_name, String last_name, GeoPoint geo_point){

    Map<String, dynamic> userData = {
      'user_uid': user_uid,
      'first_name': first_name,
      'last_name': last_name,
      'interests': [],
      'location': geo_point,
    };
    users.add(userData)
        .then((value) => print("User added to Firestore"))
        .catchError((error) => print("Failed to add user: $error"));
  }

}
