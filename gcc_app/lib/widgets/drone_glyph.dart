/// A drawn quadcopter, used as the picture on node cards (field backlog
/// #6, "cards should have drone images").
///
/// Drawn rather than shipped as a photo, for two reasons that are really
/// one reason. There is no internet at a deployment, so any image has to
/// live in the binary; and a photo of a drone in the binary is a photo of
/// SOME drone, which is misleading the moment a volunteer turns up with a
/// different airframe. A schematic top view says "this is a drone in the
/// fleet" without claiming to be a portrait of it.
///
/// The colour carries the state, so the picture is not decoration: a
/// glance at the card tells you healthy, stale or degraded before you have
/// read a single number.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class DroneGlyph extends StatelessWidget {
  const DroneGlyph({
    super.key,
    required this.color,
    this.size = 56,
    this.dimmed = false,
  });

  final Color color;
  final double size;

  /// Draws the rotors as dashed outlines instead of solid rings, for a node
  /// we are no longer hearing from. Deliberately visible at a glance: a
  /// drone we have lost contact with should not look identical to one we
  /// are talking to.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DronePainter(color: color, dimmed: dimmed),
      ),
    );
  }
}

class _DronePainter extends CustomPainter {
  _DronePainter({required this.color, required this.dimmed});

  final Color color;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final arm = r * 0.62;
    final rotor = r * 0.30;

    final stroke = Paint()
      ..color = color.withValues(alpha: dimmed ? 0.55 : 1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, size.width / 28)
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = color.withValues(alpha: dimmed ? 0.12 : 0.22)
      ..style = PaintingStyle.fill;

    // Four arms on the diagonals, which is what a quadcopter looks like
    // from above and what nobody mistakes for anything else.
    for (var i = 0; i < 4; i++) {
      final a = math.pi / 4 + i * math.pi / 2;
      final hub = Offset(c.dx + arm * math.cos(a), c.dy + arm * math.sin(a));
      canvas.drawLine(c, hub, stroke);
      if (dimmed) {
        _dashedCircle(canvas, hub, rotor, stroke);
      } else {
        canvas.drawCircle(hub, rotor, fill);
        canvas.drawCircle(hub, rotor, stroke);
      }
    }

    // Body, slightly taller than wide so the nose direction reads.
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: r * 0.52, height: r * 0.72),
      Radius.circular(r * 0.16),
    );
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);
  }

  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint p) {
    const segments = 12;
    for (var i = 0; i < segments; i += 2) {
      final start = i * 2 * math.pi / segments;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        2 * math.pi / segments,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DronePainter old) =>
      old.color != color || old.dimmed != dimmed;
}
