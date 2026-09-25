import 'package:control/data/habits.dart';
import 'package:control/ui/habit_heatmap.dart';
import 'package:control/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Wednesday 23 September 2026.
  final today = DateTime(2026, 9, 23);

  HabitStats statsFor(DateTime createdAt, Map<int, int> log) => HabitStats.of(
    Habit(
      id: 'read',
      name: 'Read',
      kind: HabitKind.count,
      target: 10,
      unit: 'pages',
      weekdays: const {1, 2, 3, 4, 5},
      createdAt: createdAt,
    ),
    log,
    today,
  );

  Future<List<DateTime>> host(
    WidgetTester tester,
    HabitStats stats, {
    double width = 400,
    double scale = 1,
    DateTime? selected,
  }) async {
    final picked = <DateTime>[];
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildControlTheme(brightness: Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => HabitHeatmap(
                stats: stats,
                selected: selected ?? today,
                onSelect: (day) => setState(() {
                  picked.add(day);
                  selected = day;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  for (final (width, scale) in [(320.0, 2.0), (400.0, 1.0), (1200.0, 1.0)]) {
    testWidgets('fits $width at ${scale}x', (tester) async {
      await host(
        tester,
        statsFor(DateTime(2026, 9, 1), {dayKey(today): 4}),
        width: width,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Today: 4 of 10 pages'), findsOneWidget);
      expect(find.text('Less'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });
  }

  testWidgets('any past day can be picked; the future cannot', (tester) async {
    final semantics = tester.ensureSemantics();
    final picked = await host(
      tester,
      statsFor(DateTime(2026, 9, 1), {dayKey(DateTime(2026, 9, 14)): 10}),
    );

    tester.semantics.tap(
      find.semantics.byLabel(RegExp(r'^Monday, September 14, 2026')),
    );
    await tester.pumpAndSettle();
    expect(picked, [DateTime(2026, 9, 14)]);
    expect(find.text('Mon, Sep 14: 10 of 10 pages'), findsOneWidget);

    // Nothing after today is drawn, so nothing after today can be chosen.
    expect(
      find.semantics.byLabel(RegExp(r'^Thursday, September 24, 2026')),
      findsNothing,
    );
    // Weekends are days off for this habit, and say so.
    expect(
      find.semantics.byLabel('Sunday, September 20, 2026, day off'),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('a long history opens on today and scrolls back to its start', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await host(tester, statsFor(DateTime(2025, 1, 6), const {}));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    // Reversed, so zero is the newest end.
    expect(position.pixels, 0);
    // About 90 weeks at 22 each, less the viewport.
    expect(position.maxScrollExtent, greaterThan(1500));
    expect(
      find.semantics.byLabel(RegExp(r'^Monday, January 6, 2025')),
      findsOne,
      reason: 'the history reaches back to the first day',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(3000, 0),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a very old habit stops scrolling at about three years', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await host(tester, statsFor(DateTime(2015, 1, 5), const {}));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(20000, 0),
    );
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel(RegExp(r'2015')), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('a habit started this week still scrolls back a year', (
    tester,
  ) async {
    await host(tester, statsFor(DateTime(2026, 9, 21), const {}));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, 0, reason: 'opens on the newest week');
    // 53 weeks at 22 each, less the visible part.
    expect(position.maxScrollExtent, greaterThan(800));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'dragging right goes back');
    expect(tester.takeException(), isNull);
  });

  testWidgets('days before the habit began are shown but cannot be picked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final picked = await host(
      tester,
      statsFor(DateTime(2026, 9, 21), const {}),
    );
    final before = find.semantics.byLabel(
      'Friday, September 18, 2026, before the habit began',
    );
    expect(before, findsOne);
    // No tap action for a screen reader, and none for a finger.
    expect(
      before.evaluate().single.getSemanticsData().hasAction(
        SemanticsAction.tap,
      ),
      isFalse,
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(CustomPaint).last) + const Offset(1, 1),
    );
    await tester.pumpAndSettle();
    expect(picked, isEmpty);

    // The first day itself can be.
    tester.semantics.tap(
      find.semantics.byLabel(RegExp(r'^Monday, September 21, 2026')),
    );
    await tester.pumpAndSettle();
    expect(picked, [DateTime(2026, 9, 21)]);
    semantics.dispose();
  });
}
