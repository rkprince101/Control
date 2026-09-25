import 'dart:io';

import 'package:control/data/habits.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday 23 September 2026.
final _today = DateTime(2026, 9, 23);

DateTime _daysAgo(int days) =>
    DateTime(_today.year, _today.month, _today.day - days);

Habit _habit({
  HabitKind kind = HabitKind.check,
  int target = 1,
  Set<int> weekdays = const {1, 2, 3, 4, 5, 6, 7},
  DateTime? createdAt,
}) => Habit(
  id: 'h',
  name: 'Stretch',
  kind: kind,
  target: target,
  weekdays: weekdays,
  createdAt: createdAt ?? _daysAgo(60),
);

Map<int, int> _log(Iterable<int> daysAgo, [int amount = 1]) => {
  for (final days in daysAgo) dayKey(_daysAgo(days)): amount,
};

void main() {
  group('streaks', () {
    test('today still open does not break the run', () {
      final stats = HabitStats.of(_habit(), _log([1, 2, 3]), _today);
      expect(stats.currentStreak, 3);
    });

    test('today done extends the run', () {
      final stats = HabitStats.of(_habit(), _log([0, 1, 2]), _today);
      expect(stats.currentStreak, 3);
    });

    test('a missed due day breaks it', () {
      final stats = HabitStats.of(_habit(), _log([0, 1, 3, 4, 5, 6]), _today);
      expect(stats.currentStreak, 2);
      expect(stats.longestStreak, 4);
    });

    test('days off neither break nor count', () {
      // Weekdays only. Sat 19 and Sun 20 are off, and not done.
      final habit = _habit(weekdays: {1, 2, 3, 4, 5});
      final stats = HabitStats.of(habit, _log([1, 2, 5, 6]), _today);
      expect(stats.currentStreak, 4);
      expect(stats.longestStreak, 4);
    });

    test('doing it on a day off still counts', () {
      final habit = _habit(weekdays: {1, 2, 3, 4, 5});
      final stats = HabitStats.of(habit, _log([1, 2, 3, 4, 5, 6]), _today);
      expect(stats.currentStreak, 6);
    });

    test('a count only counts once the goal is met', () {
      final habit = _habit(kind: HabitKind.count, target: 8);
      final stats = HabitStats.of(habit, {
        ..._log([1], 8),
        ..._log([2], 5),
      }, _today);
      expect(stats.isDoneOn(_daysAgo(1)), isTrue);
      expect(stats.progressOn(_daysAgo(2)), closeTo(5 / 8, 1e-9));
      expect(stats.currentStreak, 1);
    });

    test('a timer goal is minutes, stored as seconds', () {
      final habit = _habit(kind: HabitKind.timer, target: 20);
      expect(habit.goal, 1200);
      final stats = HabitStats.of(habit, _log([0], 1199), _today);
      expect(stats.isDoneOn(_today), isFalse);
    });

    test('the walk stops at the first day the habit existed', () {
      final stats = HabitStats.of(
        _habit(createdAt: _daysAgo(2)),
        _log([0, 1, 2]),
        _today,
      );
      expect(stats.currentStreak, 3);
      expect(stats.completionRate(), 1);
    });

    test('nothing counts before the day the habit was created', () {
      // Logged before the rule existed: set aside, not counted.
      final stats = HabitStats.of(
        _habit(createdAt: _today),
        _log([0, 1, 2, 3]),
        _today,
      );
      expect(stats.firstDay, _today);
      expect(stats.currentStreak, 1);
      expect(stats.totalDone, 1);
      expect(stats.amountOn(_daysAgo(2)), 0);
      expect(stats.canLog(_today), isTrue);
      expect(stats.canLog(_daysAgo(1)), isFalse);
      expect(stats.canLog(_today.add(const Duration(days: 1))), isFalse);
    });
  });

  test('completion rate leaves an unfinished today out', () {
    final stats = HabitStats.of(
      _habit(createdAt: _daysAgo(3)),
      _log([1, 3]),
      _today,
    );
    // Due: days 1, 2, 3. Today is not done yet, so it is not counted.
    expect(stats.completionRate(), closeTo(2 / 3, 1e-9));
  });

  test('a timer run past midnight is split between the two days', () {
    final timer = HabitTimer(
      habitId: 'h',
      startedAt: DateTime(2026, 9, 22, 23, 50),
    );
    final split = timer.secondsByDay(DateTime(2026, 9, 23, 0, 5));
    expect(split, {20260922: 600, 20260923: 300});
  });

  test('ranks climb on points', () {
    expect(HabitRank.forPoints(0).name, 'Seed');
    expect(HabitRank.forPoints(29).name, 'Sprout');
    expect(HabitRank.nextAfter(29)!.name, 'Sapling');
    expect(HabitRank.progress(20), closeTo(0.5, 1e-9));
    expect(HabitRank.nextAfter(10000), isNull);
    expect(HabitRank.progress(10000), 1);
  });

  test('habits round trip and bad entries are dropped', () {
    final habit = Habit(
      id: 'water',
      name: 'Drink water',
      description: 'Before coffee',
      iconAsset: 'assets/icons/glass-7613mgbn-.svg',
      color: HabitPalette.seeds[1],
      kind: HabitKind.count,
      target: 8,
      unit: 'glasses',
      weekdays: const {1, 3, 5},
      reminders: const [540, 1200],
      createdAt: DateTime(2026, 9, 1),
    );
    final back = Habit.fromMap(habit.toMap())!;
    expect(back.toMap(), habit.toMap());
    expect(Habit.fromMap({'name': 'no id'}), isNull);
    expect(Habit.fromMap({'id': 'x', 'name': 'x', 'weekdays': []})!.weekdays, {
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    });
  });

  group('store', () {
    late Directory storage;
    final reminderCalls = <List<Object?>>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      storage = Directory.systemTemp.createTempSync('control_habits');
      reminderCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.control/enforcement'),
            (call) async {
              if (call.method == 'setHabitReminders') {
                reminderCalls.add(
                  (call.arguments as Map)['reminders'] as List<Object?>,
                );
              }
              return switch (call.method) {
                'isAccessibilityEnabled' => false,
                'hasUsageAccess' => false,
                'stepsStatus' => <String, Object?>{
                  'granted': false,
                  'available': false,
                },
                'protectionStatus' => <String, Object?>{
                  'adminActive': false,
                  'deviceOwner': false,
                  'uninstallBlocked': false,
                },
                'shortcutCounts' => <String, Object?>{},
                _ => null,
              };
            },
          );
    });

    tearDown(() => storage.deleteSync(recursive: true));

    ControlStore newStore() => ControlStore(storageDirectory: storage);

    test('habits and their log survive a restart', () async {
      final today = dateOnly(DateTime.now());
      final first = newStore();
      await first.init();
      await first.addHabit(
        Habit(
          id: 'water',
          name: 'Drink water',
          kind: HabitKind.count,
          target: 3,
          createdAt: today,
        ),
      );
      await first.addHabitAmount('water', today, 1);
      await first.addHabitAmount('water', today, 2);
      expect(first.habitStats(first.habits.single).isDoneOn(today), isTrue);
      first.dispose();

      final second = newStore();
      await second.init();
      expect(second.habits.single.name, 'Drink water');
      expect(second.habitStats(second.habits.single).amountOn(today), 3);
      expect(second.habitPoints, 1);
      second.dispose();
    });

    test('days before creation, and after today, cannot be logged', () async {
      final today = dateOnly(DateTime.now());
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final store = newStore();
      await store.init();
      await store.addHabit(Habit(id: 'h', name: 'Stretch', createdAt: today));
      await store.toggleHabit('h', yesterday);
      await store.setHabitAmount('h', tomorrow, 1);
      await store.addHabitAmount('h', yesterday, 3);
      final stats = store.habitStats(store.habits.single);
      expect(stats.amountOn(yesterday), 0);
      expect(stats.amountOn(tomorrow), 0);
      expect(stats.totalDone, 0);
      // Nor is it counted as due on a day it did not exist.
      expect(store.habitProgressOn(yesterday), (done: 0, due: 0));
      expect(store.habitProgressOn(today), (done: 0, due: 1));
      await store.toggleHabit('h', today);
      expect(store.habitProgressOn(today), (done: 1, due: 1));
      store.dispose();
    });

    test('toggling a check flips done and never goes negative', () async {
      final today = dateOnly(DateTime.now());
      final store = newStore();
      await store.init();
      await store.addHabit(Habit(id: 'h', name: 'Stretch', createdAt: today));
      await store.toggleHabit('h', today);
      expect(store.habitProgressOn(today), (done: 1, due: 1));
      await store.toggleHabit('h', today);
      expect(store.habitProgressOn(today), (done: 0, due: 1));
      await store.addHabitAmount('h', today, -5);
      expect(store.habitStats(store.habits.single).amountOn(today), 0);
      store.dispose();
    });

    test('changing how a habit is measured keeps the done days', () async {
      final today = dateOnly(DateTime.now());
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final store = newStore();
      await store.init();
      final habit = Habit(
        id: 'read',
        name: 'Read',
        kind: HabitKind.timer,
        target: 20,
        createdAt: yesterday,
      );
      await store.addHabit(habit);
      await store.setHabitAmount('read', yesterday, 1500);
      await store.setHabitAmount('read', today, 300);

      await store.updateHabit(
        habit.copyWith(kind: HabitKind.count, target: 30, unit: 'pages'),
      );
      final stats = store.habitStats(store.habits.single);
      expect(stats.amountOn(yesterday), 30);
      expect(stats.amountOn(today), 0);
      store.dispose();
    });

    test('reminders reach Android with the day they were finished', () async {
      final today = dateOnly(DateTime.now());
      final store = newStore();
      await store.init();
      await store.addHabit(
        Habit(
          id: 'h',
          name: 'Stretch',
          weekdays: const {1, 3},
          reminders: const [540],
          createdAt: today,
        ),
      );
      final scheduled = reminderCalls.last.single! as Map;
      expect(scheduled['id'], 'h@540');
      expect(scheduled['minute'], 540);
      expect(scheduled['weekdays'], [1, 3]);
      expect(scheduled['doneDay'], 0);

      await store.toggleHabit('h', today);
      expect((reminderCalls.last.single! as Map)['doneDay'], dayKey(today));

      await store.removeHabit('h');
      expect(reminderCalls.last, isEmpty);
      store.dispose();
    });
  });

  group('period summaries', () {
    // Wednesday 23 September 2026; 8 glasses a day, created 1 September.
    final habit = Habit(
      id: 'water',
      name: 'Water',
      kind: HabitKind.count,
      target: 8,
      unit: 'glasses',
      createdAt: DateTime(2026, 9, 1),
    );

    test('a week runs Monday to Sunday and counts every due day', () {
      final stats = HabitStats.of(habit, {
        dayKey(DateTime(2026, 9, 21)): 8,
        dayKey(DateTime(2026, 9, 22)): 4,
        dayKey(DateTime(2026, 9, 23)): 3,
        // Outside the week.
        dayKey(DateTime(2026, 9, 20)): 8,
      }, _today);
      final week = HabitPeriodSummary.of(stats, HabitPeriod.week, _today);
      expect(week.start, DateTime(2026, 9, 21));
      expect(week.lastDay, DateTime(2026, 9, 27));
      expect(week.bars, hasLength(7));
      expect(week.goal, 56, reason: 'the whole week, future days included');
      expect(week.completed, 15);
      expect(week.completion, closeTo(15 / 56, 1e-9));
      expect(week.isCurrent, isTrue);
      expect(week.bars[1].fill, 0.5);
      expect(week.bars[2].isCurrent, isTrue);
      expect(week.bars[3].isFuture, isTrue);
    });

    test('a month leaves out the days before the habit existed', () {
      final late = Habit(
        id: 'late',
        name: 'Late',
        createdAt: DateTime(2026, 9, 21),
      );
      final stats = HabitStats.of(late, const {}, _today);
      final month = HabitPeriodSummary.of(stats, HabitPeriod.month, _today);
      expect(month.bars, hasLength(30));
      expect(month.goal, 10, reason: '21 to 30 September');
      expect(month.bars.first.goal, 0);
    });

    test('a year is twelve monthly bars that add up', () {
      final stats = HabitStats.of(habit, {
        dayKey(DateTime(2026, 9, 2)): 8,
        dayKey(DateTime(2026, 9, 3)): 8,
      }, _today);
      final year = HabitPeriodSummary.of(stats, HabitPeriod.year, _today);
      expect(year.bars, hasLength(12));
      expect(year.bars[7].goal, 0, reason: 'August, before the habit');
      expect(year.bars[8].goal, 240);
      expect(year.bars[8].amount, 16);
      expect(year.bars[8].isCurrent, isTrue);
      expect(year.bars[9].isFuture, isTrue);
      // September to December: 30 + 31 + 30 + 31 days.
      expect(year.goal, 122 * 8);
      expect(year.completed, 16);
    });

    test('days off count toward nothing, and extra credit shows full', () {
      final weekdays = Habit(
        id: 'gym',
        name: 'Gym',
        weekdays: const {1, 3, 5},
        createdAt: DateTime(2026, 9, 1),
      );
      final stats = HabitStats.of(weekdays, {
        dayKey(DateTime(2026, 9, 22)): 1, // Tuesday, a day off.
      }, _today);
      final week = HabitPeriodSummary.of(stats, HabitPeriod.week, _today);
      expect(week.goal, 3);
      expect(week.bars[1].goal, 0);
      expect(week.bars[1].fill, 1);
    });

    test('periods step back and forward on calendar boundaries', () {
      expect(
        HabitPeriod.week.shift(DateTime(2026, 9, 21), -1),
        DateTime(2026, 9, 14),
      );
      expect(
        HabitPeriod.month.shift(DateTime(2026, 1, 1), -1),
        DateTime(2025, 12),
      );
      expect(HabitPeriod.year.startOf(_today), DateTime(2026));
      final stats = HabitStats.of(habit, const {}, _today);
      final past = HabitPeriodSummary.of(
        stats,
        HabitPeriod.month,
        DateTime(2026, 8, 10),
      );
      expect(past.isCurrent, isFalse);
      expect(past.goal, 0);
      expect(past.completion, 0);
    });
  });

  group('growth', () {
    Habit plain(String id, DateTime created) =>
        Habit(id: id, name: id, createdAt: created);

    test('check-ins add up across habits, and stages are dated', () {
      final a = HabitStats.of(plain('a', DateTime(2026, 8, 1)), {
        for (var d = 1; d <= 12; d++) dayKey(DateTime(2026, 9, d)): 1,
      }, _today);
      final b = HabitStats.of(plain('b', DateTime(2026, 9, 5)), {
        dayKey(DateTime(2026, 9, 5)): 1,
        dayKey(DateTime(2026, 9, 6)): 1,
        // Not done: under the goal does not count.
        dayKey(DateTime(2026, 9, 7)): 0,
      }, _today);
      final growth = HabitGrowth.of([a, b], _today);
      expect(growth.points, 14);
      expect(growth.rank.name, 'Sprout');
      expect(growth.next!.name, 'Sapling');
      expect(growth.toNext, 16);
      expect(growth.withinStage, closeTo(4 / 20, 1e-9));
      // Planted when the first habit was; ten check-ins by 8 September
      // (1 to 8 from a, 5 and 6 from b).
      expect(growth.reachedOn[0], DateTime(2026, 8, 1));
      expect(growth.reachedOn[1], DateTime(2026, 9, 8));
      expect(growth.reachedOn[2], isNull);
    });

    test('pace looks back two weeks and projects the next stage', () {
      final stats = HabitStats.of(plain('a', DateTime(2026, 9, 1)), {
        for (var d = 10; d <= 23; d++) dayKey(DateTime(2026, 9, d)): 1,
      }, _today);
      final growth = HabitGrowth.of([stats], _today);
      expect(growth.points, 14);
      expect(growth.pacePerDay, 1);
      expect(growth.daysToNext, 16);
      expect(growth.lastWeek, 7);
      expect(growth.lastMonth, 14);
    });

    test('no recent check-ins means no projection, not a wrong one', () {
      final stats = HabitStats.of(plain('a', DateTime(2026, 1, 1)), {
        dayKey(DateTime(2026, 2, 1)): 1,
      }, _today);
      final growth = HabitGrowth.of([stats], _today);
      expect(growth.pacePerDay, 0);
      expect(growth.daysToNext, isNull);
    });

    test('the top of the ladder has nothing next', () {
      final stats = HabitStats.of(plain('a', DateTime(2024, 1, 1)), {
        for (var d = 0; d < 700; d++) dayKey(DateTime(2024, 1, 1 + d)): 1,
      }, _today);
      final growth = HabitGrowth.of([stats], _today);
      expect(growth.rank.name, 'Old growth');
      expect(growth.next, isNull);
      expect(growth.toNext, 0);
      expect(growth.daysToNext, isNull);
      expect(growth.withinStage, 1);
      expect(growth.reachedOn.every((day) => day != null), isTrue);
    });

    test('no habits is a seed with nothing dated', () {
      final growth = HabitGrowth.of(const [], _today);
      expect(growth.stage, 0);
      expect(growth.points, 0);
      expect(growth.reachedOn[0], isNull);
    });
  });
}
