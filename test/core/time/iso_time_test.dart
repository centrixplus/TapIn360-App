import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/time/iso_time.dart';

void main() {
  group('isoWithOffset (tapped_at / captured_at)', () {
    test('writes the wall-clock time with a positive offset, no milliseconds', () {
      final utc = DateTime.utc(2026, 11, 17, 6, 2, 11, 987);
      expect(isoWithOffset(utc, const Duration(hours: 3)), '2026-11-17T09:02:11+03:00');
    });

    test('handles negative and half-hour offsets', () {
      final utc = DateTime.utc(2026, 1, 1, 2, 0, 5);
      expect(isoWithOffset(utc, const Duration(hours: -5)), '2025-12-31T21:00:05-05:00');
      expect(isoWithOffset(utc, const Duration(hours: 5, minutes: 30)), '2026-01-01T07:30:05+05:30');
    });

    test('UTC phone offset is written as +00:00', () {
      expect(isoWithOffset(DateTime.utc(2026, 11, 17, 6), Duration.zero), '2026-11-17T06:00:00+00:00');
    });

    test('localIso uses the DateTime own offset', () {
      final now = DateTime(2026, 11, 17, 9, 2, 11);
      final text = localIso(now);
      expect(DateTime.parse(text).toUtc(), now.toUtc());
      expect(text, startsWith('2026-11-17T09:02:11'));
    });
  });

  group('parseServerTime', () {
    test('parses ISO 8601 UTC into a UTC DateTime', () {
      final t = parseServerTime('2026-11-17T06:02:11Z');
      expect(t, DateTime.utc(2026, 11, 17, 6, 2, 11));
      expect(t!.isUtc, isTrue);
    });

    test('returns null for null, non-strings and garbage', () {
      expect(parseServerTime(null), isNull);
      expect(parseServerTime(17), isNull);
      expect(parseServerTime('yesterday'), isNull);
    });
  });
}
