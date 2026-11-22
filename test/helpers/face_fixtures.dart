import 'dart:ui';

import 'package:nfc_attendance/core/photo/face_finder.dart';
import 'package:nfc_attendance/core/photo/face_quality.dart';

/// The upload photo of a portrait selfie (640 px long side).
const photoSize = Size(480, 640);

/// A synthetic face: centred, 50 % of the width, looking straight at the
/// camera, all landmarks where a real face has them. Pass [box] to move or
/// resize it (landmarks follow the box) and [without] to drop landmarks.
FaceInfo face({
  Rect box = const Rect.fromLTWH(120, 170, 240, 300),
  double? yaw = 0,
  double? roll = 0,
  double? pitch = 0,
  Set<FaceLandmarkKind> without = const {},
  Map<FaceLandmarkKind, Offset> moved = const {},
}) {
  Offset at(double fx, double fy) => Offset(box.left + fx * box.width, box.top + fy * box.height);
  final marks = {
    FaceLandmarkKind.leftEye: at(0.32, 0.38),
    FaceLandmarkKind.rightEye: at(0.68, 0.38),
    FaceLandmarkKind.noseBase: at(0.5, 0.62),
    FaceLandmarkKind.leftMouth: at(0.36, 0.78),
    FaceLandmarkKind.rightMouth: at(0.64, 0.78),
    FaceLandmarkKind.bottomMouth: at(0.5, 0.84),
  }..addAll(moved);
  marks.removeWhere((kind, _) => without.contains(kind));
  return FaceInfo(box: box, yaw: yaw, roll: roll, pitch: pitch, landmarks: marks);
}

FaceScan scanOf(List<FaceInfo> faces, [Size size = photoSize]) => FaceScan(faces, size);

final goodScan = scanOf([face()]);
final noFaceScan = scanOf(const []);
final twoFacesScan = scanOf([
  face(box: const Rect.fromLTWH(30, 200, 180, 220)),
  face(box: const Rect.fromLTWH(270, 200, 180, 220)),
]);

/// Half the face past the left edge: the case that used to pass.
final halfFaceScan = scanOf([face(box: const Rect.fromLTWH(-120, 170, 240, 300))]);
final farFaceScan = scanOf([face(box: const Rect.fromLTWH(195, 260, 90, 110))]);
final turnedFaceScan = scanOf([face(yaw: 38)]);
