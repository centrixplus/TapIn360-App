import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/queue/sqlite_tap_store.dart';
import 'package:nfc_attendance/core/queue/tap_record.dart';
import 'package:nfc_attendance/core/session/session.dart';
import 'package:nfc_attendance/core/time/iso_time.dart';
import 'package:nfc_attendance/features/history/history_screen.dart';

import '../../helpers/app_scope.dart';
import '../../helpers/localized.dart';
import '../../helpers/queue_fixtures.dart';
import '../../helpers/stub_adapter.dart';

TapRecord tapAt(String uuid, DateTime at, {String action = 'auto'}) {
  final tap = waitingTap(uuid: uuid, createdAt: at.toUtc());
  tap.request['tapped_at'] = localIso(at);
  tap.request['action'] = action;
  return tap;
}

void main() {
  late SqliteTapStore taps;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 8, 1);
  final yesterday = today.subtract(const Duration(days: 1)).add(const Duration(hours: 9, minutes: 30));

  setUp(() async {
    taps = await openMemoryStore();
    await taps.insert(tapAt('y-out', yesterday, action: 'check_out'));
    await taps.markSent('y-out', result: 'check_out', message: '', site: 'Head Office');
    await taps.insert(tapAt('t-in', today));
    await taps.markSent('t-in', result: 'check_in', message: 'Checked in at 08:01', site: 'Head Office');
    await taps.insert(tapAt('t-bad', today.add(const Duration(minutes: 1))));
    await taps.markRejected('t-bad', code: 'too_soon', message: 'Too soon after your check-in');
    await taps.insert(tapAt('t-wait', today.add(const Duration(hours: 5)), action: 'check_out'));
    await taps.recordFailedAttempt('t-wait', error: 'timeout');
    await taps.recordFailedAttempt('t-wait', error: 'timeout');
  });
  tearDown(() => taps.close());

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    await pumpLocalized(
      tester,
      ProviderScope(
        overrides: appOverrides(
          session: const Session(
            deviceId: 'dev-1',
            serverUrl: 'http://localhost:8046/nfc/api/v1',
            token: 't',
            employee: Employee(id: 17, name: 'Ahmed Ali'),
          ),
          taps: taps,
          adapter: StubAdapter((_) => jsonResponse(200, {})),
          store: memorySessionStore(),
        ),
        child: const HistoryScreen(),
      ),
      locale: locale,
      settle: false,
    );
    await settle(tester);
  }

  String hm(DateTime t) => DateFormat.Hm('en').format(t);

  testWidgets('groups taps by day with status, detail and time (AppHistory)', (tester) async {
    await pump(tester);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('Check out · 2 tries so far'), findsOneWidget);
    expect(find.text('Not recorded'), findsOneWidget);
    expect(find.text('Too soon after your check-in'), findsOneWidget);
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Checked out'), findsOneWidget);
    expect(find.text('Head Office'), findsNWidgets(2));
    expect(find.text(hm(today)), findsOneWidget);
    final waitingY = tester.getTopLeft(find.text('Waiting to send')).dy;
    final yesterdayY = tester.getTopLeft(find.text('YESTERDAY')).dy;
    expect(waitingY, lessThan(yesterdayY), reason: 'newest first');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap the server could not take for over a day: Not recorded, with the reason', (tester) async {
    await tester.runAsync(() async {
      await taps.insert(tapAt('t-stuck', today.add(const Duration(hours: 6))));
      await taps.markRejected('t-stuck', code: 'undeliverable', message: '');
    });
    await pump(tester);
    expect(find.text('Not sent: the server kept answering with an error for over a day. Tell HR.'), findsOneWidget);
    expect(find.text('Not recorded'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('undeliverable, in Arabic', (tester) async {
    await tester.runAsync(() async {
      await taps.insert(tapAt('t-stuck', today.add(const Duration(hours: 6))));
      await taps.markRejected('t-stuck', code: 'undeliverable', message: '');
    });
    await pump(tester, locale: const Locale('ar'));
    expect(find.text('لم يُرسل: ظلّ الخادم يرد بخطأ لأكثر من يوم. أبلغ الموارد البشرية.'), findsOneWidget);
  });

  testWidgets('Arabic, right-to-left', (tester) async {
    await pump(tester, locale: const Locale('ar'));
    expect(Directionality.of(tester.element(find.byType(HistoryScreen))), TextDirection.rtl);
    expect(find.text('السجل'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    expect(find.text('بانتظار الإرسال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty history', (tester) async {
    await tester.runAsync(() async {
      await taps.discardWaiting();
      for (final id in ['y-out', 't-in', 't-bad']) {
        await taps.markRejected(id, code: 'x', message: '');
      }
      await taps.prune(keep: 0);
    });
    await pump(tester);
    expect(find.text('No taps yet'), findsOneWidget);
  });
}
