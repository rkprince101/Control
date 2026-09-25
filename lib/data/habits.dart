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
  ///
  /// A habit's history starts the day it was created. Anything logged before
  /// that, left over from before the rule, is set aside: a habit cannot have
  /// been kept on days it did not exist, and counting those days would let a
  /// new habit arrive with a streak it never earned.
  factory HabitStats.of(Habit habit, Map<int, int> log, DateTime today) {
    final day = dateOnly(today);
    var first = dateOnly(habit.createdAt);
    if (first.isAfter(day)) first = day;
    final firstKey = dayKey(first);
    return HabitStats._(
      habit: habit,
      log: {
        for (final entry in log.entries)
          if (entry.key >= firstKey) entry.key: entry.value,
      },
      today: day,
      firstDay: first,
    );
  }

  final Habit habit;
  final Map<int, int> log;
  final DateTime today;

  /// The day the habit was created: the earliest day it can be logged.
  final DateTime firstDay;

  /// Whether [day] can be logged: from the day the habit was created up to
  /// today, never before it and never ahead.
  bool canLog(DateTime day) {
    final date = dateOnly(day);
    return !date.isBefore(firstDay) && !date.isAfter(today);
  }

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

/// The span a progress chart covers.
enum HabitPeriod {
  week('Week'),
  month('Month'),
  year('Year');

  const HabitPeriod(this.label);

  final String label;

  /// First day of the period that holds [day].
  DateTime startOf(DateTime day) => switch (this) {
    HabitPeriod.week => DateTime(
      day.year,
      day.month,
      day.day - day.weekday + 1,
    ),
    HabitPeriod.month => DateTime(day.year, day.month),
    HabitPeriod.year => DateTime(day.year),
  };

  /// First day of the period [steps] away from the one starting at [start].
  DateTime shift(DateTime start, int steps) => switch (this) {
    HabitPeriod.week => DateTime(
      start.year,
      start.month,
      start.day + 7 * steps,
    ),
    HabitPeriod.month => DateTime(start.year, start.month + steps),
    HabitPeriod.year => DateTime(start.year + steps),
  };
}

/// One bar on a progress chart: a day, or for a year a whole month.
class HabitBar {
  const HabitBar({
    required this.start,
    required this.amount,
    required this.goal,
    required this.isCurrent,
    required this.isFuture,
  });

  /// The day, or the first of the month.
  final DateTime start;

  /// Logged, in the habit's log unit.
  final int amount;

  /// What would fill the bar: the day's goal on a due day, the sum of the due
  /// days' goals for a month. Zero on a day off, or before the habit existed.
  final int goal;

  /// Today, or this month.
  final bool isCurrent;
  final bool isFuture;

  /// Filled share. Done on a day off counts as full: extra credit shows.
  double get fill {
    if (amount <= 0) return 0;
    if (goal <= 0) return 1;
    return (amount / goal).clamp(0.0, 1.0);
  }
}

/// A week, a month or a year of one habit: the bars, the goal, and how much
/// of it is done.
///
/// The goal counts every due day in the period, future ones included, so it
/// reads as "the whole week's target" rather than moving as the days go by.
/// Days before the habit existed are left out of it: nobody is behind on a
/// habit for the months before they started it.
class HabitPeriodSummary {
  const HabitPeriodSummary({
    required this.period,
    required this.start,
    required this.end,
    required this.bars,
    required this.goal,
    required this.completed,
    required this.isCurrent,
  });

  factory HabitPeriodSummary.of(
    HabitStats stats,
    HabitPeriod period,
    DateTime anchor,
  ) {
    final habit = stats.habit;
    final today = stats.today;
    final start = period.startOf(anchor);
    final end = period.shift(start, 1);

    int dayGoal(DateTime day) =>
        habit.isDueOn(day) && !day.isBefore(stats.firstDay) ? habit.goal : 0;

    HabitBar dayBar(DateTime day) => HabitBar(
      start: day,
      amount: stats.amountOn(day),
      goal: dayGoal(day),
      isCurrent: day == today,
      isFuture: day.isAfter(today),
    );

    final List<HabitBar> bars;
    if (period == HabitPeriod.year) {
      bars = [
        for (var month = 1; month <= 12; month++)
          () {
            final first = DateTime(start.year, month);
            final next = DateTime(start.year, month + 1);
            var amount = 0;
            var goal = 0;
            for (
              var day = first;
              day.isBefore(next);
              day = DateTime(day.year, day.month, day.day + 1)
            ) {
              amount += stats.amountOn(day);
              goal += dayGoal(day);
            }
            return HabitBar(
              start: first,
              amount: amount,
              goal: goal,
              isCurrent: first.year == today.year && first.month == today.month,
              isFuture: first.isAfter(today),
            );
          }(),
      ];
    } else {
      bars = [
        for (
          var day = start;
          day.isBefore(end);
          day = DateTime(day.year, day.month, day.day + 1)
        )
          dayBar(day),
      ];
    }

    return HabitPeriodSummary(
      period: period,
      start: start,
      end: end,
      bars: bars,
      goal: bars.fold(0, (total, bar) => total + bar.goal),
      completed: bars.fold(0, (total, bar) => total + bar.amount),
      isCurrent: !today.isBefore(start) && today.isBefore(end),
    );
  }

  final HabitPeriod period;

  /// First day, inclusive.
  final DateTime start;

  /// First day of the next period, exclusive.
  final DateTime end;

  final List<HabitBar> bars;

  /// In the habit's log unit: units, seconds, or done days for a check.
  final int goal;
  final int completed;

  /// Holds today.
  final bool isCurrent;

  /// Completed over goal, capped at 100%. Anything logged against a period
  /// with no due days counts as complete.
  double get completion {
    if (goal <= 0) return completed > 0 ? 1 : 0;
    return (completed / goal).clamp(0.0, 1.0);
  }

  /// The last day in the period, for a "1 - 7 Sep" style label.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);
}

/// A step on the rank ladder.
///
/// Named for growing things, because that is what this app is about: less
/// scrolling, more room. Points are days a habit was done, so the only way up
/// is showing up.
class HabitRank {
  const HabitRank(this.name, this.threshold, this.blurb);

  final String name;
  final int threshold;

  /// One line for the journey list: what reaching this stage means.
  final String blurb;

  static const ladder = [
    HabitRank('Seed', 0, 'Planted. Every habit starts here.'),
    HabitRank('Sprout', 10, 'The first leaves: ten days of showing up.'),
    HabitRank('Sapling', 30, 'A stem that holds itself up.'),
    HabitRank('Tree', 75, 'Roots deep enough to weather a bad week.'),
    HabitRank('Grove', 150, 'Not one habit now, a few, growing together.'),
    HabitRank(
      'Forest',
      300,
      'Room enough to shelter the next habit you plant.',
    ),
    HabitRank('Old growth', 600, 'Hundreds of days. Part of who you are now.'),
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

/// Where the whole garden stands: the stage, how far into it, when each stage
/// was reached, and the recent pace.
///
/// A check-in is one habit done on one day, so three habits done today are
/// three. Nothing is ever taken away: a missed day slows the growth, it never
/// shrinks what has grown. Apps that make a streak something to lose tend to
/// lose the person on the first bad week.
class HabitGrowth {
  const HabitGrowth({
    required this.points,
    required this.stage,
    required this.withinStage,
    required this.reachedOn,
    required this.lastWeek,
    required this.lastMonth,
    required this.pacePerDay,
  });

  /// How far back the pace looks. Long enough to smooth a slow weekend,
  /// short enough to notice a change of habit.
  static const paceDays = 14;

  factory HabitGrowth.of(Iterable<HabitStats> habits, DateTime today) {
    final day = dateOnly(today);
    // Check-ins per day, across habits.
    final perDay = <int, int>{};
    for (final stats in habits) {
      for (final entry in stats.log.entries) {
        if (entry.value >= stats.habit.goal) {
          perDay[entry.key] = (perDay[entry.key] ?? 0) + 1;
        }
      }
    }

    final keys = perDay.keys.toList()..sort();
    final ladder = HabitRank.ladder;
    final reached = List<DateTime?>.filled(ladder.length, null);
    var running = 0;
    for (final key in keys) {
      running += perDay[key]!;
      for (var i = 0; i < ladder.length; i++) {
        if (reached[i] == null && running >= ladder[i].threshold) {
          reached[i] = dayFromKey(key);
        }
      }
    }
    // The seed is planted the day the first habit was.
    DateTime? planted;
    for (final stats in habits) {
      if (planted == null || stats.firstDay.isBefore(planted)) {
        planted = stats.firstDay;
      }
    }
    if (planted != null &&
        (reached[0] == null || planted.isBefore(reached[0]!))) {
      reached[0] = planted;
    }

    int since(int days) {
      final from = dayKey(DateTime(day.year, day.month, day.day - days + 1));
      final to = dayKey(day);
      var total = 0;
      for (final entry in perDay.entries) {
        if (entry.key >= from && entry.key <= to) total += entry.value;
      }
      return total;
    }

    final points = running;
    final stage = ladder.lastIndexWhere((rank) => points >= rank.threshold);
    return HabitGrowth(
      points: points,
      stage: stage,
      withinStage: HabitRank.progress(points),
      reachedOn: reached,
      lastWeek: since(7),
      lastMonth: since(30),
      pacePerDay: since(paceDays) / paceDays,
    );
  }

  final int points;

  /// Index into [HabitRank.ladder].
  final int stage;

  /// 0..1 from this stage's threshold to the next; 1 at the top.
  final double withinStage;

  /// Per stage, the day it was reached; null for those still ahead.
  final List<DateTime?> reachedOn;

  final int lastWeek;
  final int lastMonth;

  /// Check-ins a day, averaged over the last [paceDays].
  final double pacePerDay;

  HabitRank get rank => HabitRank.ladder[stage];

  /// Null at the top.
  HabitRank? get next =>
      stage + 1 < HabitRank.ladder.length ? HabitRank.ladder[stage + 1] : null;

  int get toNext => next == null ? 0 : next!.threshold - points;

  /// Days to the next stage at the recent pace. Null at the top, or with no
  /// recent check-ins to project from.
  int? get daysToNext {
    if (next == null || pacePerDay <= 0) return null;
    return (toNext / pacePerDay).ceil();
  }
}
