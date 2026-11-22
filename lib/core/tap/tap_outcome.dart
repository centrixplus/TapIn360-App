import '../api/error_codes.dart';

/// What the Home screen shows after a card read (spec §6.2, §8).
sealed class TapOutcome {
  const TapOutcome();
}

/// Debounced or arrived while another tap was in progress: no feedback.
final class TapIgnored extends TapOutcome {
  const TapIgnored();
}

/// Manual mode: Check In / Check Out not pressed yet. Nothing recorded.
final class TapNeedsAction extends TapOutcome {
  const TapNeedsAction();
}

/// Photo required and the employee pressed Cancel on the camera: the tap is
/// discarded (nothing recorded or sent).
final class TapCancelled extends TapOutcome {
  const TapCancelled();
}

/// No GPS fix within 10 s. Nothing recorded or sent.
final class TapNoGps extends TapOutcome {
  const TapNoGps();
}

/// 200: the server recorded it.
final class TapSent extends TapOutcome {
  const TapSent({
    required this.result,
    required this.message,
    this.site,
    this.time,
    this.tappedAt,
    this.photoTaken = false,
  });

  /// `check_in` / `check_out`.
  final String result;
  final String message;
  final String? site;

  /// Attendance time recorded by the server (UTC).
  final DateTime? time;

  /// When the card was read.
  final DateTime? tappedAt;
  final bool photoTaken;
}

/// 4xx: refused; never retried.
final class TapRejected extends TapOutcome {
  const TapRejected({required this.code, required this.message});

  final String code;
  final String message;

  bool get isUnauthorized => code == ErrorCodes.invalidToken || code == 'http_401';
}

/// No answer / 5xx: Waiting, sent automatically later.
final class TapSaved extends TapOutcome {
  const TapSaved({this.tappedAt, this.photoTaken = false, this.heldBy});

  final DateTime? tappedAt;
  final bool photoTaken;

  /// Why the server could not take it now although it answered, e.g.
  /// `access_switched_off`; the tap still waits and is sent later.
  final String? heldBy;
}

/// Waiting because the queue is paused by a 401; the app asks for login.
/// Also: a tap that finished while logging out or switched off (not stored).
final class TapNeedsLogin extends TapOutcome {
  const TapNeedsLogin();
}
