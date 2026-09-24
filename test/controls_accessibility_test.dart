import 'dart:ui' show SemanticsAction;

import 'package:control/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chips and segments expose accessible tap actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ControlChip(label: 'Browsers', selected: true, onTap: () {}),
              ControlSegmented(
                value: 0,
                options: const [(0, 'Day'), (1, 'Week')],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    for (final label in ['Browsers', 'Day', 'Week']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester.getSize(find.bySemanticsLabel(label)).height,
        greaterThanOrEqualTo(48),
      );
    }
    semantics.dispose();
  });

  testWidgets(
    'weekdays have full labels and disabled days are not actionable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      Future<void> host(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WeekdayPicker(
              selected: const {1},
              enabled: enabled,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await host(true);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Monday'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await host(false);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Monday'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      semantics.dispose();
    },
  );
}
