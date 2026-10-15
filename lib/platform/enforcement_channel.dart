import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';

import '../data/thoughts.dart';

import 'platform_models.dart';

/// Dart side of the enforcement seam.
///
/// Publishes decisions plus the time-dependent rules Android must enforce when
/// the Flutter isolate is stopped. Category membership stays platform-owned.
class EnforcementChannel {
  const EnforcementChannel();

  static const MethodChannel _channel = MethodChannel(
    'dev.control/enforcement',
  );

  /// Pushes the current plan to the native enforcer, which caches it and reads
  /// it on every app switch, long after this isolate is gone.
  ///
  /// [details] is keyed by package name, and by domain for the browser guard.
  /// It carries the wording the block screen shows, because only Dart knows the
  /// rules and the screen has to explain itself with the app process dead.
  ///
  /// [stepGates] holds, per block, the steps that unlock it with every other
  /// condition already met. Android mints that allowance itself when the
  /// target is reached, so walking unlocks apps without opening Control.
  Future<void> applyPlan(
    EnforcementPlan plan, {
    Map<String, Map<String, Object?>>? details,
    Iterable<Block>? blocks,
    Map<String, UnlockGrant> grants = const {},
    Map<String, int> stepGates = const {},
  }) {
    return _channel.invokeMethod<void>('applyPlan', <String, Object?>{
      'blockedPackages': plan.blockedApps.toList(),
      'blockedDomains': plan.blockedDomains.toList(),
      'nextWakeAt': plan.nextWakeAt?.millisecondsSinceEpoch ?? 0,
      'details': details ?? const <String, Map<String, Object?>>{},
      if (blocks != null)
        'rules': [
          for (final block in blocks)
            if (block.enabled && block.hasTargets)
              {
                'id': block.id,
                'title': block.name,
                'mode': block.mode.name,
                'apps': block.apps.toList(),
                'categories': block.categories.toList(),
                'excludedApps': block.excludedApps.toList(),
                'blockedDomains': block.blockedDomains.toList(),
                'schedule': [
                  for (final range in block.schedule)
                    {
                      'startMinute': range.startMinute,
                      'endMinute': range.endMinute,
                      'weekdays': range.weekdays.toList(),
                    },
                ],
                'schedulePolarity':
                    block.schedulePolarity == RulePolarity.blockDuring
                    ? 'blockDuring'
                    : 'allowDuring',
                'blocked': plan.decisions
                    .where((decision) => decision.blockId == block.id)
                    .any((decision) => decision.blocked),
                'allowedUntil': block.mode == LimitMode.condition
                    ? grants[block.id]
                              ?.effectiveExpiry()
                              .millisecondsSinceEpoch ??
                          0
                    : 0,
                'stepsTarget': stepGates[block.id] ?? 0,
                'unlockForMillis': block.blockAgainAfter?.inMilliseconds ?? 0,
              },
        ],
    });
  }

  // Parked thoughts -------------------------------------------------------------

  /// Every parked thought, newest first, each with whether its app is still
  /// blocked right now.
  Future<List<ParkedThought>> thoughts() async {
    final result = await _channel.invokeMethod<List<Object?>>('thoughts');
    return [
      for (final entry in result ?? const <Object?>[])
        ?ParkedThought.fromChannel(entry),
    ];
  }

  Future<void> addThought(String text) =>
      _channel.invokeMethod<Object?>('addThought', {'text': text});

  Future<void> updateThought(String id, String text) => _channel
      .invokeMethod<void>('updateThought', {'id': id, 'text': text});

  Future<void> setThoughtDone(String id, {required bool done}) => _channel
      .invokeMethod<void>('setThoughtDone', {'id': id, 'done': done});

  Future<void> deleteThought(String id) =>
      _channel.invokeMethod<void>('deleteThought', {'id': id});

  /// Puts a deleted thought back exactly as it was.
  Future<void> restoreThought(ParkedThought thought) =>
      _channel.invokeMethod<bool>('restoreThought', {'json': thought.raw});

  Future<void> clearDoneThoughts() =>
      _channel.invokeMethod<void>('clearDoneThoughts');

  /// Opens the app a thought was about, or the site in the browser. False if
  /// it could not be opened.
  Future<bool> openThoughtTarget(ParkedThought thought) async =>
      await _channel.invokeMethod<bool>('openThoughtTarget', {
        'packageName': thought.packageName,
        'target': thought.target,
      }) ??
      false;

  /// Allowances Android minted on its own when a steps target was reached
  /// while Flutter was not running.
  Future<Map<String, UnlockGrant>> nativeGrants() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'nativeGrants',
    );
    if (result == null) return const {};
    return {
      for (final entry in result.entries)
        if (entry.key is String && entry.value is Map)
          entry.key! as String: UnlockGrant(
            grantedAt: DateTime.fromMillisecondsSinceEpoch(
              ((entry.value! as Map)['grantedAt'] as num).toInt(),
            ),
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              ((entry.value! as Map)['expiresAt'] as num).toInt(),
            ),
          ),
    };
  }

  /// When the block screen last could not appear and Android was sent Home
  /// instead, or null if that has not happened.
  Future<DateTime?> lastShieldFallback() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'shieldHealth',
    );
    final millis = (result?['lastFallbackAt'] as num?)?.toInt() ?? 0;
    return millis <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> clearShieldHealth() =>
      _channel.invokeMethod<void>('clearShieldHealth');

  Future<bool> isAccessibilityEnabled() async =>
      await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;

  Future<DateTime?> enforcementTime() async {
    final millis = await _channel.invokeMethod<int>('enforcementTime');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  Future<bool> hasUsageAccess() async =>
      await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;

  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod<void>('openUsageAccessSettings');

  /// Legacy signal reads return an empty snapshot when usage access is denied.
  /// Insights uses [usageTimeline] instead so failures are not hidden.
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

  /// Event-based timeline. Permission and query failures stay visible to callers.
  Future<UsageSnapshot> usageTimeline({
    required DateTime start,
    required DateTime end,
    required String bucket,
  }) async {
    final result = await _channel
        .invokeMethod<Map<Object?, Object?>>('usageTimeline', <String, Object?>{
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
          'bucket': bucket,
        });
    if (result == null) {
      throw PlatformException(
        code: 'usage_unavailable',
        message: 'Android did not return usage history.',
      );
    }
    return UsageSnapshot.fromMap(result);
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
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'stepsStatus',
    );
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
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'locationStatus',
    );
    return result == null
        ? const LocationStatus.unknown()
        : LocationStatus.fromMap(result);
  }

  Future<void> requestLocationPermission() =>
      _channel.invokeMethod<void>('requestLocationPermission');

  /// One fix, taken now. Null when there is no permission, no provider, or no
  /// fix within the timeout.
  /// The best fresh fix Android can give within a few seconds, or null.
  Future<LocationFix?> currentLocation() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'currentLocation',
    );
    return result == null ? null : LocationFix.fromMap(result);
  }

  // Health Connect -------------------------------------------------------------

  Future<HealthStatus> healthStatus() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'healthStatus',
    );
    return result == null
        ? const HealthStatus.unknown()
        : HealthStatus.fromMap(result);
  }

  /// Health Connect's own permission screen. False when it could not open.
  Future<bool> requestHealthPermissions() async =>
      await _channel.invokeMethod<bool>('requestHealthPermissions') ?? false;

  /// Install or update Health Connect, or open its settings once it is there.
  Future<bool> openHealthConnect() async =>
      await _channel.invokeMethod<bool>('openHealthConnect') ?? false;

  /// Start and end of every workout and mindfulness session recorded in
  /// Health Connect between [start] and [end].
  Future<({List<(DateTime, DateTime)> workout, List<(DateTime, DateTime)> mindful})>
  healthSessions({required DateTime start, required DateTime end}) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'healthSessions',
      <String, Object?>{
        'startMillis': start.millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
      },
    );
    List<(DateTime, DateTime)> spans(Object? raw) => [
      if (raw is List)
        for (final span in raw)
          if (span is List && span.length == 2)
            (
              DateTime.fromMillisecondsSinceEpoch((span[0] as num).toInt()),
              DateTime.fromMillisecondsSinceEpoch((span[1] as num).toInt()),
            ),
    ];
    return (workout: spans(result?['workout']), mindful: spans(result?['mindful']));
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
  }) => _channel.invokeMethod<void>('updateSummary', <String, Object?>{
    'screenTime': screenTime,
    'focusToday': focusToday,
    'blockedCount': blockedCount,
    'activeBlocks': activeBlocks,
    'weeklyReport': weeklyReport,
  });

  Future<bool> weeklyReportEnabled() async =>
      await _channel.invokeMethod<bool>('weeklyReportEnabled') ?? false;

  Future<void> setWeeklyReport(bool enabled) => _channel.invokeMethod<void>(
    'setWeeklyReport',
    <String, Object?>{'enabled': enabled},
  );

  Future<void> requestNotificationPermission() =>
      _channel.invokeMethod<void>('requestNotificationPermission');

  /// Shows, or updates, the running focus timer. With [clockAt] set it runs
  /// in a foreground service and Android runs the clock itself: counting down
  /// to it, or up from it. With [endsAt] set, Android also announces the end
  /// with [doneTitle] and [doneText], app open or not.
  Future<void> showFocusTimer({
    required String title,
    required String text,
    DateTime? clockAt,
    bool countDown = false,
    DateTime? endsAt,
    String doneTitle = '',
    String doneText = '',
  }) => _channel.invokeMethod<void>('showFocusTimer', <String, Object?>{
    'title': title,
    'text': text,
    'clockAt': clockAt?.millisecondsSinceEpoch ?? 0,
    'countDown': countDown,
    'endsAt': endsAt?.millisecondsSinceEpoch ?? 0,
    'doneTitle': doneTitle,
    'doneText': doneText,
  });

  /// Stopped by the user: nothing to announce.
  Future<void> cancelFocusTimer() =>
      _channel.invokeMethod<void>('cancelFocusTimer');

  /// The session or break reached its end here first: announce it now, once.
  Future<void> finishFocusTimer() =>
      _channel.invokeMethod<void>('finishFocusTimer');

  Future<NotificationStatus> notificationStatus() async =>
      NotificationStatus.fromMap(
        await _channel.invokeMethod<Map<Object?, Object?>>(
          'notificationStatus',
        ),
      );

  /// Asks for the permission while Android will still show the prompt, and
  /// opens the app's notification settings once it will not.
  Future<void> fixNotifications() =>
      _channel.invokeMethod<void>('fixNotifications');

  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');

  Future<InstallInfo> installInfo() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>('installInfo');
    return raw == null ? const InstallInfo.unknown() : InstallInfo.fromMap(raw);
  }

  /// Control's own App info page, where "Allow restricted settings" lives.
  Future<void> openAppInfo() => _channel.invokeMethod<void>('openAppInfo');

  /// A system screen a setup step points at. False when no version of it
  /// exists on this phone.
  Future<bool> openSystemScreen(SystemScreen screen) async =>
      await _channel.invokeMethod<bool>('openSystemScreen', <String, Object?>{
        'screen': screen.name,
      }) ??
      false;

  // Shortcut channels ---------------------------------------------------------

  Future<Map<String, int>> shortcutCounts() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'shortcutCounts',
    );
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
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'protectionStatus',
    );
    return result == null
        ? const ProtectionStatus.none()
        : ProtectionStatus.fromMap(result);
  }

  Future<DeviceOwnerStatus> deviceOwnerStatus() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'deviceOwnerStatus',
    );
    return result == null
        ? const DeviceOwnerStatus.unknown()
        : DeviceOwnerStatus.fromMap(result);
  }

  Future<void> requestDeviceAdmin() =>
      _channel.invokeMethod<void>('requestDeviceAdmin');

  /// Only succeeds when the app is device owner; returns false otherwise.
  Future<bool> setUninstallBlocked(bool blocked) async =>
      await _channel.invokeMethod<bool>(
        'setUninstallBlocked',
        <String, Object?>{'blocked': blocked},
      ) ??
      false;

  Future<void> releaseProtection() =>
      _channel.invokeMethod<void>('releaseProtection');

  /// Turns the tamper guard on or off in the accessibility service, which keeps
  /// its own copy of the flag so it still works when this isolate is dead.
  Future<void> setHardMode(bool enabled) => _channel.invokeMethod<void>(
    'setHardMode',
    <String, Object?>{'enabled': enabled},
  );

  /// PNG bytes for one app icon, or null when the app has vanished.
  Future<Uint8List?> appIcon(AppId id) => _channel.invokeMethod<Uint8List>(
    'appIcon',
    <String, Object?>{'package': id},
  );
}
