import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';

import 'platform_models.dart';

/// Dart side of the enforcement seam.
///
/// Every decision is made by [RuleEngine] here in Dart; this class only ships
/// the flattened result down and reads measurements back up. Keeping the rules
/// on one side of the channel is what stops Android, Windows, and iOS from
/// slowly growing three different definitions of "blocked".
class EnforcementChannel {
  const EnforcementChannel();

  static const MethodChannel _channel = MethodChannel('dev.control/enforcement');

  /// Pushes the current plan to the native enforcer, which caches it and reads
  /// it on every app switch, long after this isolate is gone.
  ///
  /// [details] is keyed by package name, and by domain for the browser guard.
  /// It carries the wording the block screen shows, because only Dart knows the
  /// rules and the screen has to explain itself with the app process dead.
  Future<void> applyPlan(
    EnforcementPlan plan, {
    Map<String, Map<String, Object?>>? details,
  }) {
    return _channel.invokeMethod<void>('applyPlan', <String, Object?>{
      'blockedPackages': plan.blockedApps.toList(),
      'blockedDomains': plan.blockedDomains.toList(),
      'nextWakeAt': plan.nextWakeAt?.millisecondsSinceEpoch ?? 0,
      'details': details ?? const <String, Map<String, Object?>>{},
    });
  }

  Future<bool> isAccessibilityEnabled() async =>
      await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  Future<bool> hasUsageAccess() async =>
      await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;

  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod<void>('openUsageAccessSettings');

  /// Returns an empty snapshot rather than throwing when usage access has not
  /// been granted, so the Insights screen can render its own prompt.
  Future<UsageSnapshot> usageSnapshot({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'usageSnapshot',
        <String, Object?>{
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        },
      );
      if (result == null) return const UsageSnapshot.empty();
      return UsageSnapshot.fromMap(result);
    } on PlatformException catch (error) {
      if (error.code == 'permission_denied') return const UsageSnapshot.empty();
      rethrow;
    }
  }

  Future<List<InstalledApp>> installedApps() async {
    final result = await _channel.invokeMethod<List<Object?>>('installedApps');
    if (result == null) return const [];
    return result
        .map((e) => InstalledApp.fromMap(e! as Map<Object?, Object?>))
        .toList();
  }

  // Steps -------------------------------------------------------------------

  Future<StepsStatus> stepsStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('stepsStatus');
    return result == null
        ? const StepsStatus.unknown()
        : StepsStatus.fromMap(result);
  }

  Future<void> requestStepsPermission() =>
      _channel.invokeMethod<void>('requestStepsPermission');

  Future<int> stepsToday() async =>
      await _channel.invokeMethod<int>('stepsToday') ?? 0;

  // Location -----------------------------------------------------------------

  Future<LocationStatus> locationStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('locationStatus');
    return result == null
        ? const LocationStatus.unknown()
        : LocationStatus.fromMap(result);
  }

  Future<void> requestLocationPermission() =>
      _channel.invokeMethod<void>('requestLocationPermission');

  /// One fix, taken now. Null when there is no permission, no provider, or no
  /// fix within the timeout.
  Future<GeoReading?> currentLocation() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('currentLocation');
    if (result == null) return null;

    return GeoReading(
      point: GeoPoint(
        (result['latitude']! as num).toDouble(),
        (result['longitude']! as num).toDouble(),
      ),
      accuracyMeters: (result['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }

  // Widget, tile and weekly report -------------------------------------------

  /// Hands the outside surfaces a flattened snapshot.
  ///
  /// The widget, the Quick Settings tile and the weekly notification all wake
  /// without a Flutter isolate, so they cannot compute any of this themselves.
  /// The strings are formatted here because the formatting rules live here, and
  /// a second copy in Kotlin is how two screens end up disagreeing.
  Future<void> updateSummary({
    required String screenTime,
    required String focusToday,
    required int blockedCount,
    required int activeBlocks,
    required String weeklyReport,
  }) =>
      _channel.invokeMethod<void>('updateSummary', <String, Object?>{
        'screenTime': screenTime,
        'focusToday': focusToday,
        'blockedCount': blockedCount,
        'activeBlocks': activeBlocks,
        'weeklyReport': weeklyReport,
      });

  Future<bool> weeklyReportEnabled() async =>
      await _channel.invokeMethod<bool>('weeklyReportEnabled') ?? false;

  Future<void> setWeeklyReport(bool enabled) =>
      _channel.invokeMethod<void>('setWeeklyReport', <String, Object?>{
        'enabled': enabled,
      });

  Future<void> requestNotificationPermission() =>
      _channel.invokeMethod<void>('requestNotificationPermission');

  // Shortcut channels ---------------------------------------------------------

  Future<Map<String, int>> shortcutCounts() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('shortcutCounts');
    if (result == null) return const {};
    return {
      for (final entry in result.entries)
        entry.key! as String: (entry.value! as num).toInt(),
    };
  }

  /// Fires a channel from inside the app. The same thing an NFC tag does, used
  /// by the editor so a channel can be tested before it is relied on.
  Future<int> fireShortcut(String channel) async =>
      await _channel.invokeMethod<int>('fireShortcut', <String, Object?>{
        'channel': channel,
      }) ??
      0;

  // Uninstall protection ------------------------------------------------------

  Future<ProtectionStatus> protectionStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('protectionStatus');
    return result == null
        ? const ProtectionStatus.none()
        : ProtectionStatus.fromMap(result);
  }

  Future<DeviceOwnerStatus> deviceOwnerStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('deviceOwnerStatus');
    return result == null
        ? const DeviceOwnerStatus.unknown()
        : DeviceOwnerStatus.fromMap(result);
  }

  Future<void> requestDeviceAdmin() =>
      _channel.invokeMethod<void>('requestDeviceAdmin');

  /// Only succeeds when the app is device owner; returns false otherwise.
  Future<bool> setUninstallBlocked(bool blocked) async =>
      await _channel.invokeMethod<bool>('setUninstallBlocked', <String, Object?>{
        'blocked': blocked,
      }) ??
      false;

  Future<void> releaseProtection() =>
      _channel.invokeMethod<void>('releaseProtection');

  /// Turns the tamper guard on or off in the accessibility service, which keeps
  /// its own copy of the flag so it still works when this isolate is dead.
  Future<void> setHardMode(bool enabled) =>
      _channel.invokeMethod<void>('setHardMode', <String, Object?>{
        'enabled': enabled,
      });

  /// PNG bytes for one app icon, or null when the app has vanished.
  Future<Uint8List?> appIcon(AppId id) =>
      _channel.invokeMethod<Uint8List>('appIcon', <String, Object?>{
        'package': id,
      });
}
