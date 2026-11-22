import '../api/api_models.dart';

enum TapStatus { waiting, sent, rejected }

/// One tap in the local queue/history table (spec §6.3).
class TapRecord {
  const TapRecord({
    required this.clientUuid,
    required this.request,
    required this.status,
    required this.createdAt,
    this.id,
    this.attempts = 0,
    this.lastError,
    this.resultCode,
    this.resultMessage,
    this.employeeId,
    this.resultSite,
    this.resultTime,
    this.serverErrors = 0,
    this.firstServerErrorAt,
  });

  /// A new tap, stored before the first send.
  factory TapRecord.waiting({
    required String clientUuid,
    required Map<String, Object?> request,
    required DateTime createdAt,
    int? employeeId,
  }) {
    return TapRecord(
      clientUuid: clientUuid,
      request: request,
      status: TapStatus.waiting,
      createdAt: createdAt,
      employeeId: employeeId,
    );
  }

  final int? id;
  final String clientUuid;

  /// The `POST /punch` body, sent unchanged (only `offline` flips to true
  /// after the first failed attempt).
  final Map<String, Object?> request;
  final TapStatus status;
  final int attempts;

  /// Transport reason of the last failed attempt (e.g. `timeout`).
  final String? lastError;

  /// Attempts the server answered with an error ([ApiUnreachable.answered]),
  /// and when the first of them happened. Offline attempts never count.
  final int serverErrors;
  final DateTime? firstServerErrorAt;

  /// `check_in` / `check_out` when sent; the §5.3 code when rejected.
  final String? resultCode;
  final String? resultMessage;
  final DateTime createdAt;

  /// Employee who was logged in at tap time.
  final int? employeeId;

  /// Site and attendance time from the server's `200` answer.
  final String? resultSite;
  final DateTime? resultTime;

  String get cardUid => request['card_uid'] as String? ?? '';
  PunchAction? get action => PunchAction.parse(request['action']);
  DateTime? get tappedAt => DateTime.tryParse(request['tapped_at'] as String? ?? '');

  /// True until the first send attempt fails without an answer.
  bool get isFresh => request['offline'] != true;
}
