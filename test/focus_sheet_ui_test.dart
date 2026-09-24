import 'package:control/data/focus.dart';
import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/focus_stats_sheet.dart';
import 'package:control/ui/sheet.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Timer state held in plain fields, so each test can put the sheet in the
/// state it wants without waiting on a real clock.
class _FocusStore extends ControlStore {
  final now = DateTime(2026, 9, 23, 12);
  Duration total = const Duration(minutes: 30);
  final starts = <(String, FocusKind, Duration?)>[];
  final actions = <String>[];
  FocusSession? running;

  @override
  Duration get focusToday => total;

  @override
  DateTime focusNow() => now;

  @override
  Duration focusLengthOf(FocusSession session) => session.lengthAt(now);

  @override
  FocusSession? get runningFocus => running;

  @override
  FocusStats focusStats({String? blockId}) => FocusStats.from(
    [
      FocusSession(
        blockId: 'study',
        startedAt: now.subtract(const Duration(minutes: 15)),
        endedAt: now,
        kind: FocusKind.stopwatch,
      ),
      FocusSession(
        blockId: 'study',
        startedAt: now.subtract(const Duration(days: 1, minutes: 30)),
        endedAt: now.subtract(const Duration(days: 1, minutes: 5)),
        kind: FocusKind.pomodoro,
        plannedWork: const Duration(minutes: 25),
      ),
    ],
    now,
    blockId: blockId,
  );

  @override
  Future<void> startFocus(
    String blockId, {
    required FocusKind kind,
    Duration? plannedWork,
  }) async {
    starts.add((blockId, kind, plannedWork));
  }

  @override
  Future<void> pauseFocus() async {
    actions.add('pause');
    running = running!.pausedAt(now);
    notifyListeners();
  }

  @override
  Future<void> resumeFocus() async {
    actions.add('resume');
    running = running!.resumedAt(now);
    notifyListeners();
  }

  @override
  Future<void> stopFocus() async {
    actions.add('stop');
    lastFinishedFocus = running!.stoppedAt(now);
    running = null;
    notifyListeners();
  }

  @override
  Future<void> startBreak() async {
    actions.add('break');
    focusBreak = FocusBreak(
      blockId: 'study',
      startedAt: now,
      length: const Duration(minutes: 5),
    );
    lastFinishedFocus = null;
    notifyListeners();
  }

  @override
  Future<void> skipBreak() async {
    actions.add('skip');
    focusBreak = null;
    notifyListeners();
  }
}

void main() {
  const block = Block(
    id: 'study',
    name: 'Space for deep focus and a quieter afternoon',
    mode: LimitMode.condition,
    conditions: [FocusCondition(id: 'focus', target: Duration(hours: 1))],
  );
  late _FocusStore store;

  setUp(() => store = _FocusStore());
  tearDown(() => store.dispose());

  Future<void> open(
    WidgetTester tester, {
    bool stats = false,
    double width = 320,
    double scale = 2,
    Brightness brightness = Brightness.light,
    Block selectedBlock = block,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: buildControlTheme(brightness: brightness),
          // Layout checks need a settled frame, so the wave holds still.
          builder: (context, child) => WaveMotionScope(
            motion: WaveMotion.off,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => stats
                    ? FocusStatsSheet.show(context, selectedBlock)
                    : FocusTimerSheet.show(context, selectedBlock),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// The stats list builds lazily, so anything below the fold has to be
  /// scrolled to before it exists.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(
            of: find.byType(FocusStatsSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (800.0, 2.0)]) {
      testWidgets('stats fit $width at ${scale}x in ${brightness.name}', (
        tester,
      ) async {
        await open(
          tester,
          stats: true,
          width: width,
          scale: scale,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        // The same chrome as the block editor: a grabber and a header row.
        expect(find.byType(SheetGrabber), findsOneWidget);
        expect(find.text('Focus stats'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);

        await scrollTo(tester, find.byType(ExpressiveProgress));
        final progress = tester.widget<ExpressiveProgress>(
          find.byType(ExpressiveProgress).first,
        );
        expect(progress.value, 0.5);
        expect(progress.semanticsLabel, contains('30m of 1h'));

        // Today (Wednesday) holds 15 minutes against an hour's goal.
        await scrollTo(tester, find.byKey(const ValueKey('focus-bar-3')));
        final today = tester.getSize(find.byKey(const ValueKey('focus-bar-3')));
        final tuesday = tester.getSize(
          find.byKey(const ValueKey('focus-bar-2')),
        );
        final monday = tester.getSize(
          find.byKey(const ValueKey('focus-bar-1')),
        );
        expect(today.height, closeTo(128 * 0.25, 0.5));
        expect(tuesday.height, closeTo(128 * 25 / 60, 0.5));
        expect(monday.height, 4, reason: 'an empty day keeps a stub');

        await tester.ensureVisible(find.text('6 weeks', skipOffstage: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6 weeks'));
        await tester.pumpAndSettle();
        expect(find.text('Last 6 weeks', skipOffstage: false), findsOneWidget);
        final messages = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message)
            .whereType<String>()
            .toList();
        expect(messages, [
          for (final (day, duration)
              in store.focusStats(blockId: block.id).daily)
            '${day.day}/${day.month}: ${formatDuration(duration)}',
        ]);

        await scrollTo(tester, find.text('Pomodoro, 25m'));
        expect(find.text('Stopwatch, 15m'), findsOneWidget);
        await scrollTo(tester, find.textContaining('until midnight'));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final minutes in [15, 25, 50, 90]) {
    testWidgets('start preserves $minutes minute pomodoro at 320 and 2x', (
      tester,
    ) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SheetGrabber), findsOneWidget);
      await tapVisible(tester, '$minutes min');
      await tapVisible(tester, 'Start');
      expect(store.starts, [
        ('study', FocusKind.pomodoro, Duration(minutes: minutes)),
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stopwatch preserves kind', (tester) async {
    await open(tester, brightness: Brightness.dark);
    await tapVisible(tester, '50 min');
    await tapVisible(tester, 'Stopwatch');
    expect(find.text('50 min'), findsNothing);
    expect(
      find.text(
        'Counts up until you finish it. Closing the app does not stop it.',
      ),
      findsOneWidget,
    );
    await tapVisible(tester, 'Start');
    expect(store.starts.single.$2, FocusKind.stopwatch);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a running pomodoro counts down, pauses and resumes', (
    tester,
  ) async {
    store.running = FocusSession(
      blockId: 'study',
      startedAt: store.now.subtract(const Duration(minutes: 15)),
      kind: FocusKind.pomodoro,
      plannedWork: const Duration(minutes: 25),
    );
    await open(tester, width: 400, scale: 1);
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('left'), findsOneWidget);
    expect(find.text('Pomodoro, 25m'), findsOneWidget);

    await tapVisible(tester, 'Pause');
    expect(store.actions, ['pause']);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    await tapVisible(tester, 'Resume');
    expect(store.actions, ['pause', 'resume']);
    expect(find.text('Pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stopwatch counts up; finishing shows what was banked', (
    tester,
  ) async {
    store.running = FocusSession(
      blockId: 'study',
      startedAt: store.now.subtract(const Duration(minutes: 42, seconds: 7)),
      kind: FocusKind.stopwatch,
    );
    await open(tester, width: 400, scale: 1);
    expect(find.text('42:07'), findsOneWidget);
    expect(find.text('focused'), findsOneWidget);

    await tapVisible(tester, 'Finish');
    expect(store.actions, ['stop']);
    expect(find.text('Session finished'), findsOneWidget);
    expect(find.textContaining('42m banked'), findsOneWidget);
    expect(find.text('Start another'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a finished pomodoro offers the break, which counts down', (
    tester,
  ) async {
    store.lastFinishedFocus = FocusSession(
      blockId: 'study',
      startedAt: store.now.subtract(const Duration(minutes: 25)),
      endedAt: store.now,
      kind: FocusKind.pomodoro,
      plannedWork: const Duration(minutes: 25),
    );
    await open(tester, width: 400, scale: 1);
    expect(find.text('Pomodoro done'), findsOneWidget);
    expect(find.text('Skip the break, go again'), findsOneWidget);

    await tapVisible(tester, 'Take a 5m break');
    expect(store.actions, ['break']);
    expect(find.text('05:00'), findsOneWidget);

    await tapVisible(tester, 'Skip break');
    expect(store.actions, ['break', 'skip']);
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed goal clamps progress and shows finite allowance', (
    tester,
  ) async {
    store.total = const Duration(hours: 2);
    await open(
      tester,
      stats: true,
      selectedBlock: block.copyWith(
        blockAgainAfter: const Duration(minutes: 45),
      ),
    );
    await scrollTo(tester, find.byType(ExpressiveProgress));
    expect(
      tester
          .widget<ExpressiveProgress>(find.byType(ExpressiveProgress).first)
          .value,
      1.0,
    );
    await scrollTo(tester, find.textContaining('these apps for 45m.'));
    expect(find.textContaining('these apps for 45m.'), findsOneWidget);
    expect(find.textContaining('until midnight'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
