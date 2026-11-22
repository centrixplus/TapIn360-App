import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/tap/tap_debouncer.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 17, 6);
  DateTime at(num seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

  test('first read is accepted, the same UID 1 s later is ignored', () {
    final d = TapDebouncer();
    expect(d.accept('04DB8FE23B1590', at(0)), isTrue);
    expect(d.accept('04DB8FE23B1590', at(1)), isFalse);
  });

  test('holding the card (a read every 1 s for 30 s) is one tap', () {
    final d = TapDebouncer();
    var accepted = 0;
    for (var s = 0; s <= 30; s++) {
      if (d.accept('04DB8FE23B1590', at(s))) accepted++;
    }
    expect(accepted, 1);
  });

  test('the same UID 10 s after the previous read is a new tap', () {
    final d = TapDebouncer();
    expect(d.accept('A', at(0)), isTrue);
    expect(d.accept('A', at(9.999)), isFalse);
    expect(d.accept('A', at(19.999)), isTrue, reason: '10 s after the previous (ignored) read');
  });

  test('a different UID is accepted at once', () {
    final d = TapDebouncer();
    expect(d.accept('A', at(0)), isTrue);
    expect(d.accept('B', at(0.5)), isTrue);
    expect(d.accept('A', at(1)), isTrue, reason: 'the previous read was B');
  });

  test('reset forgets the previous read', () {
    final d = TapDebouncer();
    expect(d.accept('A', at(0)), isTrue);
    d.reset();
    expect(d.accept('A', at(1)), isTrue);
  });
}
