import '../core/sheets_api.dart';

/// One row of the "Deadlines" tab in the classwork ("bot") spreadsheet.
class Deadline {
  final String course, type, title;
  final DateTime? due;

  const Deadline({
    required this.course,
    required this.type,
    required this.title,
    this.due,
  });
}

/// Reads the class deadlines. `SheetsApi` keeps its own on-disk copy and falls
/// back to it when a fetch fails, so this still returns the last known list
/// with no internet.
class DeadlineRepository {
  DeadlineRepository._();
  static final instance = DeadlineRepository._();

  Future<List<Deadline>> load() async =>
      parse(await SheetsApi.instance.botSheetRaw('Deadlines'));

  /// Raw rows keep the GVIZ `Date(y,m,d,h,mi,s)` sentinels, so the deadline is
  /// precise to the second (the formatted sheet endpoint drops the time).
  /// Soonest upcoming first, then the most recent past ones.
  static List<Deadline> parse(List<List<String>> rows) {
    final out = <Deadline>[];
    for (final r in rows) {
      String at(int n) => n < r.length ? r[n].trim() : '';
      final course = at(0), type = at(1), title = at(2);
      if (title.isEmpty) continue;
      if (course.toLowerCase() == 'course' || type.toLowerCase() == 'type') {
        continue;
      }
      out.add(
        Deadline(
          course: course,
          type: type,
          title: title,
          due: parseGvizDate(at(3)),
        ),
      );
    }
    final now = DateTime.now();
    out.sort((a, b) {
      final am = a.due?.difference(now).inSeconds ?? 1 << 30;
      final bm = b.due?.difference(now).inSeconds ?? 1 << 30;
      if (am >= 0 && bm >= 0) return am - bm; // soonest upcoming first
      if (am >= 0) return -1; // upcoming before past
      if (bm >= 0) return 1;
      return bm - am; // most-recent past first
    });
    return out;
  }

  /// Parse GVIZ `Date(y,m,d[,h,mi,s])` (month is 0-based) or a plain date.
  static DateTime? parseGvizDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(
      r'^Date\((\d+),(\d+),(\d+)(?:,(\d+),(\d+)(?:,(\d+))?)?\)$',
    ).firstMatch(t);
    if (m != null) {
      return DateTime(
        int.parse(m[1]!),
        int.parse(m[2]!) + 1,
        int.parse(m[3]!),
        int.parse(m[4] ?? '0'),
        int.parse(m[5] ?? '0'),
        int.parse(m[6] ?? '0'),
      );
    }
    return DateTime.tryParse(t.replaceFirst(' ', 'T'));
  }
}
