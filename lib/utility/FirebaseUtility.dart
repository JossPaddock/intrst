import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:name_app/utility/FirebaseMappers.dart';
import '../models/Interest.dart';

class FirebaseUtility {

  Future<GeoPoint> retrieveUserLocation(CollectionReference users, String userUid) async {
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: userUid).get();
    return querySnapshot.docs.first['location'];
  }

  Future<List<String>> retrieveAllUserUid(CollectionReference users) async {
    List<String> uids = [];

    QuerySnapshot querySnapshot = await users.get();

    querySnapshot.docs.forEach((user) {
      uids.add(user['user_uid']);
    });

    print(uids);
    return uids;
  }

  void updateUserLocation(CollectionReference users, String userUid, GeoPoint newGeoPoint) {
    users
        .where('user_uid', isEqualTo: userUid)
        .get()
        .then((querySnapshot) {
      if (querySnapshot.docs.isNotEmpty) {
        querySnapshot.docs.first.reference
            .update({'location': newGeoPoint})
            .then((_) => print("Updated Location for user with uid: $userUid"))
            .catchError((error) => print("Couldn't update location: $error"));
      } else {
        print("No results for User");
      }
    });
  }

  FirebaseMappers fm = FirebaseMappers();
  void addUserToFirestore(CollectionReference users, String userUid,
      String firstName, String lastName, GeoPoint geoPoint) {
    Map<String, dynamic> userData = {
      'user_uid': userUid,
      'first_name': firstName,
      'last_name': lastName,
      'interests': [],
      'location': geoPoint,
    };
    users
        .add(userData)
        .then((value) => print("User added to Firestore"))
        .catchError((error) => print("Failed to add user: $error"));
  }

  Future<String> lookUpNameByUserUid(
      CollectionReference users, String uid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();
    String firstname = '';
    String lastname = '';
    querySnapshot.docs.forEach((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      firstname = data['first_name'];
      lastname = data['last_name'];
    });
    return '$firstname $lastname';
  }

  Future<List> lookUpNameAndLocationByUserUid(
      CollectionReference users, String uid) async {
    QuerySnapshot querySnapshot =
    await users.where('user_uid', isEqualTo: uid).get();
    String firstname = '';
    String lastname = '';
    GeoPoint latlng = GeoPoint(0, 0);
    querySnapshot.docs.forEach((doc) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      firstname = data['first_name'];
      lastname = data['last_name'];
      latlng = data['location'];
    });
    latlng.latitude;
    return ['$firstname $lastname', latlng.latitude, latlng.longitude];
  }

  void addInterestForUser(
      CollectionReference users, Interest interest, String uid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();
    querySnapshot.docs.forEach((doc) async {
      DocumentReference documentRef =
          FirebaseFirestore.instance.collection('users').doc(doc.id);
      DocumentSnapshot documentSnapshot = await documentRef.get();
      Map<String, dynamic>? data =
          documentSnapshot.data() as Map<String, dynamic>?;
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

  Future<List<Interest>> pullInterestsForUser(
      CollectionReference users, String uid) async {
    List<Interest> interests = [];
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();

    List<Future<void>> futures = [];

    for (QueryDocumentSnapshot doc in querySnapshot.docs)  {
      futures.add(FirebaseFirestore.instance
          .collection('users')
          .doc(doc.id)
          .get()
          .then((documentSnapshot) {
        Map<String, dynamic>? data =
            documentSnapshot.data() as Map<String, dynamic>?;
        if (data != null) {
          interests.addAll(fm.mapInterests(data['interests']));
        }
      }));
    }
    // FORCE waiting for the forEach completion
    await Future.wait(futures);
    return interests;
  }
}
