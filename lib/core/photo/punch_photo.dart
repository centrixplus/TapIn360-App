import 'dart:convert';
import 'dart:typed_data';

import '../time/iso_time.dart';

/// `POST /punch` → `photo` (spec §15.1). Stored inside the queued punch, so an
/// offline resend carries the same photo.
class PunchPhoto {
  const PunchPhoto({
    required this.jpeg,
    required this.takenAt,
    required this.faces,
    this.mime = 'image/jpeg',
  });

  final Uint8List jpeg;
  final DateTime takenAt;

  /// Faces found on the phone (always 1 for an accepted photo).
  final int faces;
  final String mime;

  Map<String, Object?> toJson() => {
    'mime': mime,
    'data': base64Encode(jpeg),
    'taken_at': localIso(takenAt),
    'faces': faces,
  };
}
