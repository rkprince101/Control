import 'models.dart';

/// The answer to "may the user do this to a locked block right now?".
enum LockVerdict {
  /// Allowed outright.
  allowed,

  /// Allowed once the block password is supplied.
  needsPassword,

  /// Refused until the timed lock expires. An emergency unlock is the only way
  /// out before then.
  refused,
}

/// A change the user wants to make to an existing block.
///
/// Locks only guard changes that make a block easier to escape. Making a block
/// stricter is always permitted, otherwise the lock would work against the
/// person who armed it.
enum BlockChange {
  /// Delete the block, disable it, or remove apps from it.
  weaken,

  /// Add apps, extend a schedule, raise a condition target.
  strengthen,

  /// Shorten or clear the lock itself.
  unlock,
}

class LockPolicy {
  const LockPolicy();

  LockVerdict verdict({
    required Block block,
    required BlockChange change,
    required DateTime now,
  }) {
    if (change == BlockChange.strengthen) return LockVerdict.allowed;

    return switch (block.lock.kind) {
      LockKind.none => LockVerdict.allowed,
      LockKind.password => LockVerdict.needsPassword,
      LockKind.timed => block.lock.isExpired(now)
          ? LockVerdict.allowed
          : LockVerdict.refused,
    };
  }

  /// Time left on a timed lock, or null when nothing is holding it.
  Duration? remaining({required Block block, required DateTime now}) {
    final until = block.lock.until;
    if (block.lock.kind != LockKind.timed || until == null) return null;
    final left = until.difference(now);
    return left.isNegative ? null : left;
  }
}

/// A finite, never-refilling pool that frees a timed lock when the password is
/// genuinely lost. Finite by design: an unlimited escape hatch is not a lock,
/// and a refilling one just teaches the user to wait for the refill.
class EmergencyUnlocks {
  const EmergencyUnlocks({required this.remaining, required this.total});

  static const int defaultTotal = 5;

  const EmergencyUnlocks.fresh()
      : remaining = defaultTotal,
        total = defaultTotal;

  final int remaining;
  final int total;

  bool get isExhausted => remaining <= 0;

  /// Consumes one unlock. Returns the unchanged pool when it is already empty,
  /// so callers can branch on [EmergencyUnlockResult.granted] alone.
  EmergencyUnlockResult consume() {
    if (isExhausted) {
      return EmergencyUnlockResult(granted: false, pool: this);
    }
    return EmergencyUnlockResult(
      granted: true,
      pool: EmergencyUnlocks(remaining: remaining - 1, total: total),
    );
  }
}

class EmergencyUnlockResult {
  const EmergencyUnlockResult({required this.granted, required this.pool});

  final bool granted;
  final EmergencyUnlocks pool;
}
