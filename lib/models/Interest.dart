import 'package:uuid/v4.dart';

class Interest {
  late final String id;
  String nextInterestId;
  bool active;
  String name;
  String description;
  String? link;
  bool favorite;
  DateTime? favorited_timestamp;
  final DateTime created_timestamp;
  DateTime updated_timestamp;

  Interest({
    String? id,
    this.nextInterestId = '',
    this.active = true,
    this.name = '',
    this.description = '',
    this.link = '',
    this.favorite = false,
    this.favorited_timestamp,
    required this.created_timestamp,
    required this.updated_timestamp,
  }) : id = id ?? UuidV4().generate();

  Map<String, dynamic> mapper() {
    return {
      'id': id,
      'nextInterestId': nextInterestId,
      'active': active,
      'name': name,
      'description': description,
      'link': link,
      'favorite': favorite,
      'favorited_timestamp': favorited_timestamp,
      'created_timestamp': created_timestamp,
      'updated_timestamp': updated_timestamp,
    };
  }

  Interest copyWith({
    String? id,
    String? nextInterestId,
    bool? active,
    String? name,
    String? description,
    String? link,
    bool? favorite,
    DateTime? favorited_timestamp,
    DateTime? created_timestamp,
    DateTime? updated_timestamp,
  }) {
    return Interest(
      id: id ?? this.id,
      nextInterestId: nextInterestId ?? this.nextInterestId,
      active: active ?? this.active,
      name: name ?? this.name,
      description: description ?? this.description,
      link: link ?? this.link,
      favorite: favorite ?? this.favorite,
      favorited_timestamp: favorited_timestamp ?? this.favorited_timestamp,
      created_timestamp: created_timestamp ?? this.created_timestamp,
      updated_timestamp: updated_timestamp ?? this.updated_timestamp,
    );
  }
}

