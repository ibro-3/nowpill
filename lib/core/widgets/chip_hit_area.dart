import 'package:flutter/widgets.dart';

/// Gives an M3E chip's 32dp visual a 48dp tap target.
///
/// From M3: touch targets must be at least 48 × 48dp; the visible chip may stay
/// smaller. The chip stays on top and keeps its own gesture, semantics and
/// keyboard activation. The transparent layer *behind* it catches taps in the
/// surrounding padding and forwards them to the same callback. Because the
/// layers are stacked, a tap is claimed by exactly one of them.
class ChipHitArea extends StatelessWidget {
  const ChipHitArea({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
