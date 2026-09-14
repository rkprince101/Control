import 'dart:io';

import 'package:control/main.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression cover for the editor.
///
/// A field that silently fails to save is the worst kind of bug in this app:
/// the user believes a site is blocked, it is not, and nothing anywhere says
/// so. That is exactly what happened to the site list, so it gets a test that
/// drives the real widget rather than the model underneath it.
void _stubChannel(WidgetTester tester, {bool failSummary = false}) {
  const channel = MethodChannel('dev.control/enforcement');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async {
      if (failSummary && call.method == 'updateSummary') {
        throw PlatformException(code: 'boom');
      }
      return switch (call.method) {
      'isAccessibilityEnabled' => true,
      'hasUsageAccess' => false,
      'stepsStatus' => <String, Object?>{'granted': false, 'available': false},
      'locationStatus' => <String, Object?>{'granted': false, 'enabled': false},
      'protectionStatus' => <String, Object?>{
          'adminActive': false,
          'deviceOwner': false,
          'uninstallBlocked': false,
          'hardMode': false,
        },
      'shortcutCounts' => <String, Object?>{},
        'installedApps' => <Object?>[],
        _ => null,
      };
    },
  );
}

void main() {
  late Directory storage;
  late ControlStore store;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_editor_test');
    store = ControlStore(storageDirectory: storage);
  });

  tearDown(() => storage.deleteSync(recursive: true));

  Future<void> openEditor(WidgetTester tester, {bool failSummary = false}) async {
    _stubChannel(tester, failSummary: failSummary);
    await tester.pumpWidget(ControlApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  testWidgets('a site added with the plus button is saved', (tester) async {
    await openEditor(tester);

    // Field 0 is the block name; field 1 is the site input.
    await tester.enterText(find.byType(TextField).at(1), 'instagram.com');
    await tester.pumpAndSettle();

    // The same path the keyboard Done key takes.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.blocks, hasLength(1));
    expect(store.blocks.single.blockedDomains, {'instagram.com'});
  });

  testWidgets('a site typed but not added is still saved', (tester) async {
    // Pressing Save with text still in the field used to discard it.
    await openEditor(tester);

    await tester.enterText(find.byType(TextField).at(1), 'youtube.com');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.blocks.single.blockedDomains, {'youtube.com'});
  });

  testWidgets('the sheet closes even when a downstream surface fails',
      (tester) async {
    // The widget summary push threw, and because closing the sheet came after
    // it, the editor stayed open over a block that had already been created.
    await openEditor(tester, failSummary: true);

    await tester.enterText(find.byType(TextField).at(1), 'instagram.com');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.blocks, hasLength(1));
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('a pasted URL is reduced to its host', (tester) async {
    await openEditor(tester);

    await tester.enterText(
      find.byType(TextField).at(1),
      'https://www.reddit.com/r/all?sort=new',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.blocks.single.blockedDomains, {'reddit.com'});
  });
}
