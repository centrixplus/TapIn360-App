import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_session.dart';
import 'face_finder.dart';
import 'face_quality.dart';
import 'photo_compressor.dart';

/// Google ML Kit face detection, offline on the phone (spec §15.3).
///
/// Accurate mode: ML Kit only guarantees the head yaw (Euler Y) there.
/// Landmarks on: the rule needs the eyes, nose base and mouth. Classification
/// (eyes open) stays off: glasses, glare and low light make it unreliable, and
/// a wrong "eyes closed" would block the person's attendance.
class MlKitFaceFinder implements FaceFinder {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      minFaceSize: detectorMinFaceWidth,
    ),
  );

  @override
  Future<FaceScan> scanPhoto(Uint8List jpeg, {required String scratchPath}) async {
    final size = jpegUprightSize(jpeg);
    final file = File(scratchPath);
    await file.writeAsBytes(jpeg, flush: true);
    try {
      final faces = await _detector.processImage(InputImage.fromFilePath(file.path));
      return FaceScan(_infos(faces), Size(size.width.toDouble(), size.height.toDouble()));
    } finally {
      try {
        await file.delete();
      } catch (_) {
        // The OS clears the cache directory anyway.
      }
    }
  }

  @override
  Future<FaceScan> scanFrame(PreviewFrame frame) async {
    final input = InputImage.fromBytes(
      bytes: frame.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(frame.rotation) ?? InputImageRotation.rotation0deg,
        format: switch (frame.format) {
          PreviewFormat.nv21 => InputImageFormat.nv21,
          PreviewFormat.bgra8888 => InputImageFormat.bgra8888,
        },
        bytesPerRow: frame.bytesPerRow,
      ),
    );
    return FaceScan(_infos(await _detector.processImage(input)), frame.uprightSize);
  }

  static const _landmarks = {
    FaceLandmarkKind.leftEye: FaceLandmarkType.leftEye,
    FaceLandmarkKind.rightEye: FaceLandmarkType.rightEye,
    FaceLandmarkKind.noseBase: FaceLandmarkType.noseBase,
    FaceLandmarkKind.leftMouth: FaceLandmarkType.leftMouth,
    FaceLandmarkKind.rightMouth: FaceLandmarkType.rightMouth,
    FaceLandmarkKind.bottomMouth: FaceLandmarkType.bottomMouth,
  };

  static List<FaceInfo> _infos(List<Face> faces) => [
    for (final face in faces)
      FaceInfo(
        box: face.boundingBox,
        yaw: face.headEulerAngleY,
        roll: face.headEulerAngleZ,
        pitch: face.headEulerAngleX,
        landmarks: {
          for (final MapEntry(key: kind, value: type) in _landmarks.entries)
            if (face.landmarks[type] case final mark?)
              kind: Offset(mark.position.x.toDouble(), mark.position.y.toDouble()),
        },
      ),
  ];

  @override
  Future<void> close() => _detector.close();
}
