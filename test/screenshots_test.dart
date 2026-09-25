import 'dart:io';
import 'dart:ui' as ui;

import 'package:control/data/habits.dart';
import 'package:control/main.dart';
import 'package:control/ui/habit_sheets.dart';
import 'package:control/ui/habits_page.dart';
import 'package:control/ui/money_page.dart';
import 'package:control/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/preview_store.dart';

/// The README's screenshots, made from the same fixtures as the previews.
///
/// Off by default. To refresh them:
///
///     SCREENSHOTS=1 flutter test test/screenshots_test.dart
///
/// Each is a phone-sized screen at twice its logical size, written to
/// docs/screenshots/.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = !Platform.environment.containsKey('SCREENSHOTS');
  const frame = ValueKey('screenshot-frame');
  const channel = MethodChannel('dev.control/enforcement');
  late PreviewStore store;

  setUpAll(loadPreviewFonts);

  setUp(() {
    store = PreviewStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> host(WidgetTester tester, {bool dark = false}) async {
    store.theme = dark ? AppThemeChoice.black : AppThemeChoice.light;
    // A tall modern phone: 432 x 936, captured at 2x.
    tester.view.physicalSize = const Size(432, 936);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: ControlApp(store: store),
      ),
    );
    // Pictures decode outside the test's fake clock.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/hushroom.png'),
        tester.element(find.byKey(frame)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> goTo(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Open navigation drawer').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(frame),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('docs/screenshots/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('blocks', skip: skip, (tester) async {
    await host(tester);
    await shoot(tester, '01_blocks');
  });

  testWidgets('habits', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Habits');
    await shoot(tester, '02_habits');
  });

  testWidgets('habit detail', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Habits');
    final habit = store.habits.firstWhere((h) => h.kind == HabitKind.count);
    HabitDetailSheet.show(tester.element(find.byType(HabitsPage)), habit);
    await tester.pumpAndSettle();
    await shoot(tester, '03_habit_detail');
  });

  testWidgets('todos', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Todos');
    await shoot(tester, '04_todos');
  });

  testWidgets('notes', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Notes');
    await shoot(tester, '05_notes');
  });

  testWidgets('money', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Money');
    await shoot(tester, '06_money');
  });

  testWidgets('money stats', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Money');
    await tester.tap(find.bySemanticsLabel('Stats'));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(MoneyPage),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '07_money_stats');
  });

  testWidgets('insights', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Insights');
    await shoot(tester, '08_insights');
  });

  testWidgets('drawer', skip: skip, (tester) async {
    await host(tester);
    await tester.tap(find.byTooltip('Open navigation drawer').hitTestable());
    await tester.pumpAndSettle();
    await shoot(tester, '09_drawer');
  });

  testWidgets('dark', skip: skip, (tester) async {
    await host(tester, dark: true);
    await goTo(tester, 'Habits');
    await shoot(tester, '10_dark');
  });

  testWidgets('privacy', skip: skip, (tester) async {
    await host(tester);
    await goTo(tester, 'Privacy policy');
    await shoot(tester, '11_privacy');
  });

  testWidgets('about', skip: skip, (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Control',
      packageName: 'com.rkprince.control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await host(tester);
    await goTo(tester, 'About');
    await shoot(tester, '12_about');
  });
}
