import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/FirebaseMappers.dart';
import 'dart:math' as math;
import '../models/Interest.dart';
import 'package:http/http.dart' as http;
import 'package:restart_app/restart_app.dart';

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

  Future<void> addFcmTokenForUser(String userUid, String fcmToken) async {
    final usersCollection = FirebaseFirestore.instance.collection('users');
    print('attempting to add FCM token for user: $userUid');
    try {
      // Find the user document by user_uid
      final querySnapshot =
          await usersCollection.where('user_uid', isEqualTo: userUid).get();

      if (querySnapshot.docs.isEmpty) {
        print('No user found with uid: $userUid');
        return;
      }

      // For each matching user (probably only one with that user uid)
      for (final doc in querySnapshot.docs) {
        final docRef = usersCollection.doc(doc.id);

        // Use arrayUnion to add the token (avoids duplicates automatically)
        await docRef.update({
          'fcm_tokens': FieldValue.arrayUnion([fcmToken])
        });

        print('FCM token added for user $userUid');
      }
    } catch (e) {
      print('Failed to add FCM token: $e');
    }
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
      'following_uids': [],
      'unread_notifications': [],
      'unread_notifications_count': <String, int>{},
    };
    users
        .add(userData)
        .then((value) => print("User added to Firestore"))
        .catchError((error) => print("Failed to add user: $error"));
  }

  Future<List<String>> retrieveFollowingUids(
      CollectionReference users, String userUid) async {
    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).limit(1).get();
    if (querySnapshot.docs.isEmpty) {
      return [];
    }

    final Map<String, dynamic> data =
        querySnapshot.docs.first.data() as Map<String, dynamic>;
    return (data['following_uids'] as List?)
            ?.map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList() ??
        [];
  }

  Future<bool> isFollowingUser(
      CollectionReference users, String userUid, String targetUid) async {
    if (userUid.isEmpty || targetUid.isEmpty || userUid == targetUid) {
      return false;
    }
    final followingUids = await retrieveFollowingUids(users, userUid);
    return followingUids.contains(targetUid);
  }

  Future<void> followUser(
      CollectionReference users, String userUid, String targetUid) async {
    if (userUid.isEmpty || targetUid.isEmpty || userUid == targetUid) {
      return;
    }

    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).limit(1).get();
    if (querySnapshot.docs.isEmpty) {
      return;
    }

    await querySnapshot.docs.first.reference.update({
      'following_uids': FieldValue.arrayUnion([targetUid]),
    });
  }

  Future<void> unfollowUser(
      CollectionReference users, String userUid, String targetUid) async {
    if (userUid.isEmpty || targetUid.isEmpty || userUid == targetUid) {
      return;
    }

    QuerySnapshot querySnapshot =
        await users.where('user_uid', isEqualTo: userUid).limit(1).get();
    if (querySnapshot.docs.isEmpty) {
      return;
    }

    await querySnapshot.docs.first.reference.update({
      'following_uids': FieldValue.arrayRemove([targetUid]),
    });
  }

  Future<bool> toggleFollowUser(
      CollectionReference users, String userUid, String targetUid) async {
    final alreadyFollowing = await isFollowingUser(users, userUid, targetUid);
    if (alreadyFollowing) {
      await unfollowUser(users, userUid, targetUid);
      return false;
    }

    await followUser(users, userUid, targetUid);
    return true;
  }

  Future<List<String>> retrieveFollowerUids(String actorUid) async {
    if (actorUid.isEmpty) return [];

    QuerySnapshot querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('following_uids', arrayContains: actorUid)
        .get();

    final followerUids = querySnapshot.docs
        .map((doc) => (doc.data() as Map<String, dynamic>)['user_uid'])
        .whereType<String>()
        .where((uid) => uid.isNotEmpty && uid != actorUid)
        .toSet()
        .toList();

    return followerUids;
  }

  Future<void> _createActivityForUsers({
    required String type,
    required String actorUid,
    required String actorName,
    required List<String> targetUids,
    String? interestId,
    String? interestName,
    String? messageContent,
  }) async {
    if (targetUids.isEmpty || actorUid.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'type': type,
      'actor_uid': actorUid,
      'actor_name': actorName,
      'target_uids': targetUids.toSet().toList(),
      'created_at': FieldValue.serverTimestamp(),
    };

    if (interestId != null && interestId.isNotEmpty) {
      payload['interest_id'] = interestId;
    }
    if (interestName != null && interestName.isNotEmpty) {
      payload['interest_name'] = interestName;
    }
    if (messageContent != null && messageContent.isNotEmpty) {
      payload['message_content'] = messageContent;
    }

    await FirebaseFirestore.instance.collection('activity_feed').add(payload);
  }

  Future<void> createInterestCreatedActivity({
    required String actorUid,
    required Interest interest,
  }) async {
    final users = FirebaseFirestore.instance.collection('users');
    final followers = await retrieveFollowerUids(actorUid);
    if (followers.isEmpty) return;

    final actorName = await lookUpNameByUserUid(users, actorUid);
    await _createActivityForUsers(
      type: 'interest_created',
      actorUid: actorUid,
      actorName: actorName,
      targetUids: followers,
      interestId: interest.id,
      interestName: interest.name,
    );
  }

  Future<void> createInterestUpdatedActivity({
    required String actorUid,
    required Interest oldInterest,
    required Interest newInterest,
    int minChangedCharacters = 10,
  }) async {
    final oldText = _flattenInterestForDiff(oldInterest);
    final newText = _flattenInterestForDiff(newInterest);
    final changedCharacterCount =
        _calculateChangedCharacterCount(oldText, newText);

    if (changedCharacterCount <= minChangedCharacters) {
      return;
    }

    final users = FirebaseFirestore.instance.collection('users');
    final followers = await retrieveFollowerUids(actorUid);
    if (followers.isEmpty) return;

    final actorName = await lookUpNameByUserUid(users, actorUid);
    await _createActivityForUsers(
      type: 'interest_updated',
      actorUid: actorUid,
      actorName: actorName,
      targetUids: followers,
      interestId: newInterest.id,
      interestName: newInterest.name,
    );
  }

  Future<void> createMessageActivity({
    required String senderUid,
    required String recipientUid,
    required String messageContent,
  }) async {
    if (senderUid.isEmpty ||
        recipientUid.isEmpty ||
        senderUid == recipientUid ||
        messageContent.trim().isEmpty) {
      return;
    }

    final users = FirebaseFirestore.instance.collection('users');
    final actorName = await lookUpNameByUserUid(users, senderUid);
    await _createActivityForUsers(
      type: 'message_sent',
      actorUid: senderUid,
      actorName: actorName,
      targetUids: [recipientUid],
      messageContent: _truncateMessagePreview(messageContent),
    );
  }

  String _truncateMessagePreview(String messageContent, {int maxLength = 140}) {
    final trimmed = messageContent.trim().replaceAll('\n', ' ');
    if (trimmed.length <= maxLength) return trimmed;
    return '${trimmed.substring(0, maxLength)}...';
  }

  String _flattenInterestForDiff(Interest interest) {
    final plainDescription =
        _extractPlainTextFromQuillJson(interest.description);
    return '${interest.name.trim()}\n$plainDescription\n${interest.link?.trim() ?? ''}';
  }

  String _extractPlainTextFromQuillJson(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';

    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (final operation in decoded) {
          if (operation is Map<String, dynamic> &&
              operation['insert'] is String) {
            buffer.write(operation['insert'] as String);
          }
        }
        return buffer.toString().trim();
      }
    } catch (_) {
      // fall through to raw text
    }
    return text;
  }

  int _calculateChangedCharacterCount(String source, String target) {
    if (source == target) return 0;
    if (source.isEmpty) return target.length;
    if (target.isEmpty) return source.length;

    List<int> previous =
        List<int>.generate(target.length + 1, (index) => index);
    List<int> current = List<int>.filled(target.length + 1, 0);

    for (int i = 1; i <= source.length; i++) {
      current[0] = i;
      for (int j = 1; j <= target.length; j++) {
        final substitutionCost =
            source.codeUnitAt(i - 1) == target.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(
            current[j - 1] + 1,
            previous[j] + 1,
          ),
          previous[j - 1] + substitutionCost,
        );
      }

      final swap = previous;
      previous = current;
      current = swap;
    }

    return previous[target.length];
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
    for (final doc in querySnapshot.docs) {
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
    }

    await createInterestCreatedActivity(actorUid: uid, interest: interest);
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

    await createInterestUpdatedActivity(
      actorUid: uid,
      oldInterest: oldInterest,
      newInterest: newInterest,
      minChangedCharacters: 10,
    );
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
      if (url == '') return true;
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

  Future<void> showReauthAndDeleteDialog(
      BuildContext context, String user_uid) async {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController emailController = TextEditingController();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Deletion"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Please re-enter your email and password to delete your account."),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                obscureText: false,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Delete Account Forever!!!!!!!!"),
              onPressed: () async {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) throw Exception("No user signed in!");

                  final credential = EmailAuthProvider.credential(
                    email: emailController.text.trim(),
                    password: passwordController.text.trim(),
                  );

                  await user.reauthenticateWithCredential(credential);

                  await user.delete();

                  final usersRef =
                      FirebaseFirestore.instance.collection('users');

                  final querySnapshot = await usersRef
                      .where('user_uid', isEqualTo: user_uid)
                      .get();

                  for (var doc in querySnapshot.docs) {
                    await doc.reference.delete();
                    print(
                        "Deleted document: ${doc.id} as part of account deletion");
                  }

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Account deleted successfully! Sorry to see you go")),
                  );
                  await Future.delayed(Duration(seconds: 3));
                  await Restart.restartApp(
                      notificationTitle: 'User account deleted',
                      notificationBody: 'tap here to reopen the interest app');
                } on FirebaseAuthException catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: ${e.message}")),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

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

  bool searchInterests(String data, String searchTerm,
      {bool includeDescription = false}) {
    String fieldPattern = includeDescription ? 'name|description' : 'name';

    RegExp regex = RegExp(
      r'(' + fieldPattern + r'):\s*[^,}]*' + RegExp.escape(searchTerm),
      caseSensitive: false,
    );

    return regex.hasMatch(data);
  }

  String getMatchedInterest(String data, String searchTerm,
      {bool includeDescription = false}) {
    // 1. Create a pattern that handles both names and the nested "insert" fields in descriptions
    String fieldPattern = includeDescription ? 'name|insert' : 'name';

    RegExp regex = RegExp(
      r'(' + fieldPattern + r'):\s*("?)(.*?)\2(?=[,}\]])',
      caseSensitive: false,
      dotAll: true, // Allows matching across newlines if description has them
    );

    // 2. Use allMatches to check EVERY instance in the data
    final matches = regex.allMatches(data);

    for (final match in matches) {
      if (match.groupCount >= 3) {
        String value = match.group(3)!.trim();
        if (value.toLowerCase().contains(searchTerm.toLowerCase())) {
          return value; // Return the first one that actually matches your search
        }
      }
    }

    return '';
  }

  Future<List<String>> searchForPeopleAndInterestsReturnUIDs(
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

  Future<List<String>> listInterests() async {
    final querySnapshot =
        await FirebaseFirestore.instance.collection('users').get();

    final List<String> interestNames = [];

    for (final doc in querySnapshot.docs) {
      final data = doc.data();

      if (data.containsKey('interests') && data['interests'] is List) {
        final List interests = data['interests'];

        for (final interest in interests) {
          if (interest is Map<String, dynamic> &&
              interest.containsKey('name') &&
              interest['name'] is String) {
            interestNames.add(interest['name']);
          }
        }
      }
    }

    return interestNames;
  }

  Future<List<String>> searchForPeopleAndInterests(
      CollectionReference users, String query, bool includeInterests) async {
    Set<String> resultingNames = {};

    if (query.trim().isEmpty) return [];

    QuerySnapshot querySnapshotFull = await users.get();

    for (var doc in querySnapshotFull.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      String firstname = data['first_name'] ?? '';
      String lastname = data['last_name'] ?? '';
      String fullName = '$firstname $lastname'.trim();

      if (fullName.toLowerCase().contains(query.toLowerCase())) {
        resultingNames.add(fullName);
      }

      if (includeInterests && data['interests'] != null) {
        if (searchInterests(data.toString(), query) && includeInterests) {
          print(getMatchedInterest(data.toString(), query));
          resultingNames.add(getMatchedInterest(data.toString(), query));
        }
      }
    }
    var ordered = reorderByQuery(resultingNames, query);
    ordered = dedupeIgnoreCase(ordered);
    return ordered.take(5).toList();
  }

  List<String> reorderByQuery(Set<String> input, String query) {
    final q = query.toLowerCase();

    int score(String s) {
      final value = s.toLowerCase();

      if (value == q) return 100;
      if (value.startsWith(q)) return 80;
      if (value.contains(q)) return 50;
      if (RegExp(q).hasMatch(value)) return 20;
      return 0;
    }

    final list = input.toList();

    list.sort((a, b) {
      final scoreDiff = score(b).compareTo(score(a));
      if (scoreDiff != 0) return scoreDiff;

      return a.length.compareTo(b.length);
    });
    return list.where((current) {
      final pattern =
          RegExp(r'\b' + RegExp.escape(current) + r'\b', caseSensitive: false);

      return !list.any((other) => other != current && pattern.hasMatch(other));
    }).toList();
  }

  List<String> dedupeIgnoreCase(List<String> input) {
    final seen = <String>{};
    final result = <String>[];

    for (final item in input) {
      final key = item.toLowerCase();
      if (seen.add(key)) {
        result.add(item); // keep first occurrence
      }
    }

    return result;
  }
}
