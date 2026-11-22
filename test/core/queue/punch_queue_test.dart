import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/api/api_outcome.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/queue/punch_queue.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/queue/tap_store.dart';

import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const _ok = ApiOk(PunchResult(result: 'check_in', message: 'Checked in'));
const _down = ApiUnreachable<PunchResult>('timeout');
ApiRejected<PunchResult> _rejected(int status, String code) =>
    ApiRejected(status: status, code: code, message: 'msg $code');

/// Fake sender: answers from [answers] per client_uuid (default ok), records
/// the bodies it receives and the maximum number of overlapping calls.
class FakeSender {
  final sent = <Map<String, Object?>>[];
  final answers = <String, List<ApiOutcome<PunchResult>>>{};
  int _inFlight = 0;
  int maxInFlight = 0;

  Future<ApiOutcome<PunchResult>> call(Map<String, Object?> body) async {
    _inFlight++;
    maxInFlight = _inFlight > maxInFlight ? _inFlight : maxInFlight;
    sent.add(Map.of(body));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _inFlight--;
    final queue = answers[body['client_uuid']];
    return (queue == null || queue.isEmpty) ? _ok : queue.removeAt(0);
  }

  List<Object?> get uuids => sent.map((b) => b['client_uuid']).toList();
}

/// Delegates to a real store but holds `prune` until [pruneGate] completes.
class SlowPruneStore implements TapStore {
  SlowPruneStore(this.inner);

  final TapStore inner;
  Completer<void>? pruneGate;

  @override
  Future<void> prune({int keep = 50}) async {
    await pruneGate?.future;
    return inner.prune(keep: keep);
  }

  @override
  Stream<void> get changes => inner.changes;
  @override
  Future<void> insert(TapRecord tap) => inner.insert(tap);
  @override
  Future<TapRecord?> byUuid(String clientUuid) => inner.byUuid(clientUuid);
  @override
  Future<TapRecord?> oldestWaiting() => inner.oldestWaiting();
  @override
  Future<int> waitingCount() => inner.waitingCount();
  @override
  Future<List<TapRecord>> recent({int limit = 50}) => inner.recent(limit: limit);
  @override
  Future<void> markSent(
    String clientUuid, {
    required String result,
    required String message,
    String? site,
    DateTime? time,
  }) => inner.markSent(clientUuid, result: result, message: message, site: site, time: time);
  @override
  Future<TapRecord?> lastSent() => inner.lastSent();
  @override
  Future<void> markRejected(String clientUuid, {required String code, required String message}) =>
      inner.markRejected(clientUuid, code: code, message: message);
  @override
  Future<void> recordFailedAttempt(
    String clientUuid, {
    required String error,
    bool serverError = false,
    DateTime? at,
  }) => inner.recordFailedAttempt(clientUuid, error: error, serverError: serverError, at: at);
  @override
  Future<int> discardWaiting() => inner.discardWaiting();
  @override
  Future<int> rejectWaitingNotOwnedBy(int employeeId, {required String message}) =>
      inner.rejectWaitingNotOwnedBy(employeeId, message: message);
  @override
  Future<void> close() => inner.close();
}

void main() {
  late SqliteTapStore store;
  late FakeSender sender;
  late PunchQueue queue;
  late int unauthorizedCalls;

  setUp(() async {
    store = await openMemoryStore();
    sender = FakeSender();
    unauthorizedCalls = 0;
    queue = PunchQueue(store: store, send: sender.call, onUnauthorized: () => unauthorizedCalls++);
  });
  tearDown(() => store.close());

  test('sends strictly oldest first and marks each Sent', () async {
    for (final id in ['a', 'b', 'c']) {
      await store.insert(waitingTap(uuid: id));
    }
    await queue.flush();
    expect(sender.uuids, ['a', 'b', 'c']);
    for (final id in ['a', 'b', 'c']) {
      final row = (await store.byUuid(id))!;
      expect(row.status, TapStatus.sent);
      expect(row.resultMessage, 'Checked in');
    }
  });

  test('one at a time, even when flush is triggered concurrently; each tap sent once', () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await store.insert(waitingTap(uuid: id));
    }
    await Future.wait([queue.flush(), queue.flush(), queue.flush()]);
    expect(sender.maxInFlight, 1);
    expect(sender.uuids, ['a', 'b', 'c', 'd']);
  });

  test('a tap stored while a flush runs is sent by that flush call', () async {
    await store.insert(waitingTap(uuid: 'a'));
    final first = queue.flush();
    await store.insert(waitingTap(uuid: 'b'));
    await queue.flush();
    await first;
    expect(sender.uuids, ['a', 'b']);
    expect(await store.waitingCount(), 0);
  });

  test('a flush requested while the previous one is pruning still sends the new tap', () async {
    final slow = SlowPruneStore(store)..pruneGate = Completer<void>();
    queue = PunchQueue(store: slow, send: sender.call);
    final first = queue.flush(); // nothing waiting: reaches prune and blocks there
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.insert(waitingTap(uuid: 'late'));
    final second = queue.flush(); // joins the running flush
    final gate = slow.pruneGate!;
    slow.pruneGate = null;
    gate.complete();
    await Future.wait([first, second]);
    expect(sender.uuids, ['late']);
  });

  test('no answer: stops at the oldest, keeps order, nothing younger is sent', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    sender.answers['a'] = [_down];
    await queue.flush();
    expect(sender.uuids, ['a']);
    final a = (await store.byUuid('a'))!;
    expect(a.status, TapStatus.waiting);
    expect(a.attempts, 1);
    expect(a.lastError, 'timeout');
    expect((await store.byUuid('b'))!.status, TapStatus.waiting);
  });

  test('resend uses the same client_uuid with offline: true', () async {
    await store.insert(waitingTap(uuid: 'a'));
    sender.answers['a'] = [_down];
    await queue.flush();
    await queue.flush();
    expect(sender.uuids, ['a', 'a']);
    expect(sender.sent[0]['offline'], isFalse);
    expect(sender.sent[1]['offline'], isTrue);
    expect(sender.sent[1]['tapped_at'], sender.sent[0]['tapped_at']);
    expect((await store.byUuid('a'))!.status, TapStatus.sent);
  });

  test('cannot_record (server attendance rules) is final like every 4xx', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.recordFailedAttempt('a', error: 'timeout');
    sender.answers['a'] = [_rejected(422, 'cannot_record')];
    await queue.flush();
    await queue.flush();
    expect(sender.uuids, ['a']);
    expect((await store.byUuid('a'))!.status, TapStatus.rejected);
    expect((await store.byUuid('a'))!.resultCode, 'cannot_record');
    expect(queue.isPaused, isFalse);
  });

  test('403 device_not_allowed is final and does not pause the queue', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    sender.answers['a'] = [_rejected(403, 'device_not_allowed')];
    await queue.flush();
    expect(sender.uuids, ['a', 'b']);
    expect((await store.byUuid('a'))!.status, TapStatus.rejected);
    expect((await store.byUuid('a'))!.resultCode, 'device_not_allowed');
    expect(queue.isPaused, isFalse);
  });

  test('4xx is Rejected, never retried, and the next tap is still sent', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    sender.answers['a'] = [_rejected(422, 'too_soon')];
    await queue.flush();
    await queue.flush();
    expect(sender.uuids, ['a', 'b']);
    final a = (await store.byUuid('a'))!;
    expect(a.status, TapStatus.rejected);
    expect(a.resultCode, 'too_soon');
    expect(a.resultMessage, 'msg too_soon');
  });

  test('401 on a queued tap pauses the queue; the tap waits for the next login', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    sender.answers['a'] = [_down, _rejected(401, 'invalid_token')];
    await queue.flush(); // a → no answer, now offline
    await queue.flush(); // a → 401
    expect(queue.isPaused, isTrue);
    expect(unauthorizedCalls, 1);
    expect((await store.byUuid('a'))!.status, TapStatus.waiting);

    await queue.flush(); // paused: nothing sent
    expect(sender.uuids, ['a', 'a']);

    queue.resume();
    await queue.flush();
    expect(sender.uuids, ['a', 'a', 'a', 'b']);
    expect(await store.waitingCount(), 0);
  });

  test('401 on the fresh tap (sent at tap time) rejects it and pauses (§6.2)', () async {
    await store.insert(waitingTap(uuid: 'a'));
    sender.answers['a'] = [_rejected(401, 'invalid_token')];
    await queue.flush();
    expect((await store.byUuid('a'))!.status, TapStatus.rejected);
    expect(queue.isPaused, isTrue);
    expect(unauthorizedCalls, 1);
  });

  test('a queue created paused sends nothing until resumed', () async {
    queue = PunchQueue(store: store, send: sender.call, paused: true);
    await store.insert(waitingTap(uuid: 'a'));
    await queue.flush();
    expect(sender.sent, isEmpty);
    queue.resume();
    await queue.flush();
    expect(sender.uuids, ['a']);
  });

  test('prunes to the newest 50 finished rows after a flush', () async {
    for (var i = 0; i < 52; i++) {
      await store.insert(waitingTap(uuid: 'p$i'));
    }
    await queue.flush();
    expect(await store.recent(limit: 1000), hasLength(50));
  });

  group('with the real API client over stubbed HTTP', () {
    late StubAdapter adapter;

    setUp(() {
      adapter = StubAdapter((_) => jsonResponse(200, {'result': 'check_in', 'message': 'ok'}));
      final api = AttendanceApi(
        dio: createApiDio()..httpClientAdapter = adapter,
        baseUrl: () => 'http://localhost:8046/nfc/api/v1',
        token: () => 't',
        language: () => 'en',
        timeout: const Duration(milliseconds: 200),
      );
      queue = PunchQueue(store: store, send: api.punch, onUnauthorized: () => unauthorizedCalls++);
    });

    test('5xx keeps the tap Waiting; the resend is offline with the same client_uuid', () async {
      await store.insert(waitingTap(uuid: 'a'));
      adapter.handler = (_) => jsonResponse(503, errorBody('unavailable', 'down'));
      await queue.flush();
      expect((await store.byUuid('a'))!.status, TapStatus.waiting);
      adapter.handler = (_) => jsonResponse(200, {'result': 'check_in', 'message': 'ok'});
      await queue.flush();
      expect(adapter.bodyOf(1)['client_uuid'], 'a');
      expect(adapter.bodyOf(1)['offline'], isTrue);
      expect((await store.byUuid('a'))!.status, TapStatus.sent);
    });

    test('timeout keeps the tap Waiting', () async {
      await store.insert(waitingTap(uuid: 'a'));
      adapter.handler = (_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return jsonResponse(200, {});
      };
      await queue.flush();
      expect((await store.byUuid('a'))!.status, TapStatus.waiting);
    });

    test('401 invalid_token on a queued tap pauses and asks for login', () async {
      final tap = waitingTap(uuid: 'a');
      await store.insert(tap);
      await store.recordFailedAttempt('a', error: 'timeout');
      adapter.handler = (_) => jsonResponse(401, errorBody('invalid_token', 'Log in again'));
      await queue.flush();
      expect(queue.isPaused, isTrue);
      expect(unauthorizedCalls, 1);
      expect((await store.byUuid('a'))!.status, TapStatus.waiting);
    });
  });

  group('403 access_switched_off', () {
    test('the tap stays Waiting (never Rejected), the queue pauses and the session is told', () async {
      var switchedOff = 0;
      queue = PunchQueue(store: store, send: sender.call, onSwitchedOff: () => switchedOff++);
      await store.insert(waitingTap(uuid: 'a'));
      await store.insert(waitingTap(uuid: 'b'));
      sender.answers['a'] = [_rejected(403, 'access_switched_off')];
      await queue.flush();
      expect(sender.uuids, ['a'], reason: 'nothing younger is sent while switched off');
      final a = (await store.byUuid('a'))!;
      expect(a.status, TapStatus.waiting);
      expect(a.lastError, 'access_switched_off');
      expect(a.isFresh, isFalse, reason: 'resent later as a queued (offline) tap');
      expect(a.serverErrors, 0, reason: 'never counts towards undeliverable');
      expect((await store.byUuid('b'))!.status, TapStatus.waiting);
      expect(queue.isPaused, isTrue);
      expect(switchedOff, 1);
      expect(unauthorizedCalls, 0);

      await queue.flush();
      expect(sender.uuids, ['a'], reason: 'paused: a later flush sends nothing');

      queue.resume(); // seat on again (the session resumes the queue)
      await queue.flush();
      expect(sender.uuids, ['a', 'a', 'b']);
      expect(await store.waitingCount(), 0);
    });
  });

  group('a head tap the server keeps answering with an error (undeliverable)', () {
    const serverError = ApiUnreachable<PunchResult>('http_500', answered: true);
    late DateTime clock;

    setUp(() {
      clock = DateTime.utc(2026, 11, 17, 6);
      queue = PunchQueue(store: store, send: sender.call, now: () => clock);
    });

    /// [n] flushes, each answered [answer] for [uuid], [every] apart.
    Future<void> tries(String uuid, int n, Duration every, ApiOutcome<PunchResult> answer) async {
      for (var i = 0; i < n; i++) {
        sender.answers[uuid] = [answer];
        await queue.flush();
        clock = clock.add(every);
      }
    }

    test('20 server errors over 24 h → Rejected as undeliverable; the next tap goes out in order', () async {
      await store.insert(waitingTap(uuid: 'stuck'));
      await store.insert(waitingTap(uuid: 'next'));
      await tries('stuck', 19, const Duration(minutes: 80), serverError); // 19th error at +24 h
      var stuck = (await store.byUuid('stuck'))!;
      expect(stuck.status, TapStatus.waiting, reason: '19 errors are not enough');
      expect(stuck.serverErrors, 19);
      expect(stuck.firstServerErrorAt, DateTime.utc(2026, 11, 17, 6));
      expect(sender.uuids.where((u) => u == 'next'), isEmpty, reason: 'nothing overtakes the head tap');

      await tries('stuck', 1, Duration.zero, serverError); // 20th error, 25 h 20 min after the first
      stuck = (await store.byUuid('stuck'))!;
      expect(stuck.status, TapStatus.rejected);
      expect(stuck.resultCode, 'undeliverable');
      expect(sender.uuids.last, 'next', reason: 'the same flush goes on with the next tap');
      expect((await store.byUuid('next'))!.status, TapStatus.sent);
    });

    test('20 server errors within minutes: still Waiting (24 h not up)', () async {
      await store.insert(waitingTap(uuid: 'a'));
      await tries('a', 30, const Duration(minutes: 1), serverError);
      final a = (await store.byUuid('a'))!;
      expect(a.status, TapStatus.waiting);
      expect(a.serverErrors, 30);
    });

    test('more than 24 h of server errors but fewer than 20: still Waiting', () async {
      await store.insert(waitingTap(uuid: 'a'));
      await tries('a', 12, const Duration(hours: 4), serverError); // 44 h
      expect((await store.byUuid('a'))!.status, TapStatus.waiting);
    });

    test('being offline never counts: 60 timeouts and gateway errors over 3 days stay Waiting', () async {
      await store.insert(waitingTap(uuid: 'a'));
      await tries('a', 30, const Duration(hours: 1), const ApiUnreachable<PunchResult>('connectionError'));
      await tries('a', 30, const Duration(hours: 1), const ApiUnreachable<PunchResult>('http_502'));
      var a = (await store.byUuid('a'))!;
      expect(a.status, TapStatus.waiting);
      expect(a.attempts, 60, reason: 'History still shows every try');
      expect(a.serverErrors, 0);
      expect(a.firstServerErrorAt, isNull);

      // Back online with a broken server: the 24 h start at its first error.
      await tries('a', 19, const Duration(hours: 2), serverError);
      a = (await store.byUuid('a'))!;
      expect(a.status, TapStatus.waiting, reason: 'only 19 server errors');
    });

    test('the 24 h count from the first server error, not from the tap time', () async {
      await store.insert(waitingTap(uuid: 'old', createdAt: DateTime.utc(2026, 11, 10)));
      await tries('old', 20, const Duration(minutes: 1), serverError);
      expect((await store.byUuid('old'))!.status, TapStatus.waiting);
    });
  });
}
