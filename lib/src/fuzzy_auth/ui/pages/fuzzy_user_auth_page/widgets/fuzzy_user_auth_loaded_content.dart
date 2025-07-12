import 'package:flutter/material.dart';
import 'package:fuzzy_chat/lib.dart';

class FuzzyUserAuthLoadedContent extends StatelessWidget {
  const FuzzyUserAuthLoadedContent({
    super.key,
    required this.items,
  });

  final List<AuthData> items;

  @override
  Widget build(BuildContext context) {
    //TODO implement your empty display
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          // TODO: Display your model's data
          title: Text(item.uid),
          subtitle: Text('Last Updated: ${item.lastUpdated}'),
        );
      },
    );
  }
}
