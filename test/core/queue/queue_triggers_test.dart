import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/queue/queue_triggers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<List<ConnectivityResult>> network;
  late int flushes;
  late QueueTriggers triggers;

  QueueTriggers make() {
    network = StreamController<List<ConnectivityResult>>();
    flushes = 0;
    return QueueTriggers(flush: () async => flushes++, connectivity: network.stream);
  }

  test('app start flushes once', () {
    fakeAsync((async) {
      triggers = make()..start();
      async.flushMicrotasks();
      expect(flushes, 1);
      triggers.dispose();
    });
  });

  test('every 60 s while open', () {
    fakeAsync((async) {
      triggers = make()..start();
      async.elapse(const Duration(seconds: 59));
      expect(flushes, 1);
      async.elapse(const Duration(seconds: 1));
      expect(flushes, 2);
      async.elapse(const Duration(seconds: 120));
      expect(flushes, 4);
      triggers.dispose();
    });
  });

  test('connectivity regained (none → wifi) flushes; staying online does not', () {
    fakeAsync((async) {
      triggers = make()..start();
      async.flushMicrotasks();
      network.add([ConnectivityResult.wifi]);
      async.flushMicrotasks();
      expect(flushes, 1);
      network.add([ConnectivityResult.none]);
      async.flushMicrotasks();
      network.add([ConnectivityResult.mobile]);
      async.flushMicrotasks();
      expect(flushes, 2);
      triggers.dispose();
    });
  });

  test('resume flushes and restarts the timer; pause stops the timer', () {
    fakeAsync((async) {
      triggers = make()..start();
      async.flushMicrotasks();
      triggers.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.elapse(const Duration(minutes: 5));
      expect(flushes, 1, reason: 'no background sync in phase 1');
      triggers.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(flushes, 2);
      async.elapse(const Duration(seconds: 60));
      expect(flushes, 3);
      triggers.dispose();
    });
  });
}
