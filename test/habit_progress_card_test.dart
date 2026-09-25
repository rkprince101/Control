import 'package:control/data/habits.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/habit_progress_card.dart';
import 'package:control/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 9, 23);
  final habit = Habit(
    id: 'read',
    name: 'Read',
    kind: HabitKind.count,
    target: 10,
    unit: 'pages',
    createdAt: DateTime(2025, 11, 3),
  );
  final stats = HabitStats.of(habit, {
    for (var i = 0; i < 300; i += 3)
      dayKey(DateTime(2026, 9, 23 - i)): 6 + i % 7,
  }, today);

  for (final (width, scale) in [(320.0, 2.0), (320.0, 1.0), (800.0, 1.5)]) {
    testWidgets('fits $width at ${scale}x in every period', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildControlTheme(brightness: Brightness.light),
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
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: HabitProgressCard(stats: stats),
            ),
          ),
        ),
      );
      for (final period in ['Week', 'Month', 'Year']) {
        await tester.tap(find.text(period));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: period);
        expect(
          find.text('${period.toUpperCase()} GOAL'),
          findsOneWidget,
          reason: period,
        );
        // Step back a period and return: nothing breaks either way.
        await tester.tap(find.byTooltip('Previous ${period.toLowerCase()}'));
        await tester.pumpAndSettle();
        expect(find.text('THIS ${period.toUpperCase()}'), findsNothing);
        await tester.tap(find.byTooltip('Next ${period.toLowerCase()}'));
        await tester.pumpAndSettle();
        expect(find.text('THIS ${period.toUpperCase()}'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: period);
      }
    });
  }
}
