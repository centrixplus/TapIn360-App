import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/api/attendance_api.dart';
import 'package:nfc_attendance/core/directory/directory_api.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/features/company/company_screen.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/localized.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

Map<String, Object?> acme({String status = 'active', String base = 'https://acme.karrix.com/nfc/api/v1'}) => {
  'code': 'acme',
  'name': 'Acme Trading Co.',
  'logo_url': null,
  'api_base_url': base,
  'status': status,
};

void main() {
  late SqliteTapStore taps;
  late StubAdapter directory;
  late ProviderContainer container;
  String? scanned;

  setUpAll(() async => taps = await openMemoryStore());
  tearDownAll(() => taps.close());
  setUp(() {
    directory = StubAdapter((_) => jsonResponse(200, acme()));
    scanned = null;
  });

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLocalized(
      tester,
      ProviderScope(
        overrides: appOverrides(
          session: const Session(deviceId: 'dev-1'),
          taps: taps,
          adapter: StubAdapter((_) => jsonResponse(200, {})),
          store: memorySessionStore(),
          extra: [
            directoryApiProvider.overrideWith(
              (ref) => DirectoryApi(
                dio: createApiDio()..httpClientAdapter = directory,
                masterUrl: 'https://tapin360-account.karrix.com',
                language: () => 'en',
              ),
            ),
            qrScannerProvider.overrideWithValue((_) async => scanned),
          ],
        ),
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const CompanyScreen();
          },
        ),
      ),
      locale: locale,
    );
  }

  Future<void> continueWith(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('company.code')), code);
    await tester.tap(find.byKey(const Key('company.continue')));
    await settle(tester);
  }

  testWidgets('renders the AppCompany layout in English', (tester) async {
    await pump(tester);
    expect(find.text('TapIn360'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('Your company'), findsOneWidget);
    expect(find.text('Type the code your HR gave you, or scan the QR code on the poster.'), findsOneWidget);
    expect(find.text('COMPANY CODE'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Use a custom server'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in Arabic, right-to-left', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(Directionality.of(tester.element(find.byType(CompanyScreen))), TextDirection.rtl);
    expect(find.text('شركتك'), findsOneWidget);
    expect(find.text('رمز الشركة'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid code is refused before any request', (tester) async {
    await pump(tester);
    await continueWith(tester, 'ab');
    expect(
      find.text('Company codes are 3 to 30 lowercase letters, numbers or dashes, starting with a letter.'),
      findsOneWidget,
    );
    expect(directory.requests, isEmpty);
  });

  testWidgets('code found: name and host shown; Continue picks the company', (tester) async {
    await pump(tester);
    await continueWith(tester, ' Acme ');
    expect(
      directory.requests.single.uri.toString(),
      'https://tapin360-account.karrix.com/tapin/api/v1/company/acme',
    );
    expect(find.text('Acme Trading Co.'), findsOneWidget);
    expect(find.text('acme.karrix.com'), findsOneWidget);
    expect(find.text('AT'), findsOneWidget, reason: 'initials when there is no logo');
    expect(container.read(sessionProvider).hasServer, isFalse);

    await tester.tap(find.byKey(const Key('company.continue')));
    await settle(tester);
    final session = container.read(sessionProvider);
    expect(session.serverUrl, 'https://acme.karrix.com/nfc/api/v1');
    expect(session.company!.code, 'acme');
  });

  testWidgets('unknown code (404)', (tester) async {
    directory.handler = (_) => jsonResponse(404, errorBody('not_found', 'Not found.'));
    await pump(tester);
    await continueWith(tester, 'nosuch');
    expect(find.text("We can't find that company code. Check it with HR."), findsOneWidget);
  });

  testWidgets('suspended company: shown with the reason, cannot continue', (tester) async {
    directory.handler = (_) => jsonResponse(200, acme(status: 'suspended'));
    await pump(tester);
    await continueWith(tester, 'acme');
    expect(find.text('Acme Trading Co.'), findsOneWidget);
    expect(find.text("This company's TapIn360 account is suspended. Ask HR."), findsOneWidget);
    await tester.tap(find.byKey(const Key('company.continue')));
    await settle(tester);
    expect(container.read(sessionProvider).hasServer, isFalse);
  });

  testWidgets('company still being set up', (tester) async {
    directory.handler = (_) => jsonResponse(200, acme(status: 'provisioning'));
    await pump(tester);
    await continueWith(tester, 'acme');
    expect(find.text('This company is still being set up. Try again in a few minutes.'), findsOneWidget);
  });

  testWidgets('company on plain http:// (not this phone) → "https required", cannot continue', (tester) async {
    directory.handler = (_) => jsonResponse(200, acme(base: 'http://erp.acme.com/nfc/api/v1'));
    await pump(tester);
    await continueWith(tester, 'acme');
    expect(find.text("This server isn't secure (https required)."), findsOneWidget);
    expect(find.text("Can't reach TapIn360. Check your internet connection and try again."), findsNothing);
    await tester.tap(find.byKey(const Key('company.continue')));
    await settle(tester);
    expect(container.read(sessionProvider).hasServer, isFalse, reason: 'never stored');
  });

  testWidgets('no connection to the master', (tester) async {
    directory.handler = (_) => jsonResponse(503, {});
    await pump(tester);
    await continueWith(tester, 'acme');
    expect(find.text("Can't reach TapIn360. Check your internet connection and try again."), findsOneWidget);
  });

  testWidgets('Scan QR code fills the code and looks it up', (tester) async {
    scanned = 'acme';
    await pump(tester);
    await tester.tap(find.byKey(const Key('company.scan')));
    await settle(tester);
    expect(find.text('Acme Trading Co.'), findsOneWidget);
    expect(directory.requests, hasLength(1));
  });
}
