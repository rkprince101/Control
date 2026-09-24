import 'dart:convert';
import 'dart:io';

import 'package:control/data/focus.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The timer as the store runs it: what a tap changes, what Android is told,
/// and what survives the app being closed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;
  final calls = <MethodCall>[];

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_focus');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.control/enforcement'),
          (call) async {
            calls.add(call);
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

  Map<String, Object?> lastTimerNotification() =>
      (calls.lastWhere((call) => call.method == 'showFocusTimer').arguments
              as Map)
          .cast<String, Object?>();

  /// Writes sessions straight into the saved state, as a previous run would
  /// have left them.
  void seed(List<FocusSession> sessions) {
    File(
      '${storage.path}${Platform.pathSeparator}control_state.json',
    ).writeAsStringSync(
      jsonEncode({
        'focusSessions': [for (final s in sessions) s.toMap()],
      }),
    );
  }

  test('start, pause, resume and finish; Android shows each state', () async {
    final store = ControlStore(storageDirectory: storage);
    await store.init();

    await store.startFocus('study', kind: FocusKind.stopwatch);
    expect(store.runningFocus!.isPaused, isFalse);
    var shown = lastTimerNotification();
    expect(shown['countDown'], isFalse);
    expect(shown['clockAt'], isNot(0), reason: 'Android runs the clock');
    expect(
      calls.map((c) => c.method),
      contains('requestNotificationPermission'),
    );

    await store.pauseFocus();
    expect(store.runningFocus!.isPaused, isTrue);
    shown = lastTimerNotification();
    expect(shown['title'], startsWith('Paused'));
    expect(shown['clockAt'], 0, reason: 'a paused clock does not run');

    await store.resumeFocus();
    expect(store.runningFocus!.isPaused, isFalse);
    expect(store.runningFocus!.pauses, hasLength(1));

    await store.stopFocus();
    expect(store.runningFocus, isNull);
    expect(store.lastFinishedFocus, isNotNull);
    expect(calls.map((c) => c.method), contains('cancelFocusTimer'));

    store.dismissFocusResult();
    expect(store.lastFinishedFocus, isNull);
    store.dispose();
  });

  test('a pomodoro counts down in the notification', () async {
    final store = ControlStore(storageDirectory: storage);
    await store.init();
    final before = DateTime.now();
    await store.startFocus(
      'study',
      kind: FocusKind.pomodoro,
      plannedWork: const Duration(minutes: 25),
    );
    final shown = lastTimerNotification();
    expect(shown['countDown'], isTrue);
    final end = DateTime.fromMillisecondsSinceEpoch(shown['clockAt']! as int);
    expect(
      end.difference(before).inMinutes,
      inInclusiveRange(24, 25),
      reason: 'counts down to the finish line',
    );
    store.dispose();
  });

  test('a pomodoro that ended while the app was closed closes at its finish '
      'line', () async {
    // Whole milliseconds, which is what the saved state holds.
    final started = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    );
    seed([
      FocusSession(
        blockId: 'study',
        startedAt: started,
        kind: FocusKind.pomodoro,
        plannedWork: const Duration(minutes: 25),
      ),
    ]);

    final store = ControlStore(storageDirectory: storage);
    await store.init();
    expect(store.runningFocus, isNull);
    final finished = store.lastFinishedFocus!;
    expect(finished.endedAt, started.add(const Duration(minutes: 25)));
    expect(store.focusLengthOf(finished), const Duration(minutes: 25));
    store.dispose();

    // And it stays closed on the next launch.
    final again = ControlStore(storageDirectory: storage);
    await again.init();
    expect(again.runningFocus, isNull);
    expect(again.focusSessions.single.endedAt, finished.endedAt);
    again.dispose();
  });

  test('a paused session stays paused across a restart', () async {
    final first = ControlStore(storageDirectory: storage);
    await first.init();
    await first.startFocus('study', kind: FocusKind.stopwatch);
    await first.pauseFocus();
    first.dispose();

    final second = ControlStore(storageDirectory: storage);
    await second.init();
    expect(second.runningFocus!.isPaused, isTrue);
    second.dispose();
  });

  test(
    'breaks are five minutes, fifteen after every fourth pomodoro',
    () async {
      final now = DateTime.now();
      seed([
        for (var i = 0; i < 4; i++)
          FocusSession(
            blockId: 'study',
            startedAt: now.subtract(Duration(seconds: 40 - i * 8)),
            endedAt: now.subtract(Duration(seconds: 38 - i * 8)),
            kind: FocusKind.pomodoro,
            plannedWork: const Duration(seconds: 1),
          ),
      ]);
      final store = ControlStore(storageDirectory: storage);
      await store.init();
      expect(store.pomodorosToday, 4);
      expect(store.nextBreakLength, const Duration(minutes: 15));

      await store.startFocus('study', kind: FocusKind.pomodoro);
      await store.stopFocus();
      // Finished early, so not a fifth completed pomodoro.
      expect(store.pomodorosToday, 4);
      await store.startBreak();
      expect(store.focusBreak!.length, const Duration(minutes: 15));
      expect(store.lastFinishedFocus, isNull);
      expect(lastTimerNotification()['title'], 'Break');

      await store.skipBreak();
      expect(store.focusBreak, isNull);
      expect(calls.last.method, 'cancelFocusTimer');
      store.dispose();
    },
  );

  test('starting another block finishes the running timer', () async {
    final store = ControlStore(storageDirectory: storage);
    await store.init();
    await store.startFocus('study', kind: FocusKind.stopwatch);
    await store.startFocus('reading', kind: FocusKind.stopwatch);
    expect(store.focusSessions, hasLength(2));
    expect(store.focusSessions.first.isRunning, isFalse);
    expect(store.runningFocus!.blockId, 'reading');
    store.dispose();
  });
}
