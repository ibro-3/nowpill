import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'package:nowpill/l10n/generated/app_localizations.dart';

/// Localization delegates for widget tests that pump NowPill screens directly
/// (outside the full app). Mirrors the delegates wired in `NowPillApp`:
/// the app strings plus the material_ui global delegates (which support all
/// shipped locales, e.g. Spanish).
const List<LocalizationsDelegate<dynamic>> testLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];

/// Supported locales for test `MaterialApp`s.
const List<Locale> testSupportedLocales = AppLocalizations.supportedLocales;
