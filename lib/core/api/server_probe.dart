enum ProbeKind { ok, notAttendanceServer, redirect, unreachable }

/// Result of the Server setup **Test** button: `GET /status` without a token
/// must answer `401 invalid_token` in the standard error shape (spec §5.2).
class ServerProbe {
  const ServerProbe(this.kind, {this.status, this.location});

  final ProbeKind kind;
  final int? status;
  final String? location;
}
