import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../api/error_codes.dart';
import 'tap_record.dart';
import 'tap_store.dart';

/// sqflite implementation of [TapStore].
class SqliteTapStore implements TapStore {
  SqliteTapStore._(this._db);

  static const _table = 'taps';

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  static Future<SqliteTapStore> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? '${await dbFactory.getDatabasesPath()}/nfc_attendance.db';
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 3, onCreate: _create, onUpgrade: _upgrade),
    );
    return SqliteTapStore._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        request TEXT NOT NULL,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        result_code TEXT,
        result_message TEXT,
        employee_id INTEGER,
        result_site TEXT,
        result_time TEXT,
        server_errors INTEGER NOT NULL DEFAULT 0,
        first_server_error_at TEXT
      )''');
    await db.execute('CREATE INDEX taps_status_id ON $_table (status, id)');
  }

  /// v2 (TapIn360 design): site and server time of sent taps.
  /// v3: server-error count and first server-error time (undeliverable cap).
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE $_table ADD COLUMN result_site TEXT');
      await db.execute('ALTER TABLE $_table ADD COLUMN result_time TEXT');
    }
    if (from < 3) {
      await db.execute('ALTER TABLE $_table ADD COLUMN server_errors INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE $_table ADD COLUMN first_server_error_at TEXT');
    }
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> insert(TapRecord tap) async {
    await _db.insert(_table, {
      'client_uuid': tap.clientUuid,
      'request': jsonEncode(tap.request),
      'status': tap.status.name,
      'attempts': tap.attempts,
      'last_error': tap.lastError,
      'created_at': tap.createdAt.toUtc().toIso8601String(),
      'result_code': tap.resultCode,
      'result_message': tap.resultMessage,
      'employee_id': tap.employeeId,
    });
    _changed();
  }

  @override
  Future<TapRecord?> byUuid(String clientUuid) async {
    final rows = await _db.query(_table, where: 'client_uuid = ?', whereArgs: [clientUuid]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<TapRecord?> oldestWaiting() async {
    final rows = await _db.query(
      _table,
      where: 'status = ?',
      whereArgs: [TapStatus.waiting.name],
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<int> waitingCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM $_table WHERE status = ?', [
      TapStatus.waiting.name,
    ]);
    return (rows.first['n'] as int?) ?? 0;
  }

  @override
  Future<List<TapRecord>> recent({int limit = 50}) async {
    final rows = await _db.query(_table, orderBy: 'id DESC', limit: limit);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> markSent(
    String clientUuid, {
    required String result,
    required String message,
    String? site,
    DateTime? time,
  }) => _finish(clientUuid, TapStatus.sent, result, message, site: site, time: time);

  @override
  Future<TapRecord?> lastSent() async {
    final rows = await _db.query(
      _table,
      where: 'status = ?',
      whereArgs: [TapStatus.sent.name],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> markRejected(String clientUuid, {required String code, required String message}) =>
      _finish(clientUuid, TapStatus.rejected, code, message);

  /// Finished rows keep only the photo metadata: the bytes were for resends,
  /// and History does not show them (keeps the table small).
  Future<void> _finish(
    String clientUuid,
    TapStatus status,
    String code,
    String message, {
    String? site,
    DateTime? time,
  }) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['request'],
        where: 'client_uuid = ?',
        whereArgs: [clientUuid],
      );
      if (rows.isEmpty) return;
      final request = jsonDecode(rows.first['request'] as String) as Map<String, Object?>;
      final photo = request['photo'];
      if (photo is Map<String, Object?>) photo.remove('data');
      await txn.rawUpdate(
        'UPDATE $_table SET status = ?, result_code = ?, result_message = ?, request = ?, '
        'result_site = ?, result_time = ?, attempts = attempts + 1 WHERE client_uuid = ?',
        [status.name, code, message, jsonEncode(request), site, time?.toUtc().toIso8601String(), clientUuid],
      );
    });
    _changed();
  }

  @override
  Future<void> recordFailedAttempt(
    String clientUuid, {
    required String error,
    bool serverError = false,
    DateTime? at,
  }) async {
    await _db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['request'],
        where: 'client_uuid = ?',
        whereArgs: [clientUuid],
      );
      if (rows.isEmpty) return;
      final request = jsonDecode(rows.first['request'] as String) as Map<String, Object?>;
      request['offline'] = true;
      await txn.rawUpdate(
        'UPDATE $_table SET request = ?, last_error = ?, attempts = attempts + 1, '
        'server_errors = server_errors + ?, '
        'first_server_error_at = CASE WHEN ? THEN COALESCE(first_server_error_at, ?) '
        'ELSE first_server_error_at END '
        'WHERE client_uuid = ?',
        [
          jsonEncode(request),
          error,
          serverError ? 1 : 0,
          serverError ? 1 : 0,
          (at ?? DateTime.now()).toUtc().toIso8601String(),
          clientUuid,
        ],
      );
    });
    _changed();
  }

  @override
  Future<void> prune({int keep = 50}) async {
    final deleted = await _db.rawDelete(
      'DELETE FROM $_table WHERE status != ? AND id NOT IN '
      '(SELECT id FROM $_table WHERE status != ? ORDER BY id DESC LIMIT ?)',
      [TapStatus.waiting.name, TapStatus.waiting.name, keep],
    );
    if (deleted > 0) _changed();
  }

  @override
  Future<int> discardWaiting() async {
    final deleted = await _db.delete(_table, where: 'status = ?', whereArgs: [TapStatus.waiting.name]);
    _changed();
    return deleted;
  }

  /// Like every finished row, a discarded one keeps only the photo metadata:
  /// it is never sent, so the previous employee's photo leaves the phone.
  @override
  Future<int> rejectWaitingNotOwnedBy(int employeeId, {required String message}) async {
    final updated = await _db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['client_uuid', 'request'],
        where: 'status = ? AND (employee_id IS NULL OR employee_id != ?)',
        whereArgs: [TapStatus.waiting.name, employeeId],
      );
      for (final row in rows) {
        final request = jsonDecode(row['request'] as String) as Map<String, Object?>;
        final photo = request['photo'];
        if (photo is Map<String, Object?>) photo.remove('data');
        await txn.rawUpdate(
          'UPDATE $_table SET status = ?, result_code = ?, result_message = ?, request = ? WHERE client_uuid = ?',
          [TapStatus.rejected.name, ErrorCodes.discarded, message, jsonEncode(request), row['client_uuid']],
        );
      }
      return rows.length;
    });
    if (updated > 0) _changed();
    return updated;
  }

  @override
  Future<void> close() async {
    // Not awaited: the done event waits for listeners (e.g. an open History
    // screen) and closing the database must not depend on them.
    unawaited(_changes.close());
    await _db.close();
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  static TapRecord _fromRow(Map<String, Object?> row) {
    return TapRecord(
      id: row['id'] as int?,
      clientUuid: row['client_uuid'] as String,
      request: jsonDecode(row['request'] as String) as Map<String, Object?>,
      status: TapStatus.values.byName(row['status'] as String),
      attempts: row['attempts'] as int? ?? 0,
      lastError: row['last_error'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      resultCode: row['result_code'] as String?,
      resultMessage: row['result_message'] as String?,
      employeeId: row['employee_id'] as int?,
      resultSite: row['result_site'] as String?,
      resultTime: DateTime.tryParse(row['result_time'] as String? ?? ''),
      serverErrors: row['server_errors'] as int? ?? 0,
      firstServerErrorAt: DateTime.tryParse(row['first_server_error_at'] as String? ?? ''),
    );
  }
}
