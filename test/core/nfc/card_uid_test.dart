import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/nfc/card_uid.dart';

void main() {
  test('formats the real wall card UID as uppercase hex without separators', () {
    final uid = Uint8List.fromList([0x04, 0xDB, 0x8F, 0xE2, 0x3B, 0x15, 0x90]);
    expect(formatCardUid(uid), '04DB8FE23B1590');
  });

  test('keeps the leading zero of every byte', () {
    expect(formatCardUid(Uint8List.fromList([0x00, 0x0A, 0xFF])), '000AFF');
  });

  test('rejects an empty UID', () {
    expect(() => formatCardUid(Uint8List(0)), throwsArgumentError);
  });
}
