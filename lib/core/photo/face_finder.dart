import 'dart:typed_data';
import 'dart:ui';

import 'camera_session.dart';
import 'face_quality.dart';

/// The faces found in one image and that image's upright size in pixels.
class FaceScan {
  const FaceScan(this.faces, this.imageSize);

  final List<FaceInfo> faces;
  final Size imageSize;

  FaceQuality get quality => evaluateFaces(faces, imageSize);
}

/// Finds faces on the device, behind an interface so the photo rule and the
/// capture screen are testable without ML Kit.
abstract interface class FaceFinder {
  /// Faces in an upright JPEG: the photo that will be uploaded. May write a
  /// temporary copy at [scratchPath], which it deletes again.
  Future<FaceScan> scanPhoto(Uint8List jpeg, {required String scratchPath});

  /// Faces in one live preview frame. Guidance only: [scanPhoto] decides.
  Future<FaceScan> scanFrame(PreviewFrame frame);

  Future<void> close();
}
