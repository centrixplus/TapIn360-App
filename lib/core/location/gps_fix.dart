import '../time/iso_time.dart';

/// One GPS reading, as sent in `POST /punch` → `location` (spec §5.2).
class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.isMocked,
    required this.capturedAt,
  });

  final double lat;
  final double lng;
  final double accuracyM;

  /// Android: the location API's mocked flag. iOS: whatever the platform
  /// reports (false when it reports nothing) — spec §6.4.
  final bool isMocked;
  final DateTime capturedAt;

  Map<String, Object?> toJson() => {
    'lat': lat,
    'lng': lng,
    'accuracy_m': accuracyM,
    'is_mocked': isMocked,
    'captured_at': localIso(capturedAt),
  };
}
