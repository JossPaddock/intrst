import 'package:uuid/v4.dart';

class Interest {
  final String id;
  String nextInterestId;
  bool active;
  String name;
  String description;
  String? link;
  bool favorite;
  final DateTime created_timestamp;
  DateTime updated_timestamp;

  Interest({
    this.nextInterestId = '',
    this.active = true,
    this.name = '',
    this.description = '',
    this.link = '',
    this.favorite = false,
    required this.created_timestamp,
    required this.updated_timestamp,
  }) : id = UuidV4().generate();

  Map<String, dynamic> mapper() {
    return {
      'id': id,
      'nextInterestId': nextInterestId,
      'active': active,
      'name': name,
      'description': description,
      'link': link,
      'favorite': favorite,
      'created_timestamp': created_timestamp,
      'updated_timestamp': updated_timestamp,
    };
  }
}
