// Guest access: someone from another section, listed on the Main Sheet's
// "Special Access" tab, sees their own routine but not what belongs to CSE 62B
// alone. Getting `isGuestSection` wrong either locks the class out of its own
// pages or shows a stranger its attendance register, so it is pinned here.
import 'package:flutter_test/flutter_test.dart';

import 'package:lucse62b/core/router.dart';
import 'package:lucse62b/data/models/student.dart';

void main() {
  group('isGuestSection', () {
    test('the class itself is not a guest', () {
      final s = Student.create('0182320012101068', 'Almas');
      expect(s.batch, '62');
      expect(s.section, 'B');
      expect(s.isGuestSection, isFalse);
    });

    test('another section is a guest', () {
      final s = Student.create(
        '0182320012101108',
        'Kolsuma',
        batch: '62',
        section: 'C',
      );
      expect(s.isGuestSection, isTrue);
    });

    test('another batch is a guest even in section B', () {
      final s = Student.create('1', 'Someone', batch: '61', section: 'B');
      expect(s.isGuestSection, isTrue);
    });

    test('demo is never treated as a guest', () {
      final s = Student.create('DEMO', 'Demo Student', isDemo: true);
      expect(s.isGuestSection, isFalse);
    });
  });

  group('sessions saved before guest access existed', () {
    test('a stored session with no batch/section stays 62 B', () {
      final s = Student.fromJson({
        'id': '0182320012101068',
        'name': 'Almas',
        'loginTime': 1,
        'sessionId': 'x',
        'sessionIssuedAt': 1,
      });
      expect(s.batch, '62');
      expect(s.section, 'B');
      expect(s.isGuestSection, isFalse);
    });

    test('a guest round-trips through JSON', () {
      final original = Student.create('1', 'Guest', batch: '62', section: 'C');
      final restored = Student.fromJson(original.toJson());
      expect(restored.batch, '62');
      expect(restored.section, 'C');
      expect(restored.isGuestSection, isTrue);
    });

    test('the section is normalised to upper case', () {
      final s = Student.fromJson({
        'id': '1',
        'name': 'Guest',
        'batch': ' 62 ',
        'section': ' c ',
        'loginTime': 1,
      });
      expect(s.batch, '62');
      expect(s.section, 'C');
    });

    test('a fresh session keeps the section', () {
      final s = Student.create(
        '1',
        'Guest',
        batch: '62',
        section: 'C',
      ).withFreshSession();
      expect(s.section, 'C');
      expect(s.isGuestSection, isTrue);
    });
  });

  test('the closed routes are exactly the class-only ones', () {
    // Cover Page, Gallery and bKash are deliberately NOT here.
    expect(classOnlyRoutes, {
      '/attendance',
      '/classwork',
      '/students',
      '/info/links',
    });
    for (final open in ['/cover-page', '/gallery', '/info/bkash', '/results']) {
      expect(classOnlyRoutes.contains(open), isFalse, reason: open);
    }
  });
}
