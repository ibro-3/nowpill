import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:motor/motor.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_scheme_provider.dart';
import '../../../domain/streak_engine.dart';

/// Displays the freeze-token wallet: a row of ❄ slots (filled = available)
/// plus a progress hint toward the next token. Newly earned tokens pop in.
class TokenWallet extends StatefulWidget {
  const TokenWallet({required this.tokens, super.key});

  final int tokens;

  @override
  State<TokenWallet> createState() => _TokenWalletState();
}

class _TokenWalletState extends State<TokenWallet>
    with SingleTickerProviderStateMixin {
  late final SingleMotionController _pop;
  late int _previous;

  @override
  void initState() {
    super.initState();
    _previous = widget.tokens;
    _pop = SingleMotionController(
      motion: MotionTokens.expressive.spatialFast,
      vsync: this,
      initialValue: 1,
    );
  }

  @override
  void didUpdateWidget(TokenWallet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tokens > _previous) {
      _pop
        ..value = 0
        ..animateTo(1);
    }
    _previous = widget.tokens;
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final tokens = MotionScope.of(context);
    _pop.motion = tokens.spatialFast;

    return AnimatedBuilder(
      animation: _pop,
      builder: (context, _) {
        final pop = _pop.value.clamp(0.0, 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < maxTokens; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _TokenSlot(
                  filled: i < widget.tokens,
                  // The newest filled slot pops when a token is earned.
                  scale: (i == widget.tokens - 1) ? 0.5 + 0.5 * pop : 1.0,
                  theme: theme,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TokenSlot extends StatelessWidget {
  const _TokenSlot({
    required this.filled,
    required this.scale,
    required this.theme,
  });

  final bool filled;
  final double scale;
  final M3EThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: filled
                ? theme.colorScheme.tertiary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Icon(
          M3EIcons.ac_unit,
          size: 15,
          color: filled
              ? theme.colorScheme.onTertiaryContainer
              : theme.colorScheme.outline,
        ),
      ),
    );
  }
}
