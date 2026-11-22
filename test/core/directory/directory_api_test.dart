import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/config/tapin_config.dart';
import 'package:nfc_attendance/core/directory/company.dart';
import 'package:nfc_attendance/core/directory/directory_api.dart';

import '../../helpers/stub_adapter.dart';

void main() {
  late StubAdapter adapter;
  late DirectoryApi api;

  Map<String, Object?> company({
    String status = 'active',
    Object? logo,
    String base = 'https://acme.tapin360.co/nfc/api/v1',
  }) => {
    'code': 'acme',
    'name': 'Acme Trading Co.',
    'logo_url': logo,
    'api_base_url': base,
    'status': status,
  };

  setUp(() {
    adapter = StubAdapter((_) => jsonResponse(200, company()));
    api = DirectoryApi(
      dio: createApiDio()..httpClientAdapter = adapter,
      masterUrl: 'http://localhost:8051/',
      language: () => 'ar',
      timeout: const Duration(milliseconds: 200),
    );
  });

  test('master URL is a build-time constant with the production default', () {
    expect(tapinMasterUrl, 'https://account.tapin360.co');
    expect(
      directoryUrl('https://account.tapin360.co/', 'acme'),
      'https://account.tapin360.co/tapin/api/v1/company/acme',
    );
  });

  test('GET <master>/tapin/api/v1/company/<code> with Accept-Language; active → found', () async {
    final result = await api.lookup('acme');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), 'http://localhost:8051/tapin/api/v1/company/acme');
    expect(request.headers['Accept-Language'], 'ar');
    expect(request.headers['Authorization'], isNull);
    final found = (result as CompanyFound).company;
    expect(found.code, 'acme');
    expect(found.name, 'Acme Trading Co.');
    expect(found.logoUrl, isNull);
    expect(found.apiBaseUrl, 'https://acme.tapin360.co/nfc/api/v1');
    expect(found.status, CompanyStatus.active);
  });

  test('grace keeps working (found)', () async {
    adapter.handler = (_) => jsonResponse(200, company(status: 'grace', logo: 'https://x/logo.png'));
    final found = (await api.lookup('acme') as CompanyFound).company;
    expect(found.status, CompanyStatus.grace);
    expect(found.logoUrl, 'https://x/logo.png');
  });

  test('api_base_url is normalised (trailing slash)', () async {
    adapter.handler = (_) => jsonResponse(200, company(base: 'https://entest2.tapin360.co/nfc/api/v1/'));
    expect(
      (await api.lookup('acme') as CompanyFound).company.apiBaseUrl,
      'https://entest2.tapin360.co/nfc/api/v1',
    );
  });

  test('a plain http:// api_base_url on another host → insecure (https required), never found', () async {
    for (final base in [
      'http://acme.tapin360.co/nfc/api/v1',
      'http://10.0.0.5:8069/nfc/api/v1',
      'http://entest2.localhost:8050/nfc/api/v1',
    ]) {
      adapter.handler = (_) => jsonResponse(200, company(base: base));
      final result = await api.lookup('acme');
      expect(result, isA<CompanyInsecure>(), reason: base);
      expect((result as CompanyInsecure).company.name, 'Acme Trading Co.');
    }
  });

  test('http:// on localhost (local tests over adb reverse) is still found', () async {
    for (final base in ['http://localhost:8052/nfc/api/v1', 'http://127.0.0.1:8046/nfc/api/v1']) {
      adapter.handler = (_) => jsonResponse(200, company(base: base));
      expect(await api.lookup('acme'), isA<CompanyFound>(), reason: base);
    }
  });

  for (final status in ['suspended', 'provisioning', 'deleted', 'something_new']) {
    test('$status → not ready, no login', () async {
      adapter.handler = (_) => jsonResponse(200, company(status: status));
      final result = await api.lookup('acme');
      expect(result, isA<CompanyNotReady>());
      expect((result as CompanyNotReady).company.canLogIn, isFalse);
    });
  }

  test('404 → not found', () async {
    adapter.handler = (_) => jsonResponse(404, errorBody('not_found', 'Not found.'));
    expect(await api.lookup('nosuch'), isA<CompanyNotFound>());
  });

  test('400 (invalid code) → not found', () async {
    adapter.handler = (_) => jsonResponse(400, errorBody('bad_request', 'Invalid code'));
    expect(await api.lookup('acme'), isA<CompanyNotFound>());
  });

  test('429 → rate limited', () async {
    adapter.handler = (_) => jsonResponse(429, errorBody('rate_limited', 'Too many requests'));
    expect(await api.lookup('acme'), isA<CompanyLookupRateLimited>());
  });

  test('5xx, timeout, connection error and garbled 200 → failed', () async {
    adapter.handler = (_) => jsonResponse(503, {});
    expect(await api.lookup('acme'), isA<CompanyLookupFailed>());
    adapter.handler = (request) => throw DioException.connectionError(requestOptions: request, reason: 'x');
    expect(await api.lookup('acme'), isA<CompanyLookupFailed>());
    adapter.handler = (_) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return jsonResponse(200, company());
    };
    expect(await api.lookup('acme'), isA<CompanyLookupFailed>());
    adapter.handler = (_) => textResponse(200, '<html>');
    expect(await api.lookup('acme'), isA<CompanyLookupFailed>());
    adapter.handler = (_) => jsonResponse(200, company(base: 'not a url'));
    expect(await api.lookup('acme'), isA<CompanyLookupFailed>());
  });

  test('Company survives a JSON round trip (stored on the phone)', () {
    final c = Company.fromJson(company(status: 'grace', logo: 'https://x/l.png'))!;
    final back = Company.fromJson(c.toJson())!;
    expect(back.code, c.code);
    expect(back.name, c.name);
    expect(back.logoUrl, c.logoUrl);
    expect(back.apiBaseUrl, c.apiBaseUrl);
    expect(back.status, CompanyStatus.grace);
    expect(c.initials, 'AT');
  });
}
