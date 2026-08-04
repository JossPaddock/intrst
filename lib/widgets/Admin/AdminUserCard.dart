import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intrst/utility/AdminUtility.dart';

/// Information card for a single user shown in the admin dashboard. Surfaces
/// every field on the user document and exposes a permanent-delete action.
class AdminUserCard extends StatelessWidget {
  const AdminUserCard({
    super.key,
    required this.record,
    required this.onDelete,
    required this.isDeleting,
    this.email,
  });

  final AdminUserRecord record;
  final VoidCallback onDelete;
  final bool isDeleting;

  /// Email fetched from Firebase Auth (emails aren't stored in Firestore).
  /// `null` means it is still loading; an empty string means none is on file.
  final String? email;

  static const Color _brand = Color(0xFF082D38);

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return 'Unknown';
    final d = ts.toDate().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'Unknown';
    final d = ts.toDate().toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _stringify(dynamic value) {
    if (value == null) return 'null';
    if (value is Timestamp) return value.toDate().toLocal().toString();
    if (value is GeoPoint) return '(${value.latitude}, ${value.longitude})';
    if (value is List) return '[${value.length} item(s)]';
    if (value is Map) return '{${value.length} key(s)}';
    final s = value.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Widget _field(String label, String value, {bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(value)
                : Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = record.location;
    final locationText = location == null
        ? 'Unknown'
        : '${location.latitude.toStringAsFixed(5)}, '
            '${location.longitude.toStringAsFixed(5)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _brand,
                  child: Text(
                    record.firstName.isNotEmpty
                        ? record.firstName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    record.fullName.isEmpty ? '(no name)' : record.fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field('First name', record.firstName),
            _field('Last name', record.lastName),
            _field(
              'Email',
              email == null ? 'Loading…' : (email!.isEmpty ? '—' : email!),
              selectable: email != null && email!.isNotEmpty,
            ),
            _field('User UID', record.userUid, selectable: true),
            _field('Firestore doc id', record.docId, selectable: true),
            _field('Birthday', _formatDate(record.birthday)),
            _field('Account created', _formatDateTime(record.profileCreatedAt)),
            _field('Interests', '${record.interestsCount}'),
            _field('Following', '${record.followingCount}'),
            _field('Friends', '${record.friendsCount}'),
            _field('Longest streak', '${record.longestStreak}'),
            _field('Messages sent', '${record.messagesSent}'),
            _field('Messages received', '${record.messagesReceived}'),
            _field('FCM tokens', '${record.fcmTokenCount}'),
            _field('Location', locationText),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'All raw fields',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                children: record.data.keys.map((key) {
                  return _field(key, _stringify(record.data[key]));
                }).toList(),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: isDeleting ? null : onDelete,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever),
                label: Text(isDeleting ? 'Deleting…' : 'Delete user'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
