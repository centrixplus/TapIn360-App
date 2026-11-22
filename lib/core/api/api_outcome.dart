import 'error_codes.dart';

/// Result of one API call, mapped from HTTP per spec §5.3 and §6.2.
sealed class ApiOutcome<T> {
  const ApiOutcome();
}

/// 2xx with a body the app understands.
final class ApiOk<T> extends ApiOutcome<T> {
  const ApiOk(this.value);
  final T value;
}

/// 4xx: the server answered and refused. Never retried.
/// [code] is the §5.3 code, or `http_<status>` when the body is not the
/// standard error shape. [details] is the whole `error` object (e.g.
/// `distance_m`, `retry_after_s`).
final class ApiRejected<T> extends ApiOutcome<T> {
  const ApiRejected({
    required this.status,
    required this.code,
    required this.message,
    this.details = const {},
  });

  final int status;
  final String code;
  final String message;
  final Map<String, Object?> details;

  bool get isUnauthorized => status == 401;

  /// `403 access_switched_off`: TapIn360 switched the seat off.
  bool get isSwitchedOff => code == ErrorCodes.accessSwitchedOff;

  ApiRejected<R> cast<R>() => ApiRejected<R>(status: status, code: code, message: message, details: details);
}

/// No usable answer: no connection, timeout, 5xx, redirect or a garbled 2xx.
/// Punches in this state stay Waiting and are resent (§6.2).
final class ApiUnreachable<T> extends ApiOutcome<T> {
  const ApiUnreachable(this.reason, {this.answered = false});
  final String reason;

  /// The server did answer, but with an error it should not give: a 500, a
  /// non-JSON 4xx, a redirect or a garbled 2xx. False for no connection,
  /// timeouts and 502/503/504 (the server behind the proxy is not there),
  /// which are being offline, not a tap the server cannot take.
  final bool answered;

  ApiUnreachable<R> cast<R>() => ApiUnreachable<R>(reason, answered: answered);
}
