import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// When the queue is flushed (spec §6.3): app start and resume, connectivity
/// regained, every [interval] while the app is open. (After each new tap is
/// handled by the tap flow itself.) Nothing runs while the app is in the
/// background — phase 1 has no background sync.
class QueueTriggers with WidgetsBindingObserver {
  QueueTriggers({
    required this._flush,
    required this._connectivity,
    this.interval = const Duration(seconds: 60),
  });

  final Future<void> Function() _flush;
  final Stream<List<ConnectivityResult>> _connectivity;
  final Duration interval;

  StreamSubscription<List<ConnectivityResult>>? _network;
  Timer? _timer;
  bool _online = true;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _network = _connectivity.listen(_onConnectivity);
    _startTimer();
    _trigger();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _network?.cancel();
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startTimer();
        _trigger();
      case AppLifecycleState.paused || AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive || AppLifecycleState.hidden:
        break;
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online && !_online) _trigger();
    _online = online;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _trigger());
  }

  void _trigger() => unawaited(_flush());
}
