import 'package:control/data/focus.dart';
import 'package:flutter_test/flutter_test.dart';

/// The focus timer buys unlocks, so miscounting it is the same class of bug as
/// miscounting a lock: it hands out access nobody earned.
void main() {
  final monday = DateTime(2026, 8, 24, 9);

  FocusSession session({
    DateTime? startedAt,
    DateTime? endedAt,
    FocusKind kind = FocusKind.stopwatch,
    Duration? plannedWork,
  }) =>
      FocusSession(
        blockId: 'study',
        startedAt: startedAt ?? monday,
        endedAt: endedAt,
        kind: kind,
        plannedWork: plannedWork,
      );

  group('length', () {
    test('a running session is measured against the clock', () {
      final running = session();
      expect(
        running.lengthAt(monday.add(const Duration(minutes: 40))),
        const Duration(minutes: 40),
      );
      expect(running.isRunning, isTrue);
    });

    test('a pomodoro does not credit the overrun', () {
      final pomodoro = session(
        kind: FocusKind.pomodoro,
        plannedWork: const Duration(minutes: 25),
      );

      // Left running for two hours after it finished.
      expect(
        pomodoro.lengthAt(monday.add(const Duration(hours: 2))),
        const Duration(minutes: 25),
      );
      expect(pomodoro.isComplete(monday.add(const Duration(minutes: 25))), isTrue);
      expect(pomodoro.isComplete(monday.add(const Duration(minutes: 24))), isFalse);
    });

    test('a clock that moved backwards cannot make a session negative', () {
      final finished = session(
        startedAt: monday,
        endedAt: monday.subtract(const Duration(hours: 1)),
      );
      expect(finished.lengthAt(monday), Duration.zero);
    });
  });

  group('day attribution', () {
    test('a session that crosses midnight is split, not double counted', () {
      // 23:00 Monday to 01:00 Tuesday.
      final late = session(
        startedAt: DateTime(2026, 8, 24, 23),
        endedAt: DateTime(2026, 8, 25, 1),
      );
      final now = DateTime(2026, 8, 25, 9);

      expect(
        late.lengthOnDay(DateTime(2026, 8, 24), now),
        const Duration(hours: 1),
      );
      expect(
        late.lengthOnDay(DateTime(2026, 8, 25), now),
        const Duration(hours: 1),
      );
      expect(late.lengthOnDay(DateTime(2026, 8, 26), now), Duration.zero);
    });

    test('a capped pomodoro splits its credited time, not its wall time', () {
      // Started at 23:50, forgotten until the next morning: 25 minutes of
      // credit, of which 10 belong to Monday and 15 to Tuesday.
      final forgotten = session(
        startedAt: DateTime(2026, 8, 24, 23, 50),
        endedAt: DateTime(2026, 8, 25, 8),
        kind: FocusKind.pomodoro,
        plannedWork: const Duration(minutes: 25),
      );
      final now = DateTime(2026, 8, 25, 9);

      final monday = forgotten.lengthOnDay(DateTime(2026, 8, 24), now);
      final tuesday = forgotten.lengthOnDay(DateTime(2026, 8, 25), now);

      expect(monday + tuesday, const Duration(minutes: 25));
      expect(monday.inMinutes, closeTo(1, 1));
    });
  });

  group('stats', () {
    test('a streak survives a today that has not started yet', () {
      final now = DateTime(2026, 8, 26, 9);
      final sessions = [
        for (var i = 1; i <= 3; i++)
          session(
            startedAt: DateTime(2026, 8, 26 - i, 10),
            endedAt: DateTime(2026, 8, 26 - i, 11),
          ),
      ];

      final stats = FocusStats.from(sessions, now);
      expect(stats.today, Duration.zero);
      expect(stats.streakDays, 3);
      expect(stats.longest, const Duration(hours: 1));
    });

    test('a gap ends the streak', () {
      final now = DateTime(2026, 8, 26, 9);
      final sessions = [
        session(
          startedAt: DateTime(2026, 8, 26, 8),
          endedAt: DateTime(2026, 8, 26, 8, 30),
        ),
        // Nothing on the 25th.
        session(
          startedAt: DateTime(2026, 8, 24, 10),
          endedAt: DateTime(2026, 8, 24, 11),
        ),
      ];

      final stats = FocusStats.from(sessions, now);
      expect(stats.streakDays, 1);
      expect(stats.perDay, hasLength(7));
      expect(stats.perDay.last.$2, const Duration(minutes: 30));
    });

    test('statistics can be narrowed to one block', () {
      final now = DateTime(2026, 8, 26, 12);
      final sessions = [
        FocusSession(
          blockId: 'study',
          startedAt: DateTime(2026, 8, 26, 9),
          endedAt: DateTime(2026, 8, 26, 10),
          kind: FocusKind.stopwatch,
        ),
        FocusSession(
          blockId: 'other',
          startedAt: DateTime(2026, 8, 26, 10),
          endedAt: DateTime(2026, 8, 26, 11),
          kind: FocusKind.stopwatch,
        ),
      ];

      expect(
        FocusStats.from(sessions, now, blockId: 'study').today,
        const Duration(hours: 1),
      );
      expect(FocusStats.from(sessions, now).today, const Duration(hours: 2));
    });
  });
}
