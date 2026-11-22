import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/directory/company_code.dart';

void main() {
  group('company code rule (TapIn360 spec §5.3)', () {
    test('valid codes', () {
      for (final code in ['acme', 'abc', 'a1-b2', 'entest2', 'a${'b' * 28}c']) {
        expect(isValidCompanyCode(code), isTrue, reason: code);
      }
    });

    test('invalid codes', () {
      for (final code in [
        '',
        'ab',
        'a${'b' * 29}c',
        '1abc',
        '-abc',
        'abc-',
        'a--b',
        'ab_c',
        'ACME',
        'acme co',
        'acmé',
      ]) {
        expect(isValidCompanyCode(code), isFalse, reason: code);
      }
    });

    test('typed codes are trimmed and lower-cased', () {
      expect(normaliseCompanyCode('  Acme '), 'acme');
      expect(normaliseCompanyCode('ab'), isNull);
    });
  });

  group('QR code', () {
    test('tapin://company/<code>', () {
      expect(companyCodeFromQr('tapin://company/acme'), 'acme');
      expect(companyCodeFromQr('TAPIN://company/Acme'), 'acme');
      expect(companyCodeFromQr('tapin://company/acme/'), 'acme');
      expect(companyCodeFromQr('  tapin://company/entest2  '), 'entest2');
    });

    test('a bare valid code is accepted', () => expect(companyCodeFromQr('acme'), 'acme'));

    test('anything else is refused', () {
      for (final raw in [
        'tapin://other/acme',
        'tapin://company/',
        'tapin://company/a/b',
        'tapin://company/1abc',
        'https://acme.tapin360.co',
        'https://evil.example/company/acme',
        'WIFI:S:office;T:WPA;P:secret;;',
        '',
      ]) {
        expect(companyCodeFromQr(raw), isNull, reason: raw);
      }
    });
  });
}
