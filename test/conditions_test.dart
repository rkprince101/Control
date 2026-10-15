import 'dart:io';

import 'package:control/data/activity.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('coveredTime', () {
    final day = DateTime(2026, 10, 14);
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 10, 14, hour, minute);

    test('overlapping sources count once', () {
      // Timed 7:00-7:45 in Control, recorded 7:10-8:00 by a watch.
      final total = coveredTime(
        [(at(7), at(7, 45)), (at(7, 10), at(8))],
        day,
        at(23),
      );
      expect(total, const Duration(hours: 1));
    });

    test('separate sessions add up', () {
      final total = coveredTime(
        [(at(7), at(7, 30)), (at(18), at(18, 20))],
        day,
        at(23),
      );
      expect(total, const Duration(minutes: 50));
    });

    test('only the part inside the window counts', () {
      // Started last night at 23:30, ran to 00:30.
      final total = coveredTime(
        [(DateTime(2026, 10, 13, 23, 30), at(0, 30))],
        day,
        at(12),
      );
      expect(total, const Duration(minutes: 30));
    });

    test('nothing inside the window is zero', () {
      expect(coveredTime([(at(20), at(21))], day, at(12)), Duration.zero);
      expect(coveredTime(const [], day, at(12)), Duration.zero);
    });
  });

  group('ActivitySession', () {
    final start = DateTime(2026, 10, 14, 6);

    test('a running timer counts up to now', () {
      final session = ActivitySession(
        kind: ActivityKind.workout,
        startedAt: start,
      );
      expect(
        session.lengthAt(start.add(const Duration(minutes: 25))),
        const Duration(minutes: 25),
      );
    });

    test('a forgotten timer stops counting at its cap', () {
      final session = ActivitySession(
        kind: ActivityKind.meditate,
        startedAt: start,
      );
      expect(
        session.lengthAt(start.add(const Duration(hours: 9))),
        ActivitySession.maxLength,
      );
    });

    test('round trips through storage', () {
      final session = ActivitySession(
        kind: ActivityKind.workout,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 40)),
      );
      final back = ActivitySession.fromMap(session.toMap())!;
      expect(back.kind, session.kind);
      expect(back.startedAt, session.startedAt);
      expect(back.endedAt, session.endedAt);
      expect(ActivitySession.fromMap(const {'kind': 'nope'}), isNull);
    });
  });

  group('store', () {
    const channel = MethodChannel('dev.control/enforcement');
    late Directory storage;
    late ControlStore store;
    late List<MethodCall> calls;
    late Map<String, Object?> healthStatus;
    late Map<String, Object?> healthSessions;
    late Map<String, Object?> locationStatus;
    Map<String, Object?>? fix;

    setUp(() {
      storage = Directory.systemTemp.createTempSync('control_conditions');
      store = ControlStore(storageDirectory: storage);
      calls = [];
      healthStatus = {
        'sdk': 'available',
        'workout': true,
        'mindful': true,
        'mindfulSupported': true,
      };
      healthSessions = {'workout': <Object?>[], 'mindful': <Object?>[]};
      locationStatus = {'granted': true, 'enabled': true};
      fix = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'healthStatus' => healthStatus,
              'healthSessions' => healthSessions,
              'locationStatus' => locationStatus,
              'currentLocation' => fix,
              'shortcutCounts' => <String, int>{},
              _ => null,
            };
          });
    });

    tearDown(() {
      store.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      storage.deleteSync(recursive: true);
    });

    const workoutBlock = Block(
      id: 'gym',
      name: 'Gym first',
      mode: LimitMode.condition,
      apps: {'video.app'},
      conditions: [
        WorkoutCondition(id: 'gym-workout', target: Duration(minutes: 30)),
      ],
    );

    test('a workout recorded in Health Connect unlocks the block', () async {
      await store.init();
      await store.addBlock(workoutBlock);
      expect(store.decisionFor('gym')!.blocked, isTrue);

      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 40));
      // Midnight-safe: only test when the session fits inside today.
      if (start.day != now.day) return;
      healthSessions = {
        'workout': [
          [
            start.millisecondsSinceEpoch,
            now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          ],
        ],
        'mindful': <Object?>[],
      };
      await store.refreshSignals();

      expect(store.signals.workoutToday, const Duration(minutes: 35));
      expect(store.decisionFor('gym')!.blocked, isFalse);
    });

    test('Health Connect is not asked when no rule needs it', () async {
      await store.init();
      expect(calls.where((call) => call.method == 'healthSessions'), isEmpty);
    });

    test('the built-in timer starts, counts and stops', () async {
      await store.init();
      await store.addBlock(workoutBlock);
      await store.startActivity(ActivityKind.workout);
      expect(store.runningActivity?.kind, ActivityKind.workout);
      // Starting the other one stops this one: one timer at a time.
      await store.startActivity(ActivityKind.meditate);
      expect(store.runningActivity?.kind, ActivityKind.meditate);
      await store.stopActivity();
      expect(store.runningActivity, isNull);
    });

    test('the timer survives a restart of the app', () async {
      await store.init();
      await store.startActivity(ActivityKind.meditate);
      store.dispose();

      store = ControlStore(storageDirectory: storage);
      await store.init();
      expect(store.runningActivity?.kind, ActivityKind.meditate);
      await store.stopActivity();
    });

    group('check-in', () {
      const placeBlock = Block(
        id: 'park',
        name: 'Park first',
        mode: LimitMode.condition,
        apps: {'video.app'},
        conditions: [
          PlaceCheckInCondition(
            id: 'park-place',
            zone: Zone(
              name: 'Park',
              center: GeoPoint(28.6139, 77.2090),
              radiusMeters: 200,
            ),
            // All day, every day.
            window: TimeRange(startMinute: 0, endMinute: 0),
          ),
        ],
      );

      Future<CheckInResult> checkIn() async {
        await store.init();
        await store.addBlock(placeBlock);
        return store.checkInPlace('park-place');
      }

      test('a fix inside the zone checks in', () async {
        fix = {'latitude': 28.6139, 'longitude': 77.2090, 'accuracy': 15.0};
        expect(await checkIn(), CheckInResult.success);
        expect(store.decisionFor('park')!.blocked, isFalse);
      });

      test('a mock location never checks in', () async {
        fix = {
          'latitude': 28.6139,
          'longitude': 77.2090,
          'accuracy': 5.0,
          'mock': true,
        };
        expect(await checkIn(), CheckInResult.mockLocation);
        expect(store.decisionFor('park')!.blocked, isTrue);
      });

      test('approximate location is named, not reported as missing', () async {
        locationStatus = {
          'granted': false,
          'enabled': true,
          'approximateOnly': true,
        };
        expect(await checkIn(), CheckInResult.approximateOnly);
      });

      test('location switched on since the last resume is noticed', () async {
        // The status read on resume said off; it is on by the time of the tap.
        locationStatus = {'granted': true, 'enabled': true};
        fix = {'latitude': 28.6139, 'longitude': 77.2090, 'accuracy': 15.0};
        await store.init();
        store.locationStatus = const LocationStatus(
          granted: true,
          enabled: false,
        );
        await store.addBlock(placeBlock);
        expect(await store.checkInPlace('park-place'), CheckInResult.success);
      });

      test('a vague fix near the edge is refused', () async {
        // 150 m from the centre, accurate to 100 m: might be outside.
        fix = {'latitude': 28.61525, 'longitude': 77.2090, 'accuracy': 100.0};
        expect(await checkIn(), CheckInResult.fixTooVague);
      });

      test('a cell-tower fix off-centre is too vague, not too far', () async {
        // Seen on a phone indoors: 502 m off, accurate to 800 m, zone 200 m.
        fix = {'latitude': 28.6184, 'longitude': 77.2090, 'accuracy': 800.0};
        expect(await checkIn(), CheckInResult.fixTooVague);
      });

      test('a fix far away is too far', () async {
        fix = {'latitude': 28.70, 'longitude': 77.2090, 'accuracy': 10.0};
        expect(await checkIn(), CheckInResult.tooFar);
      });
    });
  });
}
