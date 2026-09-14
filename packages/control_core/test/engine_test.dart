import 'package:control_core/control_core.dart';
import 'package:test/test.dart';

const engine = RuleEngine();

Block timeBlock({
  required List<TimeRange> schedule,
  RulePolarity polarity = RulePolarity.blockDuring,
}) =>
    Block(
      id: 'focus',
      name: 'Focus',
      mode: LimitMode.time,
      apps: const {'com.netflix.mediaclient'},
      schedule: schedule,
      schedulePolarity: polarity,
    );

void main() {
  group('TimeRange', () {
    test('plain window contains only its own hours', () {
      // 09:00 - 17:00, the default from the New block sheet.
      const range = TimeRange(startMinute: 540, endMinute: 1020);
      expect(range.contains(DateTime(2026, 8, 26, 8, 59)), isFalse);
      expect(range.contains(DateTime(2026, 8, 26, 9, 0)), isTrue);
      expect(range.contains(DateTime(2026, 8, 26, 16, 59)), isTrue);
      // End is exclusive: at 17:00 sharp the apps come back.
      expect(range.contains(DateTime(2026, 8, 26, 17, 0)), isFalse);
    });

    test('window wrapping midnight covers both sides of the date change', () {
      // 22:00 - 06:00.
      const range = TimeRange(startMinute: 1320, endMinute: 360);
      expect(range.wrapsMidnight, isTrue);
      expect(range.contains(DateTime(2026, 8, 26, 23, 30)), isTrue);
      expect(range.contains(DateTime(2026, 8, 27, 2, 0)), isTrue);
      expect(range.contains(DateTime(2026, 8, 27, 6, 0)), isFalse);
      expect(range.contains(DateTime(2026, 8, 26, 21, 59)), isFalse);
    });

    test('wrapping window attributes its tail to the day it started', () {
      // Friday-only 22:00 - 06:00 must still block early Saturday.
      const friday = 5;
      const range =
          TimeRange(startMinute: 1320, endMinute: 360, weekdays: {friday});
      final fridayNight = DateTime(2026, 8, 28, 23, 0);
      final saturdayMorning = DateTime(2026, 8, 29, 3, 0);
      final saturdayNight = DateTime(2026, 8, 29, 23, 0);

      expect(fridayNight.weekday, friday);
      expect(range.contains(fridayNight), isTrue);
      expect(range.contains(saturdayMorning), isTrue);
      expect(range.contains(saturdayNight), isFalse);
    });

    test('nextBoundary lands on the next flip, not the next edge', () {
      const range = TimeRange(startMinute: 540, endMinute: 1020);
      expect(
        range.nextBoundary(DateTime(2026, 8, 26, 10, 0)),
        DateTime(2026, 8, 26, 17, 0),
      );
      expect(
        range.nextBoundary(DateTime(2026, 8, 26, 18, 0)),
        DateTime(2026, 8, 27, 9, 0),
      );
    });

    test('nextBoundary skips days the window does not run', () {
      const range =
          TimeRange(startMinute: 540, endMinute: 1020, weekdays: {1});
      // Monday evening: next flip is the following Monday morning.
      final mondayEvening = DateTime(2026, 8, 24, 18, 0);
      expect(mondayEvening.weekday, 1);
      expect(range.nextBoundary(mondayEvening), DateTime(2026, 8, 31, 9, 0));
    });
  });

  group('time mode', () {
    test('blocks inside the window and schedules the exit', () {
      final block = timeBlock(
        schedule: const [TimeRange(startMinute: 540, endMinute: 1020)],
      );
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );

      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.schedule);
      expect(decision.blockedApps, {'com.netflix.mediaclient'});
      expect(decision.nextEvaluationAt, DateTime(2026, 8, 26, 17, 0));
    });

    test('unblockDuring inverts the window', () {
      final block = timeBlock(
        schedule: const [TimeRange(startMinute: 540, endMinute: 1020)],
        polarity: RulePolarity.unblockDuring,
      );

      expect(
        engine
            .evaluate(
              block: block,
              signals: const Signals(),
              now: DateTime(2026, 8, 26, 10, 0),
            )
            .blocked,
        isFalse,
      );
      expect(
        engine
            .evaluate(
              block: block,
              signals: const Signals(),
              now: DateTime(2026, 8, 26, 20, 0),
            )
            .blocked,
        isTrue,
      );
    });

    test('a decision reports no blocked apps while it is not blocking', () {
      final block = timeBlock(
        schedule: const [TimeRange(startMinute: 540, endMinute: 1020)],
      );
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 20, 0),
      );

      expect(decision.blocked, isFalse);
      expect(decision.blockedApps, isEmpty);
    });
  });

  group('place mode', () {
    const home = GeoPoint(33.7782, 74.0946);
    final block = Block(
      id: 'home',
      name: 'Home',
      mode: LimitMode.place,
      apps: const {'com.instagram.android'},
      zone: const Zone(name: 'Home', center: home, radiusMeters: 250),
    );

    test('blocks inside the zone', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(
          location: GeoReading(point: home, accuracyMeters: 10),
        ),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.zone);
    });

    test('frees the apps well outside the zone', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(
          location: GeoReading(
            point: GeoPoint(33.7882, 74.0946),
            accuracyMeters: 10,
          ),
        ),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isFalse);
    });

    test('a fix too coarse to decide keeps blocking', () {
      // Sitting ~1.1 km out, but with 2 km of uncertainty the device could still
      // be at home, so access stays shut.
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(
          location: GeoReading(
            point: GeoPoint(33.7882, 74.0946),
            accuracyMeters: 2000,
          ),
        ),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isTrue);
    });

    test('no fix at all fails closed', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.signalUnavailable);
    });

    test('unlock-here zones demand certainty before opening up', () {
      final unlockHere = Block(
        id: 'gym',
        name: 'Gym',
        mode: LimitMode.place,
        apps: const {'com.instagram.android'},
        zone: const Zone(name: 'Gym', center: home, radiusMeters: 250),
        zonePolarity: RulePolarity.unblockDuring,
      );

      // Dead centre but with a 400 m error circle: not provably inside.
      final vague = engine.evaluate(
        block: unlockHere,
        signals: const Signals(
          location: GeoReading(point: home, accuracyMeters: 400),
        ),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(vague.blocked, isTrue);

      final sharp = engine.evaluate(
        block: unlockHere,
        signals: const Signals(
          location: GeoReading(point: home, accuracyMeters: 20),
        ),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(sharp.blocked, isFalse);
    });
  });

  group('device mode', () {
    final block = Block(
      id: 'tv',
      name: 'TV time',
      mode: LimitMode.device,
      apps: const {'com.netflix.mediaclient'},
      devices: const [
        DeviceTrigger(
          id: 'AA:BB:CC:DD:EE:FF',
          kind: DeviceKind.bluetooth,
          label: 'Car',
        ),
      ],
    );

    test('blocks while the trigger device is connected', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(connectedDevices: {'AA:BB:CC:DD:EE:FF'}),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.device);
      // Nothing time-driven here: only a connection event can change it.
      expect(decision.nextEvaluationAt, isNull);
    });

    test('frees the apps when it is gone', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(connectedDevices: {'11:22:33:44:55:66'}),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(decision.blocked, isFalse);
    });
  });

  group('condition mode', () {
    final block = Block(
      id: 'steps',
      name: 'Walk first',
      mode: LimitMode.condition,
      apps: const {'com.instagram.android'},
      conditions: const [StepsCondition(id: 'c1', targetSteps: 5000)],
      blockAgainAfter: const Duration(hours: 2),
    );
    final now = DateTime(2026, 8, 26, 9, 0);

    test('blocks until the habit is done, reporting progress', () {
      final decision = engine.evaluate(
        block: block,
        signals: const Signals(stepsToday: 2500),
        now: now,
      );
      expect(decision.blocked, isTrue);
      expect(decision.reason, BlockReason.conditionUnmet);
      expect(decision.conditionProgress.single.progress, closeTo(0.5, 1e-9));
    });

    test('meeting the target alone does not unlock: a grant must be minted', () {
      const signals = Signals(stepsToday: 6000);
      expect(engine.evaluate(block: block, signals: signals, now: now).blocked,
          isTrue);

      final grant =
          engine.mintGrantIfEarned(block: block, signals: signals, now: now);
      expect(grant, isNotNull);
      expect(grant!.effectiveExpiry(), now.add(const Duration(hours: 2)));

      final after = engine.evaluate(
        block: block,
        signals: signals.copyWith(grants: {'steps': grant}),
        now: now,
      );
      expect(after.blocked, isFalse);
      expect(after.reason, BlockReason.grantActive);
      expect(after.nextEvaluationAt, now.add(const Duration(hours: 2)));
    });

    test('the block re-arms once the grant decays', () {
      const signals = Signals(stepsToday: 6000);
      final grant =
          engine.mintGrantIfEarned(block: block, signals: signals, now: now)!;

      final later = now.add(const Duration(hours: 3));
      final decision = engine.evaluate(
        block: block,
        signals: signals.copyWith(grants: {'steps': grant}),
        now: later,
      );
      expect(decision.blocked, isTrue);

      // Still standing at 6000 steps, so the same day's work earns a fresh
      // grant. Requiring new steps per cycle is a product decision, not a
      // default; today the habit counts as done.
      expect(
        engine.mintGrantIfEarned(
          block: block,
          signals: signals.copyWith(grants: {'steps': grant}),
          now: later,
        ),
        isNotNull,
      );
    });

    test('no re-arm delay means the grant lasts until local midnight', () {
      final openEnded = Block(
        id: 'steps',
        name: 'Walk first',
        mode: LimitMode.condition,
        apps: const {'com.instagram.android'},
        conditions: const [StepsCondition(id: 'c1', targetSteps: 5000)],
      );
      final grant = engine.mintGrantIfEarned(
        block: openEnded,
        signals: const Signals(stepsToday: 6000),
        now: now,
      )!;

      expect(grant.expiresAt, isNull);
      expect(grant.effectiveExpiry(), DateTime(2026, 8, 27));
      expect(grant.isActive(DateTime(2026, 8, 26, 23, 59)), isTrue);
      expect(grant.isActive(DateTime(2026, 8, 27, 0, 1)), isFalse);
    });

    test('every condition must be met, not just one', () {
      final both = Block(
        id: 'combo',
        name: 'Earn it',
        mode: LimitMode.condition,
        apps: const {'com.instagram.android'},
        conditions: const [
          StepsCondition(id: 'c1', targetSteps: 5000),
          MeditateCondition(id: 'c2', target: Duration(minutes: 10)),
        ],
      );

      expect(
        engine.mintGrantIfEarned(
          block: both,
          signals: const Signals(stepsToday: 6000),
          now: now,
        ),
        isNull,
      );
      expect(
        engine.mintGrantIfEarned(
          block: both,
          signals: const Signals(
            stepsToday: 6000,
            mindfulToday: Duration(minutes: 12),
          ),
          now: now,
        ),
        isNotNull,
      );
    });

    test('app-time conditions sum across the selected apps', () {
      const condition = AppTimeCondition(
        id: 'c1',
        apps: {'com.duolingo', 'com.anki'},
        target: Duration(minutes: 30),
      );
      const signals = Signals(
        appUsageToday: {
          'com.duolingo': Duration(minutes: 20),
          'com.anki': Duration(minutes: 15),
          'com.netflix.mediaclient': Duration(hours: 2),
        },
      );
      expect(condition.isMet(signals), isTrue);
    });

    test('focus time earns the unlock, and the re-arm sets the reward window',
        () {
      // Four hours of study buys thirty minutes of the rationed apps.
      final block = Block(
        id: 'study',
        name: 'Study first',
        mode: LimitMode.condition,
        apps: const {'com.instagram.android'},
        conditions: const [
          FocusCondition(id: 'c1', target: Duration(hours: 4)),
        ],
        blockAgainAfter: const Duration(minutes: 30),
      );

      const halfway = Signals(focusToday: Duration(hours: 2));
      expect(
        engine.evaluate(block: block, signals: halfway, now: now).blocked,
        isTrue,
      );
      expect(
        engine
            .evaluate(block: block, signals: halfway, now: now)
            .conditionProgress
            .single
            .progress,
        closeTo(0.5, 1e-9),
      );

      const done = Signals(focusToday: Duration(hours: 4));
      final grant =
          engine.mintGrantIfEarned(block: block, signals: done, now: now)!;
      expect(grant.effectiveExpiry(), now.add(const Duration(minutes: 30)));

      final unlocked = engine.evaluate(
        block: block,
        signals: done.copyWith(grants: {'study': grant}),
        now: now,
      );
      expect(unlocked.blocked, isFalse);

      // Thirty-one minutes later the apps are shut again.
      final later = engine.evaluate(
        block: block,
        signals: done.copyWith(grants: {'study': grant}),
        now: now.add(const Duration(minutes: 31)),
      );
      expect(later.blocked, isTrue);
    });

    test('a place check-in is accepted only at the place, in the window', () {
      // Be within 150 m of the park between 04:30 and 05:00.
      const park = GeoPoint(33.7782, 74.0946);
      const condition = PlaceCheckInCondition(
        id: 'sunrise',
        zone: Zone(name: 'Park', center: park, radiusMeters: 150),
        window: TimeRange(startMinute: 270, endMinute: 300),
      );

      const there = GeoReading(point: park, accuracyMeters: 15);
      const elsewhere = GeoReading(
        point: GeoPoint(33.7882, 74.0946),
        accuracyMeters: 15,
      );

      final inWindow = DateTime(2026, 8, 26, 4, 45);
      final tooLate = DateTime(2026, 8, 26, 6, 0);

      expect(condition.canCheckIn(there, inWindow), isTrue);
      expect(condition.canCheckIn(there, tooLate), isFalse);
      expect(condition.canCheckIn(elsewhere, inWindow), isFalse);
      expect(condition.canCheckIn(null, inWindow), isFalse);
    });

    test('a vague fix cannot buy a place check-in', () {
      // Standing dead centre, but with 400 m of error: not provably there.
      // Otherwise this becomes a rule you can satisfy from bed.
      const park = GeoPoint(33.7782, 74.0946);
      const condition = PlaceCheckInCondition(
        id: 'sunrise',
        zone: Zone(name: 'Park', center: park, radiusMeters: 150),
        window: TimeRange(startMinute: 270, endMinute: 300),
      );

      expect(
        condition.canCheckIn(
          const GeoReading(point: park, accuracyMeters: 400),
          DateTime(2026, 8, 26, 4, 45),
        ),
        isFalse,
      );
    });

    test('the unlock lasts on the check-in, not on still being there', () {
      const condition = PlaceCheckInCondition(
        id: 'sunrise',
        zone: Zone(
          name: 'Park',
          center: GeoPoint(33.7782, 74.0946),
          radiusMeters: 150,
        ),
        window: TimeRange(startMinute: 270, endMinute: 300),
      );

      expect(condition.isMet(const Signals()), isFalse);
      // Checked in at dawn; still unlocked at lunchtime, back home.
      expect(
        condition.isMet(const Signals(placeCheckIns: {'sunrise'})),
        isTrue,
      );
    });

    test('a shortcut condition only counts its own channel', () {
      const condition = ShortcutCondition(id: 'c1', channel: 'pushups');
      expect(
        condition.isMet(const Signals(shortcutCounts: {'cold-shower': 3})),
        isFalse,
      );
      expect(
        condition.isMet(const Signals(shortcutCounts: {'pushups': 1})),
        isTrue,
      );
    });

    test('a repeated shortcut needs every firing', () {
      const condition =
          ShortcutCondition(id: 'c1', channel: 'pushups', requiredCount: 5);
      expect(
        condition.progress(const Signals(shortcutCounts: {'pushups': 2})),
        closeTo(0.4, 1e-9),
      );
      expect(
        condition.isMet(const Signals(shortcutCounts: {'pushups': 4})),
        isFalse,
      );
      expect(
        condition.isMet(const Signals(shortcutCounts: {'pushups': 5})),
        isTrue,
      );
    });
  });

  group('plan', () {
    test('unions blocked apps and wakes at the earliest flip', () {
      final blocks = [
        timeBlock(
          schedule: const [TimeRange(startMinute: 540, endMinute: 1020)],
        ),
        const Block(
          id: 'social',
          name: 'Social',
          mode: LimitMode.time,
          apps: {'com.instagram.android'},
          schedule: [TimeRange(startMinute: 480, endMinute: 720)],
        ),
      ];

      final plan = engine.plan(
        blocks: blocks,
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );

      expect(plan.blockedApps,
          {'com.netflix.mediaclient', 'com.instagram.android'});
      expect(plan.nextWakeAt, DateTime(2026, 8, 26, 12, 0));
      expect(plan.isEmpty, isFalse);
    });

    test('blocked sites ride along with the apps and lift with them', () {
      // Blocking the app and leaving the website open is the loophole this
      // exists to close, so the two have to move together.
      const block = Block(
        id: 'social',
        name: 'Social',
        mode: LimitMode.time,
        apps: {'com.instagram.android'},
        blockedDomains: {'instagram.com'},
        schedule: [TimeRange(startMinute: 540, endMinute: 1020)],
      );

      final inside = engine.plan(
        blocks: const [block],
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(inside.blockedApps, {'com.instagram.android'});
      expect(inside.blockedDomains, {'instagram.com'});

      final outside = engine.plan(
        blocks: const [block],
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 20, 0),
      );
      expect(outside.isEmpty, isTrue);
    });

    test('a site-only block is a real block, with no apps selected', () {
      const block = Block(
        id: 'web',
        name: 'Web only',
        mode: LimitMode.time,
        blockedDomains: {'youtube.com'},
        schedule: [TimeRange(startMinute: 540, endMinute: 1020)],
      );

      final plan = engine.plan(
        blocks: const [block],
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(plan.blockedDomains, {'youtube.com'});
      expect(plan.decisions.single.reason, BlockReason.schedule);
    });

    test('a disabled block contributes nothing', () {
      final plan = engine.plan(
        blocks: [
          const Block(
            id: 'off',
            name: 'Off',
            mode: LimitMode.time,
            apps: {'com.instagram.android'},
            schedule: [TimeRange(startMinute: 0, endMinute: 1439)],
            enabled: false,
          ),
        ],
        signals: const Signals(),
        now: DateTime(2026, 8, 26, 10, 0),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.decisions.single.reason, BlockReason.disabled);
    });
  });
}
