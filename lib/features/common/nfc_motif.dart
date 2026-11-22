import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// The TapIn360 NFC motif: a dot and three concentric arcs opening to the right
/// (geometry from the artboard SVG, 120 × 120 view box). Not mirrored in RTL.
class NfcMotif extends StatelessWidget {
  const NfcMotif({super.key, this.size = 104, this.color = TapInColors.surfaceRaised});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _NfcMotifPainter(color));
  }
}

class _NfcMotifPainter extends CustomPainter {
  _NfcMotifPainter(this.color);

  final Color color;

  // Arc end x, half chord, radius (SVG: M x 60-h A r r 0 0 1 x 60+h).
  static const _arcs = [(52.0, 22.0, 32.0), (70.0, 38.0, 54.0), (88.0, 54.0, 76.0)];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 120;
    canvas.drawCircle(Offset(30 * scale, 60 * scale), 9 * scale, Paint()..color = color);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * scale
      ..strokeCap = StrokeCap.round;
    for (final (x, half, r) in _arcs) {
      final cx = x - sqrt(r * r - half * half);
      final theta = asin(half / r);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx * scale, 60 * scale), radius: r * scale),
        -theta,
        2 * theta,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_NfcMotifPainter old) => old.color != color;
}

/// The motif in white on a `primary` circle (tap screen).
class NfcMotifBadge extends StatelessWidget {
  const NfcMotifBadge({super.key, this.size = 176, this.enabled = true});

  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? TapInColors.primary : TapInColors.border,
      ),
      alignment: Alignment.center,
      child: NfcMotif(
        size: size * 104 / 176,
        color: enabled ? TapInColors.surfaceRaised : TapInColors.borderStrong,
      ),
    );
  }
}
