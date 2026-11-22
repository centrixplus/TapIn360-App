import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/features/login/login_screen.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/localized.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const base = 'http://localhost:8046/nfc/api/v1';

void main() {
  late SqliteTapStore taps;
  late StubAdapter adapter;
  late ProviderContainer container;

  setUpAll(() async => taps = await openMemoryStore());
  tearDownAll(() => taps.close());
  setUp(() => adapter = StubAdapter((_) => jsonResponse(200, {})));

  Future<void> pump(WidgetTester tester, {bool expired = false, Locale locale = const Locale('en')}) async {
    await pumpLocalized(
      tester,
      ProviderScope(
        overrides: appOverrides(
          session: Session(deviceId: 'dev-1', serverUrl: base, expired: expired),
          taps: taps,
          adapter: adapter,
          store: memorySessionStore(),
        ),
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const LoginScreen();
          },
        ),
      ),
      locale: locale,
    );
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login.id')), '041234567890');
    await tester.enterText(find.byKey(const Key('login.pin')), '1234');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pump();
    // Login touches the FFI SQLite store, which completes in real time.
    for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  testWidgets('renders Employee ID and PIN fields in English', (tester) async {
    await pump(tester);
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('EMPLOYEE ID'), findsOneWidget);
    expect(find.text('PIN / PASSWORD'), findsOneWidget);
    expect(find.text('Custom server'), findsOneWidget);
    expect(find.text('localhost'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic, right-to-left', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(find.text('الرقم الوظيفي'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(LoginScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty fields are required', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pump();
    expect(find.text('Required'), findsNWidgets(2));
    expect(adapter.requests, isEmpty);
  });

  testWidgets('a session ended by 401 explains why', (tester) async {
    await pump(tester, expired: true);
    expect(find.text('Your session ended. Log in again.'), findsOneWidget);
  });

  testWidgets('wrong PIN shows the server message', (tester) async {
    adapter.handler = (_) => jsonResponse(401, errorBody('invalid_credentials', 'Wrong Badge ID or PIN'));
    await pump(tester);
    await submit(tester);
    expect(find.text('Wrong Badge ID or PIN'), findsOneWidget);
    expect(container.read(sessionProvider).isLoggedIn, isFalse);
  });

  testWidgets('403 device_not_allowed: "not registered" card with this phone ID, stays on Login', (
    tester,
  ) async {
    adapter.handler = (_) => jsonResponse(
      403,
      errorBody('device_not_allowed', 'This phone is not registered for you. Ask HR to approve it.'),
    );
    await pump(tester);
    await submit(tester);
    expect(find.text('This phone is not registered for you'), findsOneWidget);
    expect(find.text("Ask HR to approve it. Give them this phone's ID:"), findsOneWidget);
    expect(find.text('hw-test-1'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(container.read(sessionProvider).isLoggedIn, isFalse);
  });

  testWidgets('403 subscription_inactive: server message, no phone ID, stays on Login', (tester) async {
    adapter.handler = (_) => jsonResponse(
      403,
      errorBody('subscription_inactive', "Your company's TapIn360 subscription has ended. Ask HR."),
    );
    await pump(tester);
    await submit(tester);
    expect(find.text("Your company's TapIn360 subscription has ended. Ask HR."), findsOneWidget);
    expect(find.text('hw-test-1'), findsNothing);
    expect(container.read(sessionProvider).isLoggedIn, isFalse);
  });

  testWidgets('success logs in with the device block', (tester) async {
    adapter.handler = (_) => jsonResponse(200, {
      'token': 't',
      'employee': {'id': 17, 'name': 'Ahmed Ali'},
      'settings': {'punch_mode': 'auto'},
      'server_time': '2026-11-17T06:00:00Z',
    });
    await pump(tester);
    await submit(tester);
    expect(container.read(sessionProvider).isLoggedIn, isTrue);
    final body = adapter.bodyOf(0);
    expect(body['login'], '041234567890');
    expect((body['device']! as Map)['id'], 'dev-1');
    expect((body['device']! as Map)['hardware_id'], 'hw-test-1');
  });
}
