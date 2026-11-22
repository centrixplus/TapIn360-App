import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/storage/key_value_store.dart';
import 'package:nfc_attendance/core/storage/session_store.dart';

void main() {
  late MemoryKeyValueStore kv;
  late SessionStore store;
  var ids = 0;

  setUp(() {
    kv = MemoryKeyValueStore();
    store = SessionStore(kv, newDeviceId: () => 'device-${++ids}');
  });

  test('first load creates the app-install device ID once and keeps it', () async {
    final first = await store.load();
    final second = await store.load();
    expect(first.deviceId, startsWith('device-'));
    expect(second.deviceId, first.deviceId);
    expect(first.serverUrl, isNull);
    expect(first.isLoggedIn, isFalse);
  });

  test('server URL, token, employee and punch mode survive a reload', () async {
    await store.load();
    await store.saveServerUrl('http://localhost:8046/nfc/api/v1');
    await store.saveLogin(
      token: 'tok',
      employee: const Employee(id: 17, name: 'Ahmed Ali'),
      punchMode: PunchMode.manual,
      photoRequired: true,
    );
    final session = await store.load();
    expect(session.serverUrl, 'http://localhost:8046/nfc/api/v1');
    expect(session.token, 'tok');
    expect(session.employee!.name, 'Ahmed Ali');
    expect(session.punchMode, PunchMode.manual);
    expect(session.photoRequired, isTrue);
    expect(session.isLoggedIn, isTrue);
  });

  test('clearLogin keeps the server URL and device ID', () async {
    final before = await store.load();
    await store.saveServerUrl('https://erp.client.com/nfc/api/v1');
    await store.saveLogin(
      token: 't',
      employee: const Employee(id: 1, name: 'A'),
      punchMode: PunchMode.auto,
    );
    await store.clearLogin();
    final after = await store.load();
    expect(after.token, isNull);
    expect(after.employee, isNull);
    expect(after.serverUrl, 'https://erp.client.com/nfc/api/v1');
    expect(after.deviceId, before.deviceId);
  });

  test('unreadable storage (e.g. Android keystore lost) resets instead of crashing', () async {
    kv.failReads = true;
    final session = await store.load();
    expect(session.serverUrl, isNull);
    expect(session.deviceId, isNotEmpty);
  });
}
