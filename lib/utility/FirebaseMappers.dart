import '../models/Interest.dart';

class FirebaseMappers{
  List<Interest> mapInterests(List<dynamic> data) {
    List<Map<String, dynamic>> localInterests = convertList(data);
    List<Interest> localList = [];
    localInterests.forEach((interest) {
      localList.add(Interest(
        id: interest['id'],
        nextInterestId: interest['nextInterestId'],
        active: interest['active'],
        name: interest['name'],
        description: interest['description'],
        link: interest['link'],
        favorite: interest['favorite'],
        favorited_timestamp: interest['favorited_timestamp'],
        created_timestamp: interest['created_timestamp'],
        updated_timestamp: interest['updated_timestamp']
      ));
    });
    return localList;
  }

  List<Map<String, dynamic>> convertList(List<dynamic> data) {
    return data.map((item) {
      Map<String, dynamic> map = Map<String, dynamic>.from(item);
      if (map.containsKey('created_timestamp') && map['created_timestamp'] != null) {
        int seconds = map['created_timestamp'].seconds;
        int nanoseconds = map['created_timestamp'].nanoseconds;
        DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round());
        map['created_timestamp'] = dateTime;
      }
      if (map.containsKey('updated_timestamp') && map['updated_timestamp'] != null) {
        int seconds = map['updated_timestamp'].seconds;
        int nanoseconds = map['updated_timestamp'].nanoseconds;
        DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round());
        map['updated_timestamp'] = dateTime;
      }
      if (map.containsKey('favorited_timestamp') && map['favorited_timestamp'] != null) {
        int seconds = map['favorited_timestamp'].seconds;
        int nanoseconds = map['favorited_timestamp'].nanoseconds;
        DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round());
        map['favorited_timestamp'] = dateTime;
      }
      return map;
    }).toList();
  }
}