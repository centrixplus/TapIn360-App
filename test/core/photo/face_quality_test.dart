import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/photo/face_quality.dart';

import '../../helpers/face_fixtures.dart';

void main() {
  FaceQuality check(List<FaceInfo> faces) => evaluateFaces(faces, photoSize);

  // photoSize is 480 × 640: the 3 % margin is 14.4 px across and 19.2 px down,
  // 25 % of the width is 120 px, 15 % is 72 px.

  test('a centred, close, straight face with all landmarks is accepted', () {
    expect(check([face()]), FaceQuality.ok);
  });

  group('exactly one face', () {
    test('no face → no face found', () {
      expect(check(const []), FaceQuality.noFace);
      expect(evaluateFaces([face()], Size.zero), FaceQuality.noFace, reason: 'no image size → nothing to judge');
    });

    test('two faces → only one face, please', () {
      expect(twoFacesScan.quality, FaceQuality.tooManyFaces);
    });

    test('a second face that is itself cut by the edge still counts', () {
      expect(
        check([face(), face(box: const Rect.fromLTWH(-60, 200, 120, 160))]),
        FaceQuality.tooManyFaces,
      );
    });

    test('a small face far in the background (< 15 % wide) is not a second face', () {
      expect(check([face(), face(box: const Rect.fromLTWH(400, 40, 60, 75))]), FaceQuality.ok);
    });
  });

  group('the whole face inside the image', () {
    test('half a face past the left edge → show your whole face', () {
      expect(halfFaceScan.quality, FaceQuality.notWhole);
    });

    test('a face box clipped at the left edge (x = 0) → show your whole face', () {
      expect(check([face(box: const Rect.fromLTWH(0, 170, 200, 300))]), FaceQuality.notWhole);
    });

    test('a face cut by the right, top or bottom edge → show your whole face', () {
      expect(check([face(box: const Rect.fromLTWH(300, 170, 240, 300))]), FaceQuality.notWhole, reason: 'right');
      expect(check([face(box: const Rect.fromLTWH(120, -90, 240, 300))]), FaceQuality.notWhole, reason: 'top');
      expect(check([face(box: const Rect.fromLTWH(120, 420, 240, 300))]), FaceQuality.notWhole, reason: 'bottom');
    });

    test('margin is 3 % of each side: just inside passes, just outside fails', () {
      expect(check([face(box: const Rect.fromLTRB(15, 20, 255, 320))]), FaceQuality.ok, reason: 'top-left');
      expect(check([face(box: const Rect.fromLTRB(225, 320, 465, 620))]), FaceQuality.ok, reason: 'bottom-right');
      expect(check([face(box: const Rect.fromLTRB(14, 170, 254, 470))]), FaceQuality.notWhole);
      expect(check([face(box: const Rect.fromLTRB(226, 170, 466, 470))]), FaceQuality.notWhole);
      expect(check([face(box: const Rect.fromLTRB(120, 19, 360, 319))]), FaceQuality.notWhole);
      expect(check([face(box: const Rect.fromLTRB(120, 321, 360, 621))]), FaceQuality.notWhole);
    });
  });

  group('close enough (face ≥ 25 % of the width)', () {
    test('a small far face → move closer', () {
      expect(farFaceScan.quality, FaceQuality.tooFar);
    });

    test('a lone face below the background size still gets "move closer", not "no face"', () {
      expect(check([face(box: const Rect.fromLTWH(210, 280, 60, 75))]), FaceQuality.tooFar);
    });

    test('exactly 25 % passes, just under fails', () {
      expect(check([face(box: const Rect.fromLTWH(180, 250, 120, 150))]), FaceQuality.ok);
      expect(check([face(box: const Rect.fromLTWH(180, 250, 119, 150))]), FaceQuality.tooFar);
    });
  });

  group('facing the camera (|yaw|, |roll|, |pitch| ≤ 20°)', () {
    test('head turned to either side → face the camera', () {
      expect(turnedFaceScan.quality, FaceQuality.notFacing);
      expect(check([face(yaw: -25)]), FaceQuality.notFacing);
    });

    test('head tilted towards a shoulder → face the camera', () {
      expect(check([face(roll: 30)]), FaceQuality.notFacing);
      expect(check([face(roll: -21)]), FaceQuality.notFacing);
    });

    test('head tipped down or up → face the camera', () {
      expect(check([face(pitch: -30)]), FaceQuality.notFacing);
      expect(check([face(pitch: 24)]), FaceQuality.notFacing);
    });

    test('20° on every axis is still accepted', () {
      expect(check([face(yaw: 20, roll: -20, pitch: 20)]), FaceQuality.ok);
      expect(check([face(yaw: -19.5, roll: 12, pitch: -15)]), FaceQuality.ok);
    });

    test('an angle the detector did not measure is not held against the photo', () {
      expect(check([face(yaw: null, roll: null, pitch: null)]), FaceQuality.ok);
    });
  });

  group('landmarks present and inside the image', () {
    for (final kind in FaceLandmarkKind.values) {
      test('${kind.name} missing → show your whole face', () {
        expect(check([face(without: {kind})]), FaceQuality.notWhole);
      });
    }

    test('no landmarks at all → show your whole face', () {
      final bare = FaceInfo(box: const Rect.fromLTWH(120, 170, 240, 300), yaw: 0, roll: 0, pitch: 0);
      expect(check([bare]), FaceQuality.notWhole);
    });

    test('a landmark reported outside the image → show your whole face', () {
      expect(check([face(moved: {FaceLandmarkKind.leftEye: const Offset(-8, 280)})]), FaceQuality.notWhole);
      expect(check([face(moved: {FaceLandmarkKind.bottomMouth: const Offset(240, 655)})]), FaceQuality.notWhole);
    });
  });

  group('which reason wins when several apply', () {
    test('half face that is also turned → show your whole face (edge first)', () {
      expect(check([face(box: const Rect.fromLTWH(-120, 170, 240, 300), yaw: 45)]), FaceQuality.notWhole);
    });

    test('far face that is also turned and missing landmarks → move closer', () {
      expect(
        check([face(box: const Rect.fromLTWH(195, 260, 90, 110), yaw: 30, without: {FaceLandmarkKind.rightEye})]),
        FaceQuality.tooFar,
      );
    });

    test('turned face missing the far eye → face the camera (pose before landmarks)', () {
      expect(check([face(yaw: 40, without: {FaceLandmarkKind.rightEye})]), FaceQuality.notFacing);
    });

    test('two faces, one of them half → only one face, please', () {
      final other = face(box: const Rect.fromLTWH(250, 170, 200, 260));
      expect(check([halfFaceScan.faces.single, other]), FaceQuality.tooManyFaces);
    });
  });
}
