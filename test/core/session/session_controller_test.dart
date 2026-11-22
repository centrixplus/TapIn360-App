import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/api/api_outcome.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/directory/company.dart';
import 'package:nfc_attendance/core/queue/punch_queue.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/core/session/session_controller.dart';
import 'package:nfc_attendance/core/storage/key_value_store.dart';
import 'package:nfc_attendance/core/storage/session_store.dart';

import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

const acme = Company(
  code: 'acme',
  name: 'Acme Trading Co.',
  apiBaseUrl: 'https://acme.karrix.com/nfc/api/v1',
  status: CompanyStatus.active,
);

Map<String, Object?> loginOk({int id = 17, String mode = 'auto', bool photo = false}) => {
  'token': 'new-token',
  'employee': {'id': id, 'name': 'Ahmed Ali'},
  'settings': {'punch_mode': mode, 'photo_required': photo},
  'server_time': '2026-11-17T06:00:00Z',
};

void main() {
  late SqliteTapStore taps;
  late SessionStore storage;
  late StubAdapter adapter;
  late PunchQueue queue;
  late SessionController controller;

  Future<void> build({Session? initial}) async {
    storage = SessionStore(MemoryKeyValueStore(), newDeviceId: () => 'dev-1');
    var session = await storage.load();
    if (initial != null) {
      await storage.saveServerUrl(initial.serverUrl!);
      if (initial.token != null) {
        await storage.saveLogin(
          token: initial.token!,
          employee: initial.employee!,
          punchMode: initial.punchMode,
        );
      }
      session = await storage.load();
    }
    late SessionController c;
    final api = AttendanceApi(
      dio: createApiDio()..httpClientAdapter = adapter,
      baseUrl: () => c.state.serverUrl,
      token: () => c.state.token,
      language: () => 'en',
      timeout: const Duration(milliseconds: 200),
    );
    queue = PunchQueue(
      store: taps,
      send: api.punch,
      onUnauthorized: () => c.expire(),
      paused: !session.isLoggedIn,
    );
    c = SessionController(
      initial: session,
      storage: storage,
      api: api,
      queue: queue,
      taps: taps,
      device: () async => const DeviceInfo(
        id: 'dev-1',
        platform: 'android',
        model: 'SM-S928B',
        appVersion: '1.0.0+1',
        hardwareId: 'hw-1',
        osVersion: '16',
      ),
    );
    controller = c;
  }

  setUp(() async {
    taps = await openMemoryStore();
    adapter = StubAdapter((_) => jsonResponse(200, loginOk()));
  });
  tearDown(() => taps.close());

  const loggedIn = Session(
    deviceId: 'dev-1',
    serverUrl: base,
    token: 'old-token',
    employee: Employee(id: 17, name: 'Ahmed Ali'),
  );

  test('first launch: no server → setup; saving the URL → login', () async {
    await build();
    expect(controller.state.hasServer, isFalse);
    await controller.saveServerUrl(base);
    expect(controller.state.serverUrl, base);
    expect((await storage.load()).serverUrl, base);
  });

  test('login success stores token, employee and punch mode, and resumes the queue', () async {
    await build(
      initial: const Session(deviceId: 'dev-1', serverUrl: base),
    );
    expect(queue.isPaused, isTrue);
    adapter.handler = (_) => jsonResponse(200, loginOk(mode: 'manual', photo: true));
    final outcome = await controller.login('041234567890', '1234');
    expect(outcome, isA<ApiOk<LoginResult>>());
    expect(controller.state.isLoggedIn, isTrue);
    expect(controller.state.punchMode, PunchMode.manual);
    expect(controller.state.photoRequired, isTrue);
    expect((await storage.load()).photoRequired, isTrue);
    expect((await storage.load()).token, 'new-token');
    expect(queue.isPaused, isFalse);
    expect(adapter.bodyOf(0)['device'], containsPair('id', 'dev-1'));
  });

  test('login sends waiting taps of the same employee, and closes taps of another one', () async {
    await build(
      initial: const Session(deviceId: 'dev-1', serverUrl: base),
    );
    await taps.insert(waitingTap(uuid: 'mine', employeeId: 17));
    await taps.insert(waitingTap(uuid: 'theirs', employeeId: 99));
    adapter.handler = (request) => request.uri.path.endsWith('/login')
        ? jsonResponse(200, loginOk(id: 17))
        : jsonResponse(200, {'result': 'check_in', 'message': 'ok'});
    await controller.login('x', 'y');
    await queue.flush();
    expect((await taps.byUuid('mine'))!.status, TapStatus.sent);
    expect((await taps.byUuid('theirs'))!.status, TapStatus.rejected);
  });

  test('login failure keeps the user logged out and returns the server rejection', () async {
    await build(
      initial: const Session(deviceId: 'dev-1', serverUrl: base),
    );
    adapter.handler = (_) => jsonResponse(401, errorBody('invalid_credentials', 'Wrong Badge ID or PIN'));
    final outcome = await controller.login('x', 'bad');
    expect((outcome as ApiRejected).code, 'invalid_credentials');
    expect(controller.state.isLoggedIn, isFalse);
    expect(queue.isPaused, isTrue);
  });

  test('a 401 from the queue logs out (token cleared, flagged expired) and pauses', () async {
    await build(initial: loggedIn);
    final tap = waitingTap(uuid: 'a');
    await taps.insert(tap);
    await taps.recordFailedAttempt('a', error: 'timeout');
    adapter.handler = (_) => jsonResponse(401, errorBody('invalid_token', 'Session revoked'));
    await queue.flush();
    expect(controller.state.isLoggedIn, isFalse);
    expect(controller.state.expired, isTrue);
    expect(controller.state.serverUrl, base);
    expect((await storage.load()).token, isNull);
    expect(queue.isPaused, isTrue);
    expect(await taps.waitingCount(), 1, reason: 'queued tap waits for the next login');
  });

  test('applyStatus updates the punch mode and name', () async {
    await build(initial: loggedIn);
    await controller.applyStatus(
      const StatusResult(
        employee: Employee(id: 17, name: 'Ahmed A. Ali'),
        state: AttendanceState.checkedOut,
        punchMode: PunchMode.manual,
        photoRequired: true,
      ),
    );
    expect(controller.state.photoRequired, isTrue);
    expect(controller.state.punchMode, PunchMode.manual);
    expect(controller.state.employee!.name, 'Ahmed A. Ali');
    expect((await storage.load()).punchMode, PunchMode.manual);
  });

  test('logout calls POST /logout, discards waiting taps and clears the token', () async {
    await build(initial: loggedIn);
    await taps.insert(waitingTap(uuid: 'a'));
    adapter.handler = (_) => jsonResponse(200, {'ok': true});
    await controller.logout();
    expect(adapter.requests.single.uri.path, endsWith('/logout'));
    expect(adapter.requests.single.headers['Authorization'], 'Bearer old-token');
    expect(await taps.waitingCount(), 0);
    expect(controller.state.isLoggedIn, isFalse);
    expect(controller.state.expired, isFalse);
    expect(queue.isPaused, isTrue);
  });

  test('logout still completes when the server cannot be reached', () async {
    await build(initial: loggedIn);
    adapter.handler = (_) => jsonResponse(503, {});
    await controller.logout();
    expect(controller.state.isLoggedIn, isFalse);
  });

  test('choosing a company stores its API base and the company; logged out', () async {
    await build();
    await controller.chooseCompany(acme);
    expect(controller.state.serverUrl, 'https://acme.karrix.com/nfc/api/v1');
    expect(controller.state.company!.name, 'Acme Trading Co.');
    expect(controller.state.isLoggedIn, isFalse);
    final stored = await storage.load();
    expect(stored.company!.code, 'acme');
    expect(stored.serverUrl, 'https://acme.karrix.com/nfc/api/v1');
  });

  test('a custom server URL clears the company', () async {
    await build();
    await controller.chooseCompany(acme);
    await controller.saveServerUrl(base);
    expect(controller.state.company, isNull);
    expect((await storage.load()).company, isNull);
  });

  test('change company: logs out, discards waiting taps, forgets server and company', () async {
    await build(initial: loggedIn);
    await controller.chooseCompany(acme);
    await storage.saveLogin(
      token: 't',
      employee: const Employee(id: 17, name: 'A'),
      punchMode: PunchMode.auto,
    );
    await taps.insert(waitingTap(uuid: 'w'));
    adapter.handler = (_) => jsonResponse(200, {'ok': true});
    await controller.changeCompany();
    expect(controller.state.isLoggedIn, isFalse);
    expect(controller.state.hasServer, isFalse);
    expect(controller.state.company, isNull);
    expect(await taps.waitingCount(), 0);
    final stored = await storage.load();
    expect(stored.serverUrl, isNull);
    expect(stored.company, isNull);
    expect(stored.token, isNull);
  });

  test('changing the server URL logs out and stores the new URL', () async {
    await build(initial: loggedIn);
    adapter.handler = (_) => jsonResponse(200, {'ok': true});
    await controller.changeServer('https://erp.client.com/nfc/api/v1');
    expect(adapter.requests.single.uri.toString(), '$base/logout');
    expect(controller.state.isLoggedIn, isFalse);
    expect(controller.state.serverUrl, 'https://erp.client.com/nfc/api/v1');
    expect((await storage.load()).serverUrl, 'https://erp.client.com/nfc/api/v1');
  });

  group('403 access_switched_off (TapIn360 switched the seat off)', () {
    const status = StatusResult(
      employee: Employee(id: 17, name: 'Ahmed Ali'),
      state: AttendanceState.checkedOut,
      punchMode: PunchMode.auto,
      photoRequired: false,
    );

    test('a tap answered 403: switched off, taps kept Waiting, queue paused, kept across restarts', () async {
      await build(initial: loggedIn);
      await taps.insert(waitingTap(uuid: 'a'));
      await taps.insert(waitingTap(uuid: 'b'));
      adapter.handler = (_) => jsonResponse(403, errorBody('access_switched_off', 'Switched off. Contact your HR.'));
      queue.onSwitchedOff = controller.switchOff;
      await queue.flush();
      await pumpEventQueue();
      expect(controller.state.accessSwitchedOff, isTrue);
      expect(controller.state.isLoggedIn, isTrue, reason: 'not a logout: the banner says why');
      expect(controller.state.canTap, isFalse);
      expect(queue.isPaused, isTrue);
      expect(await taps.waitingCount(), 2, reason: 'never rejected');
      expect(adapter.requests, hasLength(1));
      expect((await storage.load()).accessSwitchedOff, isTrue, reason: 'a restart keeps the block');
    });

    test('a successful /status lifts it, resumes the queue and sends the waiting taps', () async {
      await build(initial: loggedIn);
      await taps.insert(waitingTap(uuid: 'a'));
      await controller.switchOff();
      expect(queue.isPaused, isTrue);
      adapter.handler = (_) => jsonResponse(200, {'result': 'check_in', 'message': 'ok'});
      await controller.applyStatus(status);
      expect(controller.state.accessSwitchedOff, isFalse);
      expect(controller.state.canTap, isTrue);
      expect(queue.isPaused, isFalse);
      await queue.flush();
      expect((await taps.byUuid('a'))!.status, TapStatus.sent);
      expect((await storage.load()).accessSwitchedOff, isFalse);
    });

    test('back on, the revoked token gets 401: session ends, taps wait for the new login', () async {
      await build(initial: loggedIn);
      await taps.insert(waitingTap(uuid: 'a'));
      await controller.switchOff();
      await controller.expire();
      expect(controller.state.accessSwitchedOff, isFalse);
      expect(controller.state.isLoggedIn, isFalse);
      expect((await storage.load()).accessSwitchedOff, isFalse);
      expect(await taps.waitingCount(), 1);
      adapter.handler = (request) => request.uri.path.endsWith('/login')
          ? jsonResponse(200, loginOk(id: 17))
          : jsonResponse(200, {'result': 'check_in', 'message': 'ok'});
      await controller.login('2001', '1234');
      await queue.flush();
      expect((await taps.byUuid('a'))!.status, TapStatus.sent);
    });

    test('logout clears it', () async {
      await build(initial: loggedIn);
      await controller.switchOff();
      adapter.handler = (_) => jsonResponse(403, errorBody('access_switched_off', 'off'));
      await controller.logout();
      expect(controller.state.accessSwitchedOff, isFalse);
      expect((await storage.load()).accessSwitchedOff, isFalse);
    });

    test('switch-off while logged out does nothing but keep the queue paused', () async {
      await build(initial: const Session(deviceId: 'dev-1', serverUrl: base));
      await controller.switchOff();
      expect(controller.state.accessSwitchedOff, isFalse);
      expect(queue.isPaused, isTrue);
    });
  });

  test('logout: taps are refused from the start, while POST /logout is still running', () async {
    await build(initial: loggedIn);
    final answer = Completer<void>();
    adapter.handler = (_) async {
      await answer.future;
      return jsonResponse(200, {'ok': true});
    };
    final logout = controller.logout();
    await pumpEventQueue();
    expect(adapter.requests.single.uri.path, endsWith('/logout'));
    expect(controller.state.loggingOut, isTrue);
    expect(controller.state.canTap, isFalse);
    expect(controller.state.token, 'old-token', reason: 'the logout request still carries the token');
    answer.complete();
    await logout;
    expect(controller.state.loggingOut, isFalse);
    expect(controller.state.isLoggedIn, isFalse);
  });
}
