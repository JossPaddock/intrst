import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intrst/utility/FirebaseMappers.dart';
import '../models/Interest.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

class FirebaseUsersUtility {
  Future<GeoPoint> retrieveUserLocation(
      CollectionReference users, String userUid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).get();
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

  void updateUserLocation(
      CollectionReference users, String userUid, GeoPoint newGeoPoint) {
    users.where('user_uid', isEqualTo: userUid).get().then((querySnapshot) {
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

  Future<void> addInterestForUser(
      CollectionReference users, Interest interest, String uid) async {
    if(interest.link != null) {
      print('isValidWebsite:');
      print(isValidWebsite(interest.link!!));
    }
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

  Future<void> updateEditedInterest(CollectionReference users, Interest oldInterest, Interest newInterest, String uid) async {
    print('attempting to update interest: $newInterest');
    //fire base arrayRemove and arrayUnion method calls may be more performant!!!
    //fire base object must match directly if doing a plain array remove, but not so much with built-ins
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef = FirebaseFirestore.instance.collection('users').doc(doc.id);

      Map<String, dynamic> oldInterestMap = oldInterest.mapper();
      Map<String, dynamic> newInterestMap = newInterest.mapper();

      await documentRef.update({
        'interests': FieldValue.arrayRemove([oldInterestMap])
      });

      await documentRef.update({
        'interests': FieldValue.arrayUnion([newInterestMap])
      });
      if(!oldInterest.favorite && newInterest.favorite) {
        DocumentSnapshot updatedDoc = await documentRef.get();
        List<dynamic> interests = updatedDoc['interests'];
        int favoriteCount = interests
            .where((interest) => interest['favorite'] == true)
            .length;
        if(favoriteCount > 5) {

          print('User has more than 5 interests!, attempting to limit favorited interests');
          await limitFavoritedInterests(users, uid, 5);
        }
      }
    }
  }

  Future<void> limitFavoritedInterests(
      CollectionReference users, String uid, int maxFavorites) async {
    print('Checking favorite interests for user with UID: $uid');
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef = FirebaseFirestore.instance.collection('users').doc(doc.id);
      DocumentSnapshot updatedDoc = await documentRef.get();

      List<dynamic> interests = updatedDoc['interests'];

      List<Map<String, dynamic>> favoriteInterests = interests
          .where((interest) => interest['favorite'] == true)
          .cast<Map<String, dynamic>>()
          .toList();

      // maxFavorites is the limit passed into this method
      if (favoriteInterests.length > maxFavorites) {
        print('Too many favorites: ${favoriteInterests.length} (The max defined is: $maxFavorites)');

        // Sort by `favorited_timestamp` in ASCENDING order
        favoriteInterests.sort((a, b) {
          DateTime aTimestamp = (a['favorited_timestamp'] as Timestamp).toDate();
          DateTime bTimestamp = (b['favorited_timestamp'] as Timestamp).toDate();
          return aTimestamp.compareTo(bTimestamp);
        });

        // these are the favorites we need to now unfavorite
        int extraCount = favoriteInterests.length - maxFavorites;
        List<Map<String, dynamic>> interestsToUnfavorite = favoriteInterests.take(extraCount).toList();
        for (var interest in interestsToUnfavorite) {
          await documentRef.update({
            'interests': FieldValue.arrayRemove([interest]),
          });
          interest['favorite'] = false;
          await documentRef.update({
            'interests': FieldValue.arrayUnion([interest]),
          });
        }
      } else {
        print('Favorite interests count is within the limit already (${favoriteInterests.length}).');
      }
    }
  }

  Future<bool> isValidWebsite(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }

      final uri = Uri.parse(url);
      final response = await http.head(uri);

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return true;
      }
    } catch (e) {
      print('Error verifying URL: $e');
    }
    return false;
  }

  Future<void> removeInterest(CollectionReference users, Interest interest, String uid) async {
    //fire base arrayRemove and arrayUnion method calls may be more performant!!!
    //fire base object must match directly if doing a plain array remove, but not so much with built-ins
    QuerySnapshot querySnapshot = await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef = FirebaseFirestore.instance.collection('users').doc(doc.id);

      Map<String, dynamic> interestMap = interest.mapper();

      await documentRef.update({
        'interests': FieldValue.arrayRemove([interestMap])
      });
    }
  }

  Future<List<Interest>> pullInterestsForUser(
      CollectionReference users, String uid) async {
    List<Interest> interests = [];
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();

    List<Future<void>> futures = [];

    for (QueryDocumentSnapshot doc in querySnapshot.docs) {
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

  bool searchInterests(String data, String searchTerm) {
    RegExp regex = RegExp(
      r'(name|description):\s*[^,}]*' + RegExp.escape(searchTerm),
      caseSensitive: false,
    );

    return regex.hasMatch(data);
  }

  Future<List<String>> searchForPeopleAndInterests(
      CollectionReference users, String query, bool includeInterests) async {
    Set<String> resultingUids = {};
    if (query != " " && query != "") {
      QuerySnapshot querySnapshotFull = await users.get();
      for (var doc in querySnapshotFull.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String firstname = data['first_name'];
        if (searchInterests(data.toString(), query) && includeInterests) {
          resultingUids.add(data['user_uid']);
        }
        String lastname = data['last_name'];
        List<String> interestsSearchTerms = [];
        interestsSearchTerms.add('$firstname $lastname');
        for (String item in interestsSearchTerms) {
          if (item.toLowerCase().contains(query.toLowerCase()) &&
              query != " ") {
            resultingUids.add(data['user_uid']);
          }
        }
      }
    }
    return resultingUids.toList();
  }
}
