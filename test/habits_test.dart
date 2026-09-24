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

    test('backfilling before creation moves the first day back', () {
      final stats = HabitStats.of(
        _habit(createdAt: _today),
        _log([0, 1, 2, 3]),
        _today,
      );
      expect(stats.firstDay, _daysAgo(3));
      expect(stats.currentStreak, 4);
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
}
