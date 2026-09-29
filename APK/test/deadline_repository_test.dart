// The Deadlines sheet feeds both the Classwork countdowns and the reminders
// that get scheduled from them, so the parsing and the ordering are pinned.
import 'package:flutter_test/flutter_test.dart';

import 'package:lucse62b/data/deadline_repository.dart';

void main() {
  group('parseGvizDate', () {
    test('reads a GVIZ sentinel, with its 0-based month', () {
      expect(
        DeadlineRepository.parseGvizDate('Date(2026,9,5,17,30,0)'),
        DateTime(2026, 10, 5, 17, 30),
      );
    });

    test('reads a date-only sentinel', () {
      expect(
        DeadlineRepository.parseGvizDate('Date(2026,0,1)'),
        DateTime(2026, 1, 1),
      );
    });

    test('falls back to an ISO string, and gives up on anything else', () {
      expect(
        DeadlineRepository.parseGvizDate('2026-10-05 17:30:00'),
        DateTime(2026, 10, 5, 17, 30),
      );
      expect(DeadlineRepository.parseGvizDate(''), isNull);
      expect(DeadlineRepository.parseGvizDate('next week'), isNull);
    });
  });

  group('parse', () {
    test('skips the header row and rows with no title', () {
      final items = DeadlineRepository.parse([
        ['Course', 'Type', 'Title', 'Deadline'],
        ['CSE-4116', 'Lab Report', '', 'Date(2026,9,5)'],
        ['CSE-4116', 'Lab Report', 'Parser', 'Date(2026,9,5)'],
      ]);
      expect(items, hasLength(1));
      expect(items.single.title, 'Parser');
      expect(items.single.course, 'CSE-4116');
    });

    test('tolerates short rows', () {
      final items = DeadlineRepository.parse([
        ['CSE-4116', 'Viva', 'Chapter 3'],
      ]);
      expect(items.single.due, isNull);
    });

    test('orders soonest upcoming first, then the most recent past', () {
      final now = DateTime.now();
      String at(Duration d) {
        final t = now.add(d);
        return 'Date(${t.year},${t.month - 1},${t.day},${t.hour},${t.minute},0)';
      }

      final items = DeadlineRepository.parse([
        ['A', 'Quiz', 'long past', at(const Duration(days: -9))],
        ['B', 'Quiz', 'later', at(const Duration(days: 4))],
        ['C', 'Quiz', 'no date', ''],
        ['D', 'Quiz', 'soon', at(const Duration(hours: 3))],
        ['E', 'Quiz', 'just past', at(const Duration(hours: -3))],
      ]);

      expect(items.map((d) => d.title), [
        'soon',
        'later',
        'no date',
        'just past',
        'long past',
      ]);
    });
  });
}
