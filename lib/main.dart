import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'core/motion/motion_scheme_provider.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/settings/app_settings_provider.dart';
import 'core/theme/app_theme.dart';
import 'data/sync/device_identity.dart';
import 'data/widget/widget_action_handler.dart' as widget_action;
import 'l10n/generated/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The device identity must exist before the database opens so tombstones
  // carry it (Phase 18/19 sync).
  setBootDeviceId(await loadOrCreateDeviceId());
  runApp(const ProviderScope(child: NowPillApp()));
}

/// Headless entry point for home-screen widget check-ins while the app is
/// closed (Android, Phase 27). The Kotlin `WidgetActionReceiver` launches a
/// FlutterEngine here and sends the payload over `app.nowpill/widget_action`.
///
/// Declared in the root library so DartEntrypoint resolution is stable; the
/// implementation lives behind a conditional export (native does the work,
/// web/desktop no-op) so dart:ffi stays out of the web compilation.
@pragma('vm:entry-point')
void widgetActionMain() => widget_action.widgetActionMainImpl();

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
  /// The router is attached only after settings have loaded (see [build]), so
  /// the redirect can safely read the persisted onboarding flag.
  late final GoRouter _router = buildRouter(
    redirect: (context, state) {
      if (state.matchedLocation == AppRoutes.onboarding) return null;
      final seen =
          ref.read(appSettingsProvider).value?.onboardingComplete ?? false;
      return seen ? null : AppRoutes.onboarding;
    },
  );

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.value ?? const AppSettings();

    // Minimal splash while preferences load, so the first real frame already
    // has the correct theme/motion instead of flashing defaults. The splash
    // follows the platform brightness until the persisted mode is known.
    if (settingsAsync.isLoading && !settingsAsync.hasValue) {
      final platformDark =
          MediaQuery.platformBrightnessOf(context) == Brightness.dark;
      return MaterialApp(
        title: 'NowPill',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light().toThemeData(),
        darkTheme: AppTheme.light().deriveDarkTemplate().toThemeData(),
        themeMode: platformDark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: Center(child: M3ELoadingIndicator())),
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
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: settings.localeCode == null ? null : Locale(settings.localeCode!),
      builder: (context, child) {
        return _ExpressiveThemeHost(
          themeMode: settings.themeMode,
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
///
/// The user's [themeMode] drives the adaptive rules: `system` follows the
/// platform brightness; `light`/`dark` lock it. Without this, the M3E scope
/// would always follow the OS and override the MaterialApp's themeMode for
/// every M3E component (the theme picker would appear to do nothing).
class _ExpressiveThemeHost extends StatefulWidget {
  const _ExpressiveThemeHost({
    required this.themeMode,
    required this.dynamicColor,
    required this.child,
  });

  final AppThemeMode themeMode;
  final bool dynamicColor;
  final Widget child;

  @override
  State<_ExpressiveThemeHost> createState() => _ExpressiveThemeHostState();
}

class _ExpressiveThemeHostState extends State<_ExpressiveThemeHost> {
  final M3EThemeController _controller = M3EThemeController();

  @override
  void initState() {
    super.initState();
    _applyMode(widget.themeMode);
  }

  @override
  void didUpdateWidget(_ExpressiveThemeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      _applyMode(widget.themeMode);
    }
  }

  /// Maps the user's mode onto the controller: locked modes set an absolute
  /// brightness override; system clears it so platform tracking applies.
  void _applyMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        _controller.followSystem();
      case AppThemeMode.light:
        _controller.setBrightness(Brightness.light);
      case AppThemeMode.dark:
        _controller.setBrightness(Brightness.dark);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // M3EResolvedTheme (inside M3ETheme) projects the resolved expressive
    // scheme onto the nearest ancestor Material Theme. That ancestor is
    // MaterialApp's AnimatedTheme, whose data lerps over ~200ms — so derived
    // fields like scaffoldBackgroundColor would lag one mode behind while
    // colorScheme (overwritten outright) snaps, leaving a white scaffold under
    // dark cards (and vice versa). Provide an *immediate* Theme at the exact
    // resolved brightness as the merge base so every field stays in sync.
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = widget.themeMode == AppThemeMode.system
        ? platform
        : (widget.themeMode == AppThemeMode.dark
              ? Brightness.dark
              : Brightness.light);
    final base = AppTheme.light();
    final resolved = brightness == Brightness.dark
        ? base.deriveDarkTemplate()
        : base;
    return Theme(
      data: resolved.toThemeData(),
      child: M3ETheme(
        data: base,
        controller: _controller,
        // System mode tracks MediaQuery.platformBrightnessOf; locked modes use
        // the controller's absolute override (which takes precedence).
        autoTheming: widget.themeMode == AppThemeMode.system,
        dynamicColoring: widget.dynamicColor,
        initialTheme: Brightness.light,
        child: widget.child,
      ),
    );
  }
}
