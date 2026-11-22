import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/config/server_url.dart';

void main() {
  test('strips surrounding whitespace and every trailing slash', () {
    expect(normaliseServerUrl('  http://localhost:8046/nfc/api/v1///  '), 'http://localhost:8046/nfc/api/v1');
  });

  test('keeps a URL that is already normalised', () {
    expect(normaliseServerUrl('https://erp.client.com/nfc/api/v1'), 'https://erp.client.com/nfc/api/v1');
  });

  test('adds https:// when the scheme is missing', () {
    expect(normaliseServerUrl('erp.client.com/nfc/api/v1/'), 'https://erp.client.com/nfc/api/v1');
  });

  test('lower-cases the scheme', () {
    expect(normaliseServerUrl('HTTP://10.0.0.5:8069/nfc/api/v1'), 'http://10.0.0.5:8069/nfc/api/v1');
  });

  test('rejects empty, non-http schemes, missing host, query and fragment', () {
    expect(normaliseServerUrl(''), isNull);
    expect(normaliseServerUrl('   '), isNull);
    expect(normaliseServerUrl('ftp://erp.client.com/nfc/api/v1'), isNull);
    expect(normaliseServerUrl('https:///nfc/api/v1'), isNull);
    expect(normaliseServerUrl('https://erp.client.com/nfc/api/v1?db=x'), isNull);
    expect(normaliseServerUrl('https://erp.client.com/nfc/api/v1#x'), isNull);
    expect(normaliseServerUrl('https://erp client.com'), isNull);
  });

  test('endpoint joins the base and a fixed path with one slash', () {
    expect(
      endpointUrl('http://localhost:8046/nfc/api/v1', 'punch'),
      'http://localhost:8046/nfc/api/v1/punch',
    );
  });

  group('isInsecureServerUrl (plain http:// only to the phone itself)', () {
    test('http:// on localhost, 127.0.0.1 and the emulator host 10.0.2.2 is allowed', () {
      expect(isInsecureServerUrl('http://localhost:8046/nfc/api/v1'), isFalse);
      expect(isInsecureServerUrl('http://LOCALHOST:8052/nfc/api/v1'), isFalse);
      expect(isInsecureServerUrl('http://127.0.0.1:8051'), isFalse);
      expect(isInsecureServerUrl('http://10.0.2.2:8069/nfc/api/v1'), isFalse);
    });

    test('https:// is never insecure', () {
      expect(isInsecureServerUrl('https://erp.client.com/nfc/api/v1'), isFalse);
      expect(isInsecureServerUrl('https://10.0.0.5:8069/nfc/api/v1'), isFalse);
    });

    test('http:// to any other host is refused (on-premise IPs, *.localhost, look-alikes)', () {
      expect(isInsecureServerUrl('http://erp.client.com/nfc/api/v1'), isTrue);
      expect(isInsecureServerUrl('http://10.0.0.5:8069/nfc/api/v1'), isTrue);
      expect(isInsecureServerUrl('http://192.168.1.20:8069'), isTrue);
      expect(isInsecureServerUrl('http://entest2.localhost:8050/nfc/api/v1'), isTrue);
      expect(isInsecureServerUrl('http://localhost.evil.com/nfc/api/v1'), isTrue);
      expect(isInsecureServerUrl('HTTP://erp.client.com'), isTrue);
    });
  });
}
