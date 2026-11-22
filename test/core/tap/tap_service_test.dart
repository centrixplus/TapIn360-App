import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/api/api_outcome.dart';
import 'package:nfc_attendance/core/location/gps_fix.dart';
import 'package:nfc_attendance/core/photo/punch_photo.dart';
import 'package:nfc_attendance/core/queue/punch_queue.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/tap/tap_outcome.dart';
import 'package:nfc_attendance/core/tap/tap_service.dart';

import '../../helpers/queue_fixtures.dart';

void main() {
  late SqliteTapStore store;
  late PunchQueue queue;
  late List<Map<String, Object?>> sent;
  late ApiOutcome<PunchResult> Function(Map<String, Object?>) answer;
  late GpsFix? fix;
  late DateTime now;
  late int fixRequests;
  late String? localIp;
  late TapService service;
  var uuidSeq = 0;

  setUp(() async {
    store = await openMemoryStore();
    sent = [];
    answer = (_) => ApiOk(
      PunchResult(
        result: 'check_in',
        message: 'Checked in at 09:02 — Head Office',
        site: 'Head Office',
        time: DateTime.utc(2026, 11, 17, 6, 2, 11),
      ),
    );
    now = DateTime.utc(2026, 11, 17, 6, 2, 11);
    fix = GpsFix(lat: 29.3759, lng: 47.9774, accuracyM: 19, isMocked: false, capturedAt: now);
    fixRequests = 0;
    localIp = '192.168.1.25';
    queue = PunchQueue(
      store: store,
      send: (body) async {
        sent.add(body);
        return answer(body);
      },
    );
    service = TapService(
      store: store,
      queue: queue,
      fixForTap: () async {
        fixRequests++;
        return fix;
      },
      newUuid: () => 'uuid-${++uuidSeq}',
      employeeId: () => 17,
      hardwareId: 'a1b2c3d4e5f60718',
      localIp: () async => localIp,
      now: () => now,
    );
  });
  tearDown(() => store.close());

  test('auto mode: stores, sends §5.2 punch with action auto and returns Sent', () async {
    final outcome = await service.handle('04DB8FE23B1590', mode: PunchMode.auto);
    expect(outcome, isA<TapSent>());
    expect((outcome as TapSent).message, 'Checked in at 09:02 — Head Office');
    expect(outcome.site, 'Head Office');
    expect(outcome.time, DateTime.utc(2026, 11, 17, 6, 2, 11));
    expect(outcome.tappedAt, now);
    expect(outcome.photoTaken, isFalse);
    final body = sent.single;
    expect(body['client_uuid'], 'uuid-$uuidSeq');
    expect(body['card_uid'], '04DB8FE23B1590');
    expect(body['action'], 'auto');
    expect(body['offline'], isFalse);
    expect(DateTime.parse(body['tapped_at']! as String), now);
    expect(body['tapped_at'], matches(RegExp(r'[+-]\d\d:\d\d$')));
    expect((body['location']! as Map)['accuracy_m'], 19);
    expect(body['device'], {'hardware_id': 'a1b2c3d4e5f60718', 'local_ip': '192.168.1.25'});
    final row = (await store.byUuid('uuid-$uuidSeq'))!;
    expect(row.status, TapStatus.sent);
    expect(row.employeeId, 17);
  });

  test('no local IP → local_ip null (hardware_id still sent)', () async {
    localIp = null;
    await service.handle('A', mode: PunchMode.auto);
    expect(sent.single['device'], {'hardware_id': 'a1b2c3d4e5f60718', 'local_ip': null});
  });

  test('a resend keeps the tap-time local_ip, not the current one', () async {
    answer = (_) => const ApiUnreachable('timeout');
    await service.handle('A', mode: PunchMode.auto);
    localIp = '10.120.4.7'; // phone moved to mobile data
    answer = (_) => const ApiOk(PunchResult(result: 'check_in', message: 'ok'));
    await queue.flush();
    expect(sent, hasLength(2));
    expect((sent.last['device']! as Map)['local_ip'], '192.168.1.25');
    expect(sent.last['offline'], isTrue);
  });

  test('auto mode ignores a pressed button', () async {
    await service.handle('A', mode: PunchMode.auto, selected: PunchAction.checkOut);
    expect(sent.single['action'], 'auto');
  });

  test('manual mode sends the pressed action', () async {
    await service.handle('A', mode: PunchMode.manual, selected: PunchAction.checkIn);
    await service.handle('B', mode: PunchMode.manual, selected: PunchAction.checkOut);
    expect(sent.map((b) => b['action']), ['check_in', 'check_out']);
  });

  test('manual mode with nothing pressed: no punch, and the read does not count for debounce', () async {
    expect(await service.handle('A', mode: PunchMode.manual), isA<TapNeedsAction>());
    expect(await store.recent(), isEmpty);
    expect(fixRequests, 0);
    final next = await service.handle('A', mode: PunchMode.manual, selected: PunchAction.checkIn);
    expect(next, isA<TapSent>());
  });

  test('no GPS fix: shows no-signal and nothing is recorded or sent', () async {
    fix = null;
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapNoGps>());
    expect(await store.recent(), isEmpty);
    expect(sent, isEmpty);
  });

  test('the same UID within 10 s is ignored before any GPS or storage work', () async {
    await service.handle('A', mode: PunchMode.auto);
    now = now.add(const Duration(seconds: 3));
    expect(await service.handle('A', mode: PunchMode.auto), isA<TapIgnored>());
    expect(sent, hasLength(1));
    expect(fixRequests, 1);
  });

  test('reads noted while busy keep the debounce window going', () async {
    await service.handle('A', mode: PunchMode.auto);
    for (var s = 1; s <= 15; s++) {
      service.noteRead('A', at: now.add(Duration(seconds: s)));
    }
    now = now.add(const Duration(seconds: 16));
    expect(await service.handle('A', mode: PunchMode.auto), isA<TapIgnored>());
  });

  test('no answer → Saved (Waiting) for automatic resend', () async {
    answer = (_) => const ApiUnreachable('timeout');
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapSaved>());
    expect((outcome as TapSaved).tappedAt, now);
    expect(await store.waitingCount(), 1);
  });

  test('4xx → Rejected with the server message and code', () async {
    answer = (_) =>
        const ApiRejected(status: 422, code: 'out_of_range', message: 'You are 140 m from Head Office');
    final outcome = await service.handle('A', mode: PunchMode.auto) as TapRejected;
    expect(outcome.code, 'out_of_range');
    expect(outcome.message, 'You are 140 m from Head Office');
    expect((await store.recent()).single.status, TapStatus.rejected);
  });

  test('401 → Rejected and the queue pauses (the app routes to Login)', () async {
    answer = (_) => const ApiRejected(status: 401, code: 'invalid_token', message: 'Please log in again');
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapRejected>());
    expect((outcome as TapRejected).isUnauthorized, isTrue);
    expect(queue.isPaused, isTrue);
  });

  test('older taps waiting: the new tap is queued behind them (offline: true) and shows Saved', () async {
    final older = waitingTap(uuid: 'older');
    await store.insert(older);
    await store.recordFailedAttempt('older', error: 'timeout');
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapSaved>());
    final mine = (await store.byUuid('uuid-$uuidSeq'))!;
    expect(mine.request['offline'], isTrue);

    await queue.flush(); // joins the flush the tap started
    expect(sent.map((b) => b['client_uuid']), ['older', 'uuid-$uuidSeq']);
    expect(sent.last['offline'], isTrue);
    expect(await store.waitingCount(), 0);
  });

  test('a new tap never overtakes waiting ones, even when they keep failing', () async {
    await store.insert(waitingTap(uuid: 'older'));
    answer = (body) => body['client_uuid'] == 'older'
        ? const ApiUnreachable('timeout')
        : const ApiOk(PunchResult(result: 'check_in', message: 'ok'));
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapSaved>());
    await queue.flush();
    await queue.flush();
    expect(sent, isNotEmpty);
    expect(sent.map((b) => b['client_uuid']), everyElement('older'));
    expect((await store.byUuid('uuid-$uuidSeq'))!.status, TapStatus.waiting);
  });

  test('nothing waiting: the new tap is sent at once with offline: false', () async {
    await store.insert(waitingTap(uuid: 'done'));
    await store.markSent('done', result: 'check_in', message: '');
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapSent>());
    expect(sent.single['offline'], isFalse);
  });

  group('photo required (§15)', () {
    final photo = PunchPhoto(
      jpeg: Uint8List.fromList([0xFF, 0xD8, 1, 2, 0xFF, 0xD9]),
      takenAt: DateTime.utc(2026, 11, 17, 6, 2, 15),
      faces: 1,
    );

    test('not required: no camera, no photo in the punch', () async {
      var asked = 0;
      await service.handle(
        'A',
        mode: PunchMode.auto,
        takePhoto: () async {
          asked++;
          return photo;
        },
      );
      expect(asked, 0);
      expect(sent.single.containsKey('photo'), isFalse);
    });

    test(
      'required: the photo is sent inside the punch; GPS was requested before the camera closed',
      () async {
        var fixRequestsWhenCameraOpened = -1;
        final outcome = await service.handle(
          'A',
          mode: PunchMode.auto,
          photoRequired: true,
          takePhoto: () async {
            fixRequestsWhenCameraOpened = fixRequests;
            return photo;
          },
        );
        expect(outcome, isA<TapSent>());
        expect((outcome as TapSent).photoTaken, isTrue);
        expect(fixRequestsWhenCameraOpened, 1, reason: 'GPS runs in parallel with the camera');
        expect(sent.single['photo'], photo.toJson());
      },
    );

    test('tapped_at stays the card-read moment even if the camera takes 8 s', () async {
      final readAt = now;
      await service.handle(
        'A',
        mode: PunchMode.auto,
        photoRequired: true,
        takePhoto: () async {
          now = now.add(const Duration(seconds: 8));
          return photo;
        },
      );
      expect(DateTime.parse(sent.single['tapped_at']! as String), readAt);
    });

    test(
      'Cancel discards the tap: nothing stored or sent, and the card can be tapped again at once',
      () async {
        final outcome = await service.handle(
          'A',
          mode: PunchMode.auto,
          photoRequired: true,
          takePhoto: () async => null,
        );
        expect(outcome, isA<TapCancelled>());
        expect(await store.recent(), isEmpty);
        expect(sent, isEmpty);
        now = now.add(const Duration(seconds: 2));
        final again = await service.handle(
          'A',
          mode: PunchMode.auto,
          photoRequired: true,
          takePhoto: () async => photo,
        );
        expect(again, isA<TapSent>());
      },
    );

    test('photo taken but no GPS fix: nothing recorded', () async {
      fix = null;
      final outcome = await service.handle(
        'A',
        mode: PunchMode.auto,
        photoRequired: true,
        takePhoto: () async => photo,
      );
      expect(outcome, isA<TapNoGps>());
      expect(await store.recent(), isEmpty);
    });

    test('a fix that arrives while the camera is open is still used', () async {
      final late = fix;
      fix = null;
      var calls = 0;
      service = TapService(
        store: store,
        queue: queue,
        fixForTap: () async {
          calls++;
          return calls == 1 ? null : late;
        },
        newUuid: () => 'uuid-${++uuidSeq}',
        employeeId: () => 17,
        hardwareId: 'a1b2c3d4e5f60718',
        localIp: () async => localIp,
        now: () => now,
      );
      final outcome = await service.handle(
        'A',
        mode: PunchMode.auto,
        photoRequired: true,
        takePhoto: () async => photo,
      );
      expect(outcome, isA<TapSent>());
      expect(calls, 2);
    });

    test('an offline resend keeps the photo (same client_uuid)', () async {
      answer = (_) => const ApiUnreachable('timeout');
      await service.handle('A', mode: PunchMode.auto, photoRequired: true, takePhoto: () async => photo);
      answer = (_) => const ApiOk(PunchResult(result: 'check_in', message: 'ok'));
      await queue.flush();
      expect(sent, hasLength(2));
      expect(sent.last['client_uuid'], sent.first['client_uuid']);
      expect(sent.last['photo'], photo.toJson());
      expect(sent.last['offline'], isTrue);
    });
  });

  test('403 access_switched_off: Saved with the reason, still Waiting (sent when the seat is back on)', () async {
    var switchedOff = 0;
    queue.onSwitchedOff = () => switchedOff++;
    answer = (_) => const ApiRejected(status: 403, code: 'access_switched_off', message: 'Switched off.');
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapSaved>());
    expect((outcome as TapSaved).heldBy, 'access_switched_off');
    expect(switchedOff, 1);
    final row = (await store.recent()).single;
    expect(row.status, TapStatus.waiting);
  });

  test('logging out (or switched off) when the tap finishes its GPS wait: nothing stored or sent', () async {
    var accepting = true;
    service = TapService(
      store: store,
      queue: queue,
      fixForTap: () async {
        accepting = false; // logout confirmed while the GPS fix was awaited
        return fix;
      },
      newUuid: () => 'uuid-${++uuidSeq}',
      employeeId: () => 17,
      hardwareId: 'a1b2c3d4e5f60718',
      localIp: () async => localIp,
      acceptsTaps: () => accepting,
      now: () => now,
    );
    final outcome = await service.handle('A', mode: PunchMode.auto);
    expect(outcome, isA<TapNeedsLogin>());
    expect(await store.recent(), isEmpty);
    expect(sent, isEmpty);
  });
}
