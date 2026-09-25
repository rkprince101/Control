import 'package:control_core/control_core.dart';

/// One installed, launchable app as reported by the host platform.
class InstalledApp {
  const InstalledApp({
    required this.id,
    required this.label,
    required this.isSystem,
    this.categories = const {},
  });

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
    id: map['package'] as String,
    label: map['label'] as String? ?? map['package'] as String,
    isSystem: map['isSystem'] as bool? ?? false,
    categories: (map['categories'] as List<Object?>? ?? const [])
        .whereType<String>()
        .toSet(),
  );

  final AppId id;
  final String label;
  final bool isSystem;
  final Set<String> categories;
}

/// Screen time for a single app over the queried window.
class AppUsage {
  const AppUsage({
    required this.id,
    required this.label,
    required this.duration,
  });

  factory AppUsage.fromMap(Map<Object?, Object?> map) => AppUsage(
    id: map['package'] as String,
    label: map['label'] as String? ?? map['package'] as String,
    duration: Duration(milliseconds: (map['millis'] as num).toInt()),
  );

  final AppId id;
  final String label;
  final Duration duration;
}

/// Measured activity in one clipped, local-calendar timeline interval.
class UsageBucket {
  const UsageBucket({
    required this.start,
    required this.end,
    required this.screenTime,
    required this.pickups,
  });

  factory UsageBucket.fromMap(Map<Object?, Object?> map) => UsageBucket(
    start: DateTime.fromMillisecondsSinceEpoch(
      (map['startMillis'] as num).toInt(),
    ),
    end: DateTime.fromMillisecondsSinceEpoch((map['endMillis'] as num).toInt()),
    screenTime: Duration(milliseconds: (map['millis'] as num).toInt()),
    pickups: (map['pickups'] as num).toInt(),
  );

  final DateTime start;
  final DateTime end;
  final Duration screenTime;
  final int pickups;
}

/// Everything behind the Insights screen for one window.
class UsageSnapshot {
  const UsageSnapshot({
    required this.apps,
    required this.screenTime,
    required this.pickups,
    this.buckets = const [],
    this.start,
    this.end,
    this.firstEventAt,
    this.historyNote,
  });

  factory UsageSnapshot.fromMap(Map<Object?, Object?> map) => UsageSnapshot(
    apps: (map['apps'] as List<Object?>)
        .map((e) => AppUsage.fromMap(e! as Map<Object?, Object?>))
        .toList(),
    screenTime: Duration(
      milliseconds: (map['totalScreenMillis'] as num).toInt(),
    ),
    pickups: (map['pickups'] as num).toInt(),
    buckets: (map['buckets'] as List<Object?>? ?? const [])
        .map((e) => UsageBucket.fromMap(e! as Map<Object?, Object?>))
        .toList(),
    start: map['startMillis'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['startMillis'] as num).toInt(),
          ),
    end: map['endMillis'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['endMillis'] as num).toInt(),
          ),
    firstEventAt: map['firstEventAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (map['firstEventAt'] as num).toInt(),
          ),
    historyNote: map['historyNote'] as String?,
  );

  const UsageSnapshot.empty()
    : apps = const [],
      screenTime = Duration.zero,
      pickups = 0,
      buckets = const [],
      start = null,
      end = null,
      firstEventAt = null,
      historyNote = null;

  final List<AppUsage> apps;
  final Duration screenTime;
  final int pickups;
  final List<UsageBucket> buckets;
  final DateTime? start;
  final DateTime? end;

  /// Earliest event returned by Android, including the session lookback.
  /// This is not proof that earlier history is complete or absent.
  final DateTime? firstEventAt;
  final String? historyNote;
}

/// Whether Steps conditions can work on this device.
class StepsStatus {
  const StepsStatus({required this.granted, required this.available});

  factory StepsStatus.fromMap(Map<Object?, Object?> map) => StepsStatus(
    granted: map['granted'] as bool? ?? false,
    available: map['available'] as bool? ?? false,
  );

  const StepsStatus.unknown() : granted = false, available = false;

  /// Activity recognition permission, needed from Android 10 onwards.
  final bool granted;

  /// Whether the device has a step counter at all. Emulators and some older
  /// phones do not, and a Steps condition there would never be satisfiable.
  final bool available;

  bool get usable => granted && available;
}

/// Whether Control can reach the user with a notification, and on time.
class NotificationStatus {
  const NotificationStatus({
    required this.enabled,
    required this.exactAlarms,
    required this.exactRelevant,
  });

  /// Anything unreadable counts as fine: a warning shown on a guess would be
  /// worse than none.
  factory NotificationStatus.fromMap(Map<Object?, Object?>? map) =>
      NotificationStatus(
        enabled: map?['enabled'] as bool? ?? true,
        exactAlarms: map?['exactAlarms'] as bool? ?? true,
        exactRelevant: map?['exactRelevant'] as bool? ?? false,
      );

  const NotificationStatus.unknown()
    : enabled = true,
      exactAlarms = true,
      exactRelevant = false;

  /// Posting is allowed: the permission on Android 13+, and the app's
  /// notifications not switched off by hand.
  final bool enabled;

  /// Alarms may fire on the minute. Always true before Android 12.
  final bool exactAlarms;

  /// Whether exact alarms are something the user grants on this Android.
  final bool exactRelevant;
}

/// How hard it currently is to delete the app.
class ProtectionStatus {
  const ProtectionStatus({
    required this.adminActive,
    required this.deviceOwner,
    required this.uninstallBlocked,
    required this.hardMode,
  });

  factory ProtectionStatus.fromMap(Map<Object?, Object?> map) =>
      ProtectionStatus(
        adminActive: map['adminActive'] as bool? ?? false,
        deviceOwner: map['deviceOwner'] as bool? ?? false,
        uninstallBlocked: map['uninstallBlocked'] as bool? ?? false,
        hardMode: map['hardMode'] as bool? ?? false,
      );

  const ProtectionStatus.none()
    : adminActive = false,
      deviceOwner = false,
      uninstallBlocked = false,
      hardMode = false;

  /// Device admin held: Android refuses to uninstall, but the user can
  /// deactivate admin in Settings first.
  final bool adminActive;

  /// Provisioned as device owner, which needs a factory-reset device.
  final bool deviceOwner;

  /// Hard uninstall block. Only a device owner can set it.
  final bool uninstallBlocked;

  /// The accessibility tamper guard is armed.
  final bool hardMode;

  /// Device admin on its own no longer stops an uninstall: current Android
  /// offers "Deactivate & uninstall" in one step. So admin alone is not counted
  /// as a rung, and hard mode is what stands between the two ends.
  ProtectionTier get tier {
    if (uninstallBlocked) return ProtectionTier.locked;
    if (hardMode) return ProtectionTier.strong;
    return ProtectionTier.deterrent;
  }
}

/// Named so the app can be honest about which rung it is standing on, rather
/// than implying every block is equally hard to escape.
enum ProtectionTier {
  deterrent('Deterrent'),
  strong('Strong'),
  locked('Locked');

  const ProtectionTier(this.label);

  final String label;
}

/// Whether this device can still be handed device-owner rights, and the
/// component string the provisioning command needs.
class DeviceOwnerStatus {
  const DeviceOwnerStatus({
    required this.isOwner,
    required this.provisioningAllowed,
    required this.component,
  });

  factory DeviceOwnerStatus.fromMap(Map<Object?, Object?> map) =>
      DeviceOwnerStatus(
        isOwner: map['isOwner'] as bool? ?? false,
        provisioningAllowed: map['provisioningAllowed'] as bool? ?? false,
        component: map['component'] as String? ?? '',
      );

  const DeviceOwnerStatus.unknown()
    : isOwner = false,
      provisioningAllowed = false,
      component = '';

  final bool isOwner;

  /// False once any account is on the device, once it is already provisioned,
  /// or on a secondary user. This is the same check the system runs, so it is
  /// the honest answer to "will the command work".
  final bool provisioningAllowed;

  /// `com.rkprince.control/.enforcement.ControlDeviceAdminReceiver`
  final String component;

  String get command => 'adb shell dpm set-device-owner $component';
}

/// Whether a place check-in can be attempted on this device.
class LocationStatus {
  const LocationStatus({required this.granted, required this.enabled});

  factory LocationStatus.fromMap(Map<Object?, Object?> map) => LocationStatus(
    granted: map['granted'] as bool? ?? false,
    enabled: map['enabled'] as bool? ?? false,
  );

  const LocationStatus.unknown() : granted = false, enabled = false;

  final bool granted;

  /// Location services switched on at the system level. Granted but disabled is
  /// a common state and needs its own message.
  final bool enabled;

  bool get usable => granted && enabled;
}
