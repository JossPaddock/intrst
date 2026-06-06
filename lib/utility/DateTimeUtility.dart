class DateTimeUtility {
  String getFormattedTime(DateTime? dt) {
    if (dt == null) return '';

    final DateTime now = DateTime.now();
    final DateTime localDt = dt.toLocal();
    final DateTime localNow = now.toLocal();

    final DateTime todayMidnight = DateTime(localNow.year, localNow.month, localNow.day);
    final DateTime inputMidnight = DateTime(localDt.year, localDt.month, localDt.day);
    final int dayDifference = inputMidnight.difference(todayMidnight).inDays;
    final Duration absoluteDiff = localDt.difference(localNow).abs();
    final bool isWithin7Days = absoluteDiff.inHours < 168;

    String timeStr = _formatTime(localDt);

    // Today
    if (dayDifference == 0) {
      return 'Today at $timeStr';
    }

    // Yesterday / Tomorrow
    if (dayDifference == -1) return 'Yesterday at $timeStr';
    if (dayDifference == 1) return 'Tomorrow at $timeStr';

    // Within 7 days (past or future)
    if (isWithin7Days) {
      return '${_getWeekday(localDt.weekday)} at $timeStr';
    }

    // Same calendar year
    if (localDt.year == localNow.year) {
      return '${_getMonth(localDt.month)} ${localDt.day} at $timeStr';
    }

    // Different year
    return '${_getMonth(localDt.month)} ${localDt.day}, ${localDt.year} at $timeStr';
  }

  String _formatTime(DateTime dt) {
    int hour = dt.hour;
    final String ampm = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) {
      hour -= 12;
    } else if (hour == 0) {
      hour = 12;
    }
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm';
  }

  String _getWeekday(int weekday) {
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

  String _getMonth(int month) {
    switch (month) {
      case 1:  return 'January';
      case 2:  return 'February';
      case 3:  return 'March';
      case 4:  return 'April';
      case 5:  return 'May';
      case 6:  return 'June';
      case 7:  return 'July';
      case 8:  return 'August';
      case 9:  return 'September';
      case 10: return 'October';
      case 11: return 'November';
      case 12: return 'December';
      default: return '';
    }
  }
}