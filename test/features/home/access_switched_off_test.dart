import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/photo/punch_photo.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/core/tap/tap_outcome.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SqliteTapStore taps;
  late StubAdapter adapter;
  late ProviderContainer container;
  late bool seatOff;
  late Completer<void>? logoutAnswer;

  Map<String, Object?> statusOk() => {
    'employee': {'id': 17, 'name': 'Ahmed Ali'},
    'state': 'checked_out',
    'settings': {'punch_mode': 'auto', 'photo_required': true},
  };

  setUp(() async {
    taps = await openMemoryStore();
    seatOff = true;
    logoutAnswer = null;
    adapter = StubAdapter((request) async {
      final path = request.uri.path;
      if (path.endsWith('/logout')) {
        await logoutAnswer?.future;
        return jsonResponse(200, {'ok': true});
      }
      if (seatOff) {
        return jsonResponse(
          403,
          errorBody('access_switched_off', 'Your TapIn360 access is switched off. Contact your HR.'),
        );
      }
      if (path.endsWith('/status')) return jsonResponse(200, statusOk());
      return jsonResponse(200, {'result': 'check_in', 'message': 'Checked in'});
    });
    container = ProviderContainer(
      overrides: appOverrides(
        session: const Session(
          deviceId: 'dev-1',
          serverUrl: base,
          token: 'tok',
          employee: Employee(id: 17, name: 'Ahmed Ali'),
          photoRequired: true,
        ),
        taps: taps,
        adapter: adapter,
        store: memorySessionStore(),
      ),
    );
    final sub = container.listen(homeControllerProvider, (_, _) {});
    addTearDown(() async {
      sub.close();
      container.dispose();
      await taps.close();
    });
  });

  test('/status 403: blocked, no camera, nothing stored; a later /status 200 lifts it and sends', () async {
    await taps.insert(waitingTap(uuid: 'earlier'));
    final home = container.read(homeControllerProvider.notifier);
    await home.refreshStatus();
    await pumpEventQueue();

    var state = container.read(homeControllerProvider);
    expect(state.accessSwitchedOff, isTrue);
    expect(state.blocked, isTrue);
    expect(container.read(sessionProvider).accessSwitchedOff, isTrue);
    expect(container.read(punchQueueProvider).isPaused, isTrue);

    var cameraOpened = 0;
    Future<PunchPhoto?> takePhoto() async {
      cameraOpened++;
      return null;
    }

    final outcome = await home.onCardRead('04DB8FE23B1590', takePhoto: takePhoto);
    expect(outcome, isA<TapIgnored>());
    expect(cameraOpened, 0, reason: 'the camera never opens while switched off');
    expect(await taps.waitingCount(), 1, reason: 'no new tap stored; the earlier one still waits');
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/punch')), isEmpty);

    seatOff = false; // HR / TapIn360 switches the seat back on
    await home.refreshStatus();
    await pumpEventQueue();
    for (var i = 0; i < 20 && await taps.waitingCount() > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    state = container.read(homeControllerProvider);
    expect(state.accessSwitchedOff, isFalse);
    expect(state.blocked, isFalse);
    expect(container.read(punchQueueProvider).isPaused, isFalse);
    expect((await taps.byUuid('earlier'))!.status, TapStatus.sent);
  });

  test('logging out: taps are refused while POST /logout is still running', () async {
    seatOff = false;
    logoutAnswer = Completer<void>();
    final home = container.read(homeControllerProvider.notifier);
    final logout = container.read(sessionProvider.notifier).logout();
    await pumpEventQueue();
    expect(container.read(sessionProvider).loggingOut, isTrue);
    expect(container.read(homeControllerProvider).blocked, isTrue);
    var cameraOpened = 0;
    final outcome = await home.onCardRead(
      '04DB8FE23B1590',
      takePhoto: () async {
        cameraOpened++;
        return null;
      },
    );
    expect(outcome, isA<TapIgnored>());
    expect(cameraOpened, 0);
    expect(await taps.recent(), isEmpty);
    logoutAnswer!.complete();
    await logout;
    expect(container.read(sessionProvider).isLoggedIn, isFalse);
  });
}
