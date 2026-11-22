import 'dart:typed_data';

import 'camera_session.dart';
import 'face_finder.dart';
import 'face_quality.dart';
import 'punch_photo.dart';

enum PhotoProblem {
  noFace,
  tooManyFaces,
  notWhole,
  tooFar,
  notFacing,
  checkFailed;

  /// The problem behind a [FaceQuality]; null when the face is good.
  static PhotoProblem? of(FaceQuality quality) => switch (quality) {
    FaceQuality.ok => null,
    FaceQuality.noFace => PhotoProblem.noFace,
    FaceQuality.tooManyFaces => PhotoProblem.tooManyFaces,
    FaceQuality.notWhole => PhotoProblem.notWhole,
    FaceQuality.tooFar => PhotoProblem.tooFar,
    FaceQuality.notFacing => PhotoProblem.notFacing,
  };
}

sealed class PhotoResult {
  const PhotoResult();
}

final class PhotoAccepted extends PhotoResult {
  const PhotoAccepted(this.photo);
  final PunchPhoto photo;
}

final class PhotoRejected extends PhotoResult {
  const PhotoRejected(this.problem);
  final PhotoProblem problem;
}

/// Still image → compressed upright JPEG → face rule ([evaluateFaces]) →
/// [PunchPhoto] (spec §15.3). The face check runs on the compressed JPEG, so
/// it judges exactly the photo the server receives, in one unambiguous
/// orientation. Detector or encoder failures ask for another try.
class PhotoProcessor {
  PhotoProcessor({required this._faces, required this._encode});

  final FaceFinder _faces;
  final Future<Uint8List> Function(Uint8List jpeg) _encode;

  Future<PhotoResult> process(CapturedImage image) async {
    final Uint8List jpeg;
    final FaceScan scan;
    try {
      jpeg = await _encode(image.bytes);
      scan = await _faces.scanPhoto(jpeg, scratchPath: '${image.path}.check.jpg');
    } catch (_) {
      return const PhotoRejected(PhotoProblem.checkFailed);
    }
    final problem = PhotoProblem.of(scan.quality);
    if (problem != null) return PhotoRejected(problem);
    return PhotoAccepted(PunchPhoto(jpeg: jpeg, takenAt: image.takenAt, faces: 1));
  }
}
