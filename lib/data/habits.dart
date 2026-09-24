/// How a habit is measured.
///
/// Three shapes cover almost everything people track: a thing that is done or
/// not (meditate), a thing counted in units (glasses of water), and a thing
/// measured in time (read for twenty minutes).
enum HabitKind {
  check('Check'),
  count('Count'),
  timer('Timer');

  const HabitKind(this.label);

  final String label;

  static HabitKind fromName(String? name) =>
      HabitKind.values.where((kind) => kind.name == name).firstOrNull ??
      HabitKind.check;
}

/// Accent colours a habit can wear.
///
/// Seeds rather than finished colours: the UI derives light and dark tones
/// from each, so a habit reads the same on every theme without a second table.
/// Ordered round the colour wheel, then the quiet ones, so the picker reads as
/// a spectrum rather than a jumble. All of them are a little muted, to sit
/// beside the app's evergreen rather than shout over it.
abstract final class HabitPalette {
  static const seeds = [
    0xFF365E49, // moss, the app accent
    0xFF55803A, // fern
    0xFF6E6F2A, // olive
    0xFF8A6D1F, // honey
    0xFFAA563A, // clay
    0xFFB0413A, // poppy
    0xFFAD4B5B, // rose
    0xFFA0466E, // berry
    0xFF874A8C, // plum
    0xFF6A4FA0, // iris
    0xFF4C4C9E, // indigo
    0xFF3F5F9A, // dusk
    0xFF2F72A6, // sky
    0xFF2F6F73, // lagoon
    0xFF8A7560, // sand
    0xFF5B6168, // stone
  ];

  static const names = [
    'Moss',
    'Fern',
    'Olive',
    'Honey',
    'Clay',
    'Poppy',
    'Rose',
    'Berry',
    'Plum',
    'Iris',
    'Indigo',
    'Dusk',
    'Sky',
    'Lagoon',
    'Sand',
    'Stone',
  ];

  static String nameOf(int seed) {
    final index = seeds.indexOf(seed);
    return index < 0 ? 'Custom' : names[index];
  }
}

/// One habit and how it is scheduled.
///
/// The log lives beside it rather than inside it, keyed by day, so editing a
/// habit's name or colour never rewrites its history.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description = '',
    this.iconAsset,
    this.color = 0xFF365E49,
    this.kind = HabitKind.check,
    this.target = 1,
    this.unit = '',
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.reminders = const [],
  });

  final String id;
  final String name;
  final String description;
  final String? iconAsset;

  /// ARGB seed, normally one of [HabitPalette.seeds].
  final int color;
  final HabitKind kind;

  /// Units for a count, minutes for a timer, and always 1 for a check.
  final int target;

  /// What a count is counted in: "glasses", "pages". Empty for the others.
  final String unit;

  /// `DateTime.weekday` values the habit is due on. A day off never breaks a
  /// streak, which is what makes "gym three times a week" trackable at all.
  final Set<int> weekdays;

  /// Minutes after midnight, sorted.
  final List<int> reminders;

  final DateTime createdAt;

  /// The amount a day needs to count as done, in the unit the log stores:
  /// seconds for a timer, units otherwise.
  int get goal => switch (kind) {
    HabitKind.check => 1,
    HabitKind.count => target < 1 ? 1 : target,
    HabitKind.timer => (target < 1 ? 1 : target) * 60,
  };

  bool isDueOn(DateTime day) => weekdays.contains(day.weekday);

  /// "8 glasses a day", "20 min", "Once a day".
  String get goalLabel => switch (kind) {
    HabitKind.check => 'Once a day',
    HabitKind.count => '$target ${unit.isEmpty ? 'times' : unit}',
    HabitKind.timer => '$target min',
  };

  Habit copyWith({
    String? name,
    String? description,
    String? iconAsset,
    bool clearIcon = false,
    int? color,
    HabitKind? kind,
    int? target,
    String? unit,
    Set<int>? weekdays,
    List<int>? reminders,
  }) => Habit(
    id: id,
    createdAt: createdAt,
    name: name ?? this.name,
    description: description ?? this.description,
    iconAsset: clearIcon ? null : (iconAsset ?? this.iconAsset),
    color: color ?? this.color,
    kind: kind ?? this.kind,
    target: target ?? this.target,
    unit: unit ?? this.unit,
    weekdays: weekdays ?? this.weekdays,
    reminders: reminders ?? this.reminders,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'iconAsset': iconAsset,
    'color': color,
    'kind': kind.name,
    'target': target,
    'unit': unit,
    'weekdays': (weekdays.toList()..sort()),
    'reminders': reminders,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  /// Null for a map that is not a habit, so one bad entry is dropped rather
  /// than taking the rest of the list with it.
  static Habit? fromMap(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;

    final weekdays = (json['weekdays'] as List?)
        ?.whereType<num>()
        .map((day) => day.toInt())
        .where((day) => day >= 1 && day <= 7)
        .toSet();
    final reminders =
        (json['reminders'] as List?)
            ?.whereType<num>()
            .map((minute) => minute.toInt())
            .where((minute) => minute >= 0 && minute < 24 * 60)
            .toSet()
            .toList()
          ?..sort();

    return Habit(
      id: id,
      name: name,
      description: json['description'] as String? ?? '',
      iconAsset: json['iconAsset'] as String?,
      color: (json['color'] as num?)?.toInt() ?? HabitPalette.seeds.first,
      kind: HabitKind.fromName(json['kind'] as String?),
      target: (json['target'] as num?)?.toInt() ?? 1,
      unit: json['unit'] as String? ?? '',
      weekdays: weekdays == null || weekdays.isEmpty
          ? const {1, 2, 3, 4, 5, 6, 7}
          : weekdays,
      reminders: reminders ?? const [],
      // A missing date must not become 1970: every streak would walk back
      // half a century of empty days.
      createdAt: switch (json['createdAt']) {
        final num millis => DateTime.fromMillisecondsSinceEpoch(millis.toInt()),
        _ => DateTime.now(),
      },
    );
  }
}

/// A timer habit that is currently being timed.
class HabitTimer {
  const HabitTimer({required this.habitId, required this.startedAt});

  final String habitId;
  final DateTime startedAt;

  /// Seconds of the run that fall on each day, keyed by [dayKey].
  ///
  /// Split rather than credited to the start day, so a session that runs past
  /// midnight does not hand tomorrow's goal to yesterday.
  Map<int, int> secondsByDay(DateTime now) {
    final result = <int, int>{};
    var from = startedAt;
    while (from.isBefore(now)) {
      final nextMidnight = DateTime(from.year, from.month, from.day + 1);
      final to = nextMidnight.isBefore(now) ? nextMidnight : now;
      final seconds = to.difference(from).inSeconds;
      if (seconds > 0) result[dayKey(from)] = seconds;
      from = to;
    }
    return result;
  }

  Map<String, Object?> toMap() => {
    'habitId': habitId,
    'startedAt': startedAt.millisecondsSinceEpoch,
  };

  static HabitTimer? fromMap(Object? json) {
    if (json is! Map) return null;
    final id = json['habitId'];
    final started = json['startedAt'];
    if (id is! String || started is! num) return null;
    return HabitTimer(
      habitId: id,
      startedAt: DateTime.fromMillisecondsSinceEpoch(started.toInt()),
    );
  }
}

/// `20260923` for 23 September 2026. Calendar days, never 24-hour spans, so a
/// daylight-saving change cannot produce two Tuesdays or none.
int dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

DateTime dayFromKey(int key) =>
    DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);

DateTime dateOnly(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Everything the Habits screen says about one habit, computed from its log.
///
/// Pure, and deliberately so: streak rules are the part of a habit tracker
/// people notice first when they are wrong, so they are kept where a test can
/// reach them without a widget tree.
class HabitStats {
  HabitStats._({
    required this.habit,
    required this.log,
    required this.today,
    required this.firstDay,
  });

  /// [log] maps [dayKey] to the stored amount for that day.
  factory HabitStats.of(Habit habit, Map<int, int> log, DateTime today) {
    final day = dateOnly(today);
    var first = dateOnly(habit.createdAt);
    for (final key in log.keys) {
      final logged = dayFromKey(key);
      if (logged.isBefore(first)) first = logged;
    }
    if (first.isAfter(day)) first = day;
    return HabitStats._(habit: habit, log: log, today: day, firstDay: first);
  }

  final Habit habit;
  final Map<int, int> log;
  final DateTime today;

  /// The earliest day the habit could have been done: its creation, or an
  /// earlier day someone went back and filled in.
  final DateTime firstDay;

  int amountOn(DateTime day) => log[dayKey(day)] ?? 0;

  double progressOn(DateTime day) =>
      (amountOn(day) / habit.goal).clamp(0.0, 1.0);

  bool isDoneOn(DateTime day) => amountOn(day) >= habit.goal;

  /// Consecutive due days done, counting back from today.
  ///
  /// Today only adds to the streak once it is done; until then it is still in
  /// play, and a streak that reads zero every morning would be a lie.
  int get currentStreak {
    var streak = 0;
    var day = today;
    if (!isDoneOn(day)) day = _previous(day);
    while (!day.isBefore(firstDay)) {
      if (habit.isDueOn(day)) {
        if (!isDoneOn(day)) break;
        streak++;
      } else if (isDoneOn(day)) {
        // Extra credit on a day off extends the run, it never breaks it.
        streak++;
      }
      day = _previous(day);
    }
    return streak;
  }

  int get longestStreak {
    var best = 0;
    var run = 0;
    for (
      var day = firstDay;
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (isDoneOn(day)) {
        run++;
        if (run > best) best = run;
      } else if (habit.isDueOn(day) && day != today) {
        run = 0;
      }
    }
    return best;
  }

  /// Days the goal was met, ever.
  int get totalDone =>
      log.values.where((amount) => amount >= habit.goal).length;

  /// Share of due days done over the last [days], today included only once it
  /// is done, so the number does not dip every morning.
  double completionRate({int days = 30}) {
    var due = 0;
    var done = 0;
    for (var i = 0; i < days; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      if (day.isBefore(firstDay)) break;
      if (!habit.isDueOn(day)) continue;
      if (day == today && !isDoneOn(day)) continue;
      due++;
      if (isDoneOn(day)) done++;
    }
    return due == 0 ? 0 : done / due;
  }

  static DateTime _previous(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);
}

/// A step on the rank ladder.
///
/// Named for growing things, because that is what this app is about: less
/// scrolling, more room. Points are days a habit was done, so the only way up
/// is showing up.
class HabitRank {
  const HabitRank(this.name, this.threshold);

  final String name;
  final int threshold;

  static const ladder = [
    HabitRank('Seed', 0),
    HabitRank('Sprout', 10),
    HabitRank('Sapling', 30),
    HabitRank('Tree', 75),
    HabitRank('Grove', 150),
    HabitRank('Forest', 300),
    HabitRank('Old growth', 600),
  ];

  static HabitRank forPoints(int points) =>
      ladder.lastWhere((rank) => points >= rank.threshold);

  /// Null at the top of the ladder.
  static HabitRank? nextAfter(int points) =>
      ladder.where((rank) => rank.threshold > points).firstOrNull;

  /// 0..1 progress from this rank to the next, 1 at the top.
  static double progress(int points) {
    final current = forPoints(points);
    final next = nextAfter(points);
    if (next == null) return 1;
    return (points - current.threshold) / (next.threshold - current.threshold);
  }
}
