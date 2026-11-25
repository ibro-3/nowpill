import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nowpill/core/motion/app_motion.dart';
import 'package:nowpill/core/motion/motion_scheme_provider.dart';
import 'package:nowpill/core/widgets/spring_progress.dart';

import '../helpers/test_localizations.dart';

/// The M3E wavy indicator draws a waveform but feeds `value` straight to the
/// painter. These tests pin the wrapper's spring fill and its reduced-motion
/// fallback (flat, with no running wave ticker).
void main() {
  Widget wrap(Widget child, MotionTokens tokens) {
    return ProviderScope(
      overrides: [motionTokensProvider.overrideWithValue(tokens)],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(),
          child: M3ETheme(
            data: M3EThemeData.light(),
            child: MotionScope(child: Center(child: child)),
          ),
        ),
      ),
    );
  }

  double valueOf(WidgetTester tester, Key key) =>
      tester.widget<M3EProgressIndicator>(find.byKey(key)).value!;

  testWidgets('fill springs from its previous value to the new one', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 0, semanticsLabel: 'Progress'),
        MotionTokens.expressive,
      ),
    );
    expect(find.byKey(const Key('spring-progress-wavy')), findsOneWidget);
    expect(valueOf(tester, const Key('spring-progress-wavy')), 0);

    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 1, semanticsLabel: 'Progress'),
        MotionTokens.expressive,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final mid = valueOf(tester, const Key('spring-progress-wavy'));
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 2000));
    expect(
      valueOf(tester, const Key('spring-progress-wavy')),
      closeTo(1, 0.01),
    );
  });

  testWidgets(
    'circular variant springs to target, static under reduced motion',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const SpringWavyProgressBar(
            circular: true,
            value: 0,
            semanticsLabel: 'Amount',
          ),
          MotionTokens.expressive,
        ),
      );
      expect(find.byKey(const Key('spring-progress-circular')), findsOneWidget);
      expect(find.byKey(const Key('spring-progress-wavy')), findsNothing);
      expect(valueOf(tester, const Key('spring-progress-circular')), 0);

      await tester.pumpWidget(
        wrap(
          const SpringWavyProgressBar(
            circular: true,
            value: 1,
            semanticsLabel: 'Amount',
          ),
          MotionTokens.expressive,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final mid = valueOf(tester, const Key('spring-progress-circular'));
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pump(const Duration(milliseconds: 2000));
      expect(
        valueOf(tester, const Key('spring-progress-circular')),
        closeTo(1, 0.01),
      );

      await tester.pumpWidget(
        wrap(
          const SpringWavyProgressBar(
            circular: true,
            value: 0.4,
            semanticsLabel: 'Amount',
          ),
          MotionTokens.standard,
        ),
      );
      expect(valueOf(tester, const Key('spring-progress-circular')), 0.4);
    },
  );

  testWidgets('reduced motion renders a flat, static indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 0.4, semanticsLabel: 'Progress'),
        MotionTokens.standard,
      ),
    );
    expect(find.byKey(const Key('spring-progress-flat')), findsOneWidget);
    expect(find.byKey(const Key('spring-progress-wavy')), findsNothing);
    expect(valueOf(tester, const Key('spring-progress-flat')), 0.4);

    await tester.pump(const Duration(milliseconds: 200));
    expect(valueOf(tester, const Key('spring-progress-flat')), 0.4);
  });

  testWidgets('rapid retargets settle on the last value', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 0, semanticsLabel: 'Progress'),
        MotionTokens.expressive,
      ),
    );
    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 1, semanticsLabel: 'Progress'),
        MotionTokens.expressive,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(
      wrap(
        const SpringWavyProgressBar(value: 0, semanticsLabel: 'Progress'),
        MotionTokens.expressive,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2000));

    expect(tester.takeException(), isNull);
    expect(
      valueOf(tester, const Key('spring-progress-wavy')),
      closeTo(0, 0.01),
    );
  });
}
