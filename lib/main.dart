import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'core/motion/motion_scheme_provider.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/app_settings_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: NowPillApp()));
}

/// Root widget: wires go_router, the M3E adaptive theme, dynamic color, and the
/// motion scope together.
///
/// [MaterialApp.router] sits at the top so it provides the [MediaQuery]
/// (platform brightness) that the adaptive [M3ETheme] below it reads. The
/// resolved expressive theme is projected onto both M3E components (via
/// `M3ETheme.of`) and Material widgets (via the inner [Theme]).
class NowPillApp extends ConsumerStatefulWidget {
  const NowPillApp({super.key});

  @override
  ConsumerState<NowPillApp> createState() => _NowPillAppState();
}

class _NowPillAppState extends ConsumerState<NowPillApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.value ?? const AppSettings();

    // Minimal splash while preferences load, so the first real frame already
    // has the correct theme/motion instead of flashing defaults.
    if (settingsAsync.isLoading && !settingsAsync.hasValue) {
      return MaterialApp(
        title: 'NowPill',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light().toThemeData(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final themeMode = switch (settings.themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

    return MaterialApp.router(
      title: 'NowPill',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.light().toThemeData(),
      darkTheme: AppTheme.light().deriveDarkTemplate().toThemeData(),
      themeMode: themeMode,
      builder: (context, child) {
        return _ExpressiveThemeHost(
          dynamicColor: settings.dynamicColor,
          child: MotionScope(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Hosts the adaptive M3E theme inside the router's [MediaQuery] so it resolves
/// the correct brightness (and dynamic color), then projects it onto the
/// subtree for both M3E and Material widgets.
class _ExpressiveThemeHost extends StatefulWidget {
  const _ExpressiveThemeHost({required this.dynamicColor, required this.child});

  final bool dynamicColor;
  final Widget child;

  @override
  State<_ExpressiveThemeHost> createState() => _ExpressiveThemeHostState();
}

class _ExpressiveThemeHostState extends State<_ExpressiveThemeHost> {
  final M3EThemeController _controller = M3EThemeController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return M3ETheme(
      data: AppTheme.light(),
      controller: _controller,
      autoTheming: true,
      dynamicColoring: widget.dynamicColor,
      initialTheme: Brightness.light,
      child: widget.child,
    );
  }
}
