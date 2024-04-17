import 'package:flutter/material.dart';

class InterestCard extends StatelessWidget {
  final String name;
  final List<String> interests;

  const InterestCard({Key? key, required this.name, required this.interests})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$name's Interests",
              style: const TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              children: interests.map((interest) => Chip(label: Text(interest))).toList(),
            ),
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("1. Edit"),
                Text("2. Description"),
                Text("3. Top 5"),
              ],
            ),
          ],
        ),
      ),
    );
  }
}