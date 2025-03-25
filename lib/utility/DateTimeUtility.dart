class DateTimeUtility {
  String getFormattedTime(DateTime? dt) {
    if (dt == null) return ''; // Return an empty string if dt is null

    String weekday = _getWeekday(dt.weekday);
    String timeOfDay = _formatTime(dt);
    return '$weekday $timeOfDay';
  }

  String _getWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return 'weekday not valid';
    }
  }

  String _formatTime(DateTime dateTime) {
    int hour = dateTime.hour;
    String ampm = hour >= 12 ? 'PM' : 'AM';
    if (hour > 12) {
      hour -= 12;
    } else if (hour == 0) {
      hour = 12; // Midnight case
    }
    String minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute$ampm';
  }
}
