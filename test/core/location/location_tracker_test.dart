import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/location/gps_fix.dart';
import 'package:nfc_attendance/core/location/location_tracker.dart';

final t0 = DateTime.utc(2026, 11, 17, 6);

GpsFix fixAt(DateTime at, {double accuracy = 19}) =>
    GpsFix(lat: 29.3759, lng: 47.9774, accuracyM: accuracy, isMocked: false, capturedAt: at);

void main() {
  late StreamController<GpsFix> source;
  late int opened;

  LocationTracker trackerFor(FakeAsync async) {
    source = StreamController<GpsFix>.broadcast();
    opened = 0;
    return LocationTracker(
      openStream: () {
        opened++;
        return source.stream;
      },
      now: () => t0.add(async.elapsed),
    );
  }

  test('reuses the latest fix when it is at most 30 s old, without waiting', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)..start();
      source.add(fixAt(t0));
      async.elapse(const Duration(seconds: 30));
      GpsFix? got;
      tracker.fixForTap().then((f) => got = f);
      async.flushMicrotasks();
      expect(got, isNotNull);
      expect(got!.capturedAt, t0);
    });
  });

  test('a fix older than 30 s is not used; the next fresh fix within 10 s is', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)..start();
      source.add(fixAt(t0));
      async.elapse(const Duration(seconds: 31));
      GpsFix? got;
      var done = false;
      tracker.fixForTap().then((f) {
        got = f;
        done = true;
      });
      async.elapse(const Duration(seconds: 2));
      expect(done, isFalse);
      final fresh = fixAt(t0.add(const Duration(seconds: 33)), accuracy: 25);
      source.add(fresh);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(got!.accuracyM, 25);
    });
  });

  test('no fix within 10 s → null (nothing will be recorded)', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)..start();
      var done = false;
      GpsFix? got = fixAt(t0);
      tracker.fixForTap().then((f) {
        got = f;
        done = true;
      });
      async.elapse(const Duration(milliseconds: 9900));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 100));
      expect(done, isTrue);
      expect(got, isNull);
    });
  });

  test('a stale (cached) fix delivered while waiting is ignored', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)..start();
      async.elapse(const Duration(minutes: 5));
      GpsFix? got = fixAt(t0);
      tracker.fixForTap().then((f) => got = f);
      source.add(fixAt(t0)); // 5 min old
      async.elapse(const Duration(seconds: 10));
      expect(got, isNull);
      expect(tracker.latest, isNotNull, reason: 'still shown on the indicator');
    });
  });

  test('fixForTap starts the GPS stream when it is not running', () {
    fakeAsync((async) {
      final tracker = trackerFor(async);
      expect(tracker.isRunning, isFalse);
      tracker.fixForTap();
      expect(opened, 1);
      expect(tracker.isRunning, isTrue);
      async.elapse(const Duration(seconds: 10));
    });
  });

  test('start is idempotent and stop cancels the stream', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)
        ..start()
        ..start();
      expect(opened, 1);
      tracker.stop();
      async.flushMicrotasks();
      expect(tracker.isRunning, isFalse);
      expect(source.hasListener, isFalse);
    });
  });

  test('stream errors are kept for the GPS indicator and listeners are notified', () {
    fakeAsync((async) {
      final tracker = trackerFor(async)..start();
      var notified = 0;
      tracker.addListener(() => notified++);
      source.addError(StateError('Location services are disabled'));
      async.flushMicrotasks();
      expect(tracker.lastError, isA<StateError>());
      expect(notified, greaterThan(0));
      source.add(fixAt(t0));
      async.flushMicrotasks();
      expect(tracker.lastError, isNull);
    });
  });

  test('GpsFix JSON matches §5.2 location', () {
    final fix = GpsFix(
      lat: 29.3759,
      lng: 47.9774,
      accuracyM: 8.5,
      isMocked: true,
      capturedAt: DateTime.utc(2026, 11, 17, 6, 2, 9),
    );
    final json = fix.toJson();
    expect(json['lat'], 29.3759);
    expect(json['lng'], 47.9774);
    expect(json['accuracy_m'], 8.5);
    expect(json['is_mocked'], isTrue);
    expect(DateTime.parse(json['captured_at']! as String), DateTime.utc(2026, 11, 17, 6, 2, 9));
    expect(json['captured_at'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$')));
  });
}
