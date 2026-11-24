import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import '../settings/app_settings_provider.dart';
import 'app_motion.dart';

/// Resolves the active [MotionTokens] from the user's motion preference.
///
/// The OS-level reduce-motion setting is applied separately via
/// [MotionScope] (which ORs it with this preference), so this provider only
/// reflects the explicit user choice.
final motionTokensProvider = Provider<MotionTokens>((ref) {
  final mode = ref.watch(currentSettingsProvider.select((s) => s.motionMode));
  return mode == AppMotionMode.standard
      ? MotionTokens.standard
      : MotionTokens.expressive;
});

/// Provides [MotionTokens] to a subtree, honoring both the user's motion
/// preference and the OS reduce-motion accessibility setting.
///
/// Wrap the app (inside the router) with this so every descendant can call
/// `MotionScope.of(context)` and get springs that automatically flatten when
/// either the user or the OS requests reduced motion. It also publishes
/// `MediaQuery.disableAnimations` so M3E components that read it (sheets,
/// carousel) reduce motion too.
class MotionScope extends ConsumerWidget {
  const MotionScope({required this.child, super.key});

  final Widget child;

  /// The effective tokens for the nearest [MotionScope], falling back to the
  /// expressive set when none is present.
  static MotionTokens of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MotionScopeInherited>();
    return scope?.tokens ?? MotionTokens.expressive;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferred = ref.watch(motionTokensProvider);
    final osReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tokens = (preferred.reduced || osReduced)
        ? MotionTokens.standard
        : MotionTokens.expressive;

    Widget result = _MotionScopeInherited(tokens: tokens, child: child);
    if (tokens.reduced && !osReduced) {
      // Tell M3E components (and any MediaQuery-aware widget) to reduce motion.
      final media = MediaQuery.of(context);
      result = MediaQuery(
        data: media.copyWith(disableAnimations: true),
        child: result,
      );
    }
    return result;
  }
}

class _MotionScopeInherited extends InheritedWidget {
  const _MotionScopeInherited({required this.tokens, required super.child});

  final MotionTokens tokens;

  @override
  bool updateShouldNotify(_MotionScopeInherited oldWidget) =>
      tokens != oldWidget.tokens;
}
