import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'camera_session.dart';

/// [CameraSession] over the `camera` plugin: the front camera only (no
/// gallery), medium resolution (it is resized to 640 px anyway). Preview
/// frames stream as NV21 (Android) / BGRA (iOS), the formats ML Kit reads.
class CameraPluginSession implements CameraSession {
  /// Set only once initialised, so [close] disposes exactly what is open.
  CameraController? _controller;

  /// The controller being initialised; [close] clears it to abandon it.
  CameraController? _opening;

  static const _deniedCodes = {'CameraAccessDenied', 'CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted'};

  /// A controller whose initialize() fails is disposed (it holds the camera
  /// and a texture), and so is one the screen closed while it initialised.
  @override
  Future<void> open() async {
    try {
      await close(); // reopening (Try again, app resumed): never two controllers
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      if (front == null) throw const CameraUnavailable(CameraProblem.noFrontCamera, 'no front camera');
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      _opening = controller;
      try {
        await controller.initialize();
      } catch (_) {
        if (identical(_opening, controller)) _opening = null;
        await controller.dispose();
        rethrow;
      }
      if (!identical(_opening, controller)) {
        await controller.dispose();
        throw const CameraUnavailable(CameraProblem.failed, 'closed while opening');
      }
      _opening = null;
      _controller = controller;
    } on CameraException catch (e) {
      final problem = _deniedCodes.contains(e.code) ? CameraProblem.permissionDenied : CameraProblem.failed;
      throw CameraUnavailable(problem, e.description ?? e.code);
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const SizedBox.shrink();
    return CameraPreview(controller);
  }

  @override
  Future<CapturedImage> capture() async {
    final file = await _controller!.takePicture();
    return CapturedImage(path: file.path, bytes: await file.readAsBytes(), takenAt: DateTime.now());
  }

  @override
  Future<bool> startFrames(void Function(PreviewFrame frame) onFrame) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !controller.supportsImageStreaming()) {
      return false;
    }
    if (controller.value.isStreamingImages) return true;
    try {
      await controller.startImageStream((image) {
        final frame = _frame(controller, image);
        if (frame != null) onFrame(frame);
      });
      return true;
    } on CameraException {
      return false;
    }
  }

  @override
  Future<void> stopFrames() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !controller.value.isStreamingImages) return;
    try {
      await controller.stopImageStream();
    } on CameraException {
      // Already stopped or disposed: nothing left to stop.
    }
  }

  /// Device orientation → degrees, as in the ML Kit camera sample.
  static const _deviceDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Android delivers buffers in sensor orientation, so the detector is told
  /// how far to turn them; iOS buffers arrive upright.
  static PreviewFrame? _frame(CameraController controller, CameraImage image) {
    if (image.planes.length != 1) return null;
    final int rotation;
    final PreviewFormat format;
    if (Platform.isAndroid) {
      if (image.format.group != ImageFormatGroup.nv21) return null;
      final device = _deviceDegrees[controller.value.deviceOrientation] ?? 0;
      final sensor = controller.description.sensorOrientation;
      rotation = controller.description.lensDirection == CameraLensDirection.front
          ? (sensor + device) % 360
          : (sensor - device + 360) % 360;
      format = PreviewFormat.nv21;
    } else {
      if (image.format.group != ImageFormatGroup.bgra8888) return null;
      rotation = 0;
      format = PreviewFormat.bgra8888;
    }
    final plane = image.planes.single;
    return PreviewFrame(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotation: rotation,
      format: format,
    );
  }

  @override
  Future<void> discard(CapturedImage image) async {
    try {
      await File(image.path).delete();
    } catch (_) {
      // Already gone; the OS clears the cache directory anyway.
    }
  }

  @override
  Future<void> close() async {
    _opening = null; // an open() in flight disposes its controller itself
    await stopFrames();
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
