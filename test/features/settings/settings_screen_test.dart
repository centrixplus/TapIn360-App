import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/app/providers.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/directory/company.dart';
import 'package:nfc_attendance/core/location/location_gateway.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/features/settings/device_status.dart';
import 'package:nfc_attendance/features/settings/settings_screen.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import '../../helpers/app_scope.dart';
import '../../helpers/localized.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

const acme = Company(
  code: 'acme',
  name: 'Acme Trading Co.',
  apiBaseUrl: 'https://acme.tapin360.co/nfc/api/v1',
  status: CompanyStatus.active,
);

void main() {
  late SqliteTapStore taps;
  late ProviderContainer container;
  // The browser, mocked: every URL Settings asks it to open, and its answer.
  late List<Uri> opened;
  late bool browserOpens;

  setUp(() async {
    taps = await openMemoryStore();
    opened = [];
    browserOpens = true;
  });
  tearDown(() => taps.close());

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en'), bool? camera = true}) async {
    await pumpLocalized(
      tester,
      ProviderScope(
        overrides: appOverrides(
          session: Session(
            deviceId: 'dev-1',
            serverUrl: acme.apiBaseUrl,
            token: 't',
            employee: const Employee(id: 17, name: 'Ahmed Ali'),
            company: acme,
          ),
          taps: taps,
          adapter: StubAdapter((_) => jsonResponse(200, {'ok': true})),
          store: memorySessionStore(),
          extra: [
            browserProvider.overrideWithValue((url) async {
              opened.add(url);
              return browserOpens;
            }),
            deviceStatusProvider.overrideWith(
              (ref) async => DeviceStatus(
                location: LocationAccess.granted,
                camera: camera,
                nfc: NfcAvailability.enabled,
              ),
            ),
          ],
        ),
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const SettingsScreen();
          },
        ),
      ),
      locale: locale,
    );
  }

  testWidgets('AppSettings layout: company, language, phone ID, permissions, log out', (tester) async {
    await pump(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('Acme Trading Co.'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text("This phone's ID"), findsOneWidget);
    expect(find.text('hw-test-1'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Allowed'), findsNWidgets(2));
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera not granted yet → asked when needed', (tester) async {
    await pump(tester, camera: false);
    expect(find.text('Asked when needed'), findsOneWidget);
  });

  testWidgets('Change company asks first, then logs out and forgets the company', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('settings.change_company')));
    await settle(tester);
    expect(find.text('Change company?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Change company'));
    await settle(tester);
    final session = container.read(sessionProvider);
    expect(session.isLoggedIn, isFalse);
    expect(session.hasServer, isFalse);
    expect(session.company, isNull);
  });

  Future<void> tapLink(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('Privacy policy, Support and Delete my account open tapin360.co/en in the browser', (tester) async {
    await pump(tester);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
    await tapLink(tester, 'settings.privacy');
    await tapLink(tester, 'settings.support');
    await tapLink(tester, 'settings.delete_account');
    expect(opened, [
      Uri.parse('https://tapin360.co/en/app/privacy'),
      Uri.parse('https://tapin360.co/en/support'),
      Uri.parse('https://tapin360.co/en/delete-account'),
    ]);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic the links open the Arabic pages', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(find.text('سياسة الخصوصية'), findsOneWidget);
    expect(find.text('الدعم'), findsOneWidget);
    expect(find.text('حذف حسابي'), findsOneWidget);
    await tapLink(tester, 'settings.privacy');
    await tapLink(tester, 'settings.support');
    await tapLink(tester, 'settings.delete_account');
    expect(opened, [
      Uri.parse('https://tapin360.co/ar/app/privacy'),
      Uri.parse('https://tapin360.co/ar/support'),
      Uri.parse('https://tapin360.co/ar/delete-account'),
    ]);
  });

  testWidgets('switching the language switches the pages the links open', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('settings.lang_ar')));
    await tester.pumpAndSettle();
    await tapLink(tester, 'settings.support');
    expect(opened, [Uri.parse('https://tapin360.co/ar/support')]);
  });

  testWidgets('no browser → the page address is shown instead', (tester) async {
    browserOpens = false;
    await pump(tester);
    await tapLink(tester, 'settings.support');
    expect(opened, [Uri.parse('https://tapin360.co/en/support')]);
    expect(find.text("Couldn't open the page. Visit https://tapin360.co/en/support"), findsOneWidget);
  });

  testWidgets('Arabic, right-to-left', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(Directionality.of(tester.element(find.byType(SettingsScreen))), TextDirection.rtl);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('معرّف هذا الهاتف'), findsOneWidget);
    expect(find.text('تغيير'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
