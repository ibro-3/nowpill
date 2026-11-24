import 'package:flutter_test/flutter_test.dart';
import 'package:nowpill/domain/enums.dart';
import 'package:nowpill/domain/vacation.dart';

void main() {
  final today = DateTime(2026, 11, 24);
  final windowStart = DateTime(2026, 11, 20);

  VacationPeriod period(String uuid, {bool allHabits = false}) =>
      VacationPeriod(
        start: '2026-11-21',
        end: '2026-11-23',
        uuid: uuid,
        allHabits: allHabits,
      );

  VacationScope scope(
    String periodUuid,
    VacationTargetKind kind,
    String targetUuid,
  ) => VacationScope(
    periodUuid: periodUuid,
    targetKind: kind,
    targetUuid: targetUuid,
  );

  Set<String> resolve({
    required List<VacationPeriod> periods,
    List<VacationScope> scopes = const [],
    String habitUuid = 'h1',
    String? routineUuid,
  }) => resolvePausedDates(
    periods: periods,
    scopes: scopes,
    habitUuid: habitUuid,
    routineUuid: routineUuid,
    windowStart: windowStart,
    windowEnd: today,
  );

  test('all-habits period applies to everyone, even with no scopes', () {
    expect(resolve(periods: [period('p1', allHabits: true)]), {
      '2026-11-21',
      '2026-11-22',
      '2026-11-23',
    });
  });

  test('scoped period applies only to matching habit or routine', () {
    final periods = [period('p1')];
    final scopes = [
      scope('p1', VacationTargetKind.routine, 'r1'),
      scope('p1', VacationTargetKind.habit, 'h2'),
    ];
    expect(resolve(periods: periods, scopes: scopes), isEmpty);
    expect(
      resolve(periods: periods, scopes: scopes, habitUuid: 'h2'),
      hasLength(3),
    );
    expect(
      resolve(periods: periods, scopes: scopes, routineUuid: 'r1'),
      hasLength(3),
    );
    expect(
      resolve(
        periods: periods,
        scopes: scopes,
        habitUuid: 'h1',
        routineUuid: 'r9',
      ),
      isEmpty,
    );
  });

  test('duplicate targets and periods resolve as a union', () {
    final periods = [period('p1'), period('p1'), period('p2', allHabits: true)];
    final scopes = [
      scope('p1', VacationTargetKind.habit, 'h1'),
      scope('p1', VacationTargetKind.habit, 'h1'),
    ];
    expect(resolve(periods: periods, scopes: scopes), hasLength(3));
  });

  test('unknown targets never widen a vacation', () {
    final periods = [period('p1')];
    final scopes = [
      scope('p1', VacationTargetKind.routine, 'deleted-routine'),
      scope('p1', VacationTargetKind.habit, 'ghost'),
    ];
    // Stale scope rows are removed by the DB/merge layer; the resolver only
    // matches identities it is given, so an unrelated habit still sees no
    // pause.
    expect(resolve(periods: periods, scopes: scopes), isEmpty);
    expect(
      resolve(periods: [period('p2', allHabits: true)], scopes: scopes),
      hasLength(3),
    );
  });

  test('scoped period with no matching targets pauses nothing', () {
    expect(resolve(periods: [period('p1')]), isEmpty);
  });

  test('window clamping keeps only the habit lifetime', () {
    final result = resolvePausedDates(
      periods: [period('p1', allHabits: true)],
      scopes: const [],
      habitUuid: 'h1',
      windowStart: DateTime(2026, 11, 22),
      windowEnd: DateTime(2026, 11, 22),
    );
    expect(result, {'2026-11-22'});
  });

  test('stable enum indexes', () {
    expect(VacationTargetKind.routine.index, 0);
    expect(VacationTargetKind.habit.index, 1);
  });
}
