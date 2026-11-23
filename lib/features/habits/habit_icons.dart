import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// A curated habit icon, keyed by a stable string stored in the database.
class HabitIcon {
  const HabitIcon(this.key, this.icon, this.label);

  final String key;
  final IconData icon;
  final String label;
}

/// The curated icon set offered in the habit editor. Keys are persisted, so
/// they must remain stable across releases.
const List<HabitIcon> kHabitIcons = [
  HabitIcon('spark', M3EIcons.auto_awesome, 'Spark'),
  HabitIcon('run', M3EIcons.directions_run, 'Run'),
  HabitIcon('walk', M3EIcons.directions_walk, 'Walk'),
  HabitIcon('fitness', M3EIcons.fitness_center, 'Fitness'),
  HabitIcon('meditate', M3EIcons.self_improvement, 'Meditate'),
  HabitIcon('read', M3EIcons.menu_book, 'Read'),
  HabitIcon('water', M3EIcons.water_drop, 'Water'),
  HabitIcon('sleep', M3EIcons.bedtime, 'Sleep'),
  HabitIcon('eat', M3EIcons.restaurant, 'Eat well'),
  HabitIcon('music', M3EIcons.music_note, 'Music'),
  HabitIcon('code', M3EIcons.code, 'Code'),
  HabitIcon('art', M3EIcons.palette, 'Art'),
  HabitIcon('plant', M3EIcons.local_florist, 'Plant'),
  HabitIcon('sun', M3EIcons.wb_sunny, 'Morning'),
  HabitIcon('heart', M3EIcons.favorite, 'Self-care'),
  HabitIcon('mind', M3EIcons.psychology, 'Mind'),
];

/// Resolves a stored icon key to its icon data, falling back to the spark.
IconData habitIconForKey(String key) {
  for (final h in kHabitIcons) {
    if (h.key == key) return h.icon;
  }
  return M3EIcons.auto_awesome;
}

/// Brand color choices for habits (ARGB).
const List<int> kHabitColors = [
  0xFF2DD4A8, // mint
  0xFFFF6B5E, // coral
  0xFFFFB454, // amber
  0xFF5B8DEF, // blue
  0xFF9B6DFF, // violet
  0xFFEF5DA8, // pink
  0xFF4CB944, // green
  0xFF00B4D8, // cyan
];
