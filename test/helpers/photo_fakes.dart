import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:nfc_attendance/core/photo/camera_session.dart';
import 'package:nfc_attendance/core/photo/face_finder.dart';

final fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);

class FakeCamera implements CameraSession {
  FakeCamera({this.openError});

  CameraUnavailable? openError;
  int opens = 0;
  int captures = 0;
  int closes = 0;
  final discarded = <String>[];
  DateTime takenAt = DateTime.utc(2026, 11, 17, 6, 2, 13);

  @override
  Future<void> open() async {
    opens++;
    if (openError != null) throw openError!;
  }

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF203040), key: Key('fake.preview'));

  @override
  Future<CapturedImage> capture() async {
    captures++;
    return CapturedImage(path: '/tmp/shot$captures.jpg', bytes: fakeJpeg, takenAt: takenAt);
  }

  /// Live preview frames: on unless [canStream] is false.
  bool canStream = true;
  void Function(PreviewFrame frame)? _onFrame;
  int frameStarts = 0;
  int frameStops = 0;

  bool get streaming => _onFrame != null;

  @override
  Future<bool> startFrames(void Function(PreviewFrame frame) onFrame) async {
    if (!canStream) return false;
    frameStarts++;
    _onFrame = onFrame;
    return true;
  }

  @override
  Future<void> stopFrames() async {
    if (_onFrame != null) frameStops++;
    _onFrame = null;
  }

  /// Delivers one portrait NV21 frame, as Android does (sensor at 270°).
  void sendFrame() => _onFrame?.call(
    PreviewFrame(
      bytes: Uint8List(640 * 480 * 3 ~/ 2),
      width: 640,
      height: 480,
      bytesPerRow: 640,
      rotation: 270,
      format: PreviewFormat.nv21,
    ),
  );

  @override
  Future<void> discard(CapturedImage image) async => discarded.add(image.path);

  @override
  Future<void> close() async {
    closes++;
    _onFrame = null;
  }
}

/// Answers photo scans in order (the last one repeats) and live frames with
/// [frameScan]. Records the JPEGs and scratch paths it was given.
class FakeFaceFinder implements FaceFinder {
  FakeFaceFinder(this.photos, {this.frameScan});

  final List<FaceScan> photos;
  FaceScan? frameScan;
  int photoCalls = 0;
  int frameCalls = 0;
  final jpegs = <Uint8List>[];
  final scratchPaths = <String>[];
  bool closed = false;
  Object? error;

  @override
  Future<FaceScan> scanPhoto(Uint8List jpeg, {required String scratchPath}) async {
    if (error != null) throw error!;
    jpegs.add(jpeg);
    scratchPaths.add(scratchPath);
    final i = photoCalls < photos.length ? photoCalls : photos.length - 1;
    photoCalls++;
    return photos[i];
  }

  @override
  Future<FaceScan> scanFrame(PreviewFrame frame) async {
    frameCalls++;
    final scan = frameScan;
    if (scan == null) throw StateError('no frame scan scripted');
    return scan;
  }

  @override
  Future<void> close() async => closed = true;
}

Future<Uint8List> fakeEncode(Uint8List bytes) async => Uint8List.fromList([0xFF, 0xD8, 9, 9, 0xFF, 0xD9]);
