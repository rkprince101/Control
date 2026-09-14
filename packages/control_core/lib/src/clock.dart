/// A trusted reference point: wall-clock time that came from a source the user
/// cannot set (a sync response, or the value observed when the lock was armed)
/// paired with the monotonic uptime reading taken at the same instant.
class ClockAnchor {
  const ClockAnchor({required this.wallClock, required this.monotonic});

  final DateTime wallClock;

  /// Time since boot at the moment [wallClock] was captured. On Android this is
  /// `SystemClock.elapsedRealtime()`, which keeps counting through sleep and
  /// cannot be set by the user.
  final Duration monotonic;
}

/// Resolves the current time in a way that a user cannot wind backwards.
///
/// Rolling the device clock back is the cheapest way to defeat a timed lock, so
/// no expiry check may trust `DateTime.now()` alone. Three sources are combined
/// and the latest wins:
///
/// 1. the system clock, which the user controls;
/// 2. an anchor projected forward by the monotonic uptime delta, which survives
///    any clock change but resets on reboot;
/// 3. a persisted high-water mark, the latest time ever observed, which
///    survives reboot but only advances when the app runs.
///
/// Each source covers the others gap. Together, time only ever moves forward.
class TamperResistantClock {
  const TamperResistantClock();

  /// [systemNow] is `DateTime.now()`. [monotonicNow] is the current uptime
  /// reading, in the same units as [ClockAnchor.monotonic]. [highWaterMark] is
  /// the latest value previously returned by this method, loaded from storage.
  ///
  /// Persist the result as the new high-water mark after every call.
  DateTime resolve({
    required DateTime systemNow,
    Duration? monotonicNow,
    ClockAnchor? anchor,
    DateTime? highWaterMark,
  }) {
    var best = systemNow;

    if (anchor != null && monotonicNow != null) {
      final elapsed = monotonicNow - anchor.monotonic;
      // A negative delta means the device rebooted and uptime restarted; the
      // anchor is stale, so ignore it and lean on the high-water mark.
      if (!elapsed.isNegative) {
        final projected = anchor.wallClock.add(elapsed);
        if (projected.isAfter(best)) best = projected;
      }
    }

    if (highWaterMark != null && highWaterMark.isAfter(best)) {
      best = highWaterMark;
    }

    return best;
  }

  /// True when the system clock lags the resolved time by more than [tolerance],
  /// which means the user moved it backwards. Worth surfacing in the UI: silent
  /// over-blocking reads as a bug, a named tamper warning reads as the product
  /// working.
  bool detectsRollback(
    DateTime systemNow,
    DateTime resolvedNow, {
    Duration tolerance = const Duration(minutes: 5),
  }) =>
      resolvedNow.difference(systemNow) > tolerance;
}
