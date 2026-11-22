import 'dart:async';

import '../api/api_models.dart';
import '../api/error_codes.dart';
import '../location/gps_fix.dart';
import '../photo/punch_photo.dart';
import '../queue/punch_queue.dart';
import '../queue/tap_record.dart';
import '../queue/tap_store.dart';
import 'punch_action_resolver.dart';
import 'punch_body.dart';
import 'tap_debouncer.dart';
import 'tap_outcome.dart';

/// The tap flow of spec §6.2: card read → debounce → location → store as
/// Waiting → send → outcome. When older taps are already Waiting, the new tap
/// is queued behind them (`offline: true`), the queue is flushed oldest-first
/// in the background and the outcome is Saved: a new tap never overtakes
/// waiting ones (they would be rejected as `older_than_last`).
class TapService {
  TapService({
    required this._store,
    required this._queue,
    required this._fixForTap,
    required this._newUuid,
    required this._employeeId,
    required this._hardwareId,
    required this._localIp,
    bool Function()? acceptsTaps,
    DateTime Function()? now,
    TapDebouncer? debouncer,
  }) : _acceptsTaps = acceptsTaps ?? _always,
       _now = now ?? DateTime.now,
       _debouncer = debouncer ?? TapDebouncer();

  static bool _always() => true;

  final TapStore _store;
  final PunchQueue _queue;
  final Future<GpsFix?> Function() _fixForTap;
  final String Function() _newUuid;
  final int? Function() _employeeId;
  final String _hardwareId;

  /// The phone's IPv4 now (captured at tap time).
  final Future<String?> Function() _localIp;

  /// False while logging out or switched off: a tap that finishes its photo
  /// or GPS wait then is not stored (it would be discarded or never sent).
  final bool Function() _acceptsTaps;
  final DateTime Function() _now;
  final TapDebouncer _debouncer;

  /// A read that arrives while a tap is in progress or its result is shown:
  /// not a tap, but it keeps the debounce window going (card still held).
  void noteRead(String uid, {DateTime? at}) => _debouncer.accept(uid, at ?? _now());

  /// [onAccepted] runs once the read is a real tap (before the GPS wait), so
  /// the UI can show progress only for taps that will be processed.
  Future<TapOutcome> handle(
    String uid, {
    required PunchMode mode,
    PunchAction? selected,
    bool photoRequired = false,
    Future<PunchPhoto?> Function()? takePhoto,
    void Function()? onAccepted,
  }) async {
    final action = resolvePunchAction(mode, selected);
    if (action == null) return const TapNeedsAction();
    final readAt = _now();
    if (!_debouncer.accept(uid, readAt)) return const TapIgnored();
    onAccepted?.call();

    // Spec §15.3: the GPS fix is taken while the camera is open.
    final fixWhileCamera = _fixForTap();
    PunchPhoto? photo;
    if (photoRequired) {
      photo = await takePhoto?.call();
      if (photo == null) {
        // Cancel discards the tap; the card may be tapped again at once.
        _debouncer.reset();
        unawaited(fixWhileCamera);
        return const TapCancelled();
      }
    }
    var fix = await fixWhileCamera;
    // The camera can outlast the 10 s wait; a fix that arrived meanwhile counts.
    if (fix == null && photoRequired) fix = await _fixForTap();
    if (fix == null) return const TapNoGps();
    if (!_acceptsTaps()) return const TapNeedsLogin();

    final clientUuid = _newUuid();
    final localIp = await _localIp();
    final queuedBehind = await _store.waitingCount() > 0;
    await _store.insert(
      TapRecord.waiting(
        clientUuid: clientUuid,
        request: buildPunchBody(
          clientUuid: clientUuid,
          cardUid: uid,
          action: action,
          tappedAt: readAt,
          location: fix,
          hardwareId: _hardwareId,
          localIp: localIp,
          photo: photo,
          offline: queuedBehind,
        ),
        createdAt: readAt,
        employeeId: _employeeId(),
      ),
    );
    if (queuedBehind) {
      unawaited(_queue.flush());
      return TapSaved(tappedAt: readAt, photoTaken: photo != null);
    }
    await _queue.flush();

    final row = await _store.byUuid(clientUuid);
    return switch (row?.status) {
      TapStatus.sent => TapSent(
        result: row!.resultCode ?? '',
        message: row.resultMessage ?? '',
        site: row.resultSite,
        time: row.resultTime,
        tappedAt: readAt,
        photoTaken: photo != null,
      ),
      TapStatus.rejected => TapRejected(code: row!.resultCode ?? '', message: row.resultMessage ?? ''),
      _ when row?.lastError == ErrorCodes.accessSwitchedOff => TapSaved(
        tappedAt: readAt,
        photoTaken: photo != null,
        heldBy: ErrorCodes.accessSwitchedOff,
      ),
      _ => _queue.isPaused ? const TapNeedsLogin() : TapSaved(tappedAt: readAt, photoTaken: photo != null),
    };
  }
}
