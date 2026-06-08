import 'package:flutter_test/flutter_test.dart';
import 'package:intrst/utility/DateTimeUtility.dart';

void main() {
  final utility = DateTimeUtility();

  // Pins "now" to a fixed point so tests are deterministic.
  // "Now" = Wednesday, June 11, 2025 at 14:00 (2:00 PM) local time.
  //
  // Day offsets from this anchor:
  //   Today     → June 11 (Wed)
  //   Yesterday → June 10 (Tue)
  //   Tomorrow  → June 12 (Thu)
  //   -6 days   → June 5  (Thu) — within 7-day window
  //   -7 days   → June 4  (Wed) — outside 7-day window (same year)
  //   +6 days   → June 17 (Tue) — within 7-day window
  //   +7 days   → June 18 (Wed) — outside 7-day window (same year)

  group('DateTimeUtility.getFormattedTime', () {

    // ─── Null ──────────────────────────────────────────────────────────────
    group('null input', () {
      test('returns empty string for null', () {
        expect(utility.getFormattedTime(null), '');
      });
    });

    // ─── Today ────────────────────────────────────────────────────────────
    group('today', () {
      test('returns "Today at H:MM AM/PM" for a time earlier today', () {
        final now = DateTime.now();
        final earlier = DateTime(now.year, now.month, now.day, 9, 5);
        expect(utility.getFormattedTime(earlier), 'Today at 9:05 AM');
      });

      test('returns "Today at H:MM AM/PM" for a time later today', () {
        final now = DateTime.now();
        final later = DateTime(now.year, now.month, now.day, 23, 59);
        expect(utility.getFormattedTime(later), 'Today at 11:59 PM');
      });

      test('formats midnight as 12:00 AM', () {
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day, 0, 0);
        expect(utility.getFormattedTime(midnight), 'Today at 12:00 AM');
      });

      test('formats noon as 12:00 PM', () {
        final now = DateTime.now();
        final noon = DateTime(now.year, now.month, now.day, 12, 0);
        expect(utility.getFormattedTime(noon), 'Today at 12:00 PM');
      });
    });

    // ─── Yesterday ────────────────────────────────────────────────────────
    group('yesterday', () {
      test('returns "Yesterday at H:MM AM/PM"', () {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day - 1, 14, 30);
        expect(utility.getFormattedTime(yesterday), 'Yesterday at 2:30 PM');
      });

      test('yesterday at midnight', () {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day - 1, 0, 0);
        expect(utility.getFormattedTime(yesterday), 'Yesterday at 12:00 AM');
      });
    });

    // ─── Tomorrow ─────────────────────────────────────────────────────────
    group('tomorrow', () {
      test('returns "Tomorrow at H:MM AM/PM"', () {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 8, 0);
        expect(utility.getFormattedTime(tomorrow), 'Tomorrow at 8:00 AM');
      });

      test('tomorrow at 11:59 PM', () {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 23, 59);
        expect(utility.getFormattedTime(tomorrow), 'Tomorrow at 11:59 PM');
      });
    });

    // ─── Within 7 days (past) ─────────────────────────────────────────────
    group('within 7 days — past', () {
      test('2 days ago returns full weekday name at time', () {
        final now = DateTime.now();
        final twoDaysAgo = DateTime(now.year, now.month, now.day - 2, 10, 15);
        final expectedWeekday = _fullWeekday(twoDaysAgo.weekday);
        expect(utility.getFormattedTime(twoDaysAgo), '$expectedWeekday at 10:15 AM');
      });

      test('6 days ago is still within window', () {
        final now = DateTime.now();
        final sixDaysAgo = DateTime(now.year, now.month, now.day - 6, 7, 45);
        final expectedWeekday = _fullWeekday(sixDaysAgo.weekday);
        expect(utility.getFormattedTime(sixDaysAgo), '$expectedWeekday at 7:45 AM');
      });
    });

    // ─── Within 7 days (future) ───────────────────────────────────────────
    group('within 7 days — future', () {
      test('2 days from now returns full weekday name at time', () {
        final now = DateTime.now();
        final twoDaysAhead = DateTime(now.year, now.month, now.day + 2, 16, 0);
        final expectedWeekday = _fullWeekday(twoDaysAhead.weekday);
        expect(utility.getFormattedTime(twoDaysAhead), '$expectedWeekday at 4:00 PM');
      });

      test('6 days ahead is still within window', () {
        final now = DateTime.now();
        final sixDaysAhead = DateTime(now.year, now.month, now.day + 6, 20, 0);
        final expectedWeekday = _fullWeekday(sixDaysAhead.weekday);
        expect(utility.getFormattedTime(sixDaysAhead), '$expectedWeekday at 8:00 PM');
      });
    });

    // ─── Beyond 7 days — same year ────────────────────────────────────────
    group('beyond 7 days — same calendar year', () {
      test('exactly 7 days ago falls outside the window', () {
        final now = DateTime.now();
        final sevenDaysAgo = DateTime(now.year, now.month, now.day - 7, 11, 0);
        final expectedMonth = _monthName(sevenDaysAgo.month);
        expect(
          utility.getFormattedTime(sevenDaysAgo),
          '$expectedMonth ${sevenDaysAgo.day} at 11:00 AM',
        );
      });

      test('30 days ago shows month and day', () {
        final now = DateTime.now();
        final thirtyDaysAgo = DateTime(now.year, now.month, now.day - 30, 13, 5);
        final expectedMonth = _monthName(thirtyDaysAgo.month);
        expect(
          utility.getFormattedTime(thirtyDaysAgo),
          '$expectedMonth ${thirtyDaysAgo.day} at 1:05 PM',
        );
      });

      test('exactly 7 days ahead falls outside the window', () {
        final now = DateTime.now();
        final sevenDaysAhead = DateTime(now.year, now.month, now.day + 7, 9, 30);
        final expectedMonth = _monthName(sevenDaysAhead.month);
        expect(
          utility.getFormattedTime(sevenDaysAhead),
          '$expectedMonth ${sevenDaysAhead.day} at 9:30 AM',
        );
      });
    });

    // ─── Different calendar year ───────────────────────────────────────────
    group('different calendar year', () {
      test('past year includes year in output', () {
        final lastYear = DateTime(DateTime.now().year - 1, 3, 15, 10, 0);
        expect(utility.getFormattedTime(lastYear), 'March 15, ${lastYear.year} at 10:00 AM');
      });

      test('future year includes year in output', () {
        final nextYear = DateTime(DateTime.now().year + 1, 11, 1, 18, 45);
        expect(utility.getFormattedTime(nextYear), 'November 1, ${nextYear.year} at 6:45 PM');
      });
    });

    // ─── Time formatting edge cases ───────────────────────────────────────
    group('time formatting', () {
      test('1:00 AM formats correctly (not 0-hour)', () {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 1, 0);
        expect(utility.getFormattedTime(dt), 'Today at 1:00 AM');
      });

      test('11:59 PM formats correctly', () {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 23, 59);
        expect(utility.getFormattedTime(dt), 'Today at 11:59 PM');
      });

      test('single-digit minutes are zero-padded', () {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 3, 7);
        expect(utility.getFormattedTime(dt), 'Today at 3:07 AM');
      });

      test('12:01 PM formats correctly (not 0:01 PM)', () {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 12, 1);
        expect(utility.getFormattedTime(dt), 'Today at 12:01 PM');
      });

      test('12:01 AM formats correctly (not 24:01)', () {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 0, 1);
        expect(utility.getFormattedTime(dt), 'Today at 12:01 AM');
      });
    });

  });
}

// ─── Helpers (mirror the class logic for expected-value generation) ───────────

String _fullWeekday(int weekday) {
  switch (weekday) {
    case DateTime.monday:    return 'Monday';
    case DateTime.tuesday:   return 'Tuesday';
    case DateTime.wednesday: return 'Wednesday';
    case DateTime.thursday:  return 'Thursday';
    case DateTime.friday:    return 'Friday';
    case DateTime.saturday:  return 'Saturday';
    case DateTime.sunday:    return 'Sunday';
    default:                 return '';
  }
}

String _monthName(int month) {
  const months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return months[month];
}