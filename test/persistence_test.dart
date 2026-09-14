import 'package:control/state/control_store.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

/// Blocks surviving a restart is the whole product. If they do not, every lock
/// in the app is decorative, so this is the suite that must never go red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storage;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('control_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.control/enforcement'),
      (call) async => switch (call.method) {
        'isAccessibilityEnabled' => false,
        'hasUsageAccess' => false,
        'stepsStatus' => <String, Object?>{'granted': false, 'available': false},
        'protectionStatus' => <String, Object?>{
            'adminActive': false,
            'deviceOwner': false,
            'uninstallBlocked': false,
          },
        'shortcutCounts' => <String, Object?>{},
        'setHardMode' => null,
        'installedApps' => <Object?>[],
        _ => null,
      },
    );
  });

  tearDown(() => storage.deleteSync(recursive: true));

  ControlStore newStore() => ControlStore(storageDirectory: storage);

  Block sample({String id = 'b1'}) => Block(
        id: id,
        name: 'Good night',
        mode: LimitMode.time,
        apps: const {'com.instagram.android'},
        schedule: const [
          TimeRange(startMinute: 1260, endMinute: 480, weekdays: {6, 7}),
        ],
      );

  test('a block added in one session is there in the next', () async {
    final first = newStore();
    await first.init();
    await first.addBlock(sample());
    expect(first.blocks, hasLength(1));

    final second = newStore();
    await second.init();
    expect(second.blocks, hasLength(1));
    expect(second.blocks.single.name, 'Good night');
  });

  test('a block added before init finishes is not lost', () async {
    final store = newStore();

    // No await: this is the race a user hits by opening the editor the instant
    // the app launches.
    final starting = store.init();
    await store.addBlock(sample(id: 'racy'));
    await starting;

    final next = newStore();
    await next.init();
    expect(next.blocks.map((b) => b.id), contains('racy'));
  });

  test('a lock survives a restart', () async {
    final first = newStore();
    await first.init();
    await first.addBlock(sample());
    await first.lockBlock('b1', duration: const Duration(days: 7));

    final second = newStore();
    await second.init();
    expect(second.blocks.single.lock.kind, LockKind.timed);
    expect(second.lockRemaining(second.blocks.single), isNotNull);
  });

  test('a spent emergency unlock stays spent', () async {
    final first = newStore();
    await first.init();
    await first.addBlock(sample());
    await first.lockBlock('b1', duration: const Duration(days: 7));
    await first.useEmergencyUnlock('b1');
    expect(first.emergencyUnlocks.remaining, 4);

    final second = newStore();
    await second.init();
    expect(second.emergencyUnlocks.remaining, 4);
  });

  group('uninstall protection', () {
    test('locking it arms hard mode and both survive a restart', () async {
      final first = newStore();
      await first.init();
      await first.lockProtection(duration: const Duration(days: 7));

      expect(first.hardMode, isTrue);
      expect(first.protectionLocked, isTrue);

      final second = newStore();
      await second.init();
      expect(second.hardMode, isTrue);
      expect(second.protectionLock.kind, LockKind.timed);
      expect(second.protectionLockRemaining, isNotNull);
    });

    test('a timed lock refuses to let hard mode be switched off', () async {
      final store = newStore();
      await store.init();
      await store.lockProtection(duration: const Duration(days: 7));

      expect(await store.setHardMode(false), isFalse);
      expect(store.hardMode, isTrue);

      // And the password is not a way round a timed lock either.
      expect(await store.unlockProtection('anything'), isFalse);
    });

    test('a password lock opens with the right password only', () async {
      final store = newStore();
      await store.init();
      await store.lockProtection(password: 'correct horse');

      expect(await store.unlockProtection('wrong'), isFalse);
      expect(store.protectionLocked, isTrue);

      expect(await store.unlockProtection('correct horse'), isTrue);
      expect(store.protectionLocked, isFalse);
      expect(await store.setHardMode(false), isTrue);
    });

    test('an emergency unlock breaks a timed protection lock', () async {
      final store = newStore();
      await store.init();
      await store.lockProtection(duration: const Duration(days: 365));

      expect(await store.emergencyUnlockProtection(), isTrue);
      expect(store.protectionLocked, isFalse);
      expect(store.emergencyUnlocks.remaining, 4);
    });

    test('releasing device admin is refused while protection is locked',
        () async {
      final store = newStore();
      await store.init();
      await store.lockProtection(duration: const Duration(days: 7));

      expect(await store.releaseProtection(), isFalse);
    });
  });

  test('a block keeps blocking an app that is uninstalled and reinstalled',
      () async {
    // Blocks are keyed by package name, and a reinstall keeps the same package
    // name, so the rule has to survive the app disappearing from the device.
    // Pinned because any future "prune apps that are not installed" tidy-up
    // would quietly hand the user a bypass: uninstall, reinstall, unblocked.
    final store = newStore();
    await store.init();
    await store.addBlock(
      Block(
        id: 'social',
        name: 'Social',
        mode: LimitMode.time,
        apps: const {'com.instagram.android'},
        schedule: const [TimeRange(startMinute: 0, endMinute: 1439)],
      ),
    );

    // installedApps is stubbed empty above: the app is not on the device.
    await store.loadInstalledApps();
    expect(store.installedApps, isEmpty);

    expect(store.plan!.blockedApps, contains('com.instagram.android'));

    final afterRestart = newStore();
    await afterRestart.init();
    expect(
      afterRestart.blocks.single.apps,
      contains('com.instagram.android'),
    );
  });

  test('the theme choice survives a restart', () async {
    final first = newStore();
    await first.init();
    await first.setTheme(AppThemeChoice.pitchBlack);

    final second = newStore();
    await second.init();
    expect(second.theme, AppThemeChoice.pitchBlack);
  });
}
