import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/Interest.dart';


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
  Future<String> lookUpNameByUserUid(CollectionReference users, String uid) async {
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: uid).get();
    String firstname = '';
    String lastname = '';
    querySnapshot.docs.forEach((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      firstname = data['first_name'];
      lastname = data['last_name'];
    });
    return '$firstname $lastname';
  }
  void addInterestForUser(CollectionReference users, Interest interest, String uid) async {
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: uid).get();
    querySnapshot.docs.forEach((doc) async {
      DocumentReference documentRef = FirebaseFirestore.instance.collection('users').doc(doc.id);
      DocumentSnapshot documentSnapshot = await documentRef.get();
      Map<String, dynamic>? data = documentSnapshot.data() as Map<String, dynamic>?;
      if (data != null) {
        List<dynamic> array = data['interests'] ?? [];
        Map<String, dynamic> interest_map = interest.mapper();
        array.add(interest_map);
        await documentRef.update({'interests': array});
      } else {
        print('UH OH Could not find the doc');
      }
    });
  }
}
