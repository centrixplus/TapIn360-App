import 'dart:ui';

/// The face points the photo rule needs (ML Kit landmark names).
enum FaceLandmarkKind { leftEye, rightEye, noseBase, leftMouth, rightMouth, bottomMouth }

/// One face from the detector, in the pixels of the image it was found in
/// (origin top-left, image upright). Free of ML Kit types so [evaluateFaces]
/// can be tested with made-up faces.
class FaceInfo {
  const FaceInfo({required this.box, this.yaw, this.roll, this.pitch, this.landmarks = const {}});

  final Rect box;

  /// Head turned left/right (ML Kit `headEulerAngleY`), degrees. Null: not measured.
  final double? yaw;

  /// Head tilted towards a shoulder (`headEulerAngleZ`), degrees.
  final double? roll;

  /// Head tipped up/down (`headEulerAngleX`), degrees.
  final double? pitch;

  /// Landmarks the detector found; a missing key means it was not found.
  final Map<FaceLandmarkKind, Offset> landmarks;
}

/// Why a photo (or a live preview frame) is not good enough, or [ok].
enum FaceQuality { ok, noFace, tooManyFaces, notWhole, tooFar, notFacing }

/// The face box must keep this fraction of the image side free on every edge:
/// a face cut by the frame (the "half face") touches or crosses an edge.
const faceEdgeMargin = 0.03;

/// Smallest accepted face width, as a fraction of the image width.
///
/// A portrait front camera sees roughly 45–55° across. Face width (ML Kit box,
/// about 15 cm) at a normal selfie distance of 40–50 cm is 30–40 % of the
/// width; 25 % is a fully stretched arm (about 60 cm). Below that the face in
/// the 640 px upload (427–480 px wide) is under 110–120 px, near ML Kit's
/// 100 px floor for reliable landmarks and too small to recognise the person.
/// The on-screen oval is about half the photo width, so anyone following it
/// passes with room to spare.
const minFaceWidth = 0.25;

/// Faces narrower than this are people in the background: they do not count
/// as a second face (the detector ignored them before this rule existed).
const backgroundFaceWidth = 0.15;

/// The detector reports faces from this width, so a lone small face gets
/// "Move closer" instead of "No face found".
const detectorMinFaceWidth = 0.10;

/// Head pose limits, degrees. Past about 20° of yaw the far cheek and eye start
/// to disappear; 20° of pitch still allows the slight downward look of a phone
/// held at chest height.
const maxYawDegrees = 20.0;
const maxRollDegrees = 20.0;
const maxPitchDegrees = 20.0;

/// The photo rule (spec §15.3, tightened): exactly one face, whole and inside
/// the image, close enough, facing the camera, with both eyes, the nose base
/// and the mouth found inside the image.
///
/// When several things are wrong, the reason that tells the person what to fix
/// first wins: edge → distance → pose → landmarks (small and turned faces lose
/// landmarks, so those reasons come before "show your whole face").
FaceQuality evaluateFaces(List<FaceInfo> faces, Size imageSize) {
  if (faces.isEmpty || imageSize.isEmpty) return FaceQuality.noFace;
  final counted = [
    for (final face in faces)
      if (face.box.width >= backgroundFaceWidth * imageSize.width) face,
  ];
  if (counted.length > 1) return FaceQuality.tooManyFaces;
  final face = counted.isNotEmpty ? counted.single : faces.reduce((a, b) => a.box.width >= b.box.width ? a : b);

  if (!_insideWithMargin(face.box, imageSize)) return FaceQuality.notWhole;
  if (face.box.width < minFaceWidth * imageSize.width) return FaceQuality.tooFar;
  if (_beyond(face.yaw, maxYawDegrees) || _beyond(face.roll, maxRollDegrees) || _beyond(face.pitch, maxPitchDegrees)) {
    return FaceQuality.notFacing;
  }
  for (final kind in FaceLandmarkKind.values) {
    final point = face.landmarks[kind];
    if (point == null || !_inside(point, imageSize)) return FaceQuality.notWhole;
  }
  return FaceQuality.ok;
}

bool _insideWithMargin(Rect box, Size size) {
  final dx = faceEdgeMargin * size.width;
  final dy = faceEdgeMargin * size.height;
  return box.left >= dx && box.top >= dy && box.right <= size.width - dx && box.bottom <= size.height - dy;
}

bool _inside(Offset p, Size size) => p.dx >= 0 && p.dy >= 0 && p.dx <= size.width && p.dy <= size.height;

/// An angle the detector did not measure is not held against the photo.
bool _beyond(double? degrees, double limit) => degrees != null && degrees.abs() > limit;
