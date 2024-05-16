class Interest {
  String name;
  String description;
  String? link;
  DateTime created_timestamp;
  DateTime updated_timestamp;

  Interest({this.name = '', this.description = '', this.link = '', required this.created_timestamp, required this.updated_timestamp});

  Map<String, dynamic> mapper() {
    return {
      'name': name,
      'description': description,
      'link': link,
      'created_timestamp': created_timestamp,
      'updated_timestamp': updated_timestamp,
    };
  }

}