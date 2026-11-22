import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/features/setup/server_setup_screen.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/localized.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

void main() {
  late SqliteTapStore taps;
  late StubAdapter adapter;
  late ProviderContainer container;

  setUpAll(() async => taps = await openMemoryStore());
  tearDownAll(() => taps.close());
  setUp(() => adapter = StubAdapter((_) => jsonResponse(401, errorBody('invalid_token', 'Log in'))));

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLocalized(
      tester,
      ProviderScope(
        overrides: appOverrides(
          session: const Session(deviceId: 'dev-1'),
          taps: taps,
          adapter: adapter,
          store: memorySessionStore(),
        ),
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const ServerSetupScreen();
          },
        ),
      ),
      locale: locale,
    );
  }

  testWidgets('renders in English without layout errors', (tester) async {
    await pump(tester);
    expect(find.text('Custom server'), findsOneWidget);
    expect(find.text('SERVER URL'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic, right-to-left', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(find.text('خادم مخصّص'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(ServerSetupScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid URL is refused before any request', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('setup.url')), 'ftp://x');
    await tester.tap(find.byKey(const Key('setup.test')));
    await tester.pump();
    expect(find.text('Enter a valid http:// or https:// address.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('plain http:// to a non-local host → "https required", no request, nothing stored', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('setup.url')), 'http://erp.client.com/nfc/api/v1');
    await tester.tap(find.byKey(const Key('setup.test')));
    await tester.pump();
    expect(find.text("This server isn't secure (https required)."), findsOneWidget);
    expect(find.text("Can't reach the server. Check the address and your connection."), findsNothing);
    await tester.tap(find.byKey(const Key('setup.continue')));
    await tester.pump();
    expect(adapter.requests, isEmpty);
    expect(container.read(sessionProvider).serverUrl, isNull);
  });

  testWidgets('"https required" in Arabic', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    await tester.enterText(find.byKey(const Key('setup.url')), 'http://10.0.0.5:8069/nfc/api/v1');
    await tester.tap(find.byKey(const Key('setup.test')));
    await tester.pump();
    expect(find.text('هذا الخادم غير آمن (يلزم https).'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('Test: 401 invalid_token → server found; Continue stores the normalised URL', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('setup.url')), 'http://localhost:8046/nfc/api/v1/');
    await tester.tap(find.byKey(const Key('setup.test')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Server found.'), findsOneWidget);
    expect(adapter.requests.single.uri.toString(), 'http://localhost:8046/nfc/api/v1/status');
    expect(adapter.requests.single.headers['Authorization'], isNull);

    await tester.tap(find.byKey(const Key('setup.continue')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider).serverUrl, 'http://localhost:8046/nfc/api/v1');
  });

  testWidgets('Test: a 404 page is not an attendance server; Continue does not save', (tester) async {
    adapter.handler = (_) => textResponse(404, 'Not Found');
    await pump(tester);
    await tester.enterText(find.byKey(const Key('setup.url')), 'http://localhost:8046/wrong');
    await tester.tap(find.byKey(const Key('setup.continue')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('not a TapIn360 attendance server (HTTP 404)'), findsOneWidget);
    expect(container.read(sessionProvider).serverUrl, isNull);
  });
}
