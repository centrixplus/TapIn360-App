import '../api/api_models.dart';
import '../location/gps_fix.dart';
import '../photo/punch_photo.dart';
import '../time/iso_time.dart';

/// `POST /punch` body (spec §5.2). `offline` is false when the tap is sent at
/// tap time, true when it is queued behind older waiting taps; the queue also
/// flips it to true when a send gets no answer.
Map<String, Object?> buildPunchBody({
  required String clientUuid,
  required String cardUid,
  required PunchAction action,
  required DateTime tappedAt,
  required GpsFix location,
  required String hardwareId,
  required String? localIp,
  PunchPhoto? photo,
  bool offline = false,
}) {
  return {
    'client_uuid': clientUuid,
    'card_uid': cardUid,
    'action': action.wire,
    'tapped_at': localIso(tappedAt),
    'offline': offline,
    'location': location.toJson(),
    // Spec §14.1; stored with the queued tap so resends keep the tap-time IP.
    'device': {'hardware_id': hardwareId, 'local_ip': localIp},
    // Spec §15.1; kept in the queued punch so offline resends carry it.
    'photo': ?photo?.toJson(),
  };
}
