import 'sheets_api.dart';

/// "CSE -4116 NJN NL" (stray space before the dash) → "CSE-4116 NJN NL", so a
/// routine cell isn't split into code "CSE" + teacher "-4116".
String fixCourseCodeSpacing(String cell) => cell.replaceFirstMapped(
  RegExp(r'^\s*([A-Za-z]{2,5})\s*[-–]\s*(?=\d)'),
  (m) => '${m[1]}-',
);

/// Merge one day's rows from several linked routine sheets. A batch/section
/// listed in more than one sheet belongs to the FIRST sheet that lists it: Link
/// 1 is the current routine, while a later link (e.g. "everything else") often
/// still carries last semester's rows for the same section, which would blend
/// into it and clash with the new courses. Sections only a later sheet lists are
/// still added.
List<List<String>> mergeSectionRows(List<SheetTable> tables) {
  final claimed = <String>{};
  final out = <List<String>>[];
  for (final t in tables) {
    final own = <String>{};
    for (final row in t.rows) {
      final key = _sectionKey(row);
      if (key != null) {
        if (claimed.contains(key)) continue;
        own.add(key);
      }
      out.add(row);
    }
    claimed.addAll(own);
  }
  return out;
}

String? _sectionKey(List<String> row) {
  if (row.length < 3) return null;
  final batch = row[1].trim().replaceAll(RegExp(r'\.0+$'), '');
  final section = row[2].trim().toUpperCase();
  if (!RegExp(r'^\d+$').hasMatch(batch) || section.isEmpty) return null;
  return '$batch-$section';
}
