import 'dart:io';

import 'package:control/data/focus.dart';
import 'package:control/data/habits.dart';
import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/blocks_page.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/focus_stats_sheet.dart';
import 'package:control/ui/habits_page.dart';
import 'package:control/ui/insights_page.dart';
import 'package:control/ui/settings_page.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preview-only fixtures; never hydrate storage or publish enforcement plans.
class _PreviewStore extends ControlStore {
  _PreviewStore() {
    usageAccessGranted = true;
    accessibilityEnabled = true;
    theme = AppThemeChoice.light;
    // Screenshots are single frames; a travelling wave would never settle.
    waveMotion = WaveMotion.off;
    final start = DateTime(2026, 9, 23);
    // Actual hourly history through 14:00, without invented future buckets.
    const minutes = [0, 0, 0, 0, 0, 0, 5, 12, 25, 32, 18, 41, 30, 41];
    const pickups = [0, 0, 0, 0, 0, 0, 1, 2, 4, 5, 3, 6, 5, 6];
    usage = UsageSnapshot(
      apps: const [
        AppUsage(
          id: 'com.android.chrome',
          label: 'Browser',
          duration: Duration(minutes: 90),
        ),
        AppUsage(
          id: 'com.google.android.apps.messaging',
          label: 'Messages',
          duration: Duration(minutes: 45),
        ),
        AppUsage(
          id: 'com.google.android.youtube',
          label: 'Video',
          duration: Duration(minutes: 69),
        ),
      ],
      screenTime: const Duration(minutes: 204),
      pickups: pickups.fold(0, (total, count) => total + count),
      start: start,
      end: now,
      firstEventAt: start.add(const Duration(hours: 6)),
      buckets: [
        for (var hour = 0; hour < minutes.length; hour++)
          UsageBucket(
            start: start.add(Duration(hours: hour)),
            end: start.add(Duration(hours: hour + 1)),
            screenTime: Duration(minutes: minutes[hour]),
            pickups: pickups[hour],
          ),
      ],
    );
    insightsUsage = usage;
    insightsUpdatedAt = now;
  }

  static final now = DateTime(2026, 9, 23, 14);

  @override
  Future<void> init() async {}

  @override
  List<Block> get blocks => const [
    Block(
      id: 'preview-focus',
      name: 'Focus first',
      mode: LimitMode.condition,
      apps: {'com.google.android.youtube'},
      conditions: [
        FocusCondition(id: 'preview-focus-time', target: Duration(hours: 2)),
      ],
      blockAgainAfter: Duration(minutes: 30),
    ),
    Block(
      id: 'preview-browsers',
      name: 'Mindful browsing',
      mode: LimitMode.time,
      apps: {'com.android.chrome'},
      categories: {'browsers'},
      schedule: [TimeRange(startMinute: 9 * 60, endMinute: 17 * 60)],
    ),
  ];

  @override
  Duration get focusToday => const Duration(minutes: 75);

  @override
  Signals get signals => Signals(
    focusToday: focusToday,
    appUsageToday: {for (final app in usage.apps) app.id: app.duration},
  );

  @override
  BlockDecision? decisionFor(String blockId) {
    final block = blocks.where((block) => block.id == blockId).firstOrNull;
    return block == null
        ? null
        : const RuleEngine().evaluate(block: block, signals: signals, now: now);
  }

  @override
  DateTime wallNow() => now;

  /// A session to show on the running timer, when a test wants one.
  FocusSession? previewRunning;

  void notifyListenersForPreview() => notifyListeners();

  @override
  FocusSession? get runningFocus => previewRunning;

  @override
  DateTime focusNow() => now;

  @override
  Duration focusLengthOf(FocusSession session) => session.lengthAt(now);

  /// A plausible fortnight: most days a session or two, a few gaps.
  static final List<FocusSession> _focusHistory = [
    for (var day = 0; day < 20; day++)
      if (day % 5 != 3)
        FocusSession(
          blockId: 'preview-focus',
          startedAt: DateTime(2026, 9, 23 - day, 9, 10),
          endedAt: DateTime(2026, 9, 23 - day, 9, 10 + 25 + (day % 3) * 20),
          kind: day.isEven ? FocusKind.pomodoro : FocusKind.stopwatch,
          plannedWork: day.isEven
              ? Duration(minutes: 25 + (day % 3) * 20)
              : null,
        ),
    FocusSession(
      blockId: 'preview-focus',
      startedAt: DateTime(2026, 9, 23, 11),
      endedAt: DateTime(2026, 9, 23, 11, 50),
      kind: FocusKind.stopwatch,
    ),
  ];

  @override
  FocusStats focusStats({String? blockId}) =>
      FocusStats.from(_focusHistory, now, blockId: blockId);

  /// Same as the real one, minus the file write the preview never opens.
  @override
  Future<void> setWaveMotion(WaveMotion motion) async {
    waveMotion = motion;
    notifyListeners();
  }

  static final _created = DateTime(2026, 4, 26);

  @override
  List<Habit> get habits => [
    Habit(
      id: 'water',
      name: 'Drink water',
      kind: HabitKind.count,
      target: 8,
      unit: 'glasses',
      color: 0xFF2F6F73, // lagoon
      iconAsset: 'assets/icons/glass-7613mgbn-.svg',
      createdAt: _created,
    ),
    Habit(
      id: 'read',
      name: 'Read',
      kind: HabitKind.timer,
      target: 20,
      color: 0xFF3F5F9A, // dusk
      iconAsset: 'assets/icons/book-open-bkvs82d7-.svg',
      reminders: const [21 * 60],
      createdAt: _created,
    ),
    Habit(
      id: 'stretch',
      name: 'Stretch',
      color: 0xFF365E49, // moss
      iconAsset: 'assets/icons/Yoga-Back-Stretch-1.svg',
      createdAt: _created,
    ),
    Habit(
      id: 'journal',
      name: 'Journal',
      description: 'Three lines before bed.',
      weekdays: const {1, 2, 3, 4, 5},
      color: 0xFF8A6D1F, // honey
      iconAsset: 'assets/icons/Content-Pen-Write.svg',
      createdAt: _created,
    ),
  ];

  /// Deterministic history: mostly kept, with the gaps real ones have.
  static final Map<String, Map<int, int>> _logs = () {
    final logs = <String, Map<int, int>>{
      'water': {},
      'read': {},
      'stretch': {},
      'journal': {},
    };
    for (var i = 0; i < 150; i++) {
      final day = DateTime(2026, 9, 23 - i);
      final key = dayKey(day);
      logs['water']![key] = i == 0
          ? 5
          : i % 9 == 4
          ? 3
          : i % 13 == 7
          ? 0
          : 8;
      if (i > 0 && i % 5 != 3) logs['read']![key] = 1200 + (i % 3) * 300;
      if (i % 6 != 5) logs['stretch']![key] = 1;
      if (i > 0 && day.weekday <= 5 && i % 11 != 2) logs['journal']![key] = 1;
    }
    return logs;
  }();

  @override
  Map<int, int> habitLogFor(String id, {DateTime? now}) => _logs[id] ?? {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const screenshot = ValueKey('redesign-preview-screenshot');
  const channel = MethodChannel('dev.control/enforcement');
  late _PreviewStore store;

  setUpAll(() async {
    // Use Flutter's cached stock font, not Ahem or a network font service.
    final fonts = Directory(
      '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts',
    );
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      loader.addFont(
        File.fromUri(fonts.uri.resolve('roboto-$weight.ttf'))
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    store = _PreviewStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> host(
    WidgetTester tester, {
    double width = 420,
    double textScale = 1,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 920);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(key: screenshot, child: ControlApp(store: store)),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  final menu = find.byTooltip('Open navigation drawer');

  /// Gmail's search bar floats: it leaves as the page scrolls down and comes
  /// back on the first scroll up, bringing the menu with it.
  void expectMenuReachable() {
    expect(menu.hitTestable(), findsOneWidget);
  }

  Finder pageScroll(Type page) => find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;

  Future<void> revealSearchBar(WidgetTester tester, Type page) async {
    await tester.drag(pageScroll(page), const Offset(0, 120));
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String label) async {
    await tester.tap(menu.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
  }

  test('preview totals and engine progress are internally consistent', () {
    expect(
      store.usage.apps.fold(Duration.zero, (sum, app) => sum + app.duration),
      store.usage.screenTime,
    );
    expect(
      store.usage.buckets.fold(
        Duration.zero,
        (sum, bucket) => sum + bucket.screenTime,
      ),
      store.usage.screenTime,
    );
    expect(store.usage.buckets.length, 14);
    expect(store.usage.buckets.last.end, _PreviewStore.now);
    expect(store.decisionFor('preview-browsers')!.blocked, isTrue);
    expect(
      store.decisionFor('preview-focus')!.conditionProgress.single.progress,
      0.625,
    );
  });

  for (final (choice, name) in [
    (AppThemeChoice.light, 'light'),
    (AppThemeChoice.black, 'dark'),
  ]) {
    testWidgets('Insights $name preview at 420x920', (tester) async {
      store.theme = choice;
      await host(tester);
      await goTo(tester, 'Insights');
      expect(find.text('3h 24m'), findsOneWidget);
      expectMenuReachable();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(screenshot),
        matchesGoldenFile('goldens/insights_$name.png'),
      );
      await tester.drag(
        find.descendant(
          of: find.byType(InsightsPage),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('3. Messages').hitTestable(), findsOneWidget);
      expect(menu.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(screenshot),
        matchesGoldenFile('goldens/insights_details_$name.png'),
      );
      await revealSearchBar(tester, InsightsPage);
      expectMenuReachable();
    });
  }

  testWidgets('Blocks light preview with engine-driven wave progress', (
    tester,
  ) async {
    await host(tester);
    expect(find.text('1h 15m focused today'), findsOneWidget);
    final wave = find.descendant(
      of: find.byType(BlocksPage),
      matching: find.byType(ExpressiveProgress),
    );
    expect(tester.widget<ExpressiveProgress>(wave).value, 0.625);
    expectMenuReachable();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/blocks_light.png'),
    );

    // A second viewport exposes both rule cards below the introductory hero.
    await tester.drag(
      find.descendant(
        of: find.byType(BlocksPage),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(wave.hitTestable(), findsOneWidget);
    expect(find.text('Mindful browsing').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/blocks_rules_light.png'),
    );
  });

  for (final (width, scale) in [(320.0, 2.0), (1200.0, 1.0)]) {
    testWidgets('navigation and layout at ${width}px / ${scale}x text', (
      tester,
    ) async {
      await host(tester, width: width, textScale: scale);
      final wide = width >= 840;
      expect(find.byType(NavigationRail), wide ? findsOneWidget : findsNothing);
      // The rail carries the menu on wide screens; the search bar does not.
      expect(menu, wide ? findsNothing : findsWidgets);
      if (!wide) expectMenuReachable();
      expect(tester.takeException(), isNull);
      for (final (label, page) in [
        ('Habits', HabitsPage),
        ('Insights', InsightsPage),
        ('Blocks', BlocksPage),
      ]) {
        if (wide) {
          final destination = find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text(label),
          );
          await tester.tap(destination);
          await tester.pumpAndSettle();
          expect(destination.hitTestable(), findsOneWidget);
        } else {
          await goTo(tester, label);
          expect(find.byType(Drawer), findsNothing);
        }
        expect(find.byType(page).hitTestable(), findsOneWidget);
        await tester.drag(
          find.descendant(
            of: find.byType(page),
            matching: find.byType(CustomScrollView),
          ),
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!wide) {
          await revealSearchBar(tester, page);
          expectMenuReachable();
        }
      }
      if (wide) {
        await tester.tap(find.byTooltip('Expand navigation'));
        await tester.pumpAndSettle();
        expect(find.text('New block'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final (choice, name) in [
    (AppThemeChoice.light, 'light'),
    (AppThemeChoice.black, 'dark'),
  ]) {
    testWidgets('Habits $name preview with grids, streaks and rank', (
      tester,
    ) async {
      store.theme = choice;
      await host(tester);
      await goTo(tester, 'Habits');
      // Stretch done; water 5/8, reading not started; Journal due, not done.
      expect(find.text('1 of 4 done'), findsOneWidget);
      expect(find.text('5 / 8 glasses'), findsOneWidget);
      expect(find.text('Sapling'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(screenshot),
        matchesGoldenFile('goldens/habits_$name.png'),
      );

      await tester.drag(pageScroll(HabitsPage), const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(screenshot),
        matchesGoldenFile('goldens/habits_cards_$name.png'),
      );
    });
  }

  testWidgets('Habit detail sheet shows stats and a month to log', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Habits');
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_detail_light.png'),
    );
  });

  testWidgets('Gmail-style drawer with badges and rules as labels', (
    tester,
  ) async {
    await host(tester);
    await tester.tap(menu.hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('YOUR RULES'),
      ),
      findsOneWidget,
    );
    expect(find.text('Mindful browsing'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/drawer_light.png'),
    );
  });

  testWidgets('wide layout: rail with menu and action, expanding in place', (
    tester,
  ) async {
    await host(tester, width: 1200);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byTooltip('New block'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/rail_light.png'),
    );
    await tester.tap(find.byTooltip('Expand navigation'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/rail_expanded_light.png'),
    );
  });

  testWidgets('search lists pages, rules and habits as you type', (
    tester,
  ) async {
    await host(tester);
    await tester.tap(find.byType(SearchBar).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search rules, habits and pages'),
      'r',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Read'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Mindful browsing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/search_light.png'),
    );
  });

  testWidgets('progress waves travel by default; Settings stops and speeds '
      'them', (tester) async {
    store.waveMotion = WaveMotion.calm;
    await host(tester, settle: false);
    // The focus card's wave on Blocks is moving before anything is touched.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Timed pumps, not settling: with the wave moving there is always a
    // next frame, which is the point.
    Future<void> frames() async {
      // The first frame starts an animation; the second lands at its end.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await tester.tap(menu.hitTestable());
    await frames();
    await tester.tap(find.bySemanticsLabel('Settings'));
    await frames();
    await tester.scrollUntilVisible(
      find.text('Progress wave'),
      300,
      scrollable: pageScroll(SettingsPage),
    );
    await tester.ensureVisible(find.text('Lively'));
    await frames();
    final preview = find.byWidgetPredicate(
      (widget) =>
          widget is ExpressiveProgress &&
          widget.semanticsLabel == 'Progress wave preview',
    );
    expect(preview.hitTestable(), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.tap(find.bySemanticsLabel('Off'));
    await tester.pumpAndSettle();
    expect(store.waveMotion, WaveMotion.off);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.textContaining('The wave holds still'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/settings_motion_light.png'),
    );

    await tester.tap(find.bySemanticsLabel('Lively'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.waveMotion, WaveMotion.lively);
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('Focus stats sheet: grabber, tiles, week chart, recent', (
    tester,
  ) async {
    await host(tester);
    await tester.drag(pageScroll(BlocksPage), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Focus statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Focus stats'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/focus_stats_light.png'),
    );
    await tester.drag(
      find
          .descendant(
            of: find.byType(FocusStatsSheet),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -560),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/focus_stats_more_light.png'),
    );
  });

  testWidgets('Focus timer sheet: start, then a running pomodoro', (
    tester,
  ) async {
    await host(tester);
    await tester.drag(pageScroll(BlocksPage), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Start  1h 15m'));
    await tester.pumpAndSettle();
    expect(find.text('Pomodoro'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/focus_start_light.png'),
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    store.previewRunning = FocusSession(
      blockId: 'preview-focus',
      startedAt: _PreviewStore.now.subtract(
        const Duration(minutes: 10, seconds: 30),
      ),
      kind: FocusKind.pomodoro,
      plannedWork: const Duration(minutes: 25),
    );
    store.notifyListenersForPreview();
    await tester.pumpAndSettle();
    expect(find.text('14:30 left'), findsOneWidget);
    await tester.tap(find.text('14:30 left'));
    await tester.pumpAndSettle();
    expect(find.text('14:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/focus_running_light.png'),
    );
  });

  testWidgets('Habit editor: pill header and the sixteen colours', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Habits');
    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Colour'));
    await tester.pumpAndSettle();
    for (final name in HabitPalette.names) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_editor_light.png'),
    );
  });

  testWidgets('A single-action sheet keeps its action top left', (
    tester,
  ) async {
    await host(tester);
    await tester.tap(find.byTooltip('Lock Focus first'));
    await tester.pumpAndSettle();
    final close = tester.getTopLeft(find.widgetWithText(TextButton, 'Close'));
    expect(close.dx, lessThan(40));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/lock_sheet_light.png'),
    );
  });
}
