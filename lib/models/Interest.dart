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
  final List<String> sharedWithUids;
  final String? imageUrl;
  // Manual position set by drag-and-drop reordering. Null for interests the
  // user has never reordered — those fall back to created_timestamp so new
  // interests appear on top.
  int? sort_order;

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
    List<String>? sharedWithUids,
    this.imageUrl,
    this.sort_order,
  }) : id = id ?? UuidV4().generate(),
       sharedWithUids = sharedWithUids ?? [];

  int get effectiveSortOrder =>
      sort_order ?? created_timestamp.millisecondsSinceEpoch;

  // Display order everywhere interests are listed: starred (top 5) interests
  // stay pinned above the rest; within each group higher effectiveSortOrder
  // comes first, so never-reordered lists show newest created on top and
  // editing an interest does not move it.
  static int compareForDisplay(Interest a, Interest b) {
    if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
    final byOrder = b.effectiveSortOrder.compareTo(a.effectiveSortOrder);
    if (byOrder != 0) return byOrder;
    final byCreated = b.created_timestamp.compareTo(a.created_timestamp);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }

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
      privacy: map['privacy'] ?? 4,
      sharedWithUids:
          (map['shared_with_uids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [],
      imageUrl: map['image_url'] as String?,
      sort_order: (map['sort_order'] as num?)?.toInt(),
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
      'shared_with_uids': sharedWithUids,
      'image_url': imageUrl,
      'sort_order': sort_order,
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
    List<String>? sharedWithUids,
    Object? imageUrl = _sentinel,
    int? sort_order,
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
      sharedWithUids: sharedWithUids ?? this.sharedWithUids,
      imageUrl: imageUrl == _sentinel ? this.imageUrl : imageUrl as String?,
      sort_order: sort_order ?? this.sort_order,
    );
  }

  static const Object _sentinel = Object();
}
