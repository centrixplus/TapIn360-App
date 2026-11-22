import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_models.dart';
import '../api/api_outcome.dart';
import '../api/error_codes.dart';
import 'tap_record.dart';
import 'tap_store.dart';

typedef PunchSender = Future<ApiOutcome<PunchResult>> Function(Map<String, Object?> body);

/// Sends waiting taps strictly oldest first, one at a time (spec §6.3).
///
/// - 200 → Sent. 4xx → Rejected (never retried) and the next tap is sent.
/// - No answer / 5xx → the tap stays Waiting with `offline: true` and the
///   flush stops, so nothing younger overtakes it.
/// - 401 → the queue pauses until [resume] (after the next login). A fresh tap
///   (first send, at tap time) is Rejected as §6.2 says; a queued tap stays
///   Waiting and is sent after the login.
/// - 403 `access_switched_off` → the tap stays Waiting (never Rejected), the
///   queue pauses and [onSwitchedOff] runs; the session resumes it.
/// - A tap the server keeps answering with an error ([ApiUnreachable.answered]:
///   500, non-JSON 4xx, …) would block every younger tap for ever. After
///   [undeliverableAttempts] such answers **and** [undeliverableAfter] since
///   the first of them, it is Rejected as `undeliverable` and the queue goes on.
///   Offline attempts (no connection, timeout, 502/503/504) never count.
class PunchQueue {
  PunchQueue({
    required this._store,
    required this._send,
    this.onUnauthorized,
    this.onSwitchedOff,
    this._paused = false,
    this.keep = 50,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const undeliverableAttempts = 20;
  static const undeliverableAfter = Duration(hours: 24);

  final TapStore _store;
  final PunchSender _send;
  final DateTime Function() _now;

  /// Called on a 401 (the session controller sets it to logout-and-pause).
  void Function()? onUnauthorized;

  /// Called on a 403 `access_switched_off` (the session shows the block).
  void Function()? onSwitchedOff;

  /// Finished rows kept for History.
  final int keep;

  bool _paused;
  Future<void>? _running;
  bool _again = false;

  bool get isPaused => _paused;

  void pause() => _paused = true;
  void resume() => _paused = false;

  /// Sends everything that can be sent now. Calls made while a flush runs
  /// join it (and make it look for new taps once more), so sends never overlap.
  Future<void> flush() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _run();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _run() async {
    try {
      // Prune is inside the loop so a flush() that joins during it still
      // gets its own pass (e.g. a tap stored while the last pass prunes).
      do {
        _again = false;
        await _drain();
        await _store.prune(keep: keep);
      } while (_again && !_paused);
    } catch (error, stack) {
      debugPrint('PunchQueue flush failed: $error\n$stack');
    }
  }

  Future<void> _drain() async {
    while (!_paused) {
      final tap = await _store.oldestWaiting();
      if (tap == null) return;
      final outcome = await _send(tap.request);
      switch (outcome) {
        case ApiOk(:final value):
          await _store.markSent(
            tap.clientUuid,
            result: value.result,
            message: value.message,
            site: value.site,
            time: value.time,
          );
        case ApiRejected(isUnauthorized: true):
          if (tap.isFresh) {
            await _store.markRejected(tap.clientUuid, code: outcome.code, message: outcome.message);
          } else {
            await _store.recordFailedAttempt(tap.clientUuid, error: outcome.code);
          }
          _paused = true;
          onUnauthorized?.call();
          return;
        case ApiRejected(isSwitchedOff: true):
          // Not the tap's fault: it is sent once the seat is back on.
          await _store.recordFailedAttempt(tap.clientUuid, error: outcome.code);
          _paused = true;
          onSwitchedOff?.call();
          return;
        case ApiRejected(:final code, :final message):
          await _store.markRejected(tap.clientUuid, code: code, message: message);
        case ApiUnreachable(:final reason, :final answered):
          final now = _now();
          await _store.recordFailedAttempt(tap.clientUuid, error: reason, serverError: answered, at: now);
          if (!answered || !_undeliverable(tap, now)) return;
          await _store.markRejected(tap.clientUuid, code: ErrorCodes.undeliverable, message: '');
      }
    }
  }

  /// [tap] as read before this attempt, which was a server error at [now].
  static bool _undeliverable(TapRecord tap, DateTime now) {
    final first = tap.firstServerErrorAt ?? now;
    return tap.serverErrors + 1 >= undeliverableAttempts && now.difference(first) >= undeliverableAfter;
  }
}
