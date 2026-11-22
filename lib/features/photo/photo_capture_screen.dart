import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../../core/photo/camera_session.dart';
import '../../core/photo/face_finder.dart';
import '../../core/photo/face_quality.dart';
import '../../core/photo/photo_processor.dart';
import '../../core/photo/punch_photo.dart';
import '../common/tapin_widgets.dart';

enum _Phase { opening, countdown, checking, failed, unavailable }

/// Full-screen front camera for the tap photo (spec §15.3): 3 s countdown
/// with automatic capture plus a shutter button, on-device face check
/// ([evaluateFaces]: one whole face, close, facing the camera), retry on
/// failure. During the countdown, preview frames are checked with the same
/// rule so the chip says what to fix and the oval turns green when the face
/// is good. Pops the [PunchPhoto], or null when the employee cancels (the tap
/// is then discarded).
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({
    super.key,
    required this.camera,
    required this.faceFinder,
    required this.encode,
    this.onOpenSettings,
    this.countdownSeconds = 3,
    this.cardReadAt,
  });

  final CameraSession camera;
  final FaceFinder faceFinder;
  final Future<Uint8List> Function(Uint8List jpeg) encode;

  /// Opens the app's system settings (camera permission refused).
  final VoidCallback? onOpenSettings;
  final int countdownSeconds;

  /// When the card was read ("Card read at 08:02").
  final DateTime? cardReadAt;

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> with WidgetsBindingObserver {
  /// One live frame at most every [_frameGap] (plus the scan itself).
  static const _frameGap = Duration(milliseconds: 300);

  late final _processor = PhotoProcessor(faces: widget.faceFinder, encode: widget.encode);
  _Phase _phase = _Phase.opening;
  int _remaining = 0;
  Timer? _timer;
  String? _message;

  /// Live verdict on the preview; null until a frame has been checked.
  FaceQuality? _live;
  bool _frameBusy = false;
  Timer? _frameCooldown;
  CameraProblem? _cameraProblem;
  bool _closedByPause = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _frameCooldown?.cancel();
    unawaited(widget.camera.close());
    unawaited(widget.faceFinder.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_closedByPause) {
      _timer?.cancel();
      _closedByPause = true;
      unawaited(widget.camera.close());
    } else if (state == AppLifecycleState.resumed && _closedByPause) {
      _closedByPause = false;
      _open();
    }
  }

  Future<void> _open() async {
    setState(() => _phase = _Phase.opening);
    try {
      await widget.camera.open();
    } on CameraUnavailable catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.unavailable;
          _cameraProblem = e.problem;
        });
      }
      return;
    }
    if (mounted) _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.countdown;
      _remaining = widget.countdownSeconds;
      _message = null;
      _live = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        _capture();
      } else {
        setState(() => _remaining--);
      }
    });
    unawaited(_startGuidance());
  }

  Future<void> _startGuidance() async {
    try {
      await widget.camera.startFrames(_onFrame);
    } catch (_) {
      // No live guidance on this phone; the photo is still checked.
    }
  }

  void _onFrame(PreviewFrame frame) {
    if (_frameBusy || _phase != _Phase.countdown || !mounted) return;
    _frameBusy = true;
    unawaited(_checkFrame(frame));
  }

  Future<void> _checkFrame(PreviewFrame frame) async {
    try {
      final quality = (await widget.faceFinder.scanFrame(frame)).quality;
      if (mounted && _phase == _Phase.countdown && quality != _live) setState(() => _live = quality);
    } catch (_) {
      // Guidance only: the photo check decides.
    } finally {
      _frameCooldown?.cancel();
      if (mounted) _frameCooldown = Timer(_frameGap, () => _frameBusy = false);
    }
  }

  Future<void> _stopGuidance() async {
    try {
      await widget.camera.stopFrames();
    } catch (_) {
      // Nothing streaming.
    }
  }

  Future<void> _capture() async {
    if (_phase == _Phase.checking || _done) return;
    _timer?.cancel();
    setState(() {
      _phase = _Phase.checking;
      _live = null;
    });
    await _stopGuidance();
    final CapturedImage shot;
    try {
      shot = await widget.camera.capture();
    } catch (_) {
      _fail('photo.check_failed'.tr());
      return;
    }
    final result = await _processor.process(shot);
    unawaited(widget.camera.discard(shot));
    if (!mounted) return;
    switch (result) {
      case PhotoAccepted(:final photo):
        _finish(photo);
      case PhotoRejected(:final problem):
        _fail(_problemText(problem));
    }
  }

  String _problemText(PhotoProblem problem) => switch (problem) {
    PhotoProblem.noFace => 'photo.no_face'.tr(),
    PhotoProblem.tooManyFaces => 'photo.many_faces'.tr(),
    PhotoProblem.notWhole => 'photo.whole_face'.tr(),
    PhotoProblem.tooFar => 'photo.move_closer'.tr(),
    PhotoProblem.notFacing => 'photo.face_camera'.tr(),
    PhotoProblem.checkFailed => 'photo.check_failed'.tr(),
  };

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  void _finish(PunchPhoto? photo) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    Navigator.of(context).pop(photo);
  }

  @override
  Widget build(BuildContext context) {
    final arabic = isArabic(context);
    final white = TapInText.body(arabic: arabic).copyWith(color: TapInColors.surfaceRaised);
    final showPreview = _phase != _Phase.opening && _phase != _Phase.unavailable;
    final readAt = widget.cardReadAt;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(null);
      },
      child: Scaffold(
        backgroundColor: TapInColors.ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(TapInSpace.gutter, 20, TapInSpace.gutter, 24),
            child: Column(
              children: [
                Text(
                  'photo.title'.tr(),
                  textAlign: TextAlign.center,
                  style: TapInText.heading(arabic: arabic).copyWith(color: TapInColors.surfaceRaised),
                ),
                if (readAt != null) ...[
                  const SizedBox(height: TapInSpace.s1),
                  Text(
                    'photo.card_read'.tr(
                      namedArgs: {
                        'time': DateFormat.Hm(context.locale.languageCode).format(readAt.toLocal()),
                      },
                    ),
                    textAlign: TextAlign.center,
                    style: TapInText.tabular(white.copyWith(fontSize: 15)),
                  ),
                ],
                const SizedBox(height: 20),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(TapInRadius.lg),
                    child: ColoredBox(
                      color: TapInColors.cameraWell,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (showPreview) _CoverPreview(child: widget.camera.preview()),
                          if (showPreview)
                            IgnorePointer(
                              child: _FaceGuide(good: _phase == _Phase.countdown && _live == FaceQuality.ok),
                            ),
                          if (showPreview)
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: Center(child: Semantics(liveRegion: true, child: _chip())),
                            ),
                          Positioned(left: 16, right: 16, bottom: 20, child: Center(child: _bottomOfWell())),
                          if (!showPreview) Center(child: _centerOfWell()),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: TapInColors.surfaceRaised,
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          onPressed: () => _finish(null),
                          child: Text('common.cancel'.tr()),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: showPreview
                            ? _Shutter(onPressed: _canShoot ? _capture : null)
                            : const SizedBox(height: 76),
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        'photo.front'.tr(),
                        textAlign: TextAlign.end,
                        style: white.copyWith(fontSize: 13, height: 18 / 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _canShoot => _phase == _Phase.countdown || _phase == _Phase.failed;

  Widget _chip() {
    return switch (_phase) {
      _Phase.failed => Pill(
        text: _message ?? '',
        icon: Icons.error_outline_rounded,
        foreground: TapInColors.ink,
        iconColor: TapInColors.warning,
        background: TapInColors.warningTint,
      ),
      _Phase.checking => Pill(
        text: 'photo.checking'.tr(),
        icon: Icons.hourglass_top_rounded,
        foreground: TapInColors.ink,
      ),
      _ => _liveChip(),
    };
  }

  /// Countdown chip: the instruction until a frame is checked, then what to
  /// fix, or "Hold still" once the face is good.
  Widget _liveChip() {
    final live = _live;
    if (live == null) {
      return Pill(text: 'photo.face_chip'.tr(), icon: Icons.face_rounded, foreground: TapInColors.ink);
    }
    final problem = PhotoProblem.of(live);
    if (problem == null) {
      return Pill(
        key: const Key('photo.live_ok'),
        text: 'photo.face_ok'.tr(),
        icon: Icons.check_circle_rounded,
        foreground: TapInColors.ink,
        iconColor: TapInColors.successStrong,
      );
    }
    return Pill(
      key: const Key('photo.live_hint'),
      text: _problemText(problem),
      icon: Icons.info_outline_rounded,
      foreground: TapInColors.ink,
      iconColor: TapInColors.warning,
      background: TapInColors.warningTint,
    );
  }

  Widget _bottomOfWell() {
    switch (_phase) {
      case _Phase.countdown:
        return Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(color: TapInColors.surfaceRaised, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            '$_remaining',
            style: TapInText.tabular(
              const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: TapInColors.ink),
            ),
          ),
        );
      case _Phase.checking:
        return const SizedBox.square(
          dimension: 48,
          child: CircularProgressIndicator(color: TapInColors.surfaceRaised, strokeWidth: 3),
        );
      case _Phase.failed:
        return FilledButton.icon(
          onPressed: _startCountdown,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('photo.try_again'.tr()),
        );
      case _Phase.opening || _Phase.unavailable:
        return const SizedBox.shrink();
    }
  }

  Widget _centerOfWell() {
    if (_phase == _Phase.opening) return const CircularProgressIndicator(color: TapInColors.surfaceRaised);
    final (message, button, action) = switch (_cameraProblem) {
      CameraProblem.permissionDenied => (
        'photo.camera_denied'.tr(),
        widget.onOpenSettings == null ? null : 'banner.open_settings'.tr(),
        widget.onOpenSettings,
      ),
      CameraProblem.noFrontCamera => ('photo.no_camera'.tr(), null, null),
      _ => ('photo.camera_failed'.tr(), 'photo.try_again'.tr(), _open),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TapInText.body(arabic: isArabic(context)).copyWith(color: TapInColors.surfaceRaised),
          ),
          if (button != null) ...[
            const SizedBox(height: TapInSpace.s4),
            FilledButton(onPressed: action, child: Text(button)),
          ],
        ],
      ),
    );
  }
}

/// Fills the well with the preview (cropped, not stretched).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: constraints.maxWidth, child: child),
      ),
    );
  }
}

/// White ring shutter (76 px).
class _Shutter extends StatelessWidget {
  const _Shutter({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'photo.take'.tr(),
      child: InkResponse(
        key: const Key('photo.shutter'),
        onTap: onPressed,
        radius: 44,
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: TapInColors.surfaceRaised, width: 4),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(color: TapInColors.surfaceRaised, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

/// Oval outline where the face should be (220 × 290): white, green while the
/// live check finds a good face.
class _FaceGuide extends StatelessWidget {
  const _FaceGuide({required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        key: const Key('photo.face_guide'),
        duration: const Duration(milliseconds: 200),
        width: 220,
        height: 290,
        decoration: ShapeDecoration(
          shape: OvalBorder(
            side: BorderSide(color: good ? TapInColors.success : TapInColors.surfaceRaised, width: 4),
          ),
        ),
      ),
    );
  }
}
