import '../../utility/DateTimeUtility.dart';
import 'unit_test.dart';

/// Unit coverage for [DateTimeUtility.getFormattedTime]: relative-day phrasing
/// (today/yesterday/tomorrow), the 7-day weekday window, cross-year output, and
/// 12-hour clock edge cases. Times are built relative to `DateTime.now()` so the
/// tests stay deterministic without pinning the clock.
List<UnitTest> dateTimeUnitTests() {
  final utility = DateTimeUtility();

  UnitTest formatting(
          String name, String summary, String doc, UnitTestBody body) =>
      UnitTest(
        suite: 'DateTimeUtility.getFormattedTime',
        name: name,
        summary: summary,
        doc: doc,
        body: body,
      );

  return <UnitTest>[
    formatting(
      'returns empty string for null',
      'A null timestamp formats to an empty string rather than throwing.',
      '''
## What it checks
`getFormattedTime(null)` returns the empty string `''`.

## Why it matters
Timestamps are often missing — a chat with no last message, an activity with no
recorded time. The formatter must degrade to blank text, never throw a null
error into a widget build.

## Expected
`null` → `''`''',
      (t) => t.expectEqual(utility.getFormattedTime(null), ''),
    ),
    formatting(
      'returns "Today at H:MM AM/PM" for a time earlier today',
      'A time earlier the same day reads as "Today at ...".',
      '''
## What it checks
A timestamp earlier on the current calendar day is phrased as
`Today at <h:mm AM/PM>`.

## Why it matters
Same-day times are the most common case in the feed and chat; users read
"Today" far faster than a date.

## Expected
Today at 09:05 → `Today at 9:05 AM`''',
      (t) {
        final now = DateTime.now();
        final earlier = DateTime(now.year, now.month, now.day, 9, 5);
        t.expectEqual(utility.getFormattedTime(earlier), 'Today at 9:05 AM');
      },
    ),
    formatting(
      'returns "Today at H:MM AM/PM" for a time later today',
      'A time later the same day still reads as "Today at ...".',
      '''
## What it checks
A timestamp later on the current day (but still today) is still phrased as
`Today at ...` — being in the future within the day does not change the label.

## Expected
Today at 23:59 → `Today at 11:59 PM`''',
      (t) {
        final now = DateTime.now();
        final later = DateTime(now.year, now.month, now.day, 23, 59);
        t.expectEqual(utility.getFormattedTime(later), 'Today at 11:59 PM');
      },
    ),
    formatting(
      'formats midnight as 12:00 AM',
      'Midnight today is 12:00 AM, not 0:00.',
      '''
## What it checks
Hour `0` renders as `12:00 AM` on the 12-hour clock, not `0:00`.

## Why it matters
Midnight is the classic 12-hour-clock trap: the zero hour must display as 12,
with the AM meridiem.

## Expected
Today at 00:00 → `Today at 12:00 AM`''',
      (t) {
        final now = DateTime.now();
        final midnight = DateTime(now.year, now.month, now.day, 0, 0);
        t.expectEqual(
            utility.getFormattedTime(midnight), 'Today at 12:00 AM');
      },
    ),
    formatting(
      'formats noon as 12:00 PM',
      'Noon today is 12:00 PM, not 0:00 PM.',
      '''
## What it checks
Hour `12` renders as `12:00 PM`, not `0:00 PM` — the other half of the
midnight/noon boundary.

## Expected
Today at 12:00 → `Today at 12:00 PM`''',
      (t) {
        final now = DateTime.now();
        final noon = DateTime(now.year, now.month, now.day, 12, 0);
        t.expectEqual(utility.getFormattedTime(noon), 'Today at 12:00 PM');
      },
    ),
    formatting(
      'returns "Yesterday at H:MM AM/PM"',
      'The previous calendar day reads as "Yesterday at ...".',
      '''
## What it checks
A timestamp on the previous calendar day is phrased as `Yesterday at ...`.

## Why it matters
"Yesterday" is a distinct, high-frequency relative label the eye recognises
instantly, so it gets its own phrasing rather than a weekday name.

## Expected
Yesterday at 14:30 → `Yesterday at 2:30 PM`''',
      (t) {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day - 1, 14, 30);
        t.expectEqual(
            utility.getFormattedTime(yesterday), 'Yesterday at 2:30 PM');
      },
    ),
    formatting(
      'yesterday at midnight',
      'Yesterday at midnight reads as "Yesterday at 12:00 AM".',
      '''
## What it checks
The "Yesterday" label and the midnight 12-hour rule compose correctly for a
timestamp at 00:00 the previous day.

## Expected
Yesterday at 00:00 → `Yesterday at 12:00 AM`''',
      (t) {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day - 1, 0, 0);
        t.expectEqual(
            utility.getFormattedTime(yesterday), 'Yesterday at 12:00 AM');
      },
    ),
    formatting(
      'returns "Tomorrow at H:MM AM/PM"',
      'The next calendar day reads as "Tomorrow at ...".',
      '''
## What it checks
A timestamp on the next calendar day is phrased as `Tomorrow at ...`.

## Why it matters
Future timestamps are real (scheduled activities), so the formatter is
symmetric around today: it labels tomorrow just as it labels yesterday.

## Expected
Tomorrow at 08:00 → `Tomorrow at 8:00 AM`''',
      (t) {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 8, 0);
        t.expectEqual(
            utility.getFormattedTime(tomorrow), 'Tomorrow at 8:00 AM');
      },
    ),
    formatting(
      'tomorrow at 11:59 PM',
      'Late tomorrow still reads as "Tomorrow at ...".',
      '''
## What it checks
A late timestamp tomorrow is still labelled `Tomorrow` — the far edge of the
next day has not tipped into the weekday-name window.

## Expected
Tomorrow at 23:59 → `Tomorrow at 11:59 PM`''',
      (t) {
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day + 1, 23, 59);
        t.expectEqual(
            utility.getFormattedTime(tomorrow), 'Tomorrow at 11:59 PM');
      },
    ),
    formatting(
      '2 days ago returns full weekday name at time',
      'Within the past week, the day shows as its full weekday name.',
      '''
## What it checks
Between 2 and 6 days in the past the formatter uses the full weekday name
(Monday, Tuesday, …) rather than "Yesterday" or a date.

## Why it matters
Within the last week a weekday name ("Tuesday") is the most natural, scannable
reference; a full date would be overkill.

## Expected
2 days ago at 10:15 → `<Weekday> at 10:15 AM`''',
      (t) {
        final now = DateTime.now();
        final twoDaysAgo = DateTime(now.year, now.month, now.day - 2, 10, 15);
        t.expectEqual(utility.getFormattedTime(twoDaysAgo),
            '${_fullWeekday(twoDaysAgo.weekday)} at 10:15 AM');
      },
    ),
    formatting(
      '6 days ago is still within window',
      'Six days back is the far edge of the weekday window.',
      '''
## What it checks
Six days back is the **last** day still inside the weekday-name window — it
must still format as a weekday, not a date.

## Why it matters
Pins the inclusive boundary of the 7-day window from the past side, so an
off-by-one never leaks a bare date into the "this week" range.

## Expected
6 days ago at 07:45 → `<Weekday> at 7:45 AM`''',
      (t) {
        final now = DateTime.now();
        final sixDaysAgo = DateTime(now.year, now.month, now.day - 6, 7, 45);
        t.expectEqual(utility.getFormattedTime(sixDaysAgo),
            '${_fullWeekday(sixDaysAgo.weekday)} at 7:45 AM');
      },
    ),
    formatting(
      '2 days from now returns full weekday name at time',
      'Within the next week, the day shows as its full weekday name.',
      '''
## What it checks
Between 2 and 6 days in the future the formatter uses the full weekday name,
mirroring the past-side behaviour.

## Expected
2 days ahead at 16:00 → `<Weekday> at 4:00 PM`''',
      (t) {
        final now = DateTime.now();
        final twoDaysAhead = DateTime(now.year, now.month, now.day + 2, 16, 0);
        t.expectEqual(utility.getFormattedTime(twoDaysAhead),
            '${_fullWeekday(twoDaysAhead.weekday)} at 4:00 PM');
      },
    ),
    formatting(
      '6 days ahead is still within window',
      'Six days ahead is the far edge of the forward weekday window.',
      '''
## What it checks
Six days ahead is the last day still inside the forward weekday-name window.

## Why it matters
Pins the inclusive boundary of the 7-day window from the future side.

## Expected
6 days ahead at 20:00 → `<Weekday> at 8:00 PM`''',
      (t) {
        final now = DateTime.now();
        final sixDaysAhead = DateTime(now.year, now.month, now.day + 6, 20, 0);
        t.expectEqual(utility.getFormattedTime(sixDaysAhead),
            '${_fullWeekday(sixDaysAhead.weekday)} at 8:00 PM');
      },
    ),
    formatting(
      'exactly 7 days ago falls outside the window',
      'At seven days back the format switches to "Month Day at ...".',
      '''
## What it checks
At exactly 7 days back the weekday window **ends**: the format switches to
`<Month> <Day> at ...` (same calendar year, so no year).

## Why it matters
This is the exclusive edge of the window — day 7 must not still read as a
weekday, or "last Tuesday" and "the Tuesday before" would look identical.

## Expected
7 days ago at 11:00 → `<Month> <Day> at 11:00 AM`''',
      (t) {
        final now = DateTime.now();
        final sevenDaysAgo = DateTime(now.year, now.month, now.day - 7, 11, 0);
        t.expectEqual(utility.getFormattedTime(sevenDaysAgo),
            '${_monthName(sevenDaysAgo.month)} ${sevenDaysAgo.day} at 11:00 AM');
      },
    ),
    formatting(
      '30 days ago shows month and day',
      'Well outside the week, the date shows month and day (same year).',
      '''
## What it checks
Well outside the week (30 days) the date shows as `<Month> <Day> at ...` with no
year, because it is still the same calendar year.

## Expected
30 days ago at 13:05 → `<Month> <Day> at 1:05 PM`''',
      (t) {
        final now = DateTime.now();
        final thirtyDaysAgo =
            DateTime(now.year, now.month, now.day - 30, 13, 5);
        t.expectEqual(utility.getFormattedTime(thirtyDaysAgo),
            '${_monthName(thirtyDaysAgo.month)} ${thirtyDaysAgo.day} at 1:05 PM');
      },
    ),
    formatting(
      'exactly 7 days ahead falls outside the window',
      'At seven days ahead the format switches to "Month Day at ...".',
      '''
## What it checks
At exactly 7 days ahead the forward weekday window ends and the format switches
to `<Month> <Day> at ...` — the future-side mirror of the 7-days-ago edge.

## Expected
7 days ahead at 09:30 → `<Month> <Day> at 9:30 AM`''',
      (t) {
        final now = DateTime.now();
        final sevenDaysAhead =
            DateTime(now.year, now.month, now.day + 7, 9, 30);
        t.expectEqual(utility.getFormattedTime(sevenDaysAhead),
            '${_monthName(sevenDaysAhead.month)} ${sevenDaysAhead.day} at 9:30 AM');
      },
    ),
    formatting(
      'past year includes year in output',
      'A date in a previous year includes the year.',
      '''
## What it checks
A timestamp in an earlier calendar year includes the year:
`<Month> <Day>, <Year> at ...`.

## Why it matters
Once a date crosses a year boundary, the year is essential to disambiguate — a
bare "March 15" could be any year.

## Expected
Last year, Mar 15 10:00 → `March 15, <year> at 10:00 AM`''',
      (t) {
        final lastYear = DateTime(DateTime.now().year - 1, 3, 15, 10, 0);
        t.expectEqual(utility.getFormattedTime(lastYear),
            'March 15, ${lastYear.year} at 10:00 AM');
      },
    ),
    formatting(
      'future year includes year in output',
      'A date in a future year includes the year.',
      '''
## What it checks
A timestamp in a later calendar year also includes the year, mirroring the
past-year case.

## Expected
Next year, Nov 1 18:45 → `November 1, <year> at 6:45 PM`''',
      (t) {
        final nextYear = DateTime(DateTime.now().year + 1, 11, 1, 18, 45);
        t.expectEqual(utility.getFormattedTime(nextYear),
            'November 1, ${nextYear.year} at 6:45 PM');
      },
    ),
    formatting(
      '1:00 AM formats correctly (not 0-hour)',
      '1 AM shows as 1:00 AM, never a zero hour.',
      '''
## What it checks
The early-morning hour `1` renders as `1:00 AM` — confirming the 12-hour
conversion doesn't accidentally zero-index the hour.

## Expected
Today at 01:00 → `Today at 1:00 AM`''',
      (t) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 1, 0);
        t.expectEqual(utility.getFormattedTime(dt), 'Today at 1:00 AM');
      },
    ),
    formatting(
      '11:59 PM formats correctly',
      'The last minute of the day shows as 11:59 PM.',
      '''
## What it checks
The last minute of the day renders as `11:59 PM` — the top of the PM range.

## Expected
Today at 23:59 → `Today at 11:59 PM`''',
      (t) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 23, 59);
        t.expectEqual(utility.getFormattedTime(dt), 'Today at 11:59 PM');
      },
    ),
    formatting(
      'single-digit minutes are zero-padded',
      'Minutes under ten are zero-padded (3:07, not 3:7).',
      '''
## What it checks
Minutes below ten are zero-padded to two digits: `3:07`, never `3:7`.

## Why it matters
Unpadded minutes read as a different, wrong time ("3:7"); padding is what makes
the clock legible.

## Expected
Today at 03:07 → `Today at 3:07 AM`''',
      (t) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 3, 7);
        t.expectEqual(utility.getFormattedTime(dt), 'Today at 3:07 AM');
      },
    ),
    formatting(
      '12:01 PM formats correctly (not 0:01 PM)',
      'Just past noon shows as 12:01 PM, not 0:01 PM.',
      '''
## What it checks
One minute past noon renders as `12:01 PM`, not `0:01 PM` — the noon hour stays
12 even with non-zero minutes.

## Expected
Today at 12:01 → `Today at 12:01 PM`''',
      (t) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 12, 1);
        t.expectEqual(utility.getFormattedTime(dt), 'Today at 12:01 PM');
      },
    ),
    formatting(
      '12:01 AM formats correctly (not 24:01)',
      'Just past midnight shows as 12:01 AM, not 24:01.',
      '''
## What it checks
One minute past midnight renders as `12:01 AM`, not `24:01` or `0:01` — the
midnight hour stays 12 with non-zero minutes.

## Expected
Today at 00:01 → `Today at 12:01 AM`''',
      (t) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, 0, 1);
        t.expectEqual(utility.getFormattedTime(dt), 'Today at 12:01 AM');
      },
    ),
  ];
}

String _fullWeekday(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Monday';
    case DateTime.tuesday:
      return 'Tuesday';
    case DateTime.wednesday:
      return 'Wednesday';
    case DateTime.thursday:
      return 'Thursday';
    case DateTime.friday:
      return 'Friday';
    case DateTime.saturday:
      return 'Saturday';
    case DateTime.sunday:
      return 'Sunday';
    default:
      return '';
  }
}

String _monthName(int month) {
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month];
}
