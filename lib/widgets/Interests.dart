import 'package:flutter/material.dart';

class Interests extends StatelessWidget {
  final String name;
  final List<String> interests;

  const Interests({Key? key, required this.name, required this.interests})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Card Sample')),
        body: CardExample(),
      ),
    );
  }
}

class CardExample extends StatelessWidget {
  CardExample({super.key});

  List<Widget> _cardList = <Widget>[
    Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 1200,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text('soccer'),
              subtitle: Text('pickup'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  child: const Icon(Icons.link),
                  onPressed: () {/* ... */},
                ),
                const SizedBox(width: 0),
                TextButton(
                  child: const Icon(Icons.edit),
                  onPressed: () {/* ... */},
                ),
                const SizedBox(width: 0),
                TextButton(
                  child: const Icon(Icons.star),
                  onPressed: () {/* ... */},
                ),
                const SizedBox(width: 0),
              ],
            ),
          ],
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _cardList[0],
    );
  }
}
