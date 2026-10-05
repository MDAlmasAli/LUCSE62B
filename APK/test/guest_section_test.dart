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
      // …but it is flagged as a guess, so it gets resolved once.
      expect(s.sectionKnown, isFalse);
    });

    test('a session that carried a section is not re-resolved', () {
      final s = Student.fromJson({
        'id': '1',
        'name': 'Guest',
        'section': 'C',
        'loginTime': 1,
      });
      expect(s.sectionKnown, isTrue);
    });

    test('withSection fills in a guessed session without losing the login', () {
      final stale = Student.fromJson({
        'id': '0182320012101108',
        'name': 'Kolsuma',
        'loginTime': 42,
        'sessionId': 'keep-me',
        'sessionIssuedAt': 7,
      });
      expect(stale.isGuestSection, isFalse); // the wrong answer, for now

      final fixed = stale.withSection('62', 'c');
      expect(fixed.section, 'C');
      expect(fixed.sectionKnown, isTrue);
      expect(fixed.isGuestSection, isTrue);
      // The session itself must survive, or this would count as a new login.
      expect(fixed.sessionId, 'keep-me');
      expect(fixed.sessionIssuedAt, 7);
      expect(fixed.loginTime, 42);
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

  group('the seven-day expiry slides with use', () {
    const week = 7 * 24 * 60 * 60 * 1000;
    int now() => DateTime.now().millisecondsSinceEpoch;

    test('withLoginTime moves only the expiry clock', () {
      final before = Student.create(
        '1',
        'Someone',
        batch: '62',
        section: 'C',
      );
      final after = before.withLoginTime(before.loginTime + 1000);

      expect(after.loginTime, before.loginTime + 1000);
      // Everything that identifies the session has to survive, or the student
      // would be treated as newly signed in — or as the wrong section.
      expect(after.sessionId, before.sessionId);
      expect(after.sessionIssuedAt, before.sessionIssuedAt);
      expect(after.id, before.id);
      expect(after.section, 'C');
      expect(after.sectionKnown, isTrue);
      expect(after.isGuestSection, isTrue);
    });

    test('a session used within the week is not expired', () {
      final s = Student.fromJson({
        'id': '1',
        'name': 'Someone',
        'loginTime': now() - (week - 60000),
      });
      expect(now() - s.loginTime > week, isFalse);
    });

    test('a session untouched for over a week still expires', () {
      final s = Student.fromJson({
        'id': '1',
        'name': 'Someone',
        'loginTime': now() - (week + 60000),
      });
      expect(now() - s.loginTime > week, isTrue);
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
