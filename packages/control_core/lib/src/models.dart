import 'dart:math' as math;

/// Identifies an app on the host platform.
///
/// Android: package name (`com.netflix.mediaclient`).
/// Windows: lowercased executable name (`chrome.exe`).
/// iOS: bundle identifier.
typedef AppId = String;

/// How the user chose to limit the selected apps. One mode per block, mirroring
/// the "How do you want to limit them?" segmented control.
enum LimitMode { condition, time, place, device }

/// Whether the active window of a rule blocks or frees the selected apps.
enum RulePolarity {
  /// Apps are blocked while the window/zone/device is active.
  blockDuring,

  /// Apps are blocked except while the window/zone/device is active.
  unblockDuring,
}

enum DeviceKind { bluetooth, wifi }

// ---------------------------------------------------------------------------
// Unlock conditions
// ---------------------------------------------------------------------------

/// A habit the user must complete to earn access to the blocked apps.
sealed class UnlockCondition {
  const UnlockCondition({required this.id});

  final String id;

  /// Fraction of the requirement met, clamped to 0..1.
  double progress(Signals signals);

  bool isMet(Signals signals) => progress(signals) >= 1.0;
}

class StepsCondition extends UnlockCondition {
  const StepsCondition({required super.id, required this.targetSteps});

  final int targetSteps;

  @override
  double progress(Signals signals) => targetSteps <= 0
      ? 1.0
      : (signals.stepsToday / targetSteps).clamp(0.0, 1.0);
}

class WorkoutCondition extends UnlockCondition {
  const WorkoutCondition({required super.id, required this.target});

  final Duration target;

  @override
  double progress(Signals signals) => _ratio(signals.workoutToday, target);
}

class MeditateCondition extends UnlockCondition {
  const MeditateCondition({required super.id, required this.target});

  final Duration target;

  @override
  double progress(Signals signals) => _ratio(signals.mindfulToday, target);
}

/// Spend N minutes inside [apps] to unlock the blocked ones.
class AppTimeCondition extends UnlockCondition {
  const AppTimeCondition({
    required super.id,
    required this.apps,
    required this.target,
  });

  final Set<AppId> apps;
  final Duration target;

  @override
  double progress(Signals signals) {
    var spent = Duration.zero;
    for (final app in apps) {
      spent += signals.appUsageToday[app] ?? Duration.zero;
    }
    return _ratio(spent, target);
  }
}

/// Focused time put in today, measured by the app's own timer.
///
/// The unit of exchange the reference app is missing: study for four hours,
/// then get half an hour of the apps you agreed to ration. The reward window is
/// [Block.blockAgainAfter], so the two settings read as one bargain.
class FocusCondition extends UnlockCondition {
  const FocusCondition({required super.id, required this.target});

  final Duration target;

  @override
  double progress(Signals signals) => _ratio(signals.focusToday, target);
}

/// Be at a place, inside a time window, and check in there.
///
/// The rule that gets people out of bed: stand within 150 m of the park between
/// 04:30 and 05:00, open the app, and the day unlocks. It is deliberately a
/// check-in rather than passive geofencing, because passive tracking needs
/// background location, drains the battery, and can be fooled by leaving the
/// phone somewhere. Requiring the phone in your hand at the place, in the
/// window, is both cheaper and harder to cheat.
class PlaceCheckInCondition extends UnlockCondition {
  const PlaceCheckInCondition({
    required super.id,
    required this.zone,
    required this.window,
  });

  final Zone zone;

  /// When a check-in is accepted. A [TimeRange] so a window that crosses
  /// midnight, or only runs on weekdays, needs no special case here.
  final TimeRange window;

  @override
  double progress(Signals signals) =>
      signals.placeCheckIns.contains(id) ? 1.0 : 0.0;

  /// Whether a check-in would be accepted right now.
  ///
  /// Demands a fix whose whole error circle sits inside the zone. Earning an
  /// unlock is exactly where a vague fix must not count: "might be there" is
  /// how this becomes a rule you can satisfy from bed.
  bool canCheckIn(GeoReading? reading, DateTime now) =>
      window.contains(now) &&
      reading != null &&
      zone.certainlyInside(reading);
}

/// An external trigger fired [requiredCount] times: an NFC tag scan, a Tasker
/// or MacroDroid action, a home-screen shortcut, a QR code.
///
/// The [channel] is the name the outside world uses to identify this habit, so
/// one tag can mean "pushups" and another "cold shower" without either knowing
/// anything about the block it unlocks.
class ShortcutCondition extends UnlockCondition {
  const ShortcutCondition({
    required super.id,
    required this.channel,
    this.requiredCount = 1,
  });

  final String channel;
  final int requiredCount;

  @override
  double progress(Signals signals) {
    if (requiredCount <= 0) return 1.0;
    final fired = signals.shortcutCounts[channel] ?? 0;
    return (fired / requiredCount).clamp(0.0, 1.0);
  }
}

double _ratio(Duration actual, Duration target) => target <= Duration.zero
    ? 1.0
    : (actual.inSeconds / target.inSeconds).clamp(0.0, 1.0);

// ---------------------------------------------------------------------------
// Schedule / place / device
// ---------------------------------------------------------------------------

/// A recurring daily window. Wraps past midnight when [startMinute] is greater
/// than or equal to [endMinute] (22:00 to 06:00); the weekday filter applies to
/// the day the window starts on.
class TimeRange {
  const TimeRange({
    required this.startMinute,
    required this.endMinute,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
  });

  /// Minutes since local midnight, 0..1439.
  final int startMinute;
  final int endMinute;

  /// `DateTime.weekday` values: 1 = Monday ... 7 = Sunday.
  final Set<int> weekdays;

  bool get wrapsMidnight => endMinute <= startMinute;

  bool contains(DateTime local) {
    final minute = local.hour * 60 + local.minute;
    if (!wrapsMidnight) {
      return weekdays.contains(local.weekday) &&
          minute >= startMinute &&
          minute < endMinute;
    }
    // Window that began today and runs into tomorrow.
    if (minute >= startMinute && weekdays.contains(local.weekday)) return true;
    // Tail of a window that began yesterday.
    final yesterday = local.weekday == 1 ? 7 : local.weekday - 1;
    return minute < endMinute && weekdays.contains(yesterday);
  }

  /// Next instant after [local] where [contains] flips. Drives alarm scheduling
  /// so the enforcer never has to poll.
  DateTime nextBoundary(DateTime local) {
    final today = DateTime(local.year, local.month, local.day);
    final candidates = <DateTime>[];
    for (var dayOffset = 0; dayOffset <= 8; dayOffset++) {
      final day = today.add(Duration(days: dayOffset));
      candidates
        ..add(day.add(Duration(minutes: startMinute)))
        ..add(day.add(Duration(minutes: endMinute)));
    }
    candidates.sort();
    final inside = contains(local);
    for (final candidate in candidates) {
      if (!candidate.isAfter(local)) continue;
      if (contains(candidate) != inside) return candidate;
    }
    return today.add(const Duration(days: 8));
  }
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Great-circle distance in metres.
  double distanceTo(GeoPoint other) {
    const earthRadius = 6371000.0;
    final dLat = _rad(other.latitude - latitude);
    final dLon = _rad(other.longitude - longitude);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(latitude)) *
            math.cos(_rad(other.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}

class GeoReading {
  const GeoReading({required this.point, this.accuracyMeters = 0});

  final GeoPoint point;
  final double accuracyMeters;
}

class Zone {
  const Zone({
    required this.name,
    required this.center,
    required this.radiusMeters,
  });

  final String name;
  final GeoPoint center;
  final double radiusMeters;

  /// The whole accuracy circle sits inside the zone: the device is in the zone
  /// beyond doubt.
  bool certainlyInside(GeoReading reading) =>
      center.distanceTo(reading.point) + reading.accuracyMeters <=
      radiusMeters;

  /// The accuracy circle touches the zone at all: the device might be inside.
  ///
  /// Which of the two predicates applies depends on the polarity of the rule,
  /// and the engine always picks the one that keeps apps blocked when the fix
  /// is too coarse to decide. A wide fix must never hand out access.
  bool possiblyInside(GeoReading reading) =>
      center.distanceTo(reading.point) - reading.accuracyMeters <=
      radiusMeters;
}

/// A Bluetooth peer or Wi-Fi network whose presence drives the rule.
class DeviceTrigger {
  const DeviceTrigger({
    required this.id,
    required this.kind,
    required this.label,
  });

  /// Bluetooth: MAC or stable peer id. Wi-Fi: SSID.
  final String id;
  final DeviceKind kind;
  final String label;
}

// ---------------------------------------------------------------------------
// Locking
// ---------------------------------------------------------------------------

enum LockKind {
  /// Freely editable.
  none,

  /// Editable only after entering the password.
  password,

  /// Not editable before [Lock.until], password or not.
  timed,
}

/// Protects the configuration of a block. A locked block still evaluates
/// normally; the lock only decides whether the user may weaken or delete it.
class Lock {
  const Lock.none()
      : kind = LockKind.none,
        until = null,
        passwordHash = null;

  const Lock.password(String hash)
      : kind = LockKind.password,
        until = null,
        passwordHash = hash;

  const Lock.timed({required DateTime this.until, this.passwordHash})
      : kind = LockKind.timed;

  final LockKind kind;
  final DateTime? until;
  final String? passwordHash;

  bool isExpired(DateTime now) =>
      kind == LockKind.timed && until != null && !now.isBefore(until!);
}

/// Proof that a condition was satisfied, valid until it decays.
///
/// Persisted per block. [expiresAt] is null when "Block again after" is Off, in
/// which case the grant survives until the next local midnight.
class UnlockGrant {
  const UnlockGrant({required this.grantedAt, this.expiresAt});

  final DateTime grantedAt;
  final DateTime? expiresAt;

  DateTime effectiveExpiry() =>
      expiresAt ??
      DateTime(grantedAt.year, grantedAt.month, grantedAt.day)
          .add(const Duration(days: 1));

  bool isActive(DateTime now) => now.isBefore(effectiveExpiry());
}

// ---------------------------------------------------------------------------
// Block
// ---------------------------------------------------------------------------

class Block {
  const Block({
    required this.id,
    required this.name,
    required this.mode,
    this.apps = const {},
    this.categories = const {},
    this.excludedApps = const {},
    this.conditions = const [],
    this.blockAgainAfter,
    this.schedule = const [],
    this.schedulePolarity = RulePolarity.blockDuring,
    this.zone,
    this.zonePolarity = RulePolarity.blockDuring,
    this.devices = const [],
    this.devicePolarity = RulePolarity.blockDuring,
    this.lock = const Lock.none(),
    this.enabled = true,
    this.iconAsset,
    this.blockedDomains = const {},
  });

  final String id;
  final String name;
  final LimitMode mode;

  /// Asset path of the icon shown on the block card, or null to fall back to
  /// the icons of the apps the block covers.
  final String? iconAsset;

  /// Individually selected apps.
  final Set<AppId> apps;

  /// Category tokens resolved to concrete [AppId]s by the platform layer.
  final Set<String> categories;

  /// Exceptions to this block's categories, not to explicit app targets or
  /// other blocks. Keep package IDs even while an app is uninstalled.
  final Set<AppId> excludedApps;

  /// Sites blocked alongside the apps, as bare hosts (`instagram.com`).
  ///
  /// Blocking the app and leaving the website open is the loophole every one
  /// of these tools has, and the one users find within a week. A domain covers
  /// its subdomains, so `instagram.com` also stops `www.instagram.com`.
  final Set<String> blockedDomains;

  final List<UnlockCondition> conditions;

  /// Re-arm delay after a condition unlocks the apps. Null means "Off".
  final Duration? blockAgainAfter;

  final List<TimeRange> schedule;
  final RulePolarity schedulePolarity;

  final Zone? zone;
  final RulePolarity zonePolarity;

  final List<DeviceTrigger> devices;
  final RulePolarity devicePolarity;

  final Lock lock;
  final bool enabled;

  bool get hasTargets =>
      apps.isNotEmpty || categories.isNotEmpty || blockedDomains.isNotEmpty;

  Block copyWith({
    String? name,
    LimitMode? mode,
    Set<AppId>? apps,
    Set<String>? categories,
    Set<AppId>? excludedApps,
    List<UnlockCondition>? conditions,
    Duration? blockAgainAfter,
    bool clearBlockAgainAfter = false,
    List<TimeRange>? schedule,
    RulePolarity? schedulePolarity,
    Zone? zone,
    RulePolarity? zonePolarity,
    List<DeviceTrigger>? devices,
    RulePolarity? devicePolarity,
    Lock? lock,
    bool? enabled,
    String? iconAsset,
    bool clearIconAsset = false,
    Set<String>? blockedDomains,
  }) =>
      Block(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        apps: apps ?? this.apps,
        categories: categories ?? this.categories,
        excludedApps: excludedApps ?? this.excludedApps,
        conditions: conditions ?? this.conditions,
        blockAgainAfter:
            clearBlockAgainAfter ? null : (blockAgainAfter ?? this.blockAgainAfter),
        schedule: schedule ?? this.schedule,
        schedulePolarity: schedulePolarity ?? this.schedulePolarity,
        zone: zone ?? this.zone,
        zonePolarity: zonePolarity ?? this.zonePolarity,
        devices: devices ?? this.devices,
        devicePolarity: devicePolarity ?? this.devicePolarity,
        lock: lock ?? this.lock,
        enabled: enabled ?? this.enabled,
        iconAsset: clearIconAsset ? null : (iconAsset ?? this.iconAsset),
        blockedDomains: blockedDomains ?? this.blockedDomains,
      );
}

// ---------------------------------------------------------------------------
// Signals
// ---------------------------------------------------------------------------

/// Everything the platform layer measured: a read-only snapshot handed to the
/// engine. The engine never performs I/O itself.
class Signals {
  const Signals({
    this.stepsToday = 0,
    this.workoutToday = Duration.zero,
    this.mindfulToday = Duration.zero,
    this.focusToday = Duration.zero,
    this.appUsageToday = const {},
    this.location,
    this.connectedDevices = const {},
    this.placeCheckIns = const {},
    this.shortcutCounts = const {},
    this.grants = const {},
  });

  final int stepsToday;
  final Duration workoutToday;
  final Duration mindfulToday;

  /// Total focus-timer time completed today, including the session running now.
  final Duration focusToday;

  final Map<AppId, Duration> appUsageToday;

  /// Null when no fix is available yet.
  final GeoReading? location;

  /// Bluetooth peer ids plus the current Wi-Fi SSID.
  final Set<String> connectedDevices;

  /// Ids of the place conditions checked in today.
  final Set<String> placeCheckIns;

  /// How many times each shortcut channel fired today, keyed by channel name.
  final Map<String, int> shortcutCounts;

  /// Unlock grants keyed by block id, including today's spent allowances.
  final Map<String, UnlockGrant> grants;

  Signals copyWith({
    int? stepsToday,
    Duration? workoutToday,
    Duration? mindfulToday,
    Duration? focusToday,
    Map<AppId, Duration>? appUsageToday,
    GeoReading? location,
    Set<String>? connectedDevices,
    Set<String>? placeCheckIns,
    Map<String, int>? shortcutCounts,
    Map<String, UnlockGrant>? grants,
  }) {
    return Signals(
      stepsToday: stepsToday ?? this.stepsToday,
      workoutToday: workoutToday ?? this.workoutToday,
      mindfulToday: mindfulToday ?? this.mindfulToday,
      focusToday: focusToday ?? this.focusToday,
      appUsageToday: appUsageToday ?? this.appUsageToday,
      location: location ?? this.location,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      placeCheckIns: placeCheckIns ?? this.placeCheckIns,
      shortcutCounts: shortcutCounts ?? this.shortcutCounts,
      grants: grants ?? this.grants,
    );
  }
}

// ---------------------------------------------------------------------------
// Decision
// ---------------------------------------------------------------------------

enum BlockReason {
  disabled,
  noTargets,
  schedule,
  zone,
  device,
  conditionUnmet,
  grantActive,

  /// A required signal is missing (no location fix, Health permission revoked).
  /// The engine fails closed and reports this so the UI can explain itself.
  signalUnavailable,
}

class ConditionProgress {
  const ConditionProgress({
    required this.conditionId,
    required this.progress,
    required this.met,
  });

  final String conditionId;
  final double progress;
  final bool met;
}

class BlockDecision {
  const BlockDecision({
    required this.blockId,
    required this.blocked,
    required this.reason,
    this.blockedApps = const {},
    this.blockedCategories = const {},
    this.blockedDomains = const {},
    this.nextEvaluationAt,
    this.grantExpiresAt,
    this.conditionProgress = const [],
  });

  final String blockId;
  final bool blocked;
  final BlockReason reason;
  final Set<AppId> blockedApps;
  final Set<String> blockedCategories;
  final Set<String> blockedDomains;

  /// When this decision could change on its own. Enforcers turn it into an
  /// alarm rather than polling. Null means only an external signal can change it.
  final DateTime? nextEvaluationAt;

  final DateTime? grantExpiresAt;
  final List<ConditionProgress> conditionProgress;
}
