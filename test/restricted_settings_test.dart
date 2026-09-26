import 'dart:io';

import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only a downloaded or local install on Android 13+ is restricted', () {
    for (final (source, sdk, likely) in [
      ('downloadedFile', 34, true),
      ('localFile', 33, true),
      ('store', 34, false),
      ('unspecified', 34, false),
      ('downloadedFile', 32, false),
    ]) {
      final info = InstallInfo(source: source, sdk: sdk);
      expect(info.restrictedSettingsLikely, likely, reason: '$source/$sdk');
    }
    expect(const InstallInfo.unknown().restrictedSettingsPossible, isFalse);
  });

  group('coming back from Settings', () {
    late Directory storage;
    var sdk = 34;
    var accessibility = false;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      storage = Directory.systemTemp.createTempSync('control_restricted');
      sdk = 34;
      accessibility = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.control/enforcement'),
            (call) async => switch (call.method) {
              'isAccessibilityEnabled' => accessibility,
              'hasUsageAccess' => false,
              'installInfo' => <String, Object?>{
                'source': 'downloadedFile',
                'sdk': sdk,
              },
              'stepsStatus' => <String, Object?>{
                'granted': false,
                'available': false,
              },
              'protectionStatus' => <String, Object?>{
                'adminActive': false,
                'deviceOwner': false,
                'uninstallBlocked': false,
              },
              'shortcutCounts' => <String, Object?>{},
              _ => null,
            },
          );
    });

    tearDown(() => storage.deleteSync(recursive: true));

    test('a switch still off brings the steps back, once', () async {
      final store = ControlStore(storageDirectory: storage);
      await store.init();
      expect(store.installInfo.restrictedSettingsLikely, isTrue);

      await store.openAccessibilitySettings();
      await store.refreshPermissions();
      expect(store.takeMissedAccess(), SpecialAccess.appBlocking);
      expect(store.takeMissedAccess(), isNull, reason: 'reported once');

      // Opened from the guide itself: it is already on screen.
      await store.openAccessibilitySettings(watch: false);
      expect(store.takeMissedAccess(), isNull);

      // Turned on while away: nothing to say.
      await store.openAccessibilitySettings();
      accessibility = true;
      await store.refreshPermissions();
      expect(store.takeMissedAccess(), isNull);
      store.dispose();
    });

    test('before Android 13 there is nothing to explain', () async {
      sdk = 32;
      final store = ControlStore(storageDirectory: storage);
      await store.init();
      await store.openUsageAccessSettings();
      await store.refreshPermissions();
      expect(store.takeMissedAccess(), isNull);
      store.dispose();
    });
  });
}
