import 'dart:io';

import 'package:control/data/focus.dart';
import 'package:control/data/habits.dart';
import 'package:control/data/money.dart';
import 'package:control/data/notes.dart';
import 'package:control/data/todos.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preview-only fixtures; never hydrate storage or publish enforcement plans.
class PreviewStore extends ControlStore {
  PreviewStore() {
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

/// Roboto and Material Icons from Flutter's own cache: real glyphs in
/// screenshots, with no network font service.
Future<void> loadPreviewFonts() async {
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
}
