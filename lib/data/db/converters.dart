import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/recurrence_rule.dart';

/// Stores [DateTime] as UTC milliseconds since epoch (integer).
///
/// Drift's default is unix *seconds*, which loses sub-second precision; the
/// plan requires UTC millis. Values are normalized to UTC on write so the
/// stored representation is timezone-independent.
class UtcMillisConverter extends TypeConverter<DateTime, int>
    with JsonTypeConverter<DateTime, int> {
  const UtcMillisConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  @override
  DateTime fromJson(int json) => fromSql(json);

  @override
  int toJson(DateTime value) => toSql(value);
}

/// Stores a [RecurrenceRule] as JSON text.
class RecurrenceRuleConverter extends TypeConverter<RecurrenceRule, String>
    with JsonTypeConverter<RecurrenceRule, String> {
  const RecurrenceRuleConverter();

  @override
  RecurrenceRule fromSql(String fromDb) =>
      RecurrenceRule.fromJson(json.decode(fromDb) as Map<String, Object?>);

  @override
  String toSql(RecurrenceRule value) => json.encode(value.toJson());

  @override
  RecurrenceRule fromJson(String json) => fromSql(json);

  @override
  String toJson(RecurrenceRule value) => toSql(value);
}

/// Stores a list of ISO weekday numbers (1 = Monday … 7 = Sunday) as JSON text.
class WeekdaysConverter extends TypeConverter<List<int>, String>
    with JsonTypeConverter<List<int>, String> {
  const WeekdaysConverter();

  @override
  List<int> fromSql(String fromDb) => (json.decode(fromDb) as List).cast<int>();

  @override
  String toSql(List<int> value) => json.encode(value);

  @override
  List<int> fromJson(String json) => fromSql(json);

  @override
  String toJson(List<int> value) => toSql(value);
}
