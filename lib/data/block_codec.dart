import 'package:control_core/control_core.dart';

/// JSON form of a [Block], used for local persistence and, later, sync.
///
/// Written by hand rather than generated because the shape is a storage
/// contract: an old block must keep decoding after the model grows, and every
/// unknown or missing field has to degrade into something that still blocks.
abstract final class BlockCodec {
  static Map<String, Object?> encode(Block block) => {
        'id': block.id,
        'name': block.name,
        'mode': block.mode.name,
        'apps': block.apps.toList(),
        'categories': block.categories.toList(),
        'enabled': block.enabled,
        'blockAgainAfterMs': block.blockAgainAfter?.inMilliseconds,
        'conditions': block.conditions.map(_encodeCondition).toList(),
        'schedule': block.schedule.map(_encodeRange).toList(),
        'schedulePolarity': block.schedulePolarity.name,
        'zone': block.zone == null ? null : _encodeZone(block.zone!),
        'zonePolarity': block.zonePolarity.name,
        'devices': block.devices.map(_encodeDevice).toList(),
        'devicePolarity': block.devicePolarity.name,
        'lock': LockCodec.encode(block.lock),
        'iconAsset': block.iconAsset,
        'blockedDomains': block.blockedDomains.toList(),
      };

  static Block decode(Map<String, Object?> json) => Block(
        id: json['id']! as String,
        name: json['name'] as String? ?? 'Block',
        mode: _enum(LimitMode.values, json['mode'], LimitMode.time),
        apps: _stringSet(json['apps']),
        categories: _stringSet(json['categories']),
        enabled: json['enabled'] as bool? ?? true,
        blockAgainAfter: _duration(json['blockAgainAfterMs']),
        conditions: _list(json['conditions'])
            .map(_decodeCondition)
            .whereType<UnlockCondition>()
            .toList(),
        schedule: _list(json['schedule']).map(_decodeRange).toList(),
        schedulePolarity: _enum(
          RulePolarity.values,
          json['schedulePolarity'],
          RulePolarity.blockDuring,
        ),
        zone: json['zone'] == null
            ? null
            : _decodeZone(json['zone']! as Map<Object?, Object?>),
        zonePolarity: _enum(
          RulePolarity.values,
          json['zonePolarity'],
          RulePolarity.blockDuring,
        ),
        devices: _list(json['devices']).map(_decodeDevice).toList(),
        devicePolarity: _enum(
          RulePolarity.values,
          json['devicePolarity'],
          RulePolarity.blockDuring,
        ),
        lock: LockCodec.decode(json['lock']),
        iconAsset: json['iconAsset'] as String?,
        blockedDomains: _stringSet(json['blockedDomains']),
      );

  // Conditions ---------------------------------------------------------------

  static Map<String, Object?> _encodeCondition(UnlockCondition condition) =>
      switch (condition) {
        StepsCondition() => {
            'type': 'steps',
            'id': condition.id,
            'targetSteps': condition.targetSteps,
          },
        WorkoutCondition() => {
            'type': 'workout',
            'id': condition.id,
            'targetMs': condition.target.inMilliseconds,
          },
        MeditateCondition() => {
            'type': 'meditate',
            'id': condition.id,
            'targetMs': condition.target.inMilliseconds,
          },
        AppTimeCondition() => {
            'type': 'appTime',
            'id': condition.id,
            'apps': condition.apps.toList(),
            'targetMs': condition.target.inMilliseconds,
          },
        FocusCondition() => {
            'type': 'focus',
            'id': condition.id,
            'targetMs': condition.target.inMilliseconds,
          },
        PlaceCheckInCondition() => {
            'type': 'placeCheckIn',
            'id': condition.id,
            'zone': _encodeZone(condition.zone),
            'window': _encodeRange(condition.window),
          },
        ShortcutCondition() => {
            'type': 'shortcut',
            'id': condition.id,
            'channel': condition.channel,
            'requiredCount': condition.requiredCount,
          },
      };

  static UnlockCondition? _decodeCondition(Map<Object?, Object?> json) {
    final id = json['id'] as String? ?? 'condition';
    return switch (json['type']) {
      'steps' => StepsCondition(
          id: id,
          targetSteps: (json['targetSteps'] as num?)?.toInt() ?? 0,
        ),
      'workout' => WorkoutCondition(id: id, target: _target(json)),
      'meditate' => MeditateCondition(id: id, target: _target(json)),
      'appTime' => AppTimeCondition(
          id: id,
          apps: _stringSet(json['apps']),
          target: _target(json),
        ),
      'focus' => FocusCondition(id: id, target: _target(json)),
      'placeCheckIn' => PlaceCheckInCondition(
          id: id,
          zone: _decodeZone(
            (json['zone'] as Map<Object?, Object?>?) ?? const {},
          ),
          window: _decodeRange(
            (json['window'] as Map<Object?, Object?>?) ?? const {},
          ),
        ),
      'shortcut' => ShortcutCondition(
          id: id,
          channel: json['channel'] as String? ?? '',
          requiredCount: (json['requiredCount'] as num?)?.toInt() ?? 1,
        ),
      // An unrecognised condition is dropped rather than guessed at. Dropping
      // one makes a block easier to satisfy, so the caller treats a block whose
      // conditions all vanished as unconfigured rather than as earned.
      _ => null,
    };
  }

  static Duration _target(Map<Object?, Object?> json) =>
      _duration(json['targetMs']) ?? Duration.zero;

  // Schedule / zone / device -------------------------------------------------

  static Map<String, Object?> _encodeRange(TimeRange range) => {
        'start': range.startMinute,
        'end': range.endMinute,
        'weekdays': range.weekdays.toList()..sort(),
      };

  static TimeRange _decodeRange(Map<Object?, Object?> json) {
    final weekdays = _intSet(json['weekdays']);
    return TimeRange(
      startMinute: (json['start'] as num?)?.toInt() ?? 0,
      endMinute: (json['end'] as num?)?.toInt() ?? 0,
      // An empty day set would mean a schedule that never runs, so a range
      // saved before weekdays existed falls back to every day.
      weekdays: weekdays.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : weekdays,
    );
  }

  static Map<String, Object?> _encodeZone(Zone zone) => {
        'name': zone.name,
        'lat': zone.center.latitude,
        'lng': zone.center.longitude,
        'radius': zone.radiusMeters,
      };

  static Zone _decodeZone(Map<Object?, Object?> json) => Zone(
        name: json['name'] as String? ?? 'Place',
        center: GeoPoint(
          (json['lat'] as num?)?.toDouble() ?? 0,
          (json['lng'] as num?)?.toDouble() ?? 0,
        ),
        radiusMeters: (json['radius'] as num?)?.toDouble() ?? 100,
      );

  static Map<String, Object?> _encodeDevice(DeviceTrigger device) => {
        'id': device.id,
        'kind': device.kind.name,
        'label': device.label,
      };

  static DeviceTrigger _decodeDevice(Map<Object?, Object?> json) =>
      DeviceTrigger(
        id: json['id'] as String? ?? '',
        kind: _enum(DeviceKind.values, json['kind'], DeviceKind.bluetooth),
        label: json['label'] as String? ?? '',
      );

  // Helpers ------------------------------------------------------------------

  static List<Map<Object?, Object?>> _list(Object? raw) => raw is List
      ? raw.whereType<Map<Object?, Object?>>().toList()
      : const <Map<Object?, Object?>>[];

  static Set<String> _stringSet(Object? raw) =>
      raw is List ? raw.whereType<String>().toSet() : <String>{};

  static Set<int> _intSet(Object? raw) => raw is List
      ? raw.whereType<num>().map((value) => value.toInt()).toSet()
      : <int>{};

  static Duration? _duration(Object? raw) =>
      raw == null ? null : Duration(milliseconds: (raw as num).toInt());

  static T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) =>
      values.where((value) => value.name == raw).firstOrNull ?? fallback;
}

/// Lock encoding, shared by blocks and by uninstall protection.
abstract final class LockCodec {
  static Map<String, Object?> encode(Lock lock) => {
        'kind': lock.kind.name,
        'untilMs': lock.until?.millisecondsSinceEpoch,
        'passwordHash': lock.passwordHash,
      };

  /// A lock that fails to decode becomes a timed lock that is still running,
  /// never an open one. Corrupt storage must not be a way out of a commitment.
  static Lock decode(Object? raw) {
    if (raw is! Map<Object?, Object?>) return const Lock.none();

    final kind = _kind(raw['kind']);
    final hash = raw['passwordHash'] as String?;
    final untilMs = (raw['untilMs'] as num?)?.toInt();

    return switch (kind) {
      LockKind.none => const Lock.none(),
      LockKind.password =>
        hash == null ? const Lock.none() : Lock.password(hash),
      LockKind.timed => Lock.timed(
          until: untilMs == null
              ? DateTime.now().add(const Duration(days: 1))
              : DateTime.fromMillisecondsSinceEpoch(untilMs),
          passwordHash: hash,
        ),
    };
  }

  static LockKind _kind(Object? raw) =>
      LockKind.values.where((value) => value.name == raw).firstOrNull ??
      LockKind.none;
}
