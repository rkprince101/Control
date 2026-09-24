import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
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

  await tester.pumpWidget(
    ControlApp(store: ControlStore(storageDirectory: storage)),
  );
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
  await tester.tap(find.bySemanticsLabel(label));
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
    for (final label in ['Blocks', 'Habits', 'Insights', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(find.text('Create new'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Habits'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Build rhythm'), findsOneWidget);
  });

  testWidgets('a habit is created from the Habits page and ticked off', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _goTo(tester, 'Habits');
    expect(find.text('No habits yet'), findsOneWidget);

    await tester.tap(find.text('New habit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Habit name'),
      'Stretch',
    );
    // Save enables on the rebuild that follows typing.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Habit name'), findsNothing, reason: 'editor closed');
    expect(find.text('Stretch'), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Mark Stretch done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mark Stretch done'));
    await tester.pumpAndSettle();
    await tester.drag(_pageScroll, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('All done. Nice.'), findsOneWidget);
    expect(find.byTooltip('Mark Stretch not done'), findsOneWidget);
  });

  testWidgets('search jumps straight to a page', (tester) async {
    await _pumpApp(tester);

    // The bar's own field ignores pointers; the bar opens the search view.
    await tester.tap(find.byType(SearchBar).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search rules, habits and pages'),
      'sett',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Your setup'), findsOneWidget);
  });
}
