import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/session/session.dart';

import '../helpers/app_scope.dart';
import '../helpers/queue_fixtures.dart';
import '../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SqliteTapStore taps;
  late StubAdapter adapter;
  late ProviderContainer container;

  setUp(() async {
    taps = await openMemoryStore();
    adapter = StubAdapter(
      (request) => request.uri.path.endsWith('/login')
          ? jsonResponse(200, {
              'token': 'tok-new',
              'employee': {'id': 17, 'name': 'Ahmed Ali'},
              'settings': {'punch_mode': 'manual'},
              'server_time': '2026-11-17T06:00:00Z',
            })
          : jsonResponse(200, {'result': 'check_in', 'message': 'ok'}),
    );
    container = ProviderContainer(
      overrides: appOverrides(
        session: const Session(deviceId: 'dev-1', serverUrl: base),
        taps: taps,
        adapter: adapter,
        store: memorySessionStore(),
      ),
    );
  });
  tearDown(() async {
    container.dispose();
    await taps.close();
  });

  test('the real provider graph has no dependency cycle on login, punch and 401', () async {
    expect(container.read(punchQueueProvider).isPaused, isTrue);
    await container.read(sessionProvider.notifier).login('041234567890', '1234');
    expect(container.read(apiCredentialsProvider).token, 'tok-new');
    expect(container.read(punchQueueProvider).isPaused, isFalse);

    await taps.insert(waitingTap(uuid: 'a'));
    await container.read(punchQueueProvider).flush();
    expect(adapter.requests.last.headers['Authorization'], 'Bearer tok-new');
    expect((await taps.byUuid('a'))!.status, TapStatus.sent);

    await taps.insert(waitingTap(uuid: 'b'));
    await taps.recordFailedAttempt('b', error: 'timeout');
    adapter.handler = (_) => jsonResponse(401, errorBody('invalid_token', 'Revoked'));
    await container.read(punchQueueProvider).flush();

    final session = container.read(sessionProvider);
    expect(session.isLoggedIn, isFalse);
    expect(session.expired, isTrue);
    expect(container.read(apiCredentialsProvider).token, isNull);
    expect(container.read(punchQueueProvider).isPaused, isTrue);
    expect((await taps.byUuid('b'))!.status, TapStatus.waiting);
  });

  test('Home controller follows the session (mode from login, logged out after logout)', () async {
    final sub = container.listen(homeControllerProvider, (_, _) {});
    await container.read(sessionProvider.notifier).login('x', 'y');
    var home = container.read(homeControllerProvider);
    expect(home.loggedIn, isTrue);
    expect(home.employeeName, 'Ahmed Ali');
    expect(home.punchMode.name, 'manual');

    adapter.handler = (_) => jsonResponse(200, {'ok': true});
    await container.read(sessionProvider.notifier).logout();
    home = container.read(homeControllerProvider);
    expect(home.loggedIn, isFalse);
    expect(home.blocked, isTrue);
    sub.close();
  });
}
