import 'package:flutter_test/flutter_test.dart';
import 'package:intrst/utility/DateTimeUtility.dart';

void main() {
  final dateTimeUtility = DateTimeUtility();

  group('DateTimeUtility', () {
    test('returns empty string for null DateTime', () {
      expect(dateTimeUtility.getFormattedTime(null), '');
    });

    test('formats weekday and time correctly for 2:30 PM Monday', () {
      final dateTime = DateTime(2025, 7, 7, 14, 30); // A Monday
      final formatted = dateTimeUtility.getFormattedTime(dateTime);
      expect(formatted, 'Mon 2:30PM');
    });

    test('formats midnight correctly (12:00AM)', () {
      final dateTime = DateTime(2025, 7, 8, 0, 0); // A Tuesday
      final formatted = dateTimeUtility.getFormattedTime(dateTime);
      expect(formatted, 'Tue 12:00AM');
    });

    test('formats noon correctly (12:00PM)', () {
      final dateTime = DateTime(2025, 7, 9, 12, 0); // A Wednesday
      final formatted = dateTimeUtility.getFormattedTime(dateTime);
      expect(formatted, 'Wed 12:00PM');
    });

    test('adds leading zero to minutes less than 10', () {
      final dateTime = DateTime(2025, 7, 10, 9, 5); // A Thursday
      final formatted = dateTimeUtility.getFormattedTime(dateTime);
      expect(formatted, 'Thu 9:05AM');
    });
  });
}