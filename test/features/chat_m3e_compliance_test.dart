import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/core/theme/app_theme.dart';
import 'package:nowpill/data/db/app_database.dart';
import 'package:nowpill/features/chat/widgets/note_card.dart';

import '../helpers/test_localizations.dart';

/// M3E token regressions for the chat surface: exact type steps, role contrast
/// and a 48dp delete target on a card.
void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(),
          child: M3ETheme(
            data: M3EThemeData.light(),
            child: MotionScope(child: child),
          ),
        ),
      ),
    );
  }

  double luminance(Color color) {
    double channel(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  test('chat uses the exact M3 baseline type steps', () {
    final theme = M3EThemeData.light();
    expect(theme.typography.baseline.bodyMedium.fontSize, 14);
    expect(theme.typography.baseline.bodyMedium.height, 20 / 14);
    expect(theme.typography.baseline.labelSmall.fontSize, 11);
    expect(theme.typography.baseline.labelSmall.height, 16 / 11);
    expect(theme.typography.baseline.labelMedium.fontSize, 12);
    expect(theme.typography.baseline.titleLarge.fontSize, 22);
  });

  test('small text roles clear 4.5:1 on the filled card surface', () {
    final colors = M3EThemeData.light().colorScheme;
    expect(
      contrast(colors.onSurface, colors.surfaceContainerHighest),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(colors.onSurfaceVariant, colors.surfaceContainerHighest),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('link primary clears 4.5:1 on the filled card in both themes', () {
    for (final colors in [
      AppTheme.light().colorScheme,
      AppTheme.light().deriveDarkTemplate().colorScheme,
    ]) {
      expect(
        contrast(colors.primary, colors.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('note delete affordance has a 48dp touch target', (tester) async {
    final now = DateTime(2026, 11, 25, 9);
    await tester.pumpWidget(
      wrap(
        Center(
          child: NoteCard(
            note: ChatNote(
              id: 1,
              uuid: 'n1',
              createdAt: now,
              updatedAt: now,
              body: 'hello',
            ),
            onDelete: () {},
            onOpenLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final button = find.byType(M3EIconButton);
    expect(button, findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
