import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<SqliteTapStore> openMemoryStore() async {
  sqfliteFfiInit();
  return SqliteTapStore.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
}

var _seq = 0;

/// A waiting tap as the tap flow stores it (offline: false, attempts 0).
TapRecord waitingTap({
  String? uuid,
  int employeeId = 17,
  DateTime? createdAt,
  String card = '04DB8FE23B1590',
}) {
  final id = uuid ?? 'uuid-${++_seq}';
  return TapRecord.waiting(
    clientUuid: id,
    request: {
      'client_uuid': id,
      'card_uid': card,
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
    },
    createdAt: createdAt ?? DateTime.utc(2026, 11, 17, 6, 0, _seq % 60),
    employeeId: employeeId,
  );
}
