/// A widget that pulses to demand attention (field backlog #13).
///
/// Used for degraded drones on the map. The operator's complaint was that
/// a node on LoRa fallback looked like any other marker: a static red
/// aeroplane on a map already carrying victims, rescuers and placements is
/// not something the eye finds. Motion is: peripheral vision is far better
/// at detecting change than at detecting colour.
///
/// It stops the moment the node recovers, because the caller simply stops
/// wrapping it. Nothing here has to be told to stop blinking, which is the
/// bug this shape avoids.
library;

import 'package:flutter/material.dart';

class Blinking extends StatefulWidget {
  const Blinking({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 900),
    this.minOpacity = 0.25,
  });

  final Widget child;
  final Duration period;
  final double minOpacity;

  @override
  State<Blinking> createState() => _BlinkingState();
}

class _BlinkingState extends State<Blinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // Never fades fully out. A marker that disappears entirely reads as
      // "gone" rather than "in trouble", which is the opposite of the
      // message.
      opacity: Tween<double>(begin: widget.minOpacity, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}
