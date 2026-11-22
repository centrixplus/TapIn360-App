import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/location/location_gateway.dart';
import 'package:nfc_attendance/core/tap/tap_outcome.dart';
import 'package:nfc_attendance/features/home/home_actions.dart';
import 'package:nfc_attendance/features/home/home_state.dart';
import 'package:nfc_attendance/features/home/home_view.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../helpers/localized.dart';

class RecordingActions implements HomeActions {
  final calls = <String>[];

  @override
  void scan() => calls.add('scan');
  @override
  void selectAction(PunchAction action) => calls.add('select:${action.wire}');
  @override
  void cancelAction() => calls.add('cancel');
  @override
  void openHistory() => calls.add('history');
  @override
  void openSettings() => calls.add('settings');
  @override
  void allowLocation() => calls.add('allowLocation');
  @override
  void openAppSettings() => calls.add('appSettings');
  @override
  void openLocationSettings() => calls.add('locationSettings');
  @override
  void openNfcSettings() => calls.add('nfcSettings');
  @override
  void logIn() => calls.add('login');
  @override
  void dismissResult() => calls.add('dismiss');
  @override
  Future<void> refresh() async => calls.add('refresh');
  @override
  void simulateTap() => calls.add('simulate');
}

final since = DateTime.utc(2026, 11, 17, 5, 2);
String hm(DateTime t) => DateFormat.Hm('en').format(t.toLocal());

HomeState state({
  PunchMode mode = PunchMode.auto,
  bool ios = false,
  bool loggedIn = true,
  LocationAccess location = LocationAccess.granted,
  NfcAvailability nfc = NfcAvailability.enabled,
  StatusKind status = StatusKind.checkedIn,
  int waiting = 0,
  PunchAction? selected,
  TapOutcome? result,
  GpsKind gps = GpsKind.fix,
  bool photo = false,
  DateTime? lastTapAt,
  String? lastTapSite,
  bool switchedOff = false,
}) {
  return HomeState(
    employeeName: 'Ahmed Ali',
    companyName: 'Acme Trading Co.',
    punchMode: mode,
    isIos: ios,
    loggedIn: loggedIn,
    locationAccess: location,
    nfc: nfc,
    statusKind: status,
    since: status == StatusKind.checkedIn ? since : null,
    site: status == StatusKind.checkedIn ? 'Head Office' : null,
    gpsKind: gps,
    gpsAccuracy: 19.4,
    waitingCount: waiting,
    selectedAction: selected,
    result: result,
    photoRequired: photo,
    lastTapAt: lastTapAt,
    lastTapSite: lastTapSite,
    accessSwitchedOff: switchedOff,
  );
}

void main() {
  late RecordingActions actions;
  setUp(() => actions = RecordingActions());

  Future<void> pump(WidgetTester tester, HomeState s, {Locale locale = const Locale('en')}) => pumpLocalized(
    tester,
    HomeView(state: s, actions: actions),
    locale: locale,
  );

  group('tap screen (AppHome)', () {
    testWidgets('auto mode on Android: greeting, company, status, motif, hold prompt, GPS pill', (
      tester,
    ) async {
      await pump(tester, state());
      expect(find.text('Acme Trading Co.'), findsOneWidget);
      expect(find.text('Hello, Ahmed'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('Since ${hm(since)} · Head Office'), findsOneWidget);
      expect(find.text('Hold your phone to the card'), findsOneWidget);
      expect(find.text('Touch the back of the phone to the TapIn360 card at the entrance.'), findsOneWidget);
      expect(find.text('GPS ready · ±19 m'), findsOneWidget);
      expect(find.text('Scan card'), findsNothing);
      expect(find.text('Check in'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('photo required: "The camera opens next."', (tester) async {
      await pump(tester, state(photo: true));
      expect(
        find.text('Touch the back of the phone to the TapIn360 card at the entrance. The camera opens next.'),
        findsOneWidget,
      );
    });

    testWidgets('iPhone: Scan card button starts the NFC sheet', (tester) async {
      await pump(tester, state(ios: true));
      expect(find.text('Scan the card'), findsOneWidget);
      await tester.tap(find.text('Scan card'));
      expect(actions.calls, ['scan']);
    });

    testWidgets('checked out: last tap from this phone', (tester) async {
      final at = DateTime.now();
      await pump(tester, state(status: StatusKind.checkedOut, lastTapAt: at, lastTapSite: 'Warehouse 2'));
      expect(find.text('Checked out'), findsOneWidget);
      expect(find.text('Last tap today ${hm(at)} · Warehouse 2'), findsOneWidget);
    });

    testWidgets('checked out with no taps yet', (tester) async {
      await pump(tester, state(status: StatusKind.checkedOut));
      expect(find.text('No taps on this phone yet'), findsOneWidget);
    });

    testWidgets('manual mode: Check in / Check out first, then the hold prompt with Cancel', (tester) async {
      await pump(tester, state(mode: PunchMode.manual));
      expect(find.text('Check in or check out?'), findsOneWidget);
      await tester.tap(find.text('Check in'));
      await tester.tap(find.text('Check out'));
      expect(actions.calls, ['select:check_in', 'select:check_out']);

      await pump(tester, state(mode: PunchMode.manual, selected: PunchAction.checkIn));
      expect(find.text('Check in: hold your phone to the card'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      expect(actions.calls.last, 'cancel');
    });

    testWidgets('History and Settings buttons', (tester) async {
      await pump(tester, state());
      await tester.tap(find.byKey(const Key('home.history')));
      await tester.tap(find.byKey(const Key('home.settings')));
      expect(actions.calls, ['history', 'settings']);
    });

    testWidgets('debug builds: long-press on the motif simulates a card read', (tester) async {
      await pump(tester, state());
      await tester.longPress(find.byKey(const Key('home.motif')));
      expect(actions.calls, ['simulate']);
    });
  });

  group('banners and pills', () {
    testWidgets('location permission off: banner with Allow, taps paused', (tester) async {
      await pump(tester, state(location: LocationAccess.denied));
      expect(find.text('Location is needed to record attendance.'), findsOneWidget);
      expect(find.text('Taps are paused'), findsOneWidget);
      expect(find.text('Hold your phone to the card'), findsNothing);
      await tester.tap(find.text('Allow'));
      expect(actions.calls, ['allowLocation']);
    });

    testWidgets('location refused for good: Open settings', (tester) async {
      await pump(tester, state(location: LocationAccess.deniedForever));
      await tester.tap(find.text('Open settings'));
      expect(actions.calls, ['appSettings']);
    });

    testWidgets('approximate location only: "Allow precise location", Open settings, taps paused', (tester) async {
      await pump(tester, state(location: LocationAccess.approximate));
      expect(
        find.text("Allow precise location: approximate location can't confirm you are at the site."),
        findsOneWidget,
      );
      expect(find.text('Taps are paused'), findsOneWidget);
      expect(find.text('Hold your phone to the card'), findsNothing);
      await tester.tap(find.text('Open settings'));
      expect(actions.calls, ['appSettings']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('access switched off by TapIn360: blocking banner, taps paused, Check again', (tester) async {
      await pump(tester, state(switchedOff: true));
      expect(find.text('Your access is switched off. Contact your HR.'), findsOneWidget);
      expect(find.text('Taps are paused'), findsOneWidget);
      expect(find.text('Hold your phone to the card'), findsNothing);
      await tester.tap(find.text('Check again'));
      expect(actions.calls, ['refresh']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switched off, in Arabic', (tester) async {
      await pump(tester, state(switchedOff: true), locale: const Locale('ar'));
      expect(find.text('تم إيقاف وصولك. تواصل مع الموارد البشرية.'), findsOneWidget);
      expect(find.text('تحقّق مجددًا'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('location services off: Turn on', (tester) async {
      await pump(tester, state(location: LocationAccess.serviceOff));
      expect(find.text('Location is off. Turn it on to record attendance.'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      expect(actions.calls, ['locationSettings']);
    });

    testWidgets('NFC off on Android: banner; not on iPhone', (tester) async {
      await pump(tester, state(nfc: NfcAvailability.disabled));
      expect(find.text('NFC is off. Turn it on to tap the card.'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      expect(actions.calls, ['nfcSettings']);
      await pump(tester, state(ios: true, nfc: NfcAvailability.disabled));
      expect(find.text('NFC is off. Turn it on to tap the card.'), findsNothing);
    });

    testWidgets('not logged in: banner with Log in', (tester) async {
      await pump(tester, state(loggedIn: false));
      expect(find.text('You are not logged in.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      expect(actions.calls, ['login']);
    });

    testWidgets('waiting pill: one / many, opens History; hidden at 0', (tester) async {
      await pump(tester, state(waiting: 1));
      expect(find.text('1 tap waiting to send'), findsOneWidget);
      await pump(tester, state(waiting: 3));
      await tester.tap(find.text('3 taps waiting to send'));
      expect(actions.calls, ['history']);
      await pump(tester, state());
      expect(find.byKey(const Key('home.waiting')), findsNothing);
    });

    testWidgets('GPS pill: searching and off', (tester) async {
      await pump(tester, state(gps: GpsKind.searching));
      expect(find.text('Finding GPS…'), findsOneWidget);
      await pump(tester, state(gps: GpsKind.off));
      expect(find.text('GPS off'), findsOneWidget);
    });
  });

  group('result (AppResult)', () {
    final at = DateTime.utc(2026, 11, 17, 5, 2);

    testWidgets('checked in: time · site, check rows, Done; closes after 4 s', (tester) async {
      await pump(
        tester,
        state(
          result: TapSent(result: 'check_in', message: 'x', site: 'Head Office', time: at, photoTaken: true),
        ),
      );
      expect(find.text('Checked in'), findsWidgets);
      expect(find.text('${hm(at)} · Head Office'), findsOneWidget);
      expect(find.text('Within range of the card'), findsOneWidget);
      expect(find.text('Photo taken, one face'), findsOneWidget);
      expect(find.text('Closes by itself in 4 s'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(actions.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(actions.calls, ['dismiss']);
    });

    testWidgets('Done closes at once', (tester) async {
      await pump(
        tester,
        state(
          result: const TapSent(result: 'check_out', message: 'Checked out at 17:31'),
        ),
      );
      expect(find.text('Checked out'), findsWidgets);
      await tester.tap(find.byKey(const Key('result.done')));
      expect(actions.calls, ['dismiss']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('rejected: "Not recorded", server message, reason row', (tester) async {
      await pump(
        tester,
        state(
          result: const TapRejected(
            code: 'out_of_range',
            message: 'You are 340 m from Head Office. Move closer to the card and tap again.',
          ),
        ),
      );
      expect(find.text('Not recorded'), findsOneWidget);
      expect(
        find.text('You are 340 m from Head Office. Move closer to the card and tap again.'),
        findsOneWidget,
      );
      expect(find.text('Outside the allowed area'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('saved offline: "Saved", tap time, waiting row', (tester) async {
      await pump(tester, state(result: TapSaved(tappedAt: at, photoTaken: true)));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Your tap at ${hm(at)} is saved and will be sent automatically.'), findsOneWidget);
      expect(find.text('Card, location and photo recorded'), findsOneWidget);
      expect(find.text('Waiting to send · shown in History'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('saved because access is switched off: reason row, still waiting', (tester) async {
      await pump(tester, state(result: TapSaved(tappedAt: at, heldBy: 'access_switched_off')));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Your access is switched off'), findsOneWidget);
      expect(find.text('Waiting to send · shown in History'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('no GPS: nothing recorded', (tester) async {
      await pump(tester, state(result: const TapNoGps()));
      expect(find.text('No GPS signal. Move near a window and tap again.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('Arabic (AppHomeAr)', () {
    testWidgets('right-to-left tap screen', (tester) async {
      await pump(tester, state(waiting: 1), locale: const Locale('ar'));
      expect(Directionality.of(tester.element(find.byType(HomeView))), TextDirection.rtl);
      expect(find.text('مرحباً، Ahmed'), findsOneWidget);
      expect(find.text('قرّب هاتفك من البطاقة'), findsOneWidget);
      expect(find.text('تسجيل واحد بانتظار الإرسال'), findsOneWidget);
      expect(find.text('الموقع جاهز · ±19 م'), findsOneWidget);
      final width = tester.getSize(find.byType(HomeView)).width;
      expect(
        tester.getCenter(find.byKey(const Key('home.settings'))).dx,
        lessThan(width / 2),
        reason: 'header buttons sit on the left in RTL',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic result screen', (tester) async {
      await pump(
        tester,
        state(
          result: const TapSent(result: 'check_in', message: '', site: 'المكتب الرئيسي'),
        ),
        locale: const Locale('ar'),
      );
      expect(find.text('تم تسجيل الدخول'), findsWidgets);
      expect(find.text('ضمن نطاق البطاقة'), findsOneWidget);
      expect(find.text('تم'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
