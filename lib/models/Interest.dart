import 'package:cloud_firestore/cloud_firestore.dart';
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
  final int privacy;

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
    this.privacy = 4,
  }) : id = id ?? UuidV4().generate();

  // ADD THIS FACTORY METHOD
  factory Interest.fromMap(Map<String, dynamic> map) {
    return Interest(
      id: map['id'],
      nextInterestId: map['nextInterestId'] ?? '',
      active: map['active'] ?? true,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      link: map['link'],
      favorite: map['favorite'] ?? false,
      favorited_timestamp: map['favorited_timestamp'] != null
          ? (map['favorited_timestamp'] as Timestamp).toDate()
          : null,
      created_timestamp: (map['created_timestamp'] as Timestamp).toDate(),
      updated_timestamp: (map['updated_timestamp'] as Timestamp).toDate(),
      // This line ensures the privacy level is recovered from the DB
      privacy: map['privacy'] ?? 4,
    );
  }

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
      'privacy': privacy,
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
    int? privacy,
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
      privacy: privacy ?? this.privacy,
    );
  }
}