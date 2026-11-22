import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/queue_fixtures.dart';

void main() {
  late SqliteTapStore store;

  setUp(() async => store = await openMemoryStore());
  tearDown(() => store.close());

  test('insert and read back a waiting tap', () async {
    final tap = waitingTap(uuid: 'a');
    await store.insert(tap);
    final row = (await store.byUuid('a'))!;
    expect(row.status, TapStatus.waiting);
    expect(row.attempts, 0);
    expect(row.request, tap.request);
    expect(row.employeeId, 17);
    expect(row.cardUid, '04DB8FE23B1590');
    expect(row.createdAt, tap.createdAt);
  });

  test('oldestWaiting follows insertion order and skips finished rows', () async {
    for (final id in ['a', 'b', 'c']) {
      await store.insert(waitingTap(uuid: id));
    }
    expect((await store.oldestWaiting())!.clientUuid, 'a');
    await store.markSent('a', result: 'check_in', message: 'ok');
    expect((await store.oldestWaiting())!.clientUuid, 'b');
    await store.markRejected('b', code: 'too_soon', message: 'no');
    expect((await store.oldestWaiting())!.clientUuid, 'c');
    expect(await store.waitingCount(), 1);
  });

  test('markSent keeps the site and server time; lastSent returns the newest sent tap', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    await store.insert(waitingTap(uuid: 'c'));
    await store.markSent(
      'a',
      result: 'check_in',
      message: '',
      site: 'Head Office',
      time: DateTime.utc(2026, 11, 17, 5),
    );
    await store.markSent(
      'b',
      result: 'check_out',
      message: '',
      site: 'Warehouse 2',
      time: DateTime.utc(2026, 11, 17, 13),
    );
    await store.markRejected('c', code: 'too_soon', message: 'no');
    final last = (await store.lastSent())!;
    expect(last.clientUuid, 'b');
    expect(last.resultSite, 'Warehouse 2');
    expect(last.resultTime, DateTime.utc(2026, 11, 17, 13));
    expect((await store.byUuid('a'))!.resultSite, 'Head Office');
  });

  test('a version 1 database is upgraded in place (site/time columns added)', () async {
    final dir = await Directory.systemTemp.createTemp('taps');
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE taps (id INTEGER PRIMARY KEY AUTOINCREMENT, client_uuid TEXT NOT NULL UNIQUE, '
          'request TEXT NOT NULL, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, '
          'created_at TEXT NOT NULL, result_code TEXT, result_message TEXT, employee_id INTEGER)',
        ),
      ),
    );
    await v1.insert('taps', {
      'client_uuid': 'old',
      'request': '{"client_uuid":"old","card_uid":"04","action":"auto","offline":false}',
      'status': 'sent',
      'created_at': DateTime.utc(2026, 11, 17).toIso8601String(),
    });
    await v1.close();
    final upgraded = await SqliteTapStore.open(factory: databaseFactoryFfi, path: path);
    expect((await upgraded.byUuid('old'))!.resultSite, isNull);
    await upgraded.insert(waitingTap(uuid: 'new'));
    await upgraded.markSent('new', result: 'check_in', message: '', site: 'HQ');
    expect((await upgraded.lastSent())!.resultSite, 'HQ');
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('server errors are counted apart from offline tries; the first one keeps its time', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.recordFailedAttempt('a', error: 'timeout', at: DateTime.utc(2026, 11, 17, 6));
    var a = (await store.byUuid('a'))!;
    expect((a.attempts, a.serverErrors, a.firstServerErrorAt), (1, 0, null));
    await store.recordFailedAttempt('a', error: 'http_500', serverError: true, at: DateTime.utc(2026, 11, 17, 7));
    await store.recordFailedAttempt('a', error: 'http_500', serverError: true, at: DateTime.utc(2026, 11, 17, 8));
    a = (await store.byUuid('a'))!;
    expect(a.attempts, 3);
    expect(a.serverErrors, 2);
    expect(a.firstServerErrorAt, DateTime.utc(2026, 11, 17, 7));
    expect(a.lastError, 'http_500');
  });

  test('a version 2 database gets the server-error columns (v3) and keeps its waiting taps', () async {
    final dir = await Directory.systemTemp.createTemp('taps');
    final path = '${dir.path}/v2.db';
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE taps (id INTEGER PRIMARY KEY AUTOINCREMENT, client_uuid TEXT NOT NULL UNIQUE, '
          'request TEXT NOT NULL, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, '
          'created_at TEXT NOT NULL, result_code TEXT, result_message TEXT, employee_id INTEGER, '
          'result_site TEXT, result_time TEXT)',
        ),
      ),
    );
    await v2.insert('taps', {
      'client_uuid': 'waiting',
      'request': '{"client_uuid":"waiting","card_uid":"04","action":"auto","offline":true}',
      'status': 'waiting',
      'attempts': 7,
      'created_at': DateTime.utc(2026, 11, 17).toIso8601String(),
    });
    await v2.close();
    final upgraded = await SqliteTapStore.open(factory: databaseFactoryFfi, path: path);
    var tap = (await upgraded.byUuid('waiting'))!;
    expect((tap.status, tap.attempts, tap.serverErrors, tap.firstServerErrorAt), (TapStatus.waiting, 7, 0, null));
    await upgraded.recordFailedAttempt('waiting', error: 'http_500', serverError: true, at: DateTime.utc(2026, 11, 18));
    tap = (await upgraded.byUuid('waiting'))!;
    expect((tap.attempts, tap.serverErrors), (8, 1));
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('markSent / markRejected store result and count the attempt', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    await store.markSent('a', result: 'check_out', message: 'Checked out at 17:00');
    await store.markRejected('b', code: 'out_of_range', message: 'Too far (140 m)');
    final a = (await store.byUuid('a'))!;
    final b = (await store.byUuid('b'))!;
    expect(a.status, TapStatus.sent);
    expect(a.resultCode, 'check_out');
    expect(a.resultMessage, 'Checked out at 17:00');
    expect(a.attempts, 1);
    expect(b.status, TapStatus.rejected);
    expect(b.resultCode, 'out_of_range');
    expect(b.resultMessage, 'Too far (140 m)');
  });

  test('a failed attempt flags the stored request offline and keeps the client_uuid', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.recordFailedAttempt('a', error: 'timeout');
    final row = (await store.byUuid('a'))!;
    expect(row.status, TapStatus.waiting);
    expect(row.attempts, 1);
    expect(row.lastError, 'timeout');
    expect(row.request['offline'], isTrue);
    expect(row.request['client_uuid'], 'a');
  });

  test('finished rows drop the photo bytes; waiting rows keep them for resends', () async {
    final tap = waitingTap(uuid: 'p');
    tap.request['photo'] = {
      'mime': 'image/jpeg',
      'data': 'QUJD',
      'taken_at': '2026-11-17T09:02:15+03:00',
      'faces': 1,
    };
    await store.insert(tap);
    await store.recordFailedAttempt('p', error: 'timeout');
    expect(((await store.byUuid('p'))!.request['photo']! as Map)['data'], 'QUJD');
    await store.markSent('p', result: 'check_in', message: 'ok');
    final photo = (await store.byUuid('p'))!.request['photo']! as Map;
    expect(photo.containsKey('data'), isFalse);
    expect(photo['faces'], 1);
    expect(photo['taken_at'], '2026-11-17T09:02:15+03:00');
  });

  test('recent returns newest first, limited', () async {
    for (var i = 0; i < 5; i++) {
      await store.insert(waitingTap(uuid: 'r$i'));
    }
    final rows = await store.recent(limit: 3);
    expect(rows.map((r) => r.clientUuid), ['r4', 'r3', 'r2']);
  });

  test('prune keeps the newest 50 finished rows and every waiting row', () async {
    for (var i = 0; i < 55; i++) {
      await store.insert(waitingTap(uuid: 's$i'));
      await store.markSent('s$i', result: 'check_in', message: '');
    }
    for (var i = 0; i < 3; i++) {
      await store.insert(waitingTap(uuid: 'w$i'));
    }
    await store.prune(keep: 50);
    final rows = await store.recent(limit: 1000);
    final finished = rows.where((r) => r.status != TapStatus.waiting).map((r) => r.clientUuid);
    expect(finished, hasLength(50));
    expect(finished, isNot(contains('s0')));
    expect(finished, isNot(contains('s4')));
    expect(finished, contains('s5'));
    expect(await store.waitingCount(), 3);
  });

  test('discardWaiting deletes only waiting rows and returns how many', () async {
    await store.insert(waitingTap(uuid: 'a'));
    await store.insert(waitingTap(uuid: 'b'));
    await store.markSent('a', result: 'check_in', message: '');
    expect(await store.discardWaiting(), 1);
    expect(await store.byUuid('b'), isNull);
    expect(await store.byUuid('a'), isNotNull);
  });

  test("rejectWaitingNotOwnedBy closes another employee's waiting taps", () async {
    await store.insert(waitingTap(uuid: 'mine', employeeId: 17));
    await store.insert(waitingTap(uuid: 'theirs', employeeId: 99));
    expect(await store.rejectWaitingNotOwnedBy(17, message: 'Another employee logged in'), 1);
    expect((await store.byUuid('mine'))!.status, TapStatus.waiting);
    final theirs = (await store.byUuid('theirs'))!;
    expect(theirs.status, TapStatus.rejected);
    expect(theirs.resultCode, 'discarded');
  });

  test('changes emits after every mutation', () async {
    var events = 0;
    final sub = store.changes.listen((_) => events++);
    await store.insert(waitingTap(uuid: 'a'));
    await store.markSent('a', result: 'check_in', message: '');
    await Future<void>.delayed(Duration.zero);
    expect(events, 2);
    await sub.cancel();
  });
}
