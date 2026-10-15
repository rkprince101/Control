import 'package:control/data/focus.dart';
import 'package:control/data/page_lock.dart';
import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/ui/about_page.dart';
import 'package:control/ui/blocks_page.dart';
import 'package:control/ui/disclosures.dart';
import 'package:control/ui/dialogs.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/focus_stats_sheet.dart';
import 'package:control/ui/insights_page.dart';
import 'package:control/ui/legal_page.dart';
import 'package:control/ui/lock_sheet.dart';
import 'package:control/ui/page_lock.dart';
import 'package:control/ui/restricted_settings.dart';
import 'package:control/ui/settings_page.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/preview_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const screenshot = ValueKey('redesign-preview-screenshot');
  const channel = MethodChannel('dev.control/enforcement');
  late PreviewStore store;

  // Use Flutter's cached stock font, not Ahem or a network font service.
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
    // Pictures decode outside the test's fake clock; without this the
    // Hushroom icon is still blank when a screenshot is taken.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/hushroom.png'),
        tester.element(find.byKey(screenshot)),
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
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.bySemanticsLabel(label),
      ),
    );
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
    expect(store.usage.buckets.last.end, PreviewStore.now);
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
        ('Settings', SettingsPage),
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

  testWidgets('Thoughts: ready, still blocked and done', (tester) async {
    await host(tester);
    await goTo(tester, 'Thoughts');
    expect(find.text('Parked thoughts'), findsOneWidget);
    expect(find.text('READY NOW'), findsOneWidget);
    expect(find.text('Open Video'), findsOneWidget);
    expect(find.text('Today, 11:42 AM'), findsOneWidget);
    expectMenuReachable();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/thoughts_light.png'),
    );
  });

  testWidgets('Gmail-style drawer with pages, badges and the small print', (
    tester,
  ) async {
    await host(tester);
    await tester.tap(menu.hitTestable());
    await tester.pumpAndSettle();
    Finder inDrawer(String text) =>
        find.descendant(of: find.byType(Drawer), matching: find.text(text));
    expect(inDrawer('YOUR RULES'), findsNothing);
    expect(inDrawer('Mindful browsing'), findsNothing);
    expect(inDrawer('Privacy policy'), findsOneWidget);
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

  testWidgets('search lists pages and rules as you type', (tester) async {
    await host(tester);
    await tester.tap(find.byType(SearchBar).hitTestable());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search rules and pages'),
      'r',
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Focus first'), findsOneWidget);
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
      startedAt: PreviewStore.now.subtract(
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
      startedAt: PreviewStore.now.subtract(
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

  testWidgets('A locked page asks for the PIN and opens on the last digit', (
    tester,
  ) async {
    store.pageLock = const PageLock()
        .withPin('2468')
        .withPage('insights', locked: true);
    await host(tester);
    await goTo(tester, 'Insights');
    expect(find.text('Insights is locked'), findsOneWidget);
    expect(find.text('3h 24m'), findsNothing);
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
    expect(find.text('3h 24m'), findsOneWidget);
    // Lock now, from the search bar, closes it again.
    await tester.tap(find.byTooltip('Lock pages now'));
    await tester.pumpAndSettle();
    expect(find.text('Insights is locked'), findsOneWidget);
  });

  testWidgets('App lock settings: open with the PIN, pick the pages', (
    tester,
  ) async {
    store.pageLock = const PageLock()
        .withPin('2468')
        .withPage('insights', locked: true);
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

  testWidgets('Privacy policy and terms open from the drawer', (tester) async {
    await host(tester);
    await goTo(tester, 'Privacy policy');
    expect(find.byType(LegalPage), findsOneWidget);
    expect(find.text('The short version'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/privacy_light.png'),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await goTo(tester, 'Terms of use');
    await tester.drag(
      find
          .descendant(
            of: find.byType(LegalPage),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('No warranty'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/terms_light.png'),
    );
  });

  testWidgets('Support sheet: UPI and Buy me a coffee', (tester) async {
    await host(tester);
    await tester.tap(menu.hitTestable());
    await tester.pumpAndSettle();
    // The last item in the drawer, below the fold.
    await tester.scrollUntilVisible(
      find.text('Support me'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support me'));
    await tester.pumpAndSettle();
    expect(find.text('Pay with UPI'), findsOneWidget);
    expect(find.text('rishikeshprince@upi'), findsOneWidget);
    expect(find.text('Buy me a coffee'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/support_light.png'),
    );

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('Copy UPI ID'));
    await tester.pumpAndSettle();
    expect(copied, 'rishikeshprince@upi');
    expect(find.text('UPI ID copied.'), findsOneWidget);
  });

  testWidgets('About: version, the developer and a GitHub profile button', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Control',
      packageName: 'com.rkprince.control',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await host(tester);
    await goTo(tester, 'About');
    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
    expect(find.text('Rishikesh Prince Prajapati'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/about_light.png'),
    );

    // The button hands GitHub's address to the system to open.
    final opened = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        final url = (call.arguments as Map?)?['url'];
        if (url is String) opened.add(url);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      ),
    );
    await tester.tap(find.text('GitHub profile'));
    await tester.pumpAndSettle();
    expect(opened, ['https://github.com/rkprince101']);
  });

  testWidgets('A downloaded install walks through restricted settings', (
    tester,
  ) async {
    store.accessibilityEnabled = false;
    store.installInfo = const InstallInfo(source: 'downloadedFile', sdk: 35);
    await host(tester);
    Disclosures.appBlocking(tester.element(find.byType(BlocksPage)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(find.byType(RestrictedSettingsGuide), findsOneWidget);
    expect(find.text('Allow App blocking'), findsOneWidget);
    expect(find.text('Open App info'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(screenshot),
      matchesGoldenFile('goldens/restricted_settings_light.png'),
    );

    // Back from Settings with it on: the sheet says so.
    store.accessibilityEnabled = true;
    store.notifyListenersForPreview();
    await tester.pumpAndSettle();
    expect(find.text('App blocking is on'), findsOneWidget);
    expect(find.text('All set'), findsOneWidget);
  });
}
