import 'dart:convert';

import 'package:control/data/block_codec.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Storage is the one place a bug hands the user a free bypass, so the codec is
/// tested against the shapes that matter: a fully configured block, a lock that
/// must survive a restart, and stored data that predates a field.
void main() {
  Map<String, Object?> roundTrip(Block block) =>
      jsonDecode(jsonEncode(BlockCodec.encode(block)))
          as Map<String, Object?>;

  test('a fully configured block survives a round trip', () {
    final original = Block(
      id: 'b1',
      name: 'Good night',
      mode: LimitMode.time,
      apps: const {'com.instagram.android', 'com.netflix.mediaclient'},
      categories: const {'browsers', 'games'},
      excludedApps: const {'org.mozilla.firefox'},
      schedule: const [
        TimeRange(startMinute: 1260, endMinute: 480, weekdays: {6, 7}),
      ],
      schedulePolarity: RulePolarity.unblockDuring,
      enabled: false,
    );

    final decoded = BlockCodec.decode(roundTrip(original));

    expect(decoded.id, 'b1');
    expect(decoded.name, 'Good night');
    expect(decoded.mode, LimitMode.time);
    expect(decoded.apps, original.apps);
    expect(decoded.categories, original.categories);
    expect(decoded.excludedApps, original.excludedApps);
    expect(decoded.copyWith(name: 'Renamed').excludedApps, original.excludedApps);
    expect(decoded.enabled, isFalse);
    expect(decoded.schedulePolarity, RulePolarity.unblockDuring);
    expect(decoded.schedule.single.startMinute, 1260);
    expect(decoded.schedule.single.weekdays, {6, 7});
  });

  test('every condition type survives a round trip', () {
    final original = Block(
      id: 'b2',
      name: 'Earn it',
      mode: LimitMode.condition,
      apps: const {'com.instagram.android'},
      blockAgainAfter: const Duration(hours: 2),
      conditions: const [
        StepsCondition(id: 'c1', targetSteps: 6000),
        WorkoutCondition(id: 'c2', target: Duration(minutes: 20)),
        MeditateCondition(id: 'c3', target: Duration(minutes: 10)),
        AppTimeCondition(
          id: 'c4',
          apps: {'com.duolingo'},
          target: Duration(minutes: 15),
        ),
        ShortcutCondition(id: 'c5', channel: 'pushups', requiredCount: 5),
      ],
    );

    final decoded = BlockCodec.decode(roundTrip(original));

    expect(decoded.blockAgainAfter, const Duration(hours: 2));
    expect(decoded.conditions, hasLength(5));
    expect((decoded.conditions[0] as StepsCondition).targetSteps, 6000);
    expect((decoded.conditions[1] as WorkoutCondition).target.inMinutes, 20);
    expect((decoded.conditions[2] as MeditateCondition).target.inMinutes, 10);
    expect((decoded.conditions[3] as AppTimeCondition).apps, {'com.duolingo'});
    final shortcut = decoded.conditions[4] as ShortcutCondition;
    expect(shortcut.channel, 'pushups');
    expect(shortcut.requiredCount, 5);
  });

  test('a timed lock keeps its deadline across a restart', () {
    final until = DateTime(2026, 12, 25, 9);
    final original = Block(
      id: 'b3',
      name: 'Locked',
      mode: LimitMode.time,
      apps: const {'com.instagram.android'},
      lock: Lock.timed(until: until, passwordHash: 'sha256\$1\$a\$b'),
    );

    final decoded = BlockCodec.decode(roundTrip(original));

    expect(decoded.lock.kind, LockKind.timed);
    expect(decoded.lock.until, until);
    expect(decoded.lock.passwordHash, 'sha256\$1\$a\$b');
  });

  test('a corrupt lock decodes as still locked, never as open', () {
    final decoded = BlockCodec.decode({
      'id': 'b4',
      'name': 'Broken',
      'mode': 'time',
      'apps': <String>['com.instagram.android'],
      // Kind survived, deadline did not.
      'lock': {'kind': 'timed'},
    });

    expect(decoded.lock.kind, LockKind.timed);
    expect(decoded.lock.isExpired(DateTime.now()), isFalse);
  });

  test('a schedule stored before weekdays existed runs every day', () {
    final decoded = BlockCodec.decode({
      'id': 'b5',
      'name': 'Old',
      'mode': 'time',
      'apps': <String>['com.instagram.android'],
      'schedule': [
        {'start': 540, 'end': 1020},
      ],
    });

    expect(decoded.schedule.single.weekdays, {1, 2, 3, 4, 5, 6, 7});
    expect(decoded.excludedApps, isEmpty);
  });

  test('an unknown condition type is dropped, not guessed at', () {
    final decoded = BlockCodec.decode({
      'id': 'b6',
      'name': 'Future',
      'mode': 'condition',
      'apps': <String>['com.instagram.android'],
      'conditions': [
        {'type': 'sleep', 'id': 'c1', 'hours': 8},
        {'type': 'steps', 'id': 'c2', 'targetSteps': 100},
      ],
    });

    expect(decoded.conditions, hasLength(1));
    expect(decoded.conditions.single, isA<StepsCondition>());
  });
}
