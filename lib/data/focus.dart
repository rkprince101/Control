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

/// A stretch of a session spent paused. Open while the pause is still going.
class FocusPause {
  const FocusPause(this.from, [this.to]);

  final DateTime from;
  final DateTime? to;
}

/// One focus session, from start to finish, with any pauses in between.
///
/// A session that is still going has no [endedAt]; its length is measured
/// against the clock, so closing the app mid-session does not lose the time.
class FocusSession {
  const FocusSession({
    required this.blockId,
    required this.startedAt,
    required this.kind,
    this.endedAt,
    this.plannedWork,
    this.pauses = const [],
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

  /// Oldest first. Only the last one can still be open.
  final List<FocusPause> pauses;

  /// Not finished yet. A paused session is still running in this sense: it
  /// holds the timer, and nothing else can start until it ends.
  bool get isRunning => endedAt == null;

  bool get isPaused => isRunning && pauses.isNotEmpty && pauses.last.to == null;

  /// The stretches of real work, in order, ending where the credit ends.
  ///
  /// Pauses are cut out, and a pomodoro is cut off the moment it has served
  /// its planned time: overrunning the timer because you forgot to stop it is
  /// not extra credit, and the minutes after the finish line belong to no day.
  List<(DateTime, DateTime)> workSpans(DateTime now) {
    final end = endedAt ?? now;
    final spans = <(DateTime, DateTime)>[];
    var cursor = startedAt;
    for (final pause in pauses) {
      final pauseFrom = pause.from.isAfter(end) ? end : pause.from;
      if (pauseFrom.isAfter(cursor)) spans.add((cursor, pauseFrom));
      final resumed = pause.to ?? end;
      if (resumed.isAfter(cursor)) cursor = resumed;
    }
    if (end.isAfter(cursor)) spans.add((cursor, end));

    final planned = plannedWork;
    if (planned == null) return spans;

    final capped = <(DateTime, DateTime)>[];
    var left = planned;
    for (final (from, to) in spans) {
      if (left <= Duration.zero) break;
      final length = to.difference(from);
      if (length <= left) {
        capped.add((from, to));
        left -= length;
      } else {
        capped.add((from, from.add(left)));
        left = Duration.zero;
      }
    }
    return capped;
  }

  /// Credited time so far.
  Duration lengthAt(DateTime now) => workSpans(
    now,
  ).fold(Duration.zero, (total, span) => total + span.$2.difference(span.$1));

  /// True once a pomodoro has served its time and is only waiting to be closed.
  bool isComplete(DateTime now) {
    final planned = plannedWork;
    if (planned == null) return false;
    return lengthAt(now) >= planned;
  }

  /// When a complete pomodoro crossed its finish line. Null otherwise.
  ///
  /// Used to close a session that finished while nobody was watching at the
  /// moment it actually finished, not whenever the app next woke up.
  DateTime? completedAt(DateTime now) {
    if (!isComplete(now)) return null;
    final spans = workSpans(now);
    return spans.isEmpty ? startedAt : spans.last.$2;
  }

  /// Time left on a pomodoro. Null for a stopwatch.
  Duration? remainingAt(DateTime now) {
    final planned = plannedWork;
    if (planned == null) return null;
    final left = planned - lengthAt(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// The part of this session's credited time that falls inside [day].
  ///
  /// Sessions that cross midnight are split rather than credited whole, or a
  /// long night would hand tomorrow a head start it did not earn. Days are
  /// calendar days, not 24-hour spans, so a daylight-saving change cannot move
  /// an hour into the wrong one.
  Duration lengthOnDay(DateTime day, DateTime now) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    var total = Duration.zero;
    for (final (from, to) in workSpans(now)) {
      final start = from.isAfter(dayStart) ? from : dayStart;
      final finish = to.isBefore(dayEnd) ? to : dayEnd;
      if (finish.isAfter(start)) total += finish.difference(start);
    }
    return total;
  }

  FocusSession _copy({DateTime? endedAt, List<FocusPause>? pauses}) =>
      FocusSession(
        blockId: blockId,
        startedAt: startedAt,
        kind: kind,
        endedAt: endedAt ?? this.endedAt,
        plannedWork: plannedWork,
        pauses: pauses ?? this.pauses,
      );

  FocusSession pausedAt(DateTime when) => isPaused || !isRunning
      ? this
      : _copy(pauses: [...pauses, FocusPause(when)]);

  FocusSession resumedAt(DateTime when) => !isPaused
      ? this
      : _copy(
          pauses: [
            ...pauses.sublist(0, pauses.length - 1),
            FocusPause(pauses.last.from, when),
          ],
        );

  /// Closes the session. An open pause closes with it.
  FocusSession stoppedAt(DateTime when) {
    final closed = isPaused ? resumedAt(when) : this;
    return closed._copy(endedAt: when);
  }

  Map<String, Object?> toMap() => {
    'blockId': blockId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt?.millisecondsSinceEpoch,
    'kind': kind.name,
    'plannedWorkMs': plannedWork?.inMilliseconds,
    if (pauses.isNotEmpty)
      'pauses': [
        for (final pause in pauses)
          [pause.from.millisecondsSinceEpoch, pause.to?.millisecondsSinceEpoch],
      ],
  };

  static FocusSession? fromMap(Map<String, Object?> map) {
    final startedAt = (map['startedAt'] as num?)?.toInt();
    if (startedAt == null) return null;

    final endedAt = (map['endedAt'] as num?)?.toInt();
    final planned = (map['plannedWorkMs'] as num?)?.toInt();

    return FocusSession(
      blockId: map['blockId'] as String? ?? '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      endedAt: endedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(endedAt),
      kind: FocusKind.fromName(map['kind'] as String?),
      plannedWork: planned == null ? null : Duration(milliseconds: planned),
      pauses: [
        for (final entry in (map['pauses'] as List?) ?? const [])
          if (entry is List && entry.isNotEmpty && entry.first is num)
            FocusPause(
              DateTime.fromMillisecondsSinceEpoch((entry.first as num).toInt()),
              entry.length > 1 && entry[1] is num
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (entry[1] as num).toInt(),
                    )
                  : null,
            ),
      ],
    );
  }
}

/// A break between pomodoros. Not credited, and not persisted: losing one to
/// a killed app costs nothing.
class FocusBreak {
  const FocusBreak({
    required this.blockId,
    required this.startedAt,
    required this.length,
  });

  final String blockId;
  final DateTime startedAt;
  final Duration length;

  DateTime get endsAt => startedAt.add(length);

  Duration remainingAt(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool isOver(DateTime now) => !now.isBefore(endsAt);
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
    this.completedPomodoros = 0,
    this.average = Duration.zero,
    this.recent = const [],
  });

  /// How far back the heatmap looks. Five whole weeks plus the current partial
  /// one always fills a 7-column grid without a ragged edge.
  static const historyDays = 42;

  /// Sessions shorter than this are a mis-tap, not a session.
  static const minimumSession = Duration(minutes: 1);

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

  /// Sessions of at least [minimumSession], including one still going.
  final int sessionCount;
  final Duration longest;

  /// Pomodoros that ran their full length.
  final int completedPomodoros;

  /// Mean length of the sessions in [sessionCount].
  final Duration average;

  /// The latest sessions, newest first.
  final List<FocusSession> recent;

  /// Consecutive days ending today with at least one session. Today counts
  /// while it is still in progress; an empty today does not break a streak
  /// until the day is over, which is why the walk starts at yesterday when
  /// today is still blank.
  final int streakDays;

  static FocusStats from(
    List<FocusSession> sessions,
    DateTime now, {
    String? blockId,
    int recentCount = 6,
  }) {
    final relevant = blockId == null
        ? sessions
        : sessions.where((s) => s.blockId == blockId).toList();

    // Calendar days counted back by date, never by 24-hour steps: across a
    // daylight-saving change those land on the wrong day and shift the whole
    // history by one.
    DateTime dayBack(int days) => DateTime(now.year, now.month, now.day - days);
    final today = dayBack(0);

    Duration on(DateTime day) => relevant.fold(
      Duration.zero,
      (total, session) => total + session.lengthOnDay(day, now),
    );

    final daily = [
      for (var i = historyDays - 1; i >= 0; i--) (dayBack(i), on(dayBack(i))),
    ];

    var longest = Duration.zero;
    var counted = 0;
    var countedTotal = Duration.zero;
    var completed = 0;
    for (final session in relevant) {
      final length = session.lengthAt(now);
      if (length > longest) longest = length;
      if (length >= minimumSession) {
        counted++;
        countedTotal += length;
      }
      if (!session.isRunning && session.isComplete(now)) completed++;
    }

    var streak = 0;
    for (var i = 0; i < 365; i++) {
      if (on(dayBack(i)) > Duration.zero) {
        streak++;
      } else if (i > 0 || on(today) > Duration.zero) {
        break;
      }
    }

    final recent =
        relevant
            .where(
              (session) =>
                  session.isRunning || session.lengthAt(now) >= minimumSession,
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return FocusStats(
      today: on(today),
      week: daily
          .sublist(daily.length - 7)
          .fold(Duration.zero, (total, entry) => total + entry.$2),
      daily: daily,
      sessionCount: counted,
      longest: longest,
      streakDays: streak,
      completedPomodoros: completed,
      average: counted == 0 ? Duration.zero : countedTotal ~/ counted,
      recent: recent.take(recentCount).toList(),
    );
  }
}
