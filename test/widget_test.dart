import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

/// Answers the enforcement channel as a device that has granted nothing, so the
/// shell can be exercised without an Android host.
void _stubChannel(WidgetTester tester) {
  const channel = MethodChannel('dev.control/enforcement');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => switch (call.method) {
      'isAccessibilityEnabled' => false,
      'hasUsageAccess' => false,
      'stepsStatus' => <String, Object?>{'granted': false, 'available': true},
      'protectionStatus' => <String, Object?>{
        'adminActive': false,
        'deviceOwner': false,
        'uninstallBlocked': false,
      },
      'shortcutCounts' => <String, Object?>{},
      'installedApps' => <Object?>[],
      'applyPlan' => null,
      _ => null,
    },
  );
}

Future<void> _pumpApp(WidgetTester tester) async {
  _stubChannel(tester);
  final storage = Directory.systemTemp.createTempSync('control_widget_test');
  addTearDown(() => storage.deleteSync(recursive: true));
  // Motion off: the plants and waves otherwise move for ever, and these
  // tests wait for a still frame.
  final store = ControlStore(storageDirectory: storage)
    ..waveMotion = WaveMotion.off;
  await tester.pumpWidget(ControlApp(store: store));
  await tester.pumpAndSettle();
}

/// The visible page's own scroll view. The search bar's text field is a
/// scrollable too, so the default finder is ambiguous.
final _pageScroll = find
    .descendant(
      of: find.byType(CustomScrollView).hitTestable(),
      matching: find.byType(Scrollable),
    )
    .first;

/// Opens the drawer from the visible page's search bar, then picks [label].
Future<void> _goTo(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation drawer').hitTestable());
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(Drawer),
      matching: find.bySemanticsLabel(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Blocks and warns that nothing is enforcing yet', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.textContaining('not being enforced'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('No blocks yet'),
      200,
      scrollable: _pageScroll,
    );
    expect(find.textContaining('No blocks yet'), findsOneWidget);
  });

  testWidgets('Insights asks for usage access before showing numbers', (
    tester,
  ) async {
    await _pumpApp(tester);

    // By semantics label, not by icon: the drawer swaps between outlined and
    // filled icons with selection, so the icon is not a stable handle.
    await _goTo(tester, 'Insights');

    expect(find.text('Usage access needed'), findsOneWidget);
  });

  testWidgets('Settings reports the protection tier and unlock budget', (
    tester,
  ) async {
    await _pumpApp(tester);

    await _goTo(tester, 'Settings');

    expect(find.text('Deterrent'), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);

    // The theme picker sits below the fold, so the list has to be scrolled
    // before the finder can see it.
    await tester.scrollUntilVisible(
      find.text('Pitch black'),
      200,
      scrollable: _pageScroll,
    );
    expect(find.text('Pitch black'), findsOneWidget);
  });

  testWidgets('the drawer lists every place and closes on a pick', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('Open navigation drawer').hitTestable());
    await tester.pumpAndSettle();
    for (final label in ['Blocks', 'Thoughts', 'Insights', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    for (final removed in ['Habits', 'Todos', 'Notes', 'Money']) {
      expect(find.bySemanticsLabel(removed), findsNothing);
    }
    expect(find.text('Create new'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Insights'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Your time'), findsOneWidget);
  });

  testWidgets('search jumps straight to a page', (tester) async {
    await _pumpApp(tester);

    // The bar's own field ignores pointers; the bar opens the search view.
    await tester.tap(find.byType(SearchBar).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search rules and pages'),
      'sett',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Your setup'), findsOneWidget);
  });

  testWidgets('app lock: a PIN guards Insights until entered, and again after '
      'leaving the app', (tester) async {
    await _pumpApp(tester);
    await _goTo(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Set PIN'),
      200,
      scrollable: _pageScroll,
    );
    await tester.ensureVisible(find.text('Set PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1357');
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat PIN'),
      '1357',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('PIN is set'), findsOneWidget);

    final insightsSwitch = find.descendant(
      of: find.ancestor(of: find.text('Insights'), matching: find.byType(Row)),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(insightsSwitch);
    await tester.tap(insightsSwitch);
    await tester.pumpAndSettle();

    // Back up, for the search bar and its menu.
    await tester.drag(_pageScroll, const Offset(0, 300));
    await tester.pumpAndSettle();
    await _goTo(tester, 'Insights');
    expect(find.text('Insights is locked'), findsOneWidget);
    expect(find.text('Your time'), findsNothing);
    for (final digit in ['1', '3', '5', '7']) {
      await tester.tap(find.bySemanticsLabel(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Your time'), findsOneWidget);

    // Away and back: the page asks again.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(find.text('Insights is locked'), findsOneWidget);
  });
}
