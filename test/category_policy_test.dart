import 'dart:io';

import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.control/enforcement');
  late Directory storage;
  late List<MethodCall> calls;
  late List<ControlStore> stores;
  late DateTime nativeTime;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_categories');
    calls = [];
    stores = [];
    nativeTime = DateTime(2030, 9, 23, 12);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'enforcementTime' => nativeTime.millisecondsSinceEpoch,
            'isAccessibilityEnabled' => true,
            'hasUsageAccess' => false,
            'stepsStatus' => {'granted': true, 'available': true},
            'stepsToday' => 6000,
            'shortcutCounts' => <String, int>{},
            'installedApps' => <Object?>[],
            _ => null,
          };
        });
  });

  tearDown(() {
    for (final store in stores) {
      store.dispose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    storage.deleteSync(recursive: true);
  });

  Future<ControlStore> open() async {
    final store = ControlStore(storageDirectory: storage);
    stores.add(store);
    await store.init();
    return store;
  }

  Block categoryBlock() => const Block(
    id: 'categories',
    name: 'Browser break',
    mode: LimitMode.time,
    categories: {'browsers'},
    excludedApps: {'not.installed.browser'},
    schedule: [TimeRange(startMinute: 0, endMinute: 0)],
  );

  Map<Object?, Object?> lastPlan() =>
      calls.lastWhere((call) => call.method == 'applyPlan').arguments
          as Map<Object?, Object?>;

  test('category-only rules and missing exclusions survive restart', () async {
    final first = await open();
    await first.addBlock(categoryBlock());
    final second = await open();
    expect(second.blocks.single.categories, {'browsers'});
    expect(second.blocks.single.excludedApps, {'not.installed.browser'});
    expect(second.plan!.blockedCategories, {'browsers'});
    final rule = (lastPlan()['rules'] as List).single as Map;
    expect(rule['categories'], ['browsers']);
    expect(rule['excludedApps'], ['not.installed.browser']);
    expect(rule['apps'], isEmpty);
  });

  test(
    'wire includes inactive schedules, maps polarity and removes disabled rules',
    () async {
      final store = await open();
      await store.addBlock(
        categoryBlock().copyWith(schedulePolarity: RulePolarity.unblockDuring),
      );
      final rule = (lastPlan()['rules'] as List).single as Map;
      expect(rule['blocked'], isFalse);
      expect(rule['schedulePolarity'], 'allowDuring');
      expect((rule['schedule'] as List).single, {
        'startMinute': 0,
        'endMinute': 0,
        'weekdays': [1, 2, 3, 4, 5, 6, 7],
      });
      await store.setEnabled('categories', false);
      expect(lastPlan()['rules'], isEmpty);
    },
  );

  test('locked categories can tighten but cannot gain an exclusion', () async {
    final store = await open();
    await store.addBlock(categoryBlock());
    await store.lockBlock('categories', duration: const Duration(days: 7));
    var block = store.blocks.single;
    expect(
      await store.updateBlock(block.copyWith(categories: {})),
      LockVerdict.refused,
    );
    expect(
      await store.updateBlock(
        block.copyWith(excludedApps: {...block.excludedApps, 'new.browser'}),
      ),
      LockVerdict.refused,
    );
    expect(
      await store.updateBlock(
        block.copyWith(categories: {'browsers', 'games'}, excludedApps: {}),
      ),
      LockVerdict.allowed,
    );
    block = store.blocks.single;
    expect(block.categories, {'browsers', 'games'});
    expect(block.excludedApps, isEmpty);
  });

  test('existing block and protection locks cannot be replaced', () async {
    final store = await open();
    await store.addBlock(categoryBlock());
    await store.lockBlock('categories', duration: const Duration(days: 7));
    final until = store.blocks.single.lock.until;
    await store.lockBlock('categories', duration: const Duration(seconds: 1));
    expect(store.blocks.single.lock.until, until);
    await store.lockProtection(duration: const Duration(days: 7));
    final protectionUntil = store.protectionLock.until;
    await store.lockProtection(password: 'new password');
    expect(store.protectionLock.until, protectionUntil);
    expect(await store.setHardMode(false), isFalse);
    calls.clear();
    await store.setUninstallBlocked(false);
    expect(
      calls.where((call) => call.method == 'setUninstallBlocked'),
      isEmpty,
    );
  });

  test('password-locked blocks also protect deletion settings', () async {
    final store = await open();
    await store.addBlock(categoryBlock());
    await store.lockBlock('categories', password: 'accountability password');
    expect(await store.setHardMode(false), isFalse);
    expect(await store.releaseProtection(), isFalse);
    expect(
      await store.unlockBlock('categories', 'accountability password'),
      isTrue,
    );
    expect(await store.setHardMode(false), isTrue);
  });

  test('expired earned allowance cannot renew by reopening Control', () async {
    final first = await open();
    await first.addBlock(
      const Block(
        id: 'reward',
        name: 'Earn browsing',
        mode: LimitMode.condition,
        categories: {'browsers'},
        conditions: [StepsCondition(id: 'walk', targetSteps: 5000)],
        blockAgainAfter: Duration(minutes: 30),
      ),
    );
    final grant = first.signals.grants['reward']!;
    final rule = (lastPlan()['rules'] as List).single as Map;
    expect(
      rule['allowedUntil'],
      grant.effectiveExpiry().millisecondsSinceEpoch,
    );
    expect(rule['blocked'], isFalse);
    nativeTime = nativeTime.add(const Duration(hours: 1));
    final second = await open();
    expect(second.decisionFor('reward')!.blocked, isTrue);
    expect(
      second.signals.grants['reward']!.grantedAt.millisecondsSinceEpoch,
      grant.grantedAt.millisecondsSinceEpoch,
    );
    final third = await open();
    expect(third.decisionFor('reward')!.blocked, isTrue);
  });

  test(
    'locks use native enforcement time rather than advanced wall time',
    () async {
      final store = await open();
      await store.addBlock(categoryBlock());
      await store.lockBlock('categories', duration: const Duration(days: 1));
      expect(
        store.blocks.single.lock.until!.difference(nativeTime).inHours,
        24,
      );
      expect(store.isLocked(store.blocks.single), isTrue);
    },
  );

  test(
    'publishing across midnight does not reuse yesterday\'s signals',
    () async {
      final store = await open();
      await store.addBlock(
        const Block(
          id: 'reward',
          name: 'Earn browsing',
          mode: LimitMode.condition,
          categories: {'browsers'},
          conditions: [StepsCondition(id: 'walk', targetSteps: 5000)],
          blockAgainAfter: Duration(minutes: 30),
        ),
      );
      expect(store.signals.grants['reward'], isNotNull);
      nativeTime = nativeTime.add(const Duration(days: 1));
      await store.publish(at: nativeTime);
      expect(store.decisionFor('reward')!.blocked, isTrue);
      expect(store.signals.grants['reward'], isNull);
      expect(store.signals.stepsToday, 0);
      // Fresh measurements on the next day may earn that day's allowance.
      await store.refreshAll();
      expect(store.decisionFor('reward')!.blocked, isFalse);
      expect(store.signals.grants['reward']!.grantedAt.day, nativeTime.day);
    },
  );

  test(
    'adding during startup preserves previously saved locked rules',
    () async {
      final first = await open();
      await first.addBlock(categoryBlock());
      await first.lockBlock('categories', duration: const Duration(days: 7));
      final second = ControlStore(storageDirectory: storage);
      stores.add(second);
      final starting = second.init();
      await second.addBlock(
        const Block(
          id: 'new',
          name: 'New',
          mode: LimitMode.time,
          categories: {'games'},
          schedule: [TimeRange(startMinute: 0, endMinute: 0)],
        ),
      );
      await starting;
      final third = await open();
      expect(
        third.blocks.map((block) => block.id),
        containsAll(['categories', 'new']),
      );
      expect(third.blockById('categories')!.lock.kind, LockKind.timed);
    },
  );

  test('inventory decodes category metadata with old-platform defaults', () {
    expect(InstalledApp.fromMap({'package': 'legacy'}).categories, isEmpty);
    expect(
      InstalledApp.fromMap({
        'package': 'browser',
        'categories': ['browsers', 'all_apps'],
      }).categories,
      {'browsers', 'all_apps'},
    );
  });
}
