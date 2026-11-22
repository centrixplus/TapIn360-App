import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/photo/camera_session.dart';
import 'package:nfc_attendance/core/photo/face_quality.dart';
import 'package:nfc_attendance/core/photo/photo_processor.dart';
import 'package:nfc_attendance/core/photo/punch_photo.dart';

import '../../helpers/face_fixtures.dart';
import '../../helpers/photo_fakes.dart';

void main() {
  final shot = CapturedImage(
    path: '/tmp/a.jpg',
    bytes: fakeJpeg,
    takenAt: DateTime.utc(2026, 11, 17, 6, 2, 13),
  );
  var encodes = 0;
  Future<Uint8List> encode(Uint8List b) {
    encodes++;
    return fakeEncode(b);
  }

  setUp(() => encodes = 0);

  test('one good face → compressed PunchPhoto; the face check sees that same JPEG', () async {
    final finder = FakeFaceFinder([goodScan]);
    final result = await PhotoProcessor(faces: finder, encode: encode).process(shot);
    final photo = (result as PhotoAccepted).photo;
    expect(photo.faces, 1);
    expect(photo.mime, 'image/jpeg');
    expect(photo.jpeg, await fakeEncode(fakeJpeg));
    expect(photo.takenAt, shot.takenAt);
    expect(encodes, 1);
    expect(finder.jpegs.single, await fakeEncode(fakeJpeg), reason: 'the face check sees the uploaded photo');
    expect(finder.scratchPaths.single, '/tmp/a.jpg.check.jpg', reason: 'scratch copy next to the camera file');
  });

  final rejections = {
    'no face': (noFaceScan, PhotoProblem.noFace),
    'two faces': (twoFacesScan, PhotoProblem.tooManyFaces),
    'half face at the edge': (halfFaceScan, PhotoProblem.notWhole),
    'far face': (farFaceScan, PhotoProblem.tooFar),
    'turned head': (turnedFaceScan, PhotoProblem.notFacing),
  };
  for (final MapEntry(key: name, value: (scan, problem)) in rejections.entries) {
    test('$name → rejected as ${problem.name}', () async {
      final result = await PhotoProcessor(faces: FakeFaceFinder([scan]), encode: encode).process(shot);
      expect((result as PhotoRejected).problem, problem);
    });
  }

  test('every face verdict maps to a problem, and only ok to none', () {
    for (final quality in FaceQuality.values) {
      expect(PhotoProblem.of(quality) == null, quality == FaceQuality.ok, reason: quality.name);
    }
  });

  test('face detector or compression failure → check failed (retry)', () async {
    final failing = FakeFaceFinder([goodScan])..error = StateError('ml kit');
    expect(
      ((await PhotoProcessor(faces: failing, encode: encode).process(shot)) as PhotoRejected).problem,
      PhotoProblem.checkFailed,
    );
    Future<Uint8List> badEncode(Uint8List b) async => throw const FormatException('x');
    final finder = FakeFaceFinder([goodScan]);
    expect(
      ((await PhotoProcessor(faces: finder, encode: badEncode).process(shot)) as PhotoRejected).problem,
      PhotoProblem.checkFailed,
    );
    expect(finder.photoCalls, 0, reason: 'nothing to check without a JPEG');
  });

  test('PunchPhoto JSON matches §15.1', () {
    final photo = PunchPhoto(
      jpeg: Uint8List.fromList([1, 2, 3]),
      takenAt: DateTime.utc(2026, 11, 17, 6, 2, 13),
      faces: 1,
    );
    final json = photo.toJson();
    expect(json['mime'], 'image/jpeg');
    expect(json['data'], base64Encode([1, 2, 3]));
    expect(json['faces'], 1);
    expect(DateTime.parse(json['taken_at']! as String), DateTime.utc(2026, 11, 17, 6, 2, 13));
    expect(json['taken_at'], matches(RegExp(r'[+-]\d\d:\d\d$')));
  });
}
