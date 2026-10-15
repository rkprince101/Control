/// The two conditions that are paid for with a stretch of time spent doing
/// something away from the phone.
enum ActivityKind {
  workout('Workout', 'Start workout', 'worked out'),
  meditate('Meditate', 'Start meditating', 'meditated');

  const ActivityKind(this.label, this.startLabel, this.pastTense);

  final String label;
  final String startLabel;

  /// "45m worked out".
  final String pastTense;

  static ActivityKind? fromName(String? name) =>
      ActivityKind.values.where((kind) => kind.name == name).firstOrNull;
}

/// A workout or meditation timed with Control's own timer.
///
/// Running while [endedAt] is null. Its length is measured against the clock,
/// so closing the app mid-workout loses nothing.
class ActivitySession {
  const ActivitySession({
    required this.kind,
    required this.startedAt,
    this.endedAt,
  });

  final ActivityKind kind;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isRunning => endedAt == null;

  /// Longest a single timed session counts for. A timer left running
  /// overnight is a forgotten timer, not a nine-hour workout.
  static const maxLength = Duration(hours: 4);

  /// Where the credited time ends: the stop, now, or the cap.
  DateTime end(DateTime now) {
    final stop = endedAt ?? now;
    final cap = startedAt.add(maxLength);
    return stop.isAfter(cap) ? cap : stop;
  }

  Duration lengthAt(DateTime now) {
    final length = end(now).difference(startedAt);
    return length.isNegative ? Duration.zero : length;
  }

  ActivitySession stoppedAt(DateTime moment) =>
      ActivitySession(kind: kind, startedAt: startedAt, endedAt: moment);

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'endedAt': endedAt?.millisecondsSinceEpoch,
  };

  static ActivitySession? fromMap(Map<String, Object?> map) {
    final kind = ActivityKind.fromName(map['kind'] as String?);
    final started = (map['startedAt'] as num?)?.toInt();
    if (kind == null || started == null) return null;
    final ended = (map['endedAt'] as num?)?.toInt();
    return ActivitySession(
      kind: kind,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started),
      endedAt: ended == null ? null : DateTime.fromMillisecondsSinceEpoch(ended),
    );
  }
}

/// Total time covered by [spans] between [from] and [to], counting any
/// overlap once.
///
/// A workout timed in Control and recorded by a fitness app at the same time
/// is one workout, not two, so the two sources are merged as intervals rather
/// than added up.
Duration coveredTime(
  Iterable<(DateTime, DateTime)> spans,
  DateTime from,
  DateTime to,
) {
  final clipped = <(DateTime, DateTime)>[
    for (final (start, end) in spans)
      if (end.isAfter(from) && start.isBefore(to))
        (start.isBefore(from) ? from : start, end.isAfter(to) ? to : end),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  var total = Duration.zero;
  DateTime? runStart;
  DateTime? runEnd;
  for (final (start, end) in clipped) {
    if (runEnd == null || start.isAfter(runEnd)) {
      if (runStart != null) total += runEnd!.difference(runStart);
      runStart = start;
      runEnd = end;
    } else if (end.isAfter(runEnd)) {
      runEnd = end;
    }
  }
  if (runStart != null) total += runEnd!.difference(runStart);
  return total;
}
