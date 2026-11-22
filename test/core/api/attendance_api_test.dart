import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/api/api_outcome.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/api/error_codes.dart';
import 'package:nfc_attendance/core/api/server_probe.dart';

import '../../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

void main() {
  late StubAdapter adapter;
  late AttendanceApi api;
  String? token;
  var language = 'en';

  setUp(() {
    token = 'tok-1';
    language = 'en';
    adapter = StubAdapter((_) => jsonResponse(200, {}));
    final dio = createApiDio()..httpClientAdapter = adapter;
    api = AttendanceApi(
      dio: dio,
      baseUrl: () => base,
      token: () => token,
      language: () => language,
      timeout: const Duration(milliseconds: 200),
    );
  });

  final punchBody = <String, Object?>{
    'client_uuid': '6f1c2a9e-0000-4000-8000-000000000001',
    'card_uid': '04DB8FE23B1590',
    'action': 'auto',
    'tapped_at': '2026-11-17T09:02:11+03:00',
    'offline': false,
    'location': {
      'lat': 29.3759,
      'lng': 47.9774,
      'accuracy_m': 8.5,
      'is_mocked': false,
      'captured_at': '2026-11-17T09:02:09+03:00',
    },
  };

  group('login', () {
    test('POSTs JSON to /login without a token and parses the §5.2 response', () async {
      adapter.handler = (_) => jsonResponse(200, {
        'token': 'abc',
        'employee': {'id': 17, 'name': 'Ahmed Ali'},
        'settings': {'punch_mode': 'manual'},
        'server_time': '2026-11-17T06:00:00Z',
      });
      final outcome = await api.login(
        login: '041234567890',
        password: '1234',
        device: const DeviceInfo(
          id: 'dev-1',
          platform: 'android',
          model: 'SM-S928B',
          appVersion: '1.0.0+1',
          hardwareId: 'a1b2c3d4e5f60718',
          osVersion: '16',
        ),
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), '$base/login');
      expect(request.headers['Authorization'], isNull);
      expect(request.headers['Accept-Language'], 'en');
      expect(request.headers['Content-Type'], 'application/json');
      expect(adapter.bodyOf(0), {
        'login': '041234567890',
        'password': '1234',
        'device': {
          'id': 'dev-1',
          'platform': 'android',
          'model': 'SM-S928B',
          'app_version': '1.0.0+1',
          'hardware_id': 'a1b2c3d4e5f60718',
          'os_version': '16',
        },
      });
      final result = (outcome as ApiOk<LoginResult>).value;
      expect(result.token, 'abc');
      expect(result.employee.id, 17);
      expect(result.employee.name, 'Ahmed Ali');
      expect(result.punchMode, PunchMode.manual);
      expect(result.photoRequired, isFalse, reason: 'absent → false');
      expect(result.serverTime, DateTime.utc(2026, 11, 17, 6));
    });

    test('settings.photo_required is read from the login response', () async {
      adapter.handler = (_) => jsonResponse(200, {
        'token': 't',
        'employee': {'id': 1, 'name': 'A'},
        'settings': {'punch_mode': 'auto', 'photo_required': true},
      });
      final result =
          (await api.login(login: 'x', password: 'y', device: _device) as ApiOk<LoginResult>).value;
      expect(result.photoRequired, isTrue);
    });

    test('401 invalid_credentials is a rejection with the server message', () async {
      adapter.handler = (_) => jsonResponse(401, errorBody('invalid_credentials', 'Wrong Badge ID or PIN'));
      final outcome = await api.login(login: 'x', password: 'y', device: _device);
      final rejected = outcome as ApiRejected<LoginResult>;
      expect(rejected.status, 401);
      expect(rejected.code, ErrorCodes.invalidCredentials);
      expect(rejected.message, 'Wrong Badge ID or PIN');
    });

    test('403 device_not_allowed on login is a rejection with the server message', () async {
      adapter.handler = (_) => jsonResponse(
        403,
        errorBody('device_not_allowed', 'This phone is not registered for you. Ask HR to approve it.'),
      );
      final rejected =
          await api.login(login: 'x', password: 'y', device: _device) as ApiRejected<LoginResult>;
      expect(rejected.status, 403);
      expect(rejected.code, ErrorCodes.deviceNotAllowed);
      expect(rejected.isUnauthorized, isFalse);
    });

    test('423 locked keeps retry_after_s from inside error', () async {
      adapter.handler = (_) =>
          jsonResponse(423, errorBody('locked', 'Try again in 15 minutes', {'retry_after_s': 900}));
      final outcome = await api.login(login: 'x', password: 'y', device: _device);
      final rejected = outcome as ApiRejected<LoginResult>;
      expect(rejected.status, 423);
      expect(rejected.code, ErrorCodes.locked);
      expect(rejected.details['retry_after_s'], 900);
    });

    test('200 without a token is treated as a broken server, not a login', () async {
      adapter.handler = (_) => jsonResponse(200, {
        'employee': {'id': 1, 'name': 'A'},
      });
      final outcome = await api.login(login: 'x', password: 'y', device: _device);
      expect(outcome, isA<ApiUnreachable<LoginResult>>());
    });
  });

  group('punch', () {
    test('sends Bearer token, Accept-Language and the body unchanged; parses 200', () async {
      language = 'ar';
      adapter.handler = (_) => jsonResponse(200, {
        'result': 'check_in',
        'time': '2026-11-17T06:02:11Z',
        'site': 'Head Office',
        'message': 'Checked in at 09:02 — Head Office',
      });
      final outcome = await api.punch(punchBody);

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), '$base/punch');
      expect(request.headers['Authorization'], 'Bearer tok-1');
      expect(request.headers['Accept-Language'], 'ar');
      expect(adapter.bodyOf(0), punchBody);
      final result = (outcome as ApiOk<PunchResult>).value;
      expect(result.result, 'check_in');
      expect(result.time, DateTime.utc(2026, 11, 17, 6, 2, 11));
      expect(result.site, 'Head Office');
      expect(result.message, 'Checked in at 09:02 — Head Office');
    });

    const table = <(int, String)>[
      (400, 'bad_request'),
      (401, 'invalid_token'),
      (422, 'unknown_card'),
      (422, 'location_required'),
      (422, 'mock_location'),
      (422, 'out_of_range'),
      (422, 'too_old'),
      (422, 'invalid_time'),
      (422, 'older_than_last'),
      (422, 'too_soon'),
      (422, 'already_checked_in'),
      (422, 'not_checked_in'),
      (422, 'cannot_record'),
      (403, 'device_not_allowed'),
      (422, 'photo_required'),
      (422, 'invalid_photo'),
      (403, 'subscription_inactive'),
      (403, 'access_switched_off'),
    ];
    for (final (status, code) in table) {
      test('$status $code → rejected with code and message', () async {
        adapter.handler = (_) => jsonResponse(status, errorBody(code, 'msg $code', {'distance_m': 140}));
        final outcome = await api.punch(punchBody);
        final rejected = outcome as ApiRejected<PunchResult>;
        expect(rejected.status, status);
        expect(rejected.code, code);
        expect(rejected.message, 'msg $code');
        expect(rejected.isUnauthorized, status == 401);
        expect(rejected.isSwitchedOff, code == 'access_switched_off');
      });
    }

    test('every §5.3 code is known to the app', () {
      expect(ErrorCodes.all, containsAll(table.map((e) => e.$2)));
      expect(ErrorCodes.all, containsAll(['invalid_credentials', 'locked']));
    });

    test('out_of_range keeps distance_m', () async {
      adapter.handler = (_) => jsonResponse(422, errorBody('out_of_range', 'Too far', {'distance_m': 140.5}));
      final rejected = await api.punch(punchBody) as ApiRejected<PunchResult>;
      expect(rejected.details['distance_m'], 140.5);
    });

    test(
      '4xx without the standard error shape → unreachable, so a misconfigured proxy never loses taps',
      () async {
        adapter.handler = (_) => textResponse(404, '<html>Not Found</html>');
        final outcome = await api.punch(punchBody);
        expect(outcome, isA<ApiUnreachable<PunchResult>>());
        expect((outcome as ApiUnreachable<PunchResult>).reason, 'http_404');
      },
    );

    for (final status in [500, 502, 503, 504]) {
      test('$status → unreachable (queue and retry)', () async {
        adapter.handler = (_) => jsonResponse(status, errorBody('server_error', 'boom'));
        expect(await api.punch(punchBody), isA<ApiUnreachable<PunchResult>>());
      });
    }

    test('no answer within the timeout → unreachable', () async {
      adapter.handler = (_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return jsonResponse(200, {'result': 'check_in', 'message': 'late'});
      };
      final outcome = await api.punch(punchBody);
      expect(outcome, isA<ApiUnreachable<PunchResult>>());
    });

    test('connection error → unreachable', () async {
      adapter.handler = (request) =>
          throw DioException.connectionError(requestOptions: request, reason: 'Connection refused');
      expect(await api.punch(punchBody), isA<ApiUnreachable<PunchResult>>());
    });

    test('200 with a body that is not JSON → unreachable (resent later, server replays)', () async {
      adapter.handler = (_) => textResponse(200, '<html>proxy page</html>');
      expect(await api.punch(punchBody), isA<ApiUnreachable<PunchResult>>());
    });

    test('redirects are not followed and count as unreachable', () async {
      adapter.handler = (_) => textResponse(
        301,
        '',
        headers: {
          'location': ['https://x/nfc/api/v1/punch'],
        },
      );
      expect(await api.punch(punchBody), isA<ApiUnreachable<PunchResult>>());
    });

    group('"the server answered, with an error" vs offline (undeliverable cap)', () {
      Future<ApiUnreachable<PunchResult>> unreachable() async =>
          await api.punch(punchBody) as ApiUnreachable<PunchResult>;

      test('500, a non-JSON 4xx, a redirect and a garbled 200 count as answered', () async {
        adapter.handler = (_) => jsonResponse(500, errorBody('server_error', 'boom'));
        expect((await unreachable()).answered, isTrue, reason: '500');
        adapter.handler = (_) => textResponse(413, '<html>Request Entity Too Large</html>');
        expect((await unreachable()).answered, isTrue, reason: 'non-JSON 413');
        adapter.handler = (_) => textResponse(302, '', headers: {'location': ['https://x/login']});
        expect((await unreachable()).answered, isTrue, reason: '302');
        adapter.handler = (_) => textResponse(200, '<html>proxy page</html>');
        expect((await unreachable()).answered, isTrue, reason: 'garbled 200');
        adapter.handler = (_) => textResponse(200, '');
        expect((await unreachable()).answered, isTrue, reason: 'empty 200');
      });

      test('no connection, timeout and 502/503/504 (server behind the proxy down) are offline', () async {
        for (final status in [502, 503, 504]) {
          adapter.handler = (_) => textResponse(status, '<html>Bad Gateway</html>');
          expect((await unreachable()).answered, isFalse, reason: '$status');
        }
        adapter.handler = (request) =>
            throw DioException.connectionError(requestOptions: request, reason: 'Connection refused');
        expect((await unreachable()).answered, isFalse, reason: 'connection error');
        adapter.handler = (_) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return jsonResponse(200, {});
        };
        expect((await unreachable()).answered, isFalse, reason: 'timeout');
      });
    });

    test('without a stored token nothing is sent and the call is unauthorized', () async {
      token = null;
      final rejected = await api.punch(punchBody) as ApiRejected<PunchResult>;
      expect(rejected.status, 401);
      expect(rejected.code, ErrorCodes.invalidToken);
      expect(adapter.requests, isEmpty);
    });
  });

  group('status', () {
    test('GETs /status with Bearer and parses checked_in', () async {
      adapter.handler = (_) => jsonResponse(200, {
        'employee': {'id': 17, 'name': 'Ahmed Ali'},
        'state': 'checked_in',
        'since': '2026-11-17T05:02:00Z',
        'site': 'Head Office',
        'punch_mode': 'auto',
        'server_time': '2026-11-17T08:00:00Z',
      });
      final result = (await api.status() as ApiOk<StatusResult>).value;
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.uri.toString(), '$base/status');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer tok-1');
      expect(result.state, AttendanceState.checkedIn);
      expect(result.since, DateTime.utc(2026, 11, 17, 5, 2));
      expect(result.site, 'Head Office');
      expect(result.punchMode, PunchMode.auto);
      expect(result.employee.name, 'Ahmed Ali');
    });

    test('photo_required on /status: settings.photo_required, or top level', () async {
      Map<String, Object?> body(Map<String, Object?> extra) => {
        'employee': {'id': 17, 'name': 'Ahmed Ali'},
        'state': 'checked_out',
        'punch_mode': 'auto',
        ...extra,
      };
      adapter.handler = (_) => jsonResponse(
        200,
        body({
          'settings': {'photo_required': true},
        }),
      );
      expect((await api.status() as ApiOk<StatusResult>).value.photoRequired, isTrue);
      adapter.handler = (_) => jsonResponse(200, body({'photo_required': true}));
      expect((await api.status() as ApiOk<StatusResult>).value.photoRequired, isTrue);
      adapter.handler = (_) => jsonResponse(200, body({}));
      expect((await api.status() as ApiOk<StatusResult>).value.photoRequired, isFalse);
    });

    test('checked_out has null since and site', () async {
      adapter.handler = (_) => jsonResponse(200, {
        'employee': {'id': 17, 'name': 'Ahmed Ali'},
        'state': 'checked_out',
        'since': null,
        'site': null,
        'punch_mode': 'manual',
        'server_time': '2026-11-17T08:00:00Z',
      });
      final result = (await api.status() as ApiOk<StatusResult>).value;
      expect(result.state, AttendanceState.checkedOut);
      expect(result.since, isNull);
      expect(result.site, isNull);
      expect(result.punchMode, PunchMode.manual);
    });

    test('401 invalid_token → unauthorized rejection', () async {
      adapter.handler = (_) => jsonResponse(401, errorBody('invalid_token', 'Please log in again'));
      final rejected = await api.status() as ApiRejected<StatusResult>;
      expect(rejected.isUnauthorized, isTrue);
    });
  });

  test('logout POSTs with Bearer and returns ok', () async {
    adapter.handler = (_) => jsonResponse(200, {'ok': true});
    final outcome = await api.logout();
    expect(outcome, isA<ApiOk<bool>>());
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.uri.toString(), '$base/logout');
    expect(adapter.requests.single.headers['Authorization'], 'Bearer tok-1');
  });

  group('probe (Server setup → Test)', () {
    test('401 invalid_token in the standard shape → ok, and no token is sent', () async {
      adapter.handler = (_) => jsonResponse(401, errorBody('invalid_token', 'Login required'));
      final probe = await api.probe('http://10.0.0.5:8069/nfc/api/v1');
      expect(probe.kind, ProbeKind.ok);
      expect(adapter.requests.single.uri.toString(), 'http://10.0.0.5:8069/nfc/api/v1/status');
      expect(adapter.requests.single.headers['Authorization'], isNull);
    });

    test('a 404 page → not an attendance server, with the status', () async {
      adapter.handler = (_) => textResponse(404, 'Not Found');
      final probe = await api.probe(base);
      expect(probe.kind, ProbeKind.notAttendanceServer);
      expect(probe.status, 404);
    });

    test('401 with another code or a 200 → not an attendance server', () async {
      adapter.handler = (_) => jsonResponse(401, errorBody('session_expired', 'x'));
      expect((await api.probe(base)).kind, ProbeKind.notAttendanceServer);
      adapter.handler = (_) => jsonResponse(200, {'state': 'checked_in'});
      expect((await api.probe(base)).kind, ProbeKind.notAttendanceServer);
    });

    test('redirect → reports where it points', () async {
      adapter.handler = (_) => textResponse(
        301,
        '',
        headers: {
          'location': ['https://erp.client.com/nfc/api/v1/status'],
        },
      );
      final probe = await api.probe(base);
      expect(probe.kind, ProbeKind.redirect);
      expect(probe.location, 'https://erp.client.com/nfc/api/v1/status');
    });

    test('connection error → unreachable', () async {
      adapter.handler = (request) => throw DioException.connectionError(requestOptions: request, reason: 'x');
      expect((await api.probe(base)).kind, ProbeKind.unreachable);
    });
  });
}

const _device = DeviceInfo(
  id: 'd',
  platform: 'android',
  model: 'm',
  appVersion: '1.0.0+1',
  hardwareId: 'h',
  osVersion: '16',
);
