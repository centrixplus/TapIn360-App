import 'dart:typed_data';

import 'package:flutter/widgets.dart';

enum CameraProblem { permissionDenied, noFrontCamera, failed }

class CameraUnavailable implements Exception {
  const CameraUnavailable(this.problem, this.message);

  final CameraProblem problem;
  final String message;

  @override
  String toString() => 'CameraUnavailable($problem, $message)';
}

/// A still from the camera: the file (for the face detector) and its bytes.
class CapturedImage {
  const CapturedImage({required this.path, required this.bytes, required this.takenAt});

  final String path;
  final Uint8List bytes;
  final DateTime takenAt;
}

enum PreviewFormat { nv21, bgra8888 }

/// One live preview frame, in the form the face detector reads it.
class PreviewFrame {
  const PreviewFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotation,
    required this.format,
  });

  final Uint8List bytes;

  /// Buffer size as the camera delivers it (sensor orientation).
  final int width;
  final int height;
  final int bytesPerRow;

  /// Degrees (0, 90, 180, 270) the detector turns the buffer to make it
  /// upright (ML Kit `InputImageRotation`).
  final int rotation;
  final PreviewFormat format;

  /// The upright frame: the space the detector reports face boxes in.
  Size get uprightSize => rotation == 90 || rotation == 270
      ? Size(height.toDouble(), width.toDouble())
      : Size(width.toDouble(), height.toDouble());
}

/// The front camera, behind an interface so the capture screen is testable.
abstract interface class CameraSession {
  /// Throws [CameraUnavailable].
  Future<void> open();
  Widget preview();
  Future<CapturedImage> capture();

  /// Hands live preview frames to [onFrame] (face guidance) until
  /// [stopFrames]. False when this camera cannot stream; the photo is still
  /// checked after capture.
  Future<bool> startFrames(void Function(PreviewFrame frame) onFrame);

  /// Stops [startFrames]; does nothing when not streaming.
  Future<void> stopFrames();

  /// Deletes the raw camera file once it has been processed.
  Future<void> discard(CapturedImage image);
  Future<void> close();
}
