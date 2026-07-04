import 'package:add_2_calendar/add_2_calendar.dart';

class CalendarService {
  CalendarService._();

  static Future<bool> addDeadline({
    required String course,
    required String type,
    required String title,
    required DateTime deadline,
  }) {
    final start = deadline.subtract(const Duration(minutes: 30));
    return Add2Calendar.addEvent2Cal(
      Event(
        title: 'Deadline: ${course.isEmpty ? title : course}',
        description: [
          type,
          title,
        ].where((v) => v.trim().isNotEmpty).join(' · '),
        startDate: start,
        endDate: deadline,
      ),
    );
  }

  static Future<bool> addExam({
    required String course,
    required String courseName,
    required DateTime date,
    required String time,
  }) {
    final range = _timeRange(date, time);
    return Add2Calendar.addEvent2Cal(
      Event(
        title: 'Exam: $course',
        description: courseName,
        location: 'Leading University',
        startDate: range.$1,
        endDate: range.$2,
        allDay: time.trim().isEmpty,
      ),
    );
  }

  static (DateTime, DateTime) _timeRange(DateTime date, String value) {
    final matches = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?',
      caseSensitive: false,
    ).allMatches(value).toList();
    DateTime at(RegExpMatch? match, int fallbackHour) {
      if (match == null) {
        return DateTime(date.year, date.month, date.day, fallbackHour);
      }
      var hour = int.tryParse(match.group(1) ?? '') ?? fallbackHour;
      final minute = int.tryParse(match.group(2) ?? '') ?? 0;
      final suffix = (match.group(3) ?? '').toUpperCase();
      if (suffix == 'PM' && hour < 12) hour += 12;
      if (suffix == 'AM' && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    }

    final start = at(matches.isEmpty ? null : matches.first, 9);
    var end = at(matches.length > 1 ? matches[1] : null, start.hour + 2);
    if (!end.isAfter(start)) end = start.add(const Duration(hours: 2));
    return (start, end);
  }
}
