import 'dart:io';

import 'package:control/main.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/device_owner_sheet.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.control/enforcement');
  late Directory storage;
  late ControlStore store;
  late List<MethodCall> calls;
  late int steps;
  late Map<String, Object?> nativeGrants;
  late Map<String, Object?> ownerStatus;

  const walk = Block(
    id: 'walk',
    name: 'Walk first',
    mode: LimitMode.condition,
    apps: {'video.app'},
    conditions: [StepsCondition(id: 'steps', targetSteps: 5000)],
    blockAgainAfter: Duration(minutes: 30),
  );

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_steps');
    store = ControlStore(storageDirectory: storage);
    calls = [];
    steps = 0;
    nativeGrants = {};
    ownerStatus = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'stepsStatus' => {'granted': true, 'available': true},
            'stepsToday' => steps,
            'nativeGrants' => nativeGrants,
            'shortcutCounts' => <String, int>{},
            'deviceOwnerStatus' => ownerStatus,
            _ => null,
          };
        });
  });

  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    storage.deleteSync(recursive: true);
  });

  Map<Object?, Object?> lastRule() {
    final apply = calls.lastWhere((call) => call.method == 'applyPlan');
    final rules = (apply.arguments as Map)['rules'] as List;
    return rules.single as Map<Object?, Object?>;
  }

  test(
    'a steps-only block is handed to Android to unlock by walking',
    () async {
      await store.init();
      await store.addBlock(walk);
      final rule = lastRule();
      expect(rule['blocked'], isTrue);
      expect(rule['stepsTarget'], 5000);
      expect(
        rule['unlockForMillis'],
        const Duration(minutes: 30).inMilliseconds,
      );
    },
  );

  test('steps are not handed over while another condition is unmet', () async {
    await store.init();
    await store.addBlock(
      walk.copyWith(
        conditions: const [
          StepsCondition(id: 'steps', targetSteps: 5000),
          FocusCondition(id: 'focus', target: Duration(hours: 1)),
        ],
      ),
    );
    expect(lastRule()['stepsTarget'], 0);
  });

  test(
    'an allowance Android minted is adopted rather than paid twice',
    () async {
      await store.init();
      await store.addBlock(walk);
      final now = DateTime.now();
      nativeGrants = {
        'walk': {
          'grantedAt': now
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'expiresAt': now
              .add(const Duration(minutes: 25))
              .millisecondsSinceEpoch,
        },
      };
      steps = 6000;
      await store.refreshSignals();

      final grant = store.signals.grants['walk']!;
      expect(
        grant.grantedAt.millisecondsSinceEpoch,
        (nativeGrants['walk']! as Map)['grantedAt'],
        reason: 'the native allowance, not a fresh one minted now',
      );
      expect(store.decisionFor('walk')!.blocked, isFalse);
      final rule = lastRule();
      expect(rule['blocked'], isFalse);
      expect(rule['stepsTarget'], 0, reason: "today's allowance is spent");
    },
  );

  test('the live step refresh republishes when the count moves', () async {
    await store.init();
    await store.addBlock(walk);
    steps = 1200;
    final before = calls.where((call) => call.method == 'applyPlan').length;
    await store.refreshSteps();
    expect(store.signals.stepsToday, 1200);
    expect(
      calls.where((call) => call.method == 'applyPlan').length,
      before + 1,
    );
    // Same count, nothing to do.
    await store.refreshSteps();
    expect(
      calls.where((call) => call.method == 'applyPlan').length,
      before + 1,
    );
  });

  group('Locked tier sheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      DeviceOwnerSheet.show(tester.element(find.byType(SizedBox)));
      await tester.pumpAndSettle();
    }

    testWidgets('never sends a set-up phone to a factory reset first', (
      tester,
    ) async {
      ownerStatus = {
        'isOwner': false,
        'component':
            'com.rkprince.control/.enforcement.ControlDeviceAdminReceiver',
        'manufacturer': 'Google',
      };
      await openSheet(tester);
      expect(find.text('No factory reset needed'), findsOneWidget);
      expect(find.text('A factory reset is needed first'), findsNothing);
      expect(
        find.text(
          'adb shell dpm set-device-owner '
          'com.rkprince.control/.enforcement.ControlDeviceAdminReceiver',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Xiaomi'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on Xiaomi, names the switch behind "Calling identity is not '
        'authorized"', (tester) async {
      ownerStatus = {
        'isOwner': false,
        'component':
            'com.rkprince.control/.enforcement.ControlDeviceAdminReceiver',
        'manufacturer': 'Xiaomi',
      };
      await openSheet(tester);
      expect(
        find.text('Xiaomi, Redmi and POCO: one extra switch'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('If the command fails'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(DeviceOwnerSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('If the command fails'));
      await tester.pumpAndSettle();
      expect(find.text('Calling identity is not authorized'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('Xiaomi, Redmi and POCO are recognised however they are spelled', () {
    for (final maker in ['Xiaomi', 'XIAOMI', 'Redmi', 'POCO ']) {
      expect(
        DeviceOwnerStatus(
          isOwner: false,
          component: '',
          manufacturer: maker,
        ).isXiaomi,
        isTrue,
        reason: maker,
      );
      expect(
        InstallInfo(source: 'store', sdk: 34, manufacturer: maker).isXiaomi,
        isTrue,
      );
    }
    expect(const InstallInfo(source: 'store', sdk: 34).isXiaomi, isFalse);
  });
}
