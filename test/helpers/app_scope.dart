import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/queue/tap_store.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/core/storage/key_value_store.dart';
import 'package:nfc_attendance/core/storage/session_store.dart';

import 'stub_adapter.dart';

/// Provider overrides for screen tests: in-memory storage, the given tap
/// store, and the real API client over [adapter].
List<Override> appOverrides({
  required Session session,
  required TapStore taps,
  required StubAdapter adapter,
  required SessionStore store,
  List<Override> extra = const [],
}) {
  return [
    ...extra,
    initialSessionProvider.overrideWithValue(session),
    tapStoreProvider.overrideWithValue(taps),
    sessionStoreProvider.overrideWithValue(store),
    hardwareIdProvider.overrideWithValue('hw-test-1'),
    apiProvider.overrideWith((ref) {
      final credentials = ref.watch(apiCredentialsProvider);
      return AttendanceApi(
        dio: createApiDio()..httpClientAdapter = adapter,
        baseUrl: () => credentials.serverUrl,
        token: () => credentials.token,
        language: () => ref.read(languageProvider).value,
      );
    }),
  ];
}

SessionStore memorySessionStore() => SessionStore(MemoryKeyValueStore(), newDeviceId: () => 'dev-1');

/// Lets real async work (FFI SQLite, dio) finish while a spinner shows.
Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 30));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty && i > 2) break;
  }
  await tester.pump();
}
