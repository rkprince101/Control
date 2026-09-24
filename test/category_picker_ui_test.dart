import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/app_picker_sheet.dart';
import 'package:control/ui/block_editor_sheet.dart';
import 'package:control/ui/controls.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UiStore extends ControlStore {
  _UiStore() {
    installedApps = const [
      InstalledApp(
        id: 'browser',
        label: 'Test Browser',
        isSystem: false,
        categories: {'browsers'},
      ),
      InstalledApp(
        id: 'game',
        label: 'Test Game',
        isSystem: false,
        categories: {'games'},
      ),
      InstalledApp(
        id: 'com.instagram.android',
        label: 'Instagram',
        isSystem: false,
      ),
    ];
  }

  bool locked = false;
  Block? saved;

  @override
  Future<void> loadInstalledApps() async {}

  @override
  bool isLocked(Block block) => locked;

  @override
  Duration? lockRemaining(Block block) => null;

  @override
  Future<void> addBlock(Block block) async => saved = block;

  @override
  Future<LockVerdict> updateBlock(Block updated) async {
    saved = updated;
    return LockVerdict.allowed;
  }
}

void main() {
  late _UiStore store;
  AppSelection? result;

  setUp(() {
    store = _UiStore();
    result = null;
  });
  tearDown(() => store.dispose());

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> picker(
    WidgetTester tester, {
    bool allowCategories = true,
    Set<String> apps = const {},
    Set<String> categories = const {},
    Set<String> exclusions = const {},
    bool locked = false,
  }) => host(tester, (context) async {
    result = await AppPickerSheet.show(
      context,
      apps,
      allowCategories: allowCategories,
      initialCategories: categories,
      initialExcludedApps: exclusions,
      locked: locked ? apps : const {},
      lockedCategories: locked ? categories : const {},
      categoryRulesLocked: locked,
    );
  });

  ControlChip chip(WidgetTester tester, String label) => tester.widget(
    find.ancestor(of: find.text(label), matching: find.byType(ControlChip)),
  );

  Future<void> reveal(
    WidgetTester tester,
    Finder target, {
    double delta = 180,
  }) async {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find.descendant(
        of: find.descendant(
          of: find.byType(AppPickerSheet),
          matching: find.byType(CustomScrollView),
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('default picker remains an explicit app selector', (
    tester,
  ) async {
    await host(tester, (context) async {
      result = await AppPickerSheet.show(context, {});
    });
    expect(find.text('Persistent categories'), findsNothing);
    expect(find.text('Browsers'), findsNothing);
    expect(find.text('Exclude from categories'), findsNothing);
    await tester.tap(find.text('Test Browser'));
    await finish(tester);
    expect(result!.apps, {'browser'});
    expect(result!.categories, isEmpty);
    expect(result!.excludedApps, isEmpty);
  });

  testWidgets('categories return persistent tokens without expanding apps', (
    tester,
  ) async {
    await picker(tester);
    expect(chip(tester, 'All apps').selected, isFalse);
    await tester.tap(find.text('Browsers'));
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('Matches category: Browsers'));
    expect(find.textContaining('Matches category: Browsers'), findsOneWidget);
    await finish(tester);
    expect(result!.categories, {'browsers', 'games'});
    expect(result!.apps, isEmpty);
    expect(result!.domains, isEmpty);
  });

  testWidgets(
    'exclusions preserve missing IDs and do not clear explicit blocks',
    (tester) async {
      await picker(
        tester,
        apps: {'browser'},
        categories: {'browsers'},
        exclusions: {'missing.app'},
      );
      final exclude = find.byKey(const ValueKey('exclude-browser'));
      await reveal(tester, exclude);
      await tester.tap(exclude);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Explicitly blocked | Excluded from categories'),
        findsOneWidget,
      );
      await finish(tester);
      expect(result!.apps, {'browser'});
      expect(result!.excludedApps, {'missing.app', 'browser'});
    },
  );

  testWidgets('locked selection only permits stronger category rules', (
    tester,
  ) async {
    await picker(
      tester,
      apps: {'browser'},
      categories: {'browsers'},
      exclusions: {'missing.app'},
      locked: true,
    );
    await tester.tap(find.text('Browsers'));
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(chip(tester, 'Browsers').selected, isTrue);
    expect(chip(tester, 'Games').selected, isTrue);
    final browser = find.byKey(const ValueKey('exclude-browser'));
    await reveal(tester, browser);
    expect(tester.widget<TextButton>(browser).onPressed, isNull);
    final checkbox = find.ancestor(
      of: find.text('Test Browser'),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
    final missing = find.byKey(const ValueKey('exclude-missing.app'));
    await reveal(tester, missing, delta: -180);
    await tester.tap(missing);
    await tester.pumpAndSettle();
    await finish(tester);
    expect(result!.categories, {'browsers', 'games'});
    expect(result!.excludedApps, isEmpty);
    expect(result!.apps, {'browser'});
  });

  testWidgets('presets remain additive explicit selections', (tester) async {
    await picker(tester);
    await reveal(tester, find.text('Social (1)'));
    await tester.tap(find.text('Social (1)'));
    await finish(tester);
    expect(result!.apps, {'com.instagram.android'});
    expect(result!.domains, contains('instagram.com'));
    expect(result!.categories, isEmpty);
  });

  testWidgets('narrow picker scrolls caveats and apps without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await picker(tester);
    await tester.tap(find.text('All apps'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('exclude-game')));
    expect(tester.takeException(), isNull);
    await finish(tester);
    expect(result!.categories, {'all_apps'});
    expect(result!.apps, isEmpty);
  });

  testWidgets('editor accepts and saves category-only blocks', (tester) async {
    await host(tester, (context) => BlockEditorSheet.show(context));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Select apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browsers'));
    await finish(tester);
    expect(find.text('0 apps, 1 categories, 0 exclusions'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.saved!.categories, {'browsers'});
    expect(store.saved!.apps, isEmpty);
  });

  for (final locked in [false, true]) {
    testWidgets('editor retains categories and exclusions, locked=$locked', (
      tester,
    ) async {
      store.locked = locked;
      const existing = Block(
        id: 'test',
        name: 'Test',
        mode: LimitMode.time,
        categories: {'games'},
        excludedApps: {'missing.app'},
        schedule: [TimeRange(startMinute: 0, endMinute: 1439)],
      );
      await host(
        tester,
        (context) => BlockEditorSheet.show(context, existing: existing),
      );
      expect(find.text('0 apps, 1 categories, 1 exclusions'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.saved!.categories, {'games'});
      expect(store.saved!.excludedApps, {'missing.app'});
    });
  }
}
