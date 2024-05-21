import '../models/Interest.dart';

class FirebaseMappers{
  List<Interest> mapInterests(List<dynamic> data) {
    List<Map<String, dynamic>> localInterests = convertList(data);
    List<Interest> localList = [];
    localInterests.forEach((interest) {
      localList.add(Interest(
        name: interest['name'],
        description: interest['description'],
        link: interest['link'],
        created_timestamp: interest['created_timestamp'],
        updated_timestamp: interest['updated_timestamp']
      ));
    });
    return localList;
  }

  List<Map<String, dynamic>> convertList(List<dynamic> data) {
    return data.map((item) {
      Map<String, dynamic> map = Map<String, dynamic>.from(item);
      if (map.containsKey('created_timestamp')) {
        int seconds = map['created_timestamp'].seconds;
        int nanoseconds = map['created_timestamp'].nanoseconds;
        DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round());
        map['created_timestamp'] = dateTime;
      }
      if (map.containsKey('updated_timestamp')) {
        int seconds = map['updated_timestamp'].seconds;
        int nanoseconds = map['updated_timestamp'].nanoseconds;
        DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000 + (nanoseconds / 1000000).round());
        map['updated_timestamp'] = dateTime;
      }
      return map;
    }).toList();
  }
}