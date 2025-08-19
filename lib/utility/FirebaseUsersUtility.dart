import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intrst/utility/FirebaseMappers.dart';
import '../models/Interest.dart';
import 'package:http/http.dart' as http;

class FirebaseUsersUtility {
  Future<GeoPoint> retrieveUserLocation(
      CollectionReference users, String userUid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).get();
    return querySnapshot.docs.first['location'];
  }

  Future<void> removeItemsContainingSubstring({
    required String docPath,
    required String arrayField,
    required String substring,
  }) async {
    final docRef = FirebaseFirestore.instance.doc(docPath);

    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      print('Document does not exist.');
      return;
    }

    final data = snapshot.data();
    if (data == null || data[arrayField] == null || data[arrayField] is! List) {
      print('Invalid or missing array field.');
      return;
    }

    final List<dynamic> originalArray = data[arrayField];
    final List<String> updatedArray = originalArray
        .where((item) =>
            item is String &&
            !item.toLowerCase().contains(substring.toLowerCase()))
        .cast<String>()
        .toList();

    await docRef.update({arrayField: updatedArray});
    print('Removed $substring from $docPath for field $arrayField.');
  }

  Future<void> removeUnreadNotifications(String docRef, String uid) async {
    final usersCollection = FirebaseFirestore.instance.collection('users');
    final querySnapshot =
        await usersCollection.where('user_uid', isEqualTo: uid).get();
    for (final doc in querySnapshot.docs) {
      final docPath = doc.reference.path;
      await removeItemsContainingSubstring(
        docPath: docPath,
        arrayField: 'unread_notifications',
        substring: docRef,
      );
    }
    await updateUnreadNotificationCounts('users');
  }

  Future<void> addUnreadNotification(String collectionPath, String userUid,
      String docRefPath, String messageUuid) async {
    final collection = FirebaseFirestore.instance.collection(collectionPath);
    QuerySnapshot querySnapshot =
        await collection.where('user_uid', isEqualTo: userUid).get();
    querySnapshot.docs.first.reference.update({
      'unread_notifications':
          FieldValue.arrayUnion(['$docRefPath:$messageUuid'])
    });
    print('added to unread_notifications: $docRefPath:$messageUuid');
  }

//Warning this method updates notification counts for everyone and shouldn't be called too often
//right now it is called when anyone hits the send button ensuring it works when it needs to.
// But it is probably working more than it should.
  //Ideally it only runs when updateNotifications is read!
  //the method should be made more granular so it only updates notifications for one user.
  Future<void> updateUnreadNotificationCounts(String collectionPath) async {
    final collection = FirebaseFirestore.instance.collection(collectionPath);

    final querySnapshot = await collection.get();

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final List<dynamic> unreadNotifications =
          data['unread_notifications'] ?? [];

      final Map<String, int> counts = {};

      for (final notif in unreadNotifications) {
        final parts = notif.split(':');
        if (parts.length != 2) continue;

        final docRefPath = parts[0];

        if (counts.containsKey(docRefPath)) {
          counts[docRefPath] = counts[docRefPath]! + 1;
        } else {
          counts[docRefPath] = 1;
        }
      }

      await doc.reference.update({
        'unread_notifications_count': counts,
      });
    }
  }

  Future<int> retrieveNotificationCount(
      CollectionReference users, String userUid,
      [String? docRef]) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).get();
    QueryDocumentSnapshot userQDS = querySnapshot.docs.first;
    final Map<String, dynamic>? notifications =
        userQDS.get('unread_notifications_count')?.cast<String, dynamic>();
    if (notifications == null) return 0;
    if (docRef != null) {
      final value = notifications[docRef];
      return (value is num) ? value.toInt() : 0;
    }
    return notifications.values
        .whereType<num>()
        .fold<int>(0, (sum, value) => sum + value.toInt());
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
    if (interest.link != null) {
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

  Future<void> updateEditedInterest(
    CollectionReference users,
    Interest oldInterest,
    Interest newInterest,
    String uid,
  ) async {
    print('attempting to update interest: $newInterest');

    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef =
          FirebaseFirestore.instance.collection('users').doc(doc.id);

      List<dynamic> interests = (doc['interests'] ?? []) as List<dynamic>;

      // Replace the matching interest by ID
      for (int i = 0; i < interests.length; i++) {
        if (interests[i]['id'] == oldInterest.id) {
          interests[i] = newInterest.mapper();
          break;
        }
      }

      await documentRef.update({'interests': interests});

      // Enforce max 5 favorites
      if (!oldInterest.favorite && newInterest.favorite) {
        int favoriteCount =
            interests.where((interest) => interest['favorite'] == true).length;

        if (favoriteCount > 5) {
          print(
              'User has more than 5 interests!, attempting to limit favorited interests');
          await limitFavoritedInterests(users, uid, 5);
        }
      }
    }
  }

  Future<void> limitFavoritedInterests(
      CollectionReference users, String uid, int maxFavorites) async {
    print('Checking favorite interests for user with UID: $uid');
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef =
          FirebaseFirestore.instance.collection('users').doc(doc.id);
      DocumentSnapshot updatedDoc = await documentRef.get();

      List<dynamic> interests = updatedDoc['interests'];

      List<Map<String, dynamic>> favoriteInterests = interests
          .where((interest) => interest['favorite'] == true)
          .cast<Map<String, dynamic>>()
          .toList();

      // maxFavorites is the limit passed into this method
      if (favoriteInterests.length > maxFavorites) {
        print(
            'Too many favorites: ${favoriteInterests.length} (The max defined is: $maxFavorites)');

        // Sort by `favorited_timestamp` in ASCENDING order
        favoriteInterests.sort((a, b) {
          DateTime aTimestamp =
              (a['favorited_timestamp'] as Timestamp).toDate();
          DateTime bTimestamp =
              (b['favorited_timestamp'] as Timestamp).toDate();
          return aTimestamp.compareTo(bTimestamp);
        });

        // these are the favorites we need to now unfavorite
        int extraCount = favoriteInterests.length - maxFavorites;
        List<Map<String, dynamic>> interestsToUnfavorite =
            favoriteInterests.take(extraCount).toList();
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
        print(
            'Favorite interests count is within the limit already (${favoriteInterests.length}).');
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

  /*Future<void> removeInterest(CollectionReference users, Interest interest, String uid) async {
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
  }*/

  Future<void> removeInterest(
      CollectionReference users, Interest interest, String uid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: uid).get();

    for (var doc in querySnapshot.docs) {
      DocumentReference documentRef =
          FirebaseFirestore.instance.collection('users').doc(doc.id);

      List<dynamic> interests = (doc['interests'] ?? []) as List<dynamic>;

      interests.removeWhere((item) => item['id'] == interest.id);

      await documentRef.update({'interests': interests});
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
