import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/photo/punch_photo.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/core/tap/tap_outcome.dart';
import 'package:nfc_attendance/core/tap/tap_service.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

/// Answers every tap with the server's `photo_required` rejection and records
/// whether the app asked for the camera.
class _RejectingTapService implements TapService {
  bool? lastPhotoRequired;

  @override
  void noteRead(String uid, {DateTime? at}) {}

  @override
  Future<TapOutcome> handle(
    String uid, {
    required PunchMode mode,
    PunchAction? selected,
    bool photoRequired = false,
    Future<PunchPhoto?> Function()? takePhoto,
    void Function()? onAccepted,
  }) async {
    lastPhotoRequired = photoRequired;
    return const TapRejected(code: 'photo_required', message: 'A photo is required.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HR switches photos on mid-session: after the refusal the app re-reads the setting', () async {
    final taps = await openMemoryStore();
    var photoOnServer = false;
    final adapter = StubAdapter((request) {
      final path = request.uri.path;
      if (path.endsWith('/login')) {
        return jsonResponse(200, {
          'token': 'tok',
          'employee': {'id': 17, 'name': 'Ahmed Ali'},
          'settings': {'punch_mode': 'auto', 'photo_required': photoOnServer},
          'server_time': '2026-11-18T06:00:00Z',
        });
      }
      if (path.endsWith('/status')) {
        return jsonResponse(200, {
          'employee': {'id': 17, 'name': 'Ahmed Ali'},
          'state': 'checked_out',
          'settings': {'punch_mode': 'auto', 'photo_required': photoOnServer},
        });
      }
      return jsonResponse(200, {'ok': true});
    });
    final fakeTaps = _RejectingTapService();
    final container = ProviderContainer(
      overrides: appOverrides(
        session: const Session(deviceId: 'dev-1', serverUrl: base),
        taps: taps,
        adapter: adapter,
        store: memorySessionStore(),
        extra: [tapServiceProvider.overrideWithValue(fakeTaps)],
      ),
    );
    addTearDown(() async {
      container.dispose();
      await taps.close();
    });
    final sub = container.listen(homeControllerProvider, (_, _) {});
    addTearDown(sub.close);

    await container.read(sessionProvider.notifier).login('1001', '1234');
    expect(container.read(homeControllerProvider).photoRequired, isFalse);

    // HR switches photos on; the employee's app still has "off" cached.
    photoOnServer = true;
    int statusCalls() => adapter.requests.where((r) => r.uri.path.endsWith('/status')).length;
    final before = statusCalls();
    final outcome = await container.read(homeControllerProvider.notifier).onCardRead('04AABBCCDD');
    expect(outcome, isA<TapRejected>());
    expect(fakeTaps.lastPhotoRequired, isFalse);
    await pumpEventQueue();

    expect(statusCalls(), greaterThan(before), reason: 'a refused tap re-reads the company settings');
    expect(container.read(sessionProvider).photoRequired, isTrue);
    expect(container.read(homeControllerProvider).photoRequired, isTrue, reason: 'the next tap opens the camera');

    // The next tap asks for the camera.
    container.read(homeControllerProvider.notifier).dismissResult();
    await container.read(homeControllerProvider.notifier).onCardRead('04AABBCCDD');
    expect(fakeTaps.lastPhotoRequired, isTrue);
  });
}
