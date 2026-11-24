import '../../../domain/heatmap.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Shared screen-reader wording for heatmap day states (month + year grids).
String heatmapStateLabel(AppLocalizations l10n, HeatmapDayState state) =>
    switch (state) {
      HeatmapDayState.done => l10n.a11yHeatmapDone,
      HeatmapDayState.partial => l10n.a11yHeatmapPartial,
      HeatmapDayState.frozen => l10n.a11yHeatmapFrozen,
      HeatmapDayState.missed => l10n.a11yHeatmapMissed,
      HeatmapDayState.todayPending => l10n.a11yHeatmapPending,
      HeatmapDayState.relapsed => l10n.a11yHeatmapRelapsed,
      HeatmapDayState.paused => l10n.a11yHeatmapPaused,
      HeatmapDayState.unscheduled || HeatmapDayState.inactive => '',
    };
