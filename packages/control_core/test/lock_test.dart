import 'package:control_core/control_core.dart';
import 'package:test/test.dart';

const policy = LockPolicy();
const clock = TamperResistantClock();

Block locked(Lock lock) => Block(
      id: 'focus',
      name: 'Focus',
      mode: LimitMode.time,
      apps: const {'com.netflix.mediaclient'},
      lock: lock,
    );

void main() {
  group('LockPolicy', () {
    final now = DateTime(2026, 8, 26, 9, 16);

    test('an unlocked block is freely editable', () {
      expect(
        policy.verdict(
          block: locked(const Lock.none()),
          change: BlockChange.weaken,
          now: now,
        ),
        LockVerdict.allowed,
      );
    });

    test('a password lock gates weakening but not the block itself', () {
      expect(
        policy.verdict(
          block: locked(const Lock.password('argon2id\$...')),
          change: BlockChange.weaken,
          now: now,
        ),
        LockVerdict.needsPassword,
      );
    });

    test('a live timed lock refuses even with the password', () {
      final block =
          locked(Lock.timed(until: now.add(const Duration(days: 7))));
      expect(
        policy.verdict(block: block, change: BlockChange.weaken, now: now),
        LockVerdict.refused,
      );
      expect(
        policy.verdict(block: block, change: BlockChange.unlock, now: now),
        LockVerdict.refused,
      );
      expect(
        policy.remaining(block: block, now: now),
        const Duration(days: 7),
      );
    });

    test('strengthening is always allowed, lock or no lock', () {
      final block =
          locked(Lock.timed(until: now.add(const Duration(days: 365))));
      expect(
        policy.verdict(block: block, change: BlockChange.strengthen, now: now),
        LockVerdict.allowed,
      );
    });

    test('an expired timed lock stops refusing', () {
      final block =
          locked(Lock.timed(until: now.subtract(const Duration(minutes: 1))));
      expect(
        policy.verdict(block: block, change: BlockChange.weaken, now: now),
        LockVerdict.allowed,
      );
      expect(policy.remaining(block: block, now: now), isNull);
    });
  });

  group('EmergencyUnlocks', () {
    test('drains and never refills', () {
      var pool = const EmergencyUnlocks.fresh();
      expect(pool.remaining, 5);

      for (var i = 0; i < 5; i++) {
        final result = pool.consume();
        expect(result.granted, isTrue);
        pool = result.pool;
      }

      expect(pool.isExhausted, isTrue);
      final denied = pool.consume();
      expect(denied.granted, isFalse);
      expect(denied.pool.remaining, 0);
    });
  });

  group('TamperResistantClock', () {
    test('winding the system clock back does not move time back', () {
      final armed = DateTime(2026, 8, 26, 9, 0);
      final anchor = ClockAnchor(
        wallClock: armed,
        monotonic: const Duration(hours: 3),
      );

      // User sets the phone clock to last week; uptime still says two more
      // hours have passed since the anchor.
      final resolved = clock.resolve(
        systemNow: DateTime(2026, 8, 19, 9, 0),
        monotonicNow: const Duration(hours: 5),
        anchor: anchor,
        highWaterMark: DateTime(2026, 8, 26, 10, 30),
      );

      expect(resolved, DateTime(2026, 8, 26, 11, 0));
      expect(clock.detectsRollback(DateTime(2026, 8, 19, 9, 0), resolved),
          isTrue);
    });

    test('after a reboot the stale anchor is ignored, high-water mark holds', () {
      final anchor = ClockAnchor(
        wallClock: DateTime(2026, 8, 26, 9, 0),
        monotonic: const Duration(hours: 3),
      );

      // Uptime restarted, so the delta would be negative: the anchor is unusable.
      final resolved = clock.resolve(
        systemNow: DateTime(2026, 8, 20),
        monotonicNow: const Duration(minutes: 2),
        anchor: anchor,
        highWaterMark: DateTime(2026, 8, 26, 12, 0),
      );

      expect(resolved, DateTime(2026, 8, 26, 12, 0));
    });

    test('an honest clock passes through untouched', () {
      final systemNow = DateTime(2026, 8, 26, 14, 0);
      final resolved = clock.resolve(
        systemNow: systemNow,
        monotonicNow: const Duration(hours: 8),
        anchor: ClockAnchor(
          wallClock: DateTime(2026, 8, 26, 9, 0),
          monotonic: const Duration(hours: 3),
        ),
        highWaterMark: DateTime(2026, 8, 26, 13, 59),
      );

      expect(resolved, systemNow);
      expect(clock.detectsRollback(systemNow, resolved), isFalse);
    });
  });
}
