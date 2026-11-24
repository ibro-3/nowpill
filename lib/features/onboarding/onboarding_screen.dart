import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:motor/motor.dart';

import '../../core/motion/motion_scheme_provider.dart';
import '../../core/motion/shape_morph.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/app_settings_provider.dart';
import '../../data/repositories/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../habits/habit_icons.dart';

/// A lightweight first-run flow: what the app is, a few starter habits, and
/// a hand-off to Today. Everything is optional and can be changed later.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _StarterHabit {
  const _StarterHabit(this.key, this.iconKey, this.color);

  final String key;
  final String iconKey;
  final int color;

  String label(AppLocalizations l10n) => switch (key) {
    'water' => l10n.starterWater,
    'move' => l10n.starterMove,
    _ => l10n.starterRead,
  };
}

const _starters = [
  _StarterHabit('water', 'water', 0xFF00B4D8),
  _StarterHabit('move', 'run', 0xFF2DD4A8),
  _StarterHabit('read', 'read', 0xFF5B8DEF),
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final Set<String> _selected = {'water', 'read'};
  bool _busy = false;

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish(seed: true);
    }
  }

  Future<void> _finish({required bool seed}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    if (seed && _selected.isNotEmpty) {
      final habits = ref.read(habitRepositoryProvider);
      final labels = {for (final s in _starters) s.key: s.label(l10n)};
      var order = 0;
      for (final starter in _starters) {
        if (!_selected.contains(starter.key)) continue;
        await habits.create(
          name: labels[starter.key]!,
          iconKey: starter.iconKey,
          color: starter.color,
          sortOrder: order++,
        );
      }
    }
    ref.read(appSettingsProvider.notifier).setOnboardingComplete(true);
    if (mounted) context.go(AppRoutes.today);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final l10n = AppLocalizations.of(context);
    final tokens = MotionScope.of(context);

    final (title, body, icon) = switch (_step) {
      0 => (
        l10n.onboardingWelcomeTitle,
        l10n.onboardingWelcomeBody,
        M3EIcons.auto_awesome,
      ),
      1 => (
        l10n.onboardingHabitsTitle,
        l10n.onboardingHabitsBody,
        M3EIcons.checklist,
      ),
      _ => (
        l10n.onboardingReadyTitle,
        l10n.onboardingReadyBody,
        M3EIcons.check_circle,
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    SingleMotionBuilder(
                      value: i == _step ? 24.0 : 8.0,
                      motion: tokens.spatialDefault,
                      builder: (context, width, child) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: width,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _step
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              SingleMotionBuilder(
                value: _step.toDouble(),
                motion: tokens.spatialDefault,
                builder: (context, step, child) {
                  // cookie → soft burst → flower as the story advances. The
                  // second morph starts where the first ends, so the swap at
                  // the midpoint is invisible.
                  final firstHalf = step <= 1;
                  final morph = firstHalf
                      ? shapeMorph(
                          M3EShapeKind.cookie9Sided,
                          M3EShapeKind.softBurst,
                        )
                      : shapeMorph(M3EShapeKind.softBurst, M3EShapeKind.flower);
                  final local = firstHalf ? step : step - 1;
                  return CustomPaint(
                    painter: MorphShapePainter(
                      morph: morph,
                      progress: local.clamp(0.0, 1.0),
                      fill: theme.colorScheme.primaryContainer,
                    ),
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: Center(
                        child: Icon(
                          icon,
                          size: 52,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.typography.emphasized.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.typography.baseline.bodyLarge.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_step == 1) ...[
                const SizedBox(height: 24),
                for (final starter in _starters)
                  Semantics(
                    container: true,
                    checked: _selected.contains(starter.key),
                    label: starter.label(l10n),
                    child: ListTile(
                      key: ValueKey('starter-${starter.key}'),
                      leading: Icon(
                        habitIconForKey(starter.iconKey),
                        color: Color(starter.color),
                      ),
                      title: Text(starter.label(l10n)),
                      trailing: M3ECheckbox(
                        value: _selected.contains(starter.key),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selected.add(starter.key);
                          } else {
                            _selected.remove(starter.key);
                          }
                        }),
                      ),
                      onTap: () => setState(() {
                        if (_selected.contains(starter.key)) {
                          _selected.remove(starter.key);
                        } else {
                          _selected.add(starter.key);
                        }
                      }),
                    ),
                  ),
              ],
              const Spacer(),
              Row(
                children: [
                  if (_step > 0)
                    M3EButton(
                      style: M3EButtonStyle.text,
                      onPressed: () => setState(() => _step--),
                      label: Text(l10n.onboardingBack),
                    ),
                  const Spacer(),
                  if (_step < 2)
                    M3EButton(
                      key: const ValueKey('onboarding-skip'),
                      style: M3EButtonStyle.text,
                      onPressed: _busy ? null : () => _finish(seed: false),
                      label: Text(l10n.onboardingSkip),
                    ),
                  M3EButton(
                    key: const ValueKey('onboarding-next'),
                    onPressed: _busy ? null : _next,
                    label: Text(
                      _step == 2 ? l10n.onboardingStart : l10n.onboardingNext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
