import 'package:flutter/material.dart';

import 'simple_markdown.dart';

const Color _brand = Color(0xFF082D38);

/// Opens a scrollable preview of a test's / scenario's documentation as a
/// draggable bottom sheet. Shared by the admin dashboard's **Unit tests** and
/// **Patrol tests** tabs so both render docs identically.
///
/// [suite] and [name] head the sheet; [doc] is lightweight markdown rendered by
/// [SimpleMarkdown]. [note], when given, shows a small italic caption under the
/// title (e.g. "runs under the flutter test harness only", or how a scenario
/// runs).
void showTestDocSheet(
  BuildContext context, {
  required String suite,
  required String name,
  required String doc,
  String? note,
  IconData? noteIcon,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => _DocSheet(
        suite: suite,
        name: name,
        doc: doc,
        note: note,
        noteIcon: noteIcon,
        controller: scrollController,
      ),
    ),
  );
}

class _DocSheet extends StatelessWidget {
  const _DocSheet({
    required this.suite,
    required this.name,
    required this.doc,
    required this.controller,
    this.note,
    this.noteIcon,
  });

  final String suite;
  final String name;
  final String doc;
  final String? note;
  final IconData? noteIcon;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suite,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _brand.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _brand,
                ),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(noteIcon ?? Icons.info_outline,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          note!,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 16),
        Expanded(
          child: SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: SimpleMarkdown(doc),
          ),
        ),
      ],
    );
  }
}
