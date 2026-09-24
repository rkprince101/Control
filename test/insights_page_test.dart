import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/block_editor_sheet.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/insights_page.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _InsightsStore extends ControlStore {
  int refreshes = 0;
  int settingsOpened = 0;
  Block? saved;

  @override
  Future<void> addBlock(Block block) async {
    saved = block;
  }

  @override
  Future<void> refreshInsights() async {
    refreshes++;
  }

  @override
  Future<void> setInsightsRange(InsightsRange range) async {
    insightsRange = range;
    notifyListeners();
  }

  @override
  Future<void> openUsageAccessSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> loadInstalledApps() async {}
}

void main() {
  late _InsightsStore store;
  final start = DateTime(2026, 9, 23);

  UsageSnapshot populated({String? historyNote}) => UsageSnapshot(
    // Deliberately unsorted. Rank and chronology must not depend on transport.
    apps: const [
      AppUsage(id: 'reader', label: 'Reader', duration: Duration(minutes: 30)),
      AppUsage(
        id: 'browser',
        label: 'Browser',
        duration: Duration(minutes: 90),
      ),
    ],
    screenTime: const Duration(hours: 2),
    pickups: 12,
    start: start,
    end: start.add(const Duration(hours: 3)),
    firstEventAt: start,
    historyNote: historyNote,
    buckets: [
      UsageBucket(
        start: start.add(const Duration(hours: 1)),
        end: start.add(const Duration(hours: 2)),
        screenTime: const Duration(minutes: 60),
        pickups: 7,
      ),
      UsageBucket(
        start: start,
        end: start.add(const Duration(hours: 1)),
        screenTime: const Duration(minutes: 40),
        pickups: 3,
      ),
      UsageBucket(
        start: start.add(const Duration(hours: 2)),
        end: start.add(const Duration(hours: 3)),
        screenTime: const Duration(minutes: 20),
        pickups: 2,
      ),
    ],
  );

  setUp(() {
    store = _InsightsStore()..usageAccessGranted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.control/enforcement'),
          (_) async => null,
        );
  });

  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.control/enforcement'),
          null,
        );
  });

  Future<void> host(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF245344),
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
    // Loading is intentionally indeterminate. Never settle its animation.
    await tester.pump(const Duration(milliseconds: 250));
  }

  Finder getPageScroll() => find
      .descendant(
        of: find.byType(InsightsPage),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: getPageScroll(),
      maxScrolls: 40,
    );
    await tester.pump(const Duration(milliseconds: 250));
  }

  Finder bucket(int hour) => find.byKey(
    ValueKey(
      'usage-bucket-${start.add(Duration(hours: hour)).millisecondsSinceEpoch}',
    ),
  );

  testWidgets('permission keeps required title and local privacy explanation', (
    tester,
  ) async {
    store.usageAccessGranted = false;
    await host(tester);
    expect(find.text('Usage access needed'), findsOneWidget);
    expect(
      find.textContaining('on this device, not on a server'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('screen-time-total')), findsNothing);
    await tester.tap(find.text('Open settings'));
    expect(store.settingsOpened, 1);
  });

  testWidgets(
    'populated insights use period data and rank actual total shares',
    (tester) async {
      store.insightsUsage = populated();
      store.usage = const UsageSnapshot(
        apps: [],
        screenTime: Duration(hours: 99),
        pickups: 999,
      );
      await host(tester);
      expect(find.text('Your time'), findsOneWidget);
      expect(find.text('INSIGHTS'), findsOneWidget);
      expect(
        find.text('See your patterns. Choose your next step.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('screen-time-total')))
            .data,
        '2h',
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('75% of total'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('usage-app-reader')));
      expect(find.text('1. Browser'), findsOneWidget);
      expect(find.text('2. Reader'), findsOneWidget);
      expect(find.text('1h 30m  /  75%'), findsOneWidget);
      expect(find.text('30m  /  25%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chart sorts chronologically and selects accessible real buckets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        store.insightsUsage = populated();
        await host(tester);
        await reveal(tester, bucket(1));
        expect(
          tester.getTopLeft(bucket(0)).dx,
          lessThan(tester.getTopLeft(bucket(1)).dx),
        );
        expect(tester.getSize(bucket(0)).width, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(bucket(1)).label,
          contains('1h recorded screen time, 7 pickups'),
        );
        await tester.tap(bucket(1));
        await tester.pump();
        final readout = find.byKey(const ValueKey('bucket-readout'));
        expect(
          find.descendant(of: readout, matching: find.text('1h')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: readout, matching: find.text('7 pickups')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final (width, textScale, stacked) in [
    (360.0, 1.0, false),
    (390.0, 1.5, false),
    (320.0, 1.0, true),
    (390.0, 2.0, true),
  ]) {
    testWidgets('hero metrics adapt at ${width}dp / ${textScale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.insightsUsage = populated();
      await host(tester, textScale: textScale);
      await reveal(tester, find.text('Most used'));
      final pickupsTop = tester.getTopLeft(find.text('Pickups')).dy;
      final mostUsedTop = tester.getTopLeft(find.text('Most used')).dy;
      expect(mostUsedTop, stacked ? greaterThan(pickupsTop) : pickupsTop);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (range, count, activeIndex) in [
    (InsightsRange.day, 24, 20),
    (InsightsRange.month, 30, 26),
    (InsightsRange.day, 24, null),
  ]) {
    testWidgets(
      '$range opens latest ${activeIndex == null ? 'empty' : 'active'} '
      'bucket and keeps earlier history reachable',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final stride = range == InsightsRange.day ? 1 : 24;
        store.insightsRange = range;
        store.insightsUsage = UsageSnapshot(
          apps: const [],
          screenTime: Duration(minutes: activeIndex == null ? 0 : 45),
          pickups: activeIndex == null ? 0 : 5,
          start: start,
          end: start.add(Duration(hours: count * stride)),
          buckets: [
            for (var i = count - 1; i >= 0; i--)
              UsageBucket(
                start: start.add(Duration(hours: i * stride)),
                end: start.add(Duration(hours: (i + 1) * stride)),
                screenTime: Duration(minutes: i == activeIndex ? 45 : 0),
                pickups: i == activeIndex ? 5 : 0,
              ),
          ],
        );
        await host(tester);
        final chart = find.byKey(const ValueKey('activity-chart-scroll'));
        final readout = find.byKey(const ValueKey('bucket-readout'));
        await reveal(tester, chart);
        final scroll = tester.widget<SingleChildScrollView>(chart).controller!;
        expect(scroll.offset, greaterThan(0));
        final selected = bucket((activeIndex ?? count - 1) * stride);
        expect(
          tester.getRect(chart).contains(tester.getCenter(selected)),
          isTrue,
        );
        expect(
          find.descendant(
            of: readout,
            matching: find.text(activeIndex == null ? '0m' : '45m'),
          ),
          findsOneWidget,
        );
        if (range == InsightsRange.day) {
          expect(tester.getSize(readout).height, lessThan(100));
        }
        await tester.drag(chart, const Offset(4000, 0));
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(
          tester.getRect(chart).contains(tester.getCenter(bucket(0))),
          isTrue,
        );
        await tester.tap(bucket(0));
        await tester.pump();
        expect(
          find.descendant(of: readout, matching: find.text('0m')),
          findsOneWidget,
        );
        // Unrelated store notifications must not reset selection or viewport.
        await store.setInsightsRange(range);
        await tester.pump();
        expect(scroll.offset, 0);
        expect(
          find.descendant(of: readout, matching: find.text('0m')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Day Week Month change selected query range', (tester) async {
    await host(tester);
    await tester.tap(find.text('Week'));
    await tester.pump();
    expect(store.insightsRange, InsightsRange.week);
    expect(find.text('Last 7 days'), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(store.insightsRange, InsightsRange.month);
    expect(find.text('Last 30 days'), findsOneWidget);
    await tester.tap(find.text('Day'));
    await tester.pump();
    expect(store.insightsRange, InsightsRange.day);
  });

  testWidgets('daily bars preserve dates, missing intervals and real totals', (
    tester,
  ) async {
    store.insightsRange = InsightsRange.month;
    store.insightsUsage = UsageSnapshot(
      apps: const [],
      screenTime: const Duration(hours: 3),
      pickups: 9,
      start: start.subtract(const Duration(days: 2)),
      end: start.add(const Duration(days: 1)),
      buckets: [
        UsageBucket(
          start: start,
          end: start.add(const Duration(days: 1)),
          screenTime: const Duration(hours: 2),
          pickups: 6,
        ),
        UsageBucket(
          start: start.subtract(const Duration(days: 2)),
          end: start.subtract(const Duration(days: 1)),
          screenTime: const Duration(hours: 1),
          pickups: 3,
        ),
      ],
    );
    await host(tester);
    await reveal(tester, bucket(0));
    expect(find.text('Daily recorded screen time'), findsOneWidget);
    expect(find.text('21/9'), findsOneWidget);
    expect(find.text('23/9'), findsOneWidget);
    expect(find.text('No data'), findsOneWidget);
    await tester.tap(bucket(0));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bucket-readout')),
        matching: find.text('6 pickups'),
      ),
      findsOneWidget,
    );
    final earlier = find.byKey(
      ValueKey(
        'usage-bar-${start.subtract(const Duration(days: 2)).millisecondsSinceEpoch}',
      ),
    );
    final later = find.byKey(
      ValueKey('usage-bar-${start.millisecondsSinceEpoch}'),
    );
    expect(tester.getSize(later).height, tester.getSize(earlier).height * 2);
  });

  testWidgets('zero-duration buckets never draw fake activity bars', (
    tester,
  ) async {
    store.insightsUsage = UsageSnapshot(
      apps: const [],
      screenTime: Duration.zero,
      pickups: 0,
      buckets: [
        UsageBucket(
          start: start,
          end: start.add(const Duration(hours: 1)),
          screenTime: Duration.zero,
          pickups: 0,
        ),
      ],
    );
    await host(tester);
    await reveal(tester, bucket(0));
    final bar = find.byKey(
      ValueKey('usage-bar-${start.millisecondsSinceEpoch}'),
    );
    expect(tester.getSize(bar).height, 0);
    await reveal(
      tester,
      find.text('No screen time recorded in these intervals.'),
    );
    expect(
      find.text('No screen time recorded in these intervals.'),
      findsOneWidget,
    );
  });

  testWidgets('empty history is not presented as complete zero-use history', (
    tester,
  ) async {
    await host(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('screen-time-total'))).data,
      '0m',
    );
    await reveal(
      tester,
      find.text('Missing history is not the same as no activity.'),
    );
    expect(
      find.text('No screen time recorded for this period.'),
      findsOneWidget,
    );
    expect(
      find.text('Missing history is not the same as no activity.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-chart-scroll')), findsNothing);
    await reveal(
      tester,
      find.textContaining('No app activity recorded for this period.'),
    );
    expect(
      find.textContaining('No app activity recorded for this period.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'limited history explains retained activity without comparisons',
    (tester) async {
      store.insightsUsage = populated(
        historyNote: 'Android retained only 3 days of activity.',
      );
      await host(tester);
      await reveal(tester, find.byKey(const ValueKey('activity-chart-scroll')));
      // History disclosure follows both activity and the ranked app section.
      final chartY =
          tester
              .getTopLeft(find.byKey(const ValueKey('activity-chart-scroll')))
              .dy +
          tester.state<ScrollableState>(getPageScroll()).position.pixels;
      await reveal(tester, find.byKey(const ValueKey('usage-app-reader')));
      final appsY =
          tester.getTopLeft(find.byKey(const ValueKey('usage-app-reader'))).dy +
          tester.state<ScrollableState>(getPageScroll()).position.pixels;
      await reveal(
        tester,
        find.text('Android retained only 3 days of activity.'),
      );
      expect(find.text('About this history'), findsOneWidget);
      final historyY =
          tester.getTopLeft(find.text('About this history')).dy +
          tester.state<ScrollableState>(getPageScroll()).position.pixels;
      expect(appsY, greaterThan(chartY));
      expect(historyY, greaterThan(appsY));
      expect(
        find.text('Android retained only 3 days of activity.'),
        findsOneWidget,
      );
      expect(find.textContaining('on average'), findsNothing);
      expect(find.textContaining('time saved'), findsNothing);
    },
  );

  testWidgets('error offers retry instead of invented empty totals', (
    tester,
  ) async {
    store.insightsError = 'Android could not read usage. Try again.';
    await host(tester);
    expect(find.text('Activity could not be loaded'), findsOneWidget);
    expect(find.text(store.insightsError!), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-time-total')), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(store.refreshes, 1);
  });

  testWidgets('loading uses expressive progress without stale totals', (
    tester,
  ) async {
    store.insightsUsage = populated();
    store.insightsLoading = true;
    await host(tester);
    expect(find.text('Reading recorded activity'), findsOneWidget);
    expect(
      tester.widget<ExpressiveProgress>(find.byType(ExpressiveProgress)).value,
      isNull,
    );
    expect(find.byKey(const ValueKey('screen-time-total')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'app details use real period share and preselect quick block app',
    (tester) async {
      store.insightsUsage = populated();
      await host(tester);
      final app = find.byKey(const ValueKey('usage-app-browser'));
      await reveal(tester, app);
      await tester.tap(app);
      await tester.pumpAndSettle();
      expect(
        find.text('75% of recorded screen time in this period.'),
        findsOneWidget,
      );
      expect(find.text('1h 30m'), findsOneWidget);
      await tester.tap(find.text('Create a block'));
      await tester.pumpAndSettle();
      expect(find.byType(BlockEditorSheet), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.saved?.apps, {'browser'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320dp and 2x text scroll chart, apps and details without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.insightsUsage = populated();
      await host(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await reveal(tester, find.byKey(const ValueKey('activity-chart-scroll')));
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('activity-chart-scroll')),
        const Offset(-180, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final app = find.byKey(const ValueKey('usage-app-browser'));
      await reveal(tester, app);
      await tester.tap(app);
      await tester.pumpAndSettle();
      final create = find.text('Create a block');
      await tester.ensureVisible(create);
      await tester.pump();
      expect(create, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide layout keeps chart readable', (tester) async {
    tester.view.physicalSize = const Size(1120, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.insightsUsage = populated();
    await host(tester);
    await reveal(tester, bucket(0));
    expect(tester.takeException(), isNull);
  });

  for (final state in ['permission', 'loading', 'error', 'empty']) {
    testWidgets('$state remains usable at 320dp with 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.usageAccessGranted = state != 'permission';
      store.insightsLoading = state == 'loading';
      store.insightsError = state == 'error'
          ? 'Could not read recorded activity.'
          : null;
      await host(tester, textScale: 2);
      if (state == 'permission') {
        await tester.ensureVisible(find.text('Open settings'));
        await tester.pump();
        await tester.tap(find.text('Open settings'));
        expect(store.settingsOpened, 1);
      } else if (state == 'error') {
        await reveal(tester, find.text('Try again'));
        await tester.tap(find.text('Try again'));
        expect(store.refreshes, 1);
      } else if (state == 'empty') {
        await reveal(
          tester,
          find.textContaining('No app activity recorded for this period.'),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
