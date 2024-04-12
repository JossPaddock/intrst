class Interest {
  String name = '';
  String description = '';
  String? link = '';
  DateTime created_timestamp = DateTime.now();
  DateTime updated_timestamp = DateTime.now();

  Interest(){
    this.name = '';
    this.description = '';
    this.link = '';
    this.created_timestamp = DateTime.now();
    this.updated_timestamp = DateTime.now();
  }

Map<String, dynamic> mapper() {
    return{
      'name': name,
      'description': description,
      'link': link,
      'created_timestamp': created_timestamp,
      'updated_timestamp': updated_timestamp,
    };
}


}
