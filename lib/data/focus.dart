/// How a focus session is run.
///
/// The difference is presentation, not accounting: both put real minutes into
/// the same daily total. A pomodoro simply has a finish line, which is the
/// point of it.
enum FocusKind {
  stopwatch('Stopwatch'),
  pomodoro('Pomodoro');

  const FocusKind(this.label);

  final String label;

  static FocusKind fromName(String? name) =>
      FocusKind.values.where((kind) => kind.name == name).firstOrNull ??
      FocusKind.stopwatch;
}

/// One stretch of focused time.
///
/// A session that is still running has no [endedAt]; its length is measured
/// against the clock, so closing the app mid-session does not lose the time.
class FocusSession {
  const FocusSession({
    required this.blockId,
    required this.startedAt,
    required this.kind,
    this.endedAt,
    this.plannedWork,
  });

  /// The block whose card started it. Sessions are attributed for statistics
  /// only: the minutes count towards every focus condition, because an hour of
  /// study is an hour of study and making the user run two timers for the same
  /// hour would be nonsense.
  final String blockId;

  final DateTime startedAt;
  final DateTime? endedAt;
  final FocusKind kind;

  /// Target length of a pomodoro. Null for a stopwatch.
  final Duration? plannedWork;

  bool get isRunning => endedAt == null;

  /// Length so far, capped at the planned work for a pomodoro: overrunning the
  /// timer because you forgot to stop it is not extra credit.
  Duration lengthAt(DateTime now) {
    final end = endedAt ?? now;
    var length = end.difference(startedAt);
    if (length.isNegative) length = Duration.zero;

    final planned = plannedWork;
    if (planned != null && length > planned) return planned;
    return length;
  }

  /// True once a pomodoro has served its time and is only waiting to be closed.
  bool isComplete(DateTime now) {
    final planned = plannedWork;
    if (planned == null) return false;
    return lengthAt(now) >= planned;
  }

  /// The part of this session that falls inside [day].
  ///
  /// Sessions that cross midnight are split rather than credited whole, or a
  /// long night would hand tomorrow a head start it did not earn.
  Duration lengthOnDay(DateTime day, DateTime now) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final end = endedAt ?? now;

    final from = startedAt.isAfter(dayStart) ? startedAt : dayStart;
    final to = end.isBefore(dayEnd) ? end : dayEnd;
    if (!to.isAfter(from)) return Duration.zero;

    final overlap = to.difference(from);
    final total = end.difference(startedAt);
    final counted = lengthAt(now);

    // A capped pomodoro credits its overlap proportionally, so the parts still
    // add up to the capped total. The ratio is taken first: multiplying two
    // microsecond counts overflows 64 bits once a session runs for hours.
    if (total <= Duration.zero || counted >= total) return overlap;
    final share = counted.inMicroseconds / total.inMicroseconds;
    return Duration(microseconds: (overlap.inMicroseconds * share).round());
  }

  FocusSession stoppedAt(DateTime when) => FocusSession(
        blockId: blockId,
        startedAt: startedAt,
        kind: kind,
        endedAt: when,
        plannedWork: plannedWork,
      );

  Map<String, Object?> toMap() => {
        'blockId': blockId,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'endedAt': endedAt?.millisecondsSinceEpoch,
        'kind': kind.name,
        'plannedWorkMs': plannedWork?.inMilliseconds,
      };

  static FocusSession? fromMap(Map<String, Object?> map) {
    final startedAt = (map['startedAt'] as num?)?.toInt();
    if (startedAt == null) return null;

    final endedAt = (map['endedAt'] as num?)?.toInt();
    final planned = (map['plannedWorkMs'] as num?)?.toInt();

    return FocusSession(
      blockId: map['blockId'] as String? ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      endedAt:
          endedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(endedAt),
      kind: FocusKind.fromName(map['kind'] as String?),
      plannedWork: planned == null ? null : Duration(milliseconds: planned),
    );
  }
}

/// What the stats sheet shows.
class FocusStats {
  const FocusStats({
    required this.today,
    required this.week,
    required this.daily,
    required this.sessionCount,
    required this.longest,
    required this.streakDays,
  });

  /// How far back the heatmap looks. Five whole weeks plus the current partial
  /// one always fills a 7-column grid without a ragged edge.
  static const historyDays = 42;

  final Duration today;
  final Duration week;

  /// The last [historyDays] days, oldest first, paired with the day.
  final List<(DateTime day, Duration focused)> daily;

  /// Last seven days, oldest first. The bar chart view.
  List<(DateTime day, Duration focused)> get perDay =>
      daily.sublist(daily.length - 7);

  /// The busiest day in the window, for scaling a chart.
  Duration get peak {
    var best = Duration.zero;
    for (final (_, focused) in daily) {
      if (focused > best) best = focused;
    }
    return best;
  }

  final int sessionCount;
  final Duration longest;

  /// Consecutive days ending today with at least one session. Today counts
  /// while it is still in progress; an empty today does not break a streak
  /// until the day is over, which is why the walk starts at yesterday when
  /// today is still blank.
  final int streakDays;

  static FocusStats from(
    List<FocusSession> sessions,
    DateTime now, {
    String? blockId,
  }) {
    final relevant = blockId == null
        ? sessions
        : sessions.where((s) => s.blockId == blockId).toList();

    final today = DateTime(now.year, now.month, now.day);

    Duration on(DateTime day) => relevant.fold(
          Duration.zero,
          (total, session) => total + session.lengthOnDay(day, now),
        );

    final daily = [
      for (var i = historyDays - 1; i >= 0; i--)
        (
          today.subtract(Duration(days: i)),
          on(today.subtract(Duration(days: i))),
        ),
    ];

    var longest = Duration.zero;
    for (final session in relevant) {
      final length = session.lengthAt(now);
      if (length > longest) longest = length;
    }

    var streak = 0;
    for (var i = 0; i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      if (on(day) > Duration.zero) {
        streak++;
      } else if (i > 0 || on(today) > Duration.zero) {
        break;
      }
    }

    return FocusStats(
      today: on(today),
      week: daily
          .sublist(daily.length - 7)
          .fold(Duration.zero, (total, entry) => total + entry.$2),
      daily: daily,
      sessionCount: relevant.length,
      longest: longest,
      streakDays: streak,
    );
  }
}
