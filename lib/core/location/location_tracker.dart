import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gps_fix.dart';

/// Keeps a GPS stream running while Home is visible so a fix is ready before
/// the tap, and applies the freshness rules of spec §6.2 step 3:
/// use the latest fix if it is at most [maxAge] old, otherwise wait up to
/// [maxWait] for a fresh one; no fix → null (the tap is not recorded).
class LocationTracker extends ChangeNotifier {
  LocationTracker({
    required this._openStream,
    DateTime Function()? now,
    this.maxAge = const Duration(seconds: 30),
    this.maxWait = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final Stream<GpsFix> Function() _openStream;
  final DateTime Function() _now;
  final Duration maxAge;
  final Duration maxWait;

  final _fixes = StreamController<GpsFix>.broadcast(sync: true);
  StreamSubscription<GpsFix>? _subscription;
  GpsFix? _latest;
  Object? _lastError;

  GpsFix? get latest => _latest;

  /// Last stream error (permission revoked, location services off), cleared
  /// by the next fix.
  Object? get lastError => _lastError;
  bool get isRunning => _subscription != null;

  bool isFresh(GpsFix fix) => _now().difference(fix.capturedAt) <= maxAge;

  void start() {
    if (_subscription != null) return;
    _subscription = _openStream().listen(
      _onFix,
      onError: (Object error) {
        _lastError = error;
        notifyListeners();
      },
      onDone: () {
        _subscription = null;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    notifyListeners();
  }

  /// The fix to attach to a tap, or null when none arrives in time.
  Future<GpsFix?> fixForTap() async {
    final latest = _latest;
    if (latest != null && isFresh(latest)) return latest;
    start();
    final completer = Completer<GpsFix?>();
    final subscription = _fixes.stream.listen((fix) {
      if (!completer.isCompleted && isFresh(fix)) completer.complete(fix);
    });
    final timer = Timer(maxWait, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    unawaited(subscription.cancel());
    return result;
  }

  void _onFix(GpsFix fix) {
    _latest = fix;
    _lastError = null;
    _fixes.add(fix);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _fixes.close();
    super.dispose();
  }
}
