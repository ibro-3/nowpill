import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/core/theme/app_colors.dart';
import 'package:nowpill/core/widgets/splash_logo.dart';

/// The brief splash must give the pill's white half a dark-enough backdrop.
void main() {
  testWidgets('splash logo is a filled brand-mint circle with the pill asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SplashLogo()),
      ),
    );

    final circle = find.byKey(const Key('splash-circle'));
    expect(circle, findsOneWidget);
    expect(tester.getSize(circle), const Size(112, 112));
    final decoration =
        tester.widget<Container>(circle).decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppColors.mint);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, kSplashLogoAsset);
    expect(image.semanticLabel, 'NowPill');
  });
}
