import 'dart:io';

import 'package:control/data/focus.dart';
import 'package:control/data/habits.dart';
import 'package:control/data/money.dart';
import 'package:control/data/notes.dart';
import 'package:control/data/page_lock.dart';
import 'package:control/data/todos.dart';
import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/blocks_page.dart';
import 'package:control/ui/dialogs.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/focus_stats_sheet.dart';
import 'package:control/ui/growth_art.dart';
import 'package:control/ui/growth_sheet.dart';
import 'package:control/ui/habit_sheets.dart';
import 'package:control/ui/habits_page.dart';
import 'package:control/ui/insights_page.dart';
import 'package:control/ui/lock_sheet.dart';
import 'package:control/ui/money_page.dart';
import 'package:control/ui/money_sheets.dart';
import 'package:control/ui/money_charts.dart';
import 'package:control/ui/note_editor.dart';
import 'package:control/ui/page_lock.dart';
import 'package:control/ui/todos_page.dart';
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
    // Every stage already celebrated, unless a test asks otherwise.
    growthStageSeen = 6;
    currency = Currency.byCode('INR');
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

  final celebrated = <int>[];

  // A realistic day of todos and a few notes. Read-only: the preview never
  // opens storage, so writes go nowhere.
  static DateTime _at(int day, [int hour = 9, int minute = 0]) =>
      DateTime(2026, 9, day, hour, minute);

  static final _todoFixtures = [
    Todo(
      id: 'passport',
      title: 'Renew passport',
      date: _at(21, 0),
      createdAt: _at(15),
    ),
    Todo(
      id: 'bank',
      title: 'Call the bank',
      date: _at(23, 0),
      createdAt: _at(22),
    ),
    Todo(
      id: 'trip',
      title: 'Plan the weekend trip',
      date: _at(23, 0),
      createdAt: _at(20),
      subTodos: const [
        SubTodo(id: 'train', title: 'Book the train', isDone: true),
        SubTodo(id: 'pack', title: 'Pack a bag'),
        SubTodo(id: 'map', title: 'Download offline maps'),
      ],
    ),
    Todo(
      id: 'dentist',
      title: 'Dentist appointment',
      date: _at(26, 0),
      createdAt: _at(18),
    ),
    Todo(id: 'read', title: 'Read "Deep Work"', createdAt: _at(10)),
    Todo(
      id: 'plants',
      title: 'Water the plants',
      date: _at(23, 0),
      isDone: true,
      completedAt: _at(23, 10, 15),
      createdAt: _at(22),
    ),
    Todo(
      id: 'invoice',
      title: 'Send the invoice',
      date: _at(20, 0),
      isDone: true,
      completedAt: _at(23, 9, 5),
      createdAt: _at(19),
    ),
  ];

  static final _noteFixtures = [
    Note(
      id: 'groceries',
      title: 'Groceries',
      preview: 'Eggs  Bread  Coffee beans',
      bodyDelta:
          '[{"insert":"This week"},{"insert":"\\n","attributes":{"header":2}},'
          '{"insert":"Eggs"},{"insert":"\\n","attributes":{"list":"checked"}},'
          '{"insert":"Bread"},{"insert":"\\n","attributes":{"list":"unchecked"}},'
          '{"insert":"Coffee beans"},{"insert":"\\n","attributes":{"list":"unchecked"}},'
          '{"insert":"Remember: ","attributes":{"bold":true}},'
          '{"insert":"the market closes at six","attributes":{"color":"#FF9500"}},'
          '{"insert":"\\n"}]',
      pinned: true,
      createdAt: _at(20),
      updatedAt: _at(23, 12, 40),
    ),
    Note(
      id: 'books',
      title: 'Books to read',
      preview: 'Deep Work  Four Thousand Weeks  The Overstory',
      createdAt: _at(10),
      updatedAt: _at(22, 18),
    ),
    Note(
      id: 'trip',
      title: 'Weekend trip',
      preview: 'Train at 8:10. Hostel near the old town.',
      createdAt: _at(12),
      updatedAt: _at(18, 21),
    ),
    Note(
      id: 'quote',
      title: '',
      preview: 'What we pay attention to is what we become.',
      createdAt: _at(2),
      updatedAt: _at(2, 7),
    ),
  ];

  @override
  List<Todo> get todos => _todoFixtures;

  @override
  TodoBook get todoBook => TodoBook(_todoFixtures);

  @override
  Todo? todoById(String id) =>
      _todoFixtures.where((todo) => todo.id == id).firstOrNull;

  @override
  List<Note> get notes => sortNotes(_noteFixtures);

  @override
  Note? noteById(String id) =>
      _noteFixtures.where((note) => note.id == id).firstOrNull;

  @override
  Future<void> upsertNote(Note note) async {}

  // Three months of money: salary, rent and the everyday in between, so the
  // month opens on a brought-forward balance and the heatmap has a history.
  static ExpenseEntry _money(
    String id,
    EntryType type,
    String category,
    double amount,
    DateTime date, {
    String title = '',
    String detail = '',
  }) => ExpenseEntry(
    id: id,
    type: type,
    title: title,
    amount: amount,
    category: category,
    detail: detail,
    date: date,
    createdAt: date,
  );

  static final _moneyFixtures = [
    // September.
    _money(
      'sep-salary',
      EntryType.income,
      'Salary',
      85000,
      _at(1),
      title: 'September salary',
    ),
    _money(
      'sep-logo',
      EntryType.income,
      'Freelance',
      12500,
      _at(14),
      title: 'Logo design',
    ),
    _money(
      'sep-refund',
      EntryType.income,
      'Refund',
      1299,
      _at(17),
      title: 'Returned jacket',
    ),
    _money(
      'sep-rent',
      EntryType.expense,
      'Bills',
      22000,
      _at(2),
      title: 'Rent',
    ),
    _money(
      'sep-sip',
      EntryType.expense,
      'Investment',
      10000,
      _at(5),
      title: 'Index fund',
    ),
    _money(
      'sep-metro',
      EntryType.expense,
      'Transport',
      600,
      _at(5),
      title: 'Metro card',
    ),
    _money(
      'sep-course',
      EntryType.expense,
      'Learning',
      1499,
      _at(8),
      title: 'Online course',
    ),
    _money(
      'sep-shoes',
      EntryType.expense,
      'Shopping',
      4999,
      _at(12),
      title: 'Running shoes',
    ),
    _money(
      'sep-pet',
      EntryType.expense,
      'Other',
      1200,
      _at(16),
      detail: 'Pet food',
    ),
    _money(
      'sep-pharmacy',
      EntryType.expense,
      'Health',
      760,
      _at(18),
      title: 'Pharmacy',
    ),
    _money(
      'sep-movie',
      EntryType.expense,
      'Fun',
      700,
      _at(19),
      title: 'Movie night',
    ),
    _money(
      'sep-groceries',
      EntryType.expense,
      'Food',
      3240,
      _at(20),
      title: 'Groceries',
    ),
    _money(
      'sep-dinner',
      EntryType.expense,
      'Food',
      1850,
      _at(21),
      title: 'Dinner out',
    ),
    _money(
      'sep-cab',
      EntryType.expense,
      'Transport',
      340,
      _at(22),
      title: 'Cab home',
    ),
    _money(
      'sep-coffee',
      EntryType.expense,
      'Food',
      180,
      _at(23),
      title: 'Coffee',
    ),
    // August and July, for what September opens on.
    _money(
      'aug-salary',
      EntryType.income,
      'Salary',
      85000,
      DateTime(2026, 8, 1),
    ),
    _money(
      'aug-rent',
      EntryType.expense,
      'Bills',
      22000,
      DateTime(2026, 8, 2),
      title: 'Rent',
    ),
    _money(
      'aug-sip',
      EntryType.expense,
      'Investment',
      10000,
      DateTime(2026, 8, 5),
      title: 'Index fund',
    ),
    _money(
      'aug-phone',
      EntryType.expense,
      'Shopping',
      3500,
      DateTime(2026, 8, 15),
      title: 'Phone case',
    ),
    _money(
      'jul-salary',
      EntryType.income,
      'Salary',
      80000,
      DateTime(2026, 7, 1),
    ),
    _money(
      'jul-rent',
      EntryType.expense,
      'Bills',
      22000,
      DateTime(2026, 7, 2),
      title: 'Rent',
    ),
    _money(
      'jul-sip',
      EntryType.expense,
      'Investment',
      10000,
      DateTime(2026, 7, 5),
      title: 'Index fund',
    ),
    _money(
      'jul-dividend',
      EntryType.income,
      'Investment',
      2400,
      DateTime(2026, 7, 28),
      title: 'Dividend',
    ),
    // Everyday spending through the summer, most days, never the same.
    for (var i = 24; i < 100; i++)
      if (i % 4 != 1)
        _money(
          'day-$i',
          EntryType.expense,
          i.isEven ? 'Food' : 'Transport',
          120.0 + (i * 137) % 880,
          DateTime(2026, 9, 23 - i),
          title: i.isEven ? 'Lunch' : 'Commute',
        ),
  ];

  static final _budgetFixtures = [
    Budget(
      id: 'food',
      label: 'Groceries',
      amount: 6000,
      start: _at(1, 0),
      end: _at(30, 0),
      category: 'Food',
    ),
    Budget(
      id: 'month',
      label: 'September',
      amount: 50000,
      start: _at(1, 0),
      end: _at(30, 0),
    ),
    Budget(
      id: 'goa',
      label: 'Goa trip',
      amount: 25000,
      start: DateTime(2026, 10, 10),
      end: DateTime(2026, 10, 16),
    ),
  ];

  static final _loanFixtures = [
    LoanEntry(
      id: 'arjun',
      type: LoanType.lent,
      person: 'Arjun',
      amount: 2000,
      date: _at(10, 0),
      note: 'Concert tickets',
    ),
    LoanEntry(
      id: 'priya',
      type: LoanType.borrowed,
      person: 'Priya',
      amount: 5000,
      date: DateTime(2026, 8, 28),
      note: 'Laptop repair',
    ),
    LoanEntry(
      id: 'sam',
      type: LoanType.lent,
      person: 'Sam',
      amount: 1500,
      date: DateTime(2026, 7, 20),
      settled: true,
    ),
  ];

  @override
  MoneyBook get moneyBook => MoneyBook(
    entries: _moneyFixtures,
    budgets: _budgetFixtures,
    loans: _loanFixtures,
    currency: Currency.byCode('INR'),
  );

  @override
  Future<void> markGrowthSeen(int stage) async {
    celebrated.add(stage);
    growthStageSeen = stage;
  }

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
        File.fromUri(
          fonts.uri.resolve('roboto-$weight.ttf'),
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
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
      RepaintBoundary(
        key: screenshot,
        child: ControlApp(store: store),
      ),
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

  testWidgets('Habit detail: stats, then week, month and year progress', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Habits');
    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    expect(find.text('Current streak'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_detail_light.png'),
    );

    final sheet = find
        .descendant(
          of: find.byType(HabitDetailSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(sheet, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Mon 21 to Sun 27 September; 8 glasses a day, every day. Monday and
    // Tuesday full, 5 so far today.
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('WEEK GOAL'), findsOneWidget);
    expect(find.text('56 glasses'), findsOneWidget);
    expect(find.text('21 glasses'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_progress_week_light.png'),
    );

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.text('THIS MONTH'), findsOneWidget);
    expect(find.text('MONTH GOAL'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_progress_month_light.png'),
    );

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('THIS YEAR'), findsOneWidget);
    expect(find.text('YEAR GOAL'), findsOneWidget);
    // Created in April: no year before it to step back into.
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Previous year'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_progress_year_light.png'),
    );

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous week'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsNothing);
    expect(find.text('WEEK GOAL'), findsOneWidget);
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The history: GitHub-style, today selected, and any past day a tap away.
    await tester.drag(sheet, const Offset(0, -380));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Today: 5 of 8 glasses'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_heatmap_light.png'),
    );

    // Tuesday the 22nd: a full day. Selected the way a screen reader would.
    tester.semantics.tap(
      find.semantics.byLabel(RegExp(r'^Tuesday, September 22, 2026')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tue, Sep 22: 8 of 8 glasses'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget, reason: 'log card follows');
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/habit_heatmap_selected_light.png'),
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
      find.widgetWithText(TextField, 'Search rules, habits, todos and notes'),
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
    expect(find.byType(ExpressiveCircularProgress), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // A stopwatch gets a dial of seconds instead of a ring with an end.
    store.previewRunning = FocusSession(
      blockId: 'preview-focus',
      startedAt: _PreviewStore.now.subtract(
        const Duration(minutes: 42, seconds: 17),
      ),
      kind: FocusKind.stopwatch,
    );
    store.notifyListenersForPreview();
    await tester.pumpAndSettle();
    await tester.tap(find.text('42:17'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveCircularProgress), findsNothing);
    expect(find.text('focused'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/focus_stopwatch_light.png'),
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

  for (final (choice, name) in [
    (AppThemeChoice.light, 'light'),
    (AppThemeChoice.black, 'dark'),
  ]) {
    testWidgets('growth stages, seed to old growth, $name', (tester) async {
      tester.view.physicalSize = const Size(840, 260);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenshot,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildControlTheme(
              brightness: choice == AppThemeChoice.light
                  ? Brightness.light
                  : Brightness.dark,
            ),
            builder: (context, child) =>
                WaveMotionScope(motion: WaveMotion.off, child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  // Fully grown, then just arrived, the last three locked.
                  Row(
                    children: [
                      for (var stage = 0; stage < 7; stage++)
                        Expanded(child: GrowthArt(stage: stage, size: 116)),
                    ],
                  ),
                  Row(
                    children: [
                      for (var stage = 0; stage < 7; stage++)
                        Expanded(
                          child: GrowthArt(
                            stage: stage,
                            size: 116,
                            growth: 0,
                            locked: stage > 3,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(screenshot),
        matchesGoldenFile('goldens/growth_stages_$name.png'),
      );
    });
  }

  testWidgets('Growth card on Habits opens the garden sheet', (tester) async {
    await host(tester);
    await goTo(tester, 'Habits');
    final card = find.byType(GrowthCard);
    expect(card, findsOneWidget);
    expect(find.text('Forest'), findsOneWidget);
    expect(find.textContaining('137 more to Old growth'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/growth_card_light.png'),
    );

    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Your growth'), findsOneWidget);
    expect(find.text('137 more check-ins to Old growth.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/growth_sheet_light.png'),
    );

    await tester.drag(
      find
          .descendant(
            of: find.byType(GrowthSheet),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -560),
    );
    await tester.pumpAndSettle();
    expect(find.text('THE JOURNEY'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/growth_journey_light.png'),
    );
  });

  testWidgets('a new stage is celebrated once', (tester) async {
    store.growthStageSeen = 4;
    await host(tester);
    await goTo(tester, 'Habits');
    expect(find.text('NEW STAGE'), findsOneWidget);
    expect(store.celebrated, [5]);
    // Opening the garden clears the tag; nothing celebrates twice.
    await tester.tap(find.byType(GrowthCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('NEW STAGE'), findsNothing);
    expect(store.celebrated, [5]);
  });

  testWidgets('Todos: sections, steps, composer and detail', (tester) async {
    await host(tester);
    await goTo(tester, 'Todos');
    expect(find.text('OVERDUE'), findsOneWidget);
    expect(find.text('Renew passport'), findsOneWidget);
    // Overdue 1, today 1 plus 3 steps, undated 1, finished today 2: 3 of 8.
    expect(find.text('Today · 3 of 8 done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/todos_light.png'),
    );

    await tester.drag(pageScroll(TodosPage), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Completed late: Sep 23, 2026, 9:05 AM'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/todos_more_light.png'),
    );
    await revealSearchBar(tester, TodosPage);

    await tester.tap(find.text('New todo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Add a todo'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/todos_composer_light.png'),
    );
  });

  testWidgets('Todo detail: steps, progress and the add-step bar', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Todos');
    await tester.tap(find.text('Plan the weekend trip'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailSheet), findsOneWidget);
    expect(find.text('1 of 3 steps done'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/todo_detail_light.png'),
    );
  });

  testWidgets('Notes: pinned first, then the rich editor', (tester) async {
    await host(tester);
    await goTo(tester, 'Notes');
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    // A note with no title is headed by its first words.
    expect(
      find.text('What we pay attention to is what we become.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/notes_light.png'),
    );

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/note_editor_light.png'),
    );
  });

  testWidgets('Money: balance, brought forward and the month in two lists', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Money');
    expect(find.text('September 2026'), findsOneWidget);
    // 98,799 in, 47,368 out: a surplus of 51,431.
    expect(find.text('₹51,431'), findsOneWidget);
    expect(find.text('Surplus'), findsOneWidget);
    expect(find.text('Pet food'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_overview_light.png'),
    );

    await tester.drag(pageScroll(MoneyPage), const Offset(0, -560));
    await tester.pumpAndSettle();
    expect(find.text('Brought forward'), findsWidgets);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_overview_more_light.png'),
    );
  });

  testWidgets('Money stats: savings, donuts, heatmap and categories', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Money');
    await tester.tap(find.bySemanticsLabel('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Saved this month'), findsOneWidget);
    expect(find.text('52%'), findsOneWidget);
    expect(find.byType(MoneyDonut), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_stats_light.png'),
    );

    await tester.drag(pageScroll(MoneyPage), const Offset(0, -620));
    await tester.pumpAndSettle();
    expect(find.text('Money came in'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_stats_more_light.png'),
    );

    MoneyDaySheet.show(
      tester.element(find.byType(MoneyPage)),
      DateTime(2026, 9, 21),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dinner out'), findsWidgets);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_day_light.png'),
    );
  });

  testWidgets('Money manage: investments, budgets and loans', (tester) async {
    await host(tester);
    await goTo(tester, 'Money');
    await tester.tap(find.bySemanticsLabel('Manage'));
    await tester.pumpAndSettle();
    expect(find.text('Total invested'), findsOneWidget);
    expect(find.text('₹30,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_manage_light.png'),
    );

    await tester.drag(pageScroll(MoneyPage), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Owed to you'), findsOneWidget);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_manage_more_light.png'),
    );
  });

  testWidgets('Money entry editor: an Other entry says what it was', (
    tester,
  ) async {
    await host(tester);
    await goTo(tester, 'Money');
    await tester.ensureVisible(find.text('Pet food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pet food'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditorSheet), findsOneWidget);
    expect(find.text('Edit entry'), findsOneWidget);
    expect(
      find.text('Still counts under Other in your stats.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/money_entry_light.png'),
    );
  });

  testWidgets('Money holds together at 320px and twice the text', (
    tester,
  ) async {
    await host(tester, width: 320, textScale: 2);
    await goTo(tester, 'Money');
    for (final view in ['Overview', 'Stats', 'Manage']) {
      await tester.tap(find.bySemanticsLabel(view));
      await tester.pumpAndSettle();
      await tester.drag(pageScroll(MoneyPage), const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: view);
      await revealSearchBar(tester, MoneyPage);
      await tester.drag(pageScroll(MoneyPage), const Offset(0, 2400));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('A locked page asks for the PIN and opens on the last digit', (
    tester,
  ) async {
    store.pageLock = const PageLock()
        .withPin('2468')
        .withPage('notes', locked: true);
    await host(tester);
    await goTo(tester, 'Notes');
    expect(find.text('Notes is locked'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/page_lock_light.png'),
    );

    for (final digit in ['1', '1', '1', '1']) {
      await tester.tap(find.bySemanticsLabel(digit));
      await tester.pump();
    }
    expect(find.text('Wrong PIN'), findsOneWidget);
    await tester.longPress(find.bySemanticsLabel('Erase'));
    await tester.pump();
    for (final digit in ['2', '4', '6', '8']) {
      await tester.tap(find.bySemanticsLabel(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    // Lock now, from the search bar, closes it again.
    await tester.tap(find.byTooltip('Lock pages now'));
    await tester.pumpAndSettle();
    expect(find.text('Notes is locked'), findsOneWidget);
  });

  testWidgets('App lock settings: open with the PIN, pick the pages', (
    tester,
  ) async {
    store.pageLock = const PageLock()
        .withPin('2468')
        .withPage('money', locked: true);
    store.unlockLockSettings('2468');
    await host(tester);
    await goTo(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Remove PIN'),
      300,
      scrollable: pageScroll(SettingsPage),
    );
    await tester.ensureVisible(find.text('APP LOCK'));
    await tester.pumpAndSettle();
    expect(find.text('PIN is set'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/settings_app_lock_light.png'),
    );
  });

  testWidgets('Dialogs: a badge, a clear title, and two full-width buttons', (
    tester,
  ) async {
    await host(tester);
    final page = tester.element(find.byType(BlocksPage));

    confirmAction(
      page,
      icon: Icons.delete_outline_rounded,
      tone: DialogTone.danger,
      title: 'Delete Mindful browsing?',
      message: 'The apps it covers stop being blocked.',
      cancelLabel: 'Keep',
      confirmLabel: 'Delete',
    );
    await tester.pumpAndSettle();
    expect(find.byType(ControlDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/dialog_delete_light.png'),
    );
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.byType(ControlDialog), findsNothing);

    confirmAction(
      page,
      icon: Icons.gpp_maybe_outlined,
      tone: DialogTone.caution,
      title: 'Turn on Hard mode?',
      message:
          'Control will close the Android settings screens that lead to '
          'uninstalling or disabling it, including its own accessibility '
          'setting.',
      detail: const DialogNote(
        icon: Icons.info_outline_rounded,
        text:
            'When you genuinely want to remove the app, turn it off here '
            'first.',
        tone: DialogTone.caution,
      ),
      confirmLabel: 'Turn on',
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/dialog_caution_light.png'),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A new PIN, typed twice; a short one is refused in place.
    PinDialog.show(page, title: 'Set a PIN', action: 'Save', confirm: true);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 4 digits.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/dialog_pin_light.png'),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Emergency unlock dialog shows what is left after it', (
    tester,
  ) async {
    await host(tester);
    final page = tester.element(find.byType(BlocksPage));
    LockSheet.showFor(
      page,
      LockTarget(
        name: 'Mindful browsing',
        lock: const Lock.password('preview'),
        onLock: ({duration, password}) async {},
        onUnlock: (_) async => false,
        onEmergencyUnlock: () async => false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Use an emergency unlock'));
    await tester.pumpAndSettle();
    expect(find.text('4 of 5 left after this'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/dialog_emergency_light.png'),
    );
  });

  testWidgets('Date picker wears the dialog shape and pill buttons', (
    tester,
  ) async {
    await host(tester);
    showDatePicker(
      context: tester.element(find.byType(BlocksPage)),
      initialDate: DateTime(2026, 9, 23),
      firstDate: DateTime(2025),
      lastDate: DateTime(2027),
      currentDate: DateTime(2026, 9, 23),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/dialog_date_light.png'),
    );
  });
}
