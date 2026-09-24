import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/app_picker_sheet.dart';
import 'package:control/ui/block_editor_sheet.dart';
import 'package:control/ui/controls.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LayoutStore extends ControlStore {
  _LayoutStore() {
    installedApps = const [
      InstalledApp(
        id: 'browser',
        label: 'Test Browser',
        isSystem: false,
        categories: {'browsers'},
      ),
      InstalledApp(
        id: 'com.instagram.android',
        label: 'Instagram',
        isSystem: false,
      ),
    ];
  }

  Block? saved;

  @override
  bool isLocked(Block block) => false;

  @override
  Future<void> loadInstalledApps() async {}

  @override
  Future<void> addBlock(Block block) async => saved = block;
}

Future<void> _host(
  WidgetTester tester,
  _LayoutStore store,
  double keyboard,
  Future<void> Function(BuildContext) open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 700);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpWidget(
    StoreScope(
      store: store,
      child: MaterialApp(
        theme: buildControlTheme(brightness: Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
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
  expect(tester.takeException(), isNull);
}

void _reachable(WidgetTester tester, Finder target, double keyboard) {
  expect(target.hitTestable(), findsOneWidget);
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(700 - keyboard));
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target,
  double keyboard, {
  double delta = 100,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    maxScrolls: 100,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  _reachable(tester, target, keyboard);
}

void main() {
  late _LayoutStore store;
  setUp(() => store = _LayoutStore());
  tearDown(() => store.dispose());

  for (final keyboard in [0.0, 240.0]) {
    testWidgets('editor inputs scroll and save at 2x, inset $keyboard', (
      tester,
    ) async {
      await _host(
        tester,
        store,
        keyboard,
        (context) => BlockEditorSheet.show(context, initialApps: {'browser'}),
      );
      final save = find.widgetWithText(TextButton, 'Save');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      _reachable(tester, save, keyboard);
      _reachable(tester, cancel, keyboard);
      expect(tester.widget<TextButton>(save).onPressed, isNotNull);

      final name = find.widgetWithText(TextField, 'Focus');
      await _reveal(tester, name, keyboard);
      await tester.enterText(name, 'Evening focus');
      final site = find.widgetWithText(TextField, 'instagram.com');
      await _reveal(tester, site, keyboard);
      await tester.enterText(site, 'https://www.example.com/path');
      await tester.pumpAndSettle();
      _reachable(tester, save, keyboard);
      _reachable(tester, cancel, keyboard);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BlockEditorSheet), findsNothing);
      expect(store.saved!.name, 'Evening focus');
      expect(store.saved!.apps, {'browser'});
      expect(store.saved!.blockedDomains, {'example.com'});
    });

    testWidgets('editor schedule controls scroll at 2x, inset $keyboard', (
      tester,
    ) async {
      await _host(
        tester,
        store,
        keyboard,
        (context) => BlockEditorSheet.show(context, initialApps: {'browser'}),
      );
      await _reveal(tester, find.text('9:00 AM'), keyboard);
      await _reveal(tester, find.text('5:00 PM'), keyboard);
      await _reveal(tester, find.text('Add range'), keyboard);
      await tester.tap(find.text('Add range'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _reveal(tester, find.text('8:00 PM'), keyboard);
      await _reveal(tester, find.text('10:00 PM'), keyboard);
      final remove = find.widgetWithIcon(IconButton, Icons.close).last;
      await _reveal(tester, remove, keyboard);
      await tester.tap(remove);
      await tester.pumpAndSettle();

      await _reveal(tester, find.text('On these days'), keyboard);
      await _reveal(tester, find.text('Weekdays'), keyboard);
      await tester.tap(find.text('Weekdays'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<WeekdayPicker>(find.byType(WeekdayPicker)).selected,
        {1, 2, 3, 4, 5},
      );
      await _reveal(tester, find.text('Unblock during'), keyboard);
      await tester.tap(find.text('Unblock during'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(TextButton, 'Save');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      _reachable(tester, save, keyboard);
      _reachable(tester, cancel, keyboard);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BlockEditorSheet), findsNothing);
      expect(store.saved!.apps, {'browser'});
      expect(store.saved!.schedule, hasLength(1));
      expect(store.saved!.schedule.single.startMinute, 9 * 60);
      expect(store.saved!.schedule.single.endMinute, 17 * 60);
      expect(store.saved!.schedule.single.weekdays, {1, 2, 3, 4, 5});
      expect(store.saved!.schedulePolarity, RulePolarity.unblockDuring);
    });

    testWidgets(
      'editor condition controls scroll and cancel, inset $keyboard',
      (tester) async {
        await _host(
          tester,
          store,
          keyboard,
          (context) => BlockEditorSheet.show(
            context,
            existing: const Block(
              id: 'condition',
              name: 'Condition block',
              mode: LimitMode.condition,
              apps: {'browser'},
            ),
          ),
        );
        final placeSwitch = find.descendant(
          of: find.ancestor(
            of: find.text('Be somewhere'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Switch),
        );
        await _reveal(tester, placeSwitch, keyboard);
        await tester.tap(placeSwitch);
        await tester.pumpAndSettle();
        await _reveal(tester, find.text('4:30 AM'), keyboard);
        await _reveal(tester, find.text('5:00 AM'), keyboard);
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        _reachable(tester, cancel, keyboard);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(BlockEditorSheet), findsNothing);
        expect(store.saved, isNull);
      },
    );

    testWidgets(
      'picker categories, presets and exclusions scroll, inset $keyboard',
      (tester) async {
        AppSelection? result;
        await _host(tester, store, keyboard, (context) async {
          result = await AppPickerSheet.show(
            context,
            {'browser'},
            allowCategories: true,
            initialCategories: {'browsers'},
            initialExcludedApps: {'missing.app'},
          );
        });
        final done = find.widgetWithText(TextButton, 'Done');
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        _reachable(tester, done, keyboard);
        _reachable(tester, cancel, keyboard);
        final search = find.byType(TextField);
        _reachable(tester, search, keyboard);
        await _reveal(tester, find.text('Persistent categories'), keyboard);
        for (final label in ['Browsers', 'Games', 'All apps']) {
          await _reveal(tester, find.text(label), keyboard);
          if (label != 'Browsers') {
            await tester.tap(find.text(label));
            await tester.pumpAndSettle();
          }
        }
        await _reveal(
          tester,
          find.text('Presets: add installed apps and sites'),
          keyboard,
        );
        await _reveal(tester, find.text('Social (1)'), keyboard);
        await tester.tap(find.text('Social (1)'));
        await tester.pumpAndSettle();
        final exclude = find.byKey(const ValueKey('exclude-browser'));
        await _reveal(tester, exclude, keyboard);
        await tester.tap(exclude);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _reveal(tester, find.text('Test Browser'), keyboard, delta: -100);
        _reachable(tester, done, keyboard);
        _reachable(tester, cancel, keyboard);
        await tester.tap(done);
        await tester.pumpAndSettle();
        expect(result!.apps, {'browser', 'com.instagram.android'});
        expect(result!.categories, {'browsers', 'games', 'all_apps'});
        expect(result!.excludedApps, {'missing.app', 'browser'});
        expect(result!.domains, contains('instagram.com'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('picker search and cancel stay reachable, inset $keyboard', (
      tester,
    ) async {
      AppSelection? result;
      var closed = false;
      await _host(tester, store, keyboard, (context) async {
        result = await AppPickerSheet.show(context, {'browser'});
        closed = true;
      });
      final search = find.byType(TextField);
      _reachable(tester, search, keyboard);
      await tester.enterText(search, 'Test Browser');
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.widgetWithText(CheckboxListTile, 'Test Browser'),
        keyboard,
      );
      expect(find.text('Instagram'), findsNothing);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      _reachable(tester, cancel, keyboard);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(closed, isTrue);
      expect(result, isNull);
    });
  }
}
