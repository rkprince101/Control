import 'dart:async';
import 'dart:io';

import 'package:control/platform/enforcement_channel.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.control/enforcement');
  late Directory storage;
  late ControlStore store;
  late List<MethodCall> calls;
  late bool granted;
  late bool disposed;
  Future<Object?> Function(MethodCall)? timelineReply;
  Object? Function(MethodCall)? snapshotReply;
  DateTime? enforcementTime;

  Map<String, Object?> snapshot(int minutes) => {
    'apps': [
      {'package': 'reader', 'label': 'Reader', 'millis': minutes * 60000},
    ],
    'totalScreenMillis': minutes * 60000,
    'pickups': 2,
  };

  Map<String, Object?> timeline(MethodCall call, int minutes) {
    final args = call.arguments as Map;
    return {
      ...snapshot(minutes),
      'startMillis': args['startMillis'],
      'endMillis': args['endMillis'],
      'firstEventAt': args['startMillis'],
      'historyNote': 'Android may omit older activity.',
      'buckets': [
        {
          'startMillis': args['startMillis'],
          'endMillis': args['endMillis'],
          'millis': minutes * 60000,
          'pickups': 2,
        },
      ],
    };
  }

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_insights');
    store = ControlStore(storageDirectory: storage);
    calls = [];
    granted = true;
    disposed = false;
    timelineReply = null;
    snapshotReply = null;
    enforcementTime = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'usageTimeline') {
            return timelineReply == null
                ? timeline(call, 180)
                : await timelineReply!(call);
          }
          return switch (call.method) {
            'hasUsageAccess' => granted,
            'usageSnapshot' => snapshotReply?.call(call) ?? snapshot(15),
            'enforcementTime' => enforcementTime?.millisecondsSinceEpoch,
            'shortcutCounts' => <String, int>{},
            _ => null,
          };
        });
  });

  tearDown(() {
    if (!disposed) store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    storage.deleteSync(recursive: true);
  });

  test('legacy snapshots and constructors retain optional defaults', () {
    final old = UsageSnapshot.fromMap(snapshot(15));
    const constructed = UsageSnapshot(
      apps: [],
      screenTime: Duration.zero,
      pickups: 0,
    );
    for (final value in [old, constructed, const UsageSnapshot.empty()]) {
      expect(value.buckets, isEmpty);
      expect(value.start, isNull);
      expect(value.end, isNull);
      expect(value.firstEventAt, isNull);
      expect(value.historyNote, isNull);
    }
    expect(old.screenTime, const Duration(minutes: 15));
  });

  test('channel sends exact timeline contract and decodes metadata', () async {
    final start = DateTime(2026, 9, 22);
    final end = DateTime(2026, 9, 23, 12);
    final value = await const EnforcementChannel().usageTimeline(
      start: start,
      end: end,
      bucket: 'day',
    );
    expect(calls.single.arguments, {
      'startMillis': start.millisecondsSinceEpoch,
      'endMillis': end.millisecondsSinceEpoch,
      'bucket': 'day',
    });
    expect(value.start, start);
    expect(value.end, end);
    expect(value.firstEventAt, start);
    expect(value.historyNote, contains('older activity'));
    expect(value.buckets.single.start, start);
    expect(value.buckets.single.end, end);
    expect(value.buckets.single.screenTime, value.screenTime);
    expect(value.buckets.single.pickups, value.pickups);
  });

  test('range dates are trailing local calendar days', () {
    final now = DateTime(2026, 3, 10, 14);
    expect(InsightsRange.day.startFrom(now), DateTime(2026, 3, 10));
    expect(InsightsRange.week.startFrom(now), DateTime(2026, 3, 4));
    expect(InsightsRange.month.startFrom(now), DateTime(2026, 2, 9));
  });

  test(
    'refreshAll keeps today signals and widget separate from insights',
    () async {
      await store.setInsightsRange(InsightsRange.week);
      await store.refreshAll();
      expect(store.usage.screenTime, const Duration(minutes: 15));
      expect(
        store.signals.appUsageToday['reader'],
        const Duration(minutes: 15),
      );
      expect(store.insightsUsage.screenTime, const Duration(minutes: 180));
      expect(store.insightsUpdatedAt, isNotNull);
      expect(store.insightsError, isNull);
      expect(store.insightsLoading, isFalse);
      final summary = calls.lastWhere((c) => c.method == 'updateSummary');
      expect((summary.arguments as Map)['screenTime'], '15m');
      final todayCall = calls.lastWhere((c) => c.method == 'usageSnapshot');
      final today = DateTime.fromMillisecondsSinceEpoch(
        (todayCall.arguments as Map)['startMillis'] as int,
      );
      final current = DateTime.now();
      expect(today, DateTime(current.year, current.month, current.day));
      final historyCall = calls.lastWhere((c) => c.method == 'usageTimeline');
      final args = historyCall.arguments as Map;
      expect(args['bucket'], 'day');
      expect(
        DateTime.fromMillisecondsSinceEpoch(args['startMillis'] as int),
        InsightsRange.week.startFrom(current),
      );
      expect(calls.indexOf(todayCall), lessThan(calls.indexOf(historyCall)));

      await store.setInsightsRange(InsightsRange.month);
      await store.publish();
      expect(store.usage.screenTime, const Duration(minutes: 15));
      expect(
        (calls.lastWhere((c) => c.method == 'updateSummary').arguments
            as Map)['screenTime'],
        '15m',
      );
    },
  );

  test(
    'range change clears old data synchronously and rejects stale success',
    () async {
      store.usageAccessGranted = true;
      await store.refreshInsights();
      final pending = <Completer<Object?>>[];
      timelineReply = (call) {
        final result = Completer<Object?>();
        pending.add(result);
        return result.future;
      };
      final week = store.setInsightsRange(InsightsRange.week);
      expect(store.insightsUsage.buckets, isEmpty);
      expect(store.insightsUpdatedAt, isNull);
      expect(store.insightsLoading, isTrue);
      await pumpEventQueue();
      final month = store.setInsightsRange(InsightsRange.month);
      await pumpEventQueue();
      pending[1].complete(snapshot(300));
      await month;
      final updated = store.insightsUpdatedAt;
      pending[0].complete(snapshot(60));
      await week;
      expect(store.insightsRange, InsightsRange.month);
      expect(store.insightsUsage.screenTime, const Duration(minutes: 300));
      expect(store.insightsUpdatedAt, updated);
      expect(store.insightsLoading, isFalse);
      expect(store.usage.screenTime, Duration.zero);
    },
  );

  test('widget uses calendar today without changing protection-clock habits', () async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    enforcementTime = tomorrow.add(const Duration(hours: 12));
    snapshotReply = (call) => snapshot(
      (call.arguments as Map)['startMillis'] == tomorrow.millisecondsSinceEpoch
          ? 90 : 15,
    );
    await store.init();
    expect(store.signals.appUsageToday['reader'], const Duration(minutes: 90));
    expect(store.usage.screenTime, const Duration(minutes: 15));
    expect(
      (calls.lastWhere((call) => call.method == 'updateSummary').arguments as Map)['screenTime'],
      '15m',
    );
  });

  test('stale errors cannot revoke access or finish newer loading', () async {
    store.usageAccessGranted = true;
    final pending = <Completer<Object?>>[];
    timelineReply = (_) {
      final result = Completer<Object?>();
      pending.add(result);
      return result.future;
    };
    final first = store.refreshInsights();
    await pumpEventQueue();
    final second = store.refreshInsights();
    await pumpEventQueue();
    pending[0].completeError(PlatformException(code: 'permission_denied'));
    await first;
    expect(store.insightsLoading, isTrue);
    expect(store.usageAccessGranted, isTrue);
    expect(store.insightsError, isNull);
    pending[1].complete(snapshot(20));
    await second;
    expect(store.insightsUsage.screenTime, const Duration(minutes: 20));
  });

  test(
    'denial is visible, clears history, and supports permission retry',
    () async {
      store.usageAccessGranted = true;
      await store.refreshInsights();
      timelineReply = (_) async =>
          throw PlatformException(code: 'permission_denied');
      await store.refreshInsights();
      expect(store.usageAccessGranted, isFalse);
      expect(store.insightsError, contains('Grant usage access'));
      expect(store.insightsUsage.buckets, isEmpty);
      expect(store.insightsUpdatedAt, isNull);
      expect(store.insightsLoading, isFalse);
      final count = calls.length;
      await store.setInsightsRange(InsightsRange.month);
      expect(calls.length, count);
      timelineReply = null;
      await store.refreshAll();
      expect(store.usageAccessGranted, isTrue);
      expect(store.insightsError, isNull);
      expect(store.insightsUsage.screenTime, const Duration(minutes: 180));
    },
  );

  test(
    'null and failed timeline replies are errors, not empty success',
    () async {
      store.usageAccessGranted = true;
      timelineReply = (_) async => null;
      await store.refreshInsights();
      expect(store.insightsError, isNotNull);
      expect(store.insightsUpdatedAt, isNull);
      timelineReply = (_) async =>
          throw PlatformException(code: 'usage_unavailable');
      await store.setInsightsRange(InsightsRange.week);
      expect(store.insightsError, isNotNull);
      expect(store.insightsLoading, isFalse);
    },
  );

  test(
    'day requests hourly buckets and successful empty history stays empty',
    () async {
      store.usageAccessGranted = true;
      timelineReply = (_) async => {
        'apps': <Object?>[],
        'totalScreenMillis': 0,
        'pickups': 0,
        'buckets': <Object?>[],
      };
      await store.refreshInsights();
      expect((calls.single.arguments as Map)['bucket'], 'hour');
      expect(store.insightsError, isNull);
      expect(store.insightsUpdatedAt, isNotNull);
      expect(store.insightsUsage.screenTime, Duration.zero);
    },
  );

  test('disposing during a request drops its completion safely', () async {
    store.usageAccessGranted = true;
    final pending = Completer<Object?>();
    timelineReply = (_) => pending.future;
    final refresh = store.refreshInsights();
    await pumpEventQueue();
    store.dispose();
    disposed = true;
    pending.complete(snapshot(60));
    await refresh;
    expect(store.insightsUpdatedAt, isNull);
  });
}
