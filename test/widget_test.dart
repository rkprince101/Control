import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
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

void main() {
  testWidgets('opens on Blocks and warns that nothing is enforcing yet',
      (tester) async {
    await _pumpApp(tester);

    expect(find.textContaining('not being enforced'), findsOneWidget);
    expect(find.textContaining('No blocks yet'), findsOneWidget);
  });

  testWidgets('Insights asks for usage access before showing numbers',
      (tester) async {
    await _pumpApp(tester);

    // By semantics label, not by icon: the nav swaps between outlined and
    // filled icons with selection, so the icon is not a stable handle.
    await tester.tap(find.bySemanticsLabel('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Usage access needed'), findsOneWidget);
  });

  testWidgets('Settings reports the protection tier and unlock budget',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Deterrent'), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);

    // The theme picker sits below the fold, so the list has to be scrolled
    // before the finder can see it.
    await tester.scrollUntilVisible(find.text('Pitch black'), 200);
    expect(find.text('Pitch black'), findsOneWidget);
  });
}
