import 'package:flutter/material.dart';

import '../data/descriptions.dart';
import '../data/habits.dart';
import '../main.dart';
import 'control_page.dart';
import 'expressive_progress.dart';
import 'habit_sheets.dart';
import 'habit_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});

  @override
  State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  /// The day the cards log against. Today unless someone went back to fill in
  /// a day they forgot.
  DateTime? _picked;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final today = dateOnly(store.wallNow());
    // A day picked last night quietly becomes today again after midnight
    // rather than leaving the page stuck a day behind.
    final picked = _picked;
    final day =
        picked == null ||
            picked.isAfter(today) ||
            today.difference(picked).inDays > 6
        ? today
        : picked;

    final habits = store.habits;
    final due = [
      for (final habit in habits)
        if (habit.isDueOn(day) || store.habitStats(habit).isDoneOn(day)) habit,
    ];
    final resting = habits.where((habit) => !due.contains(habit)).toList();

    return ControlPage(
      title: 'Build rhythm',
      eyebrow: 'HABITS',
      subtitle: 'Small steps, done often, add up to a lot.',
      children: [
        _HabitHero(day: day, today: today),
        const SizedBox(height: 20),
        _DayStrip(
          selected: day,
          today: today,
          onSelect: (value) => setState(() => _picked = value),
        ),
        const SizedBox(height: 24),
        if (habits.isEmpty)
          ControlCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No habits yet',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick one small thing to do every day. Water, a page, a '
                  'stretch. Tick it off here and watch the grid fill in.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => HabitEditorSheet.show(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create a habit'),
                ),
              ],
            ),
          )
        else ...[
          SectionLabel(
            day == today
                ? 'Due today'
                : 'Due ${describeHabitDay(context, day, today).toLowerCase()}',
          ),
          if (due.isEmpty)
            ControlCard(
              child: Text(
                'Nothing is due on this day. Enjoy the rest.',
                style: TextStyle(color: colors.textMuted),
              ),
            ),
          for (final habit in due)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: HabitCard(habit: habit, day: day),
            ),
          if (resting.isNotEmpty) ...[
            const SizedBox(height: 10),
            const SectionLabel('Day off'),
            for (final habit in resting)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: HabitCard(habit: habit, day: day),
              ),
          ],
        ],
      ],
    );
  }
}

/// The day's score and the rank it is building towards.
class _HabitHero extends StatelessWidget {
  const _HabitHero({required this.day, required this.today});

  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = scheme.onSecondaryContainer;

    final progress = store.habitProgressOn(day);
    final points = store.habitPoints;
    final rank = HabitRank.forPoints(points);
    final next = HabitRank.nextAfter(points);
    final bestStreak = store.habits.fold(0, (best, habit) {
      final streak = store.habitStats(habit).currentStreak;
      return streak > best ? streak : best;
    });

    return HeroCard(
      tone: scheme.secondaryContainer,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_florist_outlined, color: foreground),
            const SizedBox(height: 16),
            Text(
              progress.due == 0
                  ? 'A clear day.'
                  : progress.done >= progress.due
                  ? 'All done. Nice.'
                  : '${progress.done} of ${progress.due} done',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            ExpressiveProgress(
              value: progress.due == 0 ? 0 : progress.done / progress.due,
              color: foreground,
              trackColor: foreground.withValues(alpha: 0.18),
              semanticsLabel: day == today
                  ? 'Habits done today'
                  : 'Habits done that day',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _HeroMetric(
                  icon: Icons.local_fire_department_rounded,
                  value: bestStreak == 1 ? '1 day' : '$bestStreak days',
                  label: 'Best running streak',
                  color: foreground,
                ),
                _HeroMetric(
                  icon: Icons.park_outlined,
                  value: rank.name,
                  label: next == null
                      ? '$points check-ins. Top rank'
                      : '${next.threshold - points} more to ${next.name}',
                  color: foreground,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The last seven days, each with a ring for how much of it got done.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final localizations = MaterialLocalizations.of(context);

    return Row(
      children: [
        for (var offset = 6; offset >= 0; offset--)
          Expanded(
            child: () {
              final day = DateTime(today.year, today.month, today.day - offset);
              final progress = store.habitProgressOn(day);
              final share = progress.due == 0
                  ? 0.0
                  : progress.done / progress.due;
              final isSelected = day == selected;

              return Semantics(
                button: true,
                selected: isSelected,
                label:
                    '${localizations.formatFullDate(day)}, '
                    '${progress.done} of ${progress.due} habits done',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => onSelect(day),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            _letters[day.weekday - 1],
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: day == today
                                  ? scheme.primary
                                  : colors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 42,
                            height: 42,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 180),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? scheme.secondaryContainer
                                        : Colors.transparent,
                                  ),
                                ),
                                CircularProgressIndicator(
                                  value: share,
                                  strokeWidth: 3,
                                  strokeCap: StrokeCap.round,
                                  color: colors.light,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 42,
                                    height: 42,
                                  ),
                                ),
                                Text(
                                  '${day.day}',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: isSelected
                                        ? scheme.onSecondaryContainer
                                        : null,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
          ),
      ],
    );
  }
}

/// One habit: what it is, a one-tap way to log it, and its grid.
class HabitCard extends StatelessWidget {
  const HabitCard({required this.habit, required this.day, super.key});

  final Habit habit;

  /// The day the log button acts on.
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final tones = HabitTones.of(context, habit.color);
    final stats = store.habitStats(habit);
    final amount = stats.amountOn(day);
    final streak = stats.currentStreak;

    final status = switch (habit.kind) {
      HabitKind.check =>
        stats.isDoneOn(day) ? 'Done' : describeWeekdays(habit.weekdays),
      HabitKind.count =>
        '$amount / ${habit.target} ${habit.unit.isEmpty ? 'times' : habit.unit}',
      HabitKind.timer => formatHabitTime(
        habit,
        amount,
        running: store.habitTimer?.habitId == habit.id && day == stats.today,
      ),
    };

    return Semantics(
      container: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: Shapes.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => HabitDetailSheet.show(context, habit, day: day),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    HabitIconTile(habit: habit),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(habit.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            status,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: stats.isDoneOn(day)
                                  ? tones.accent
                                  : colors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LogButton(habit: habit, day: day, stats: stats),
                  ],
                ),
                if (habit.kind != HabitKind.check) ...[
                  const SizedBox(height: 10),
                  ExpressiveProgress(
                    value: stats.progressOn(day),
                    color: tones.accent,
                    trackColor: colors.cardRaised,
                    semanticsLabel: '${habit.name} progress',
                  ),
                ],
                const SizedBox(height: 12),
                HabitGrid(stats: stats),
                const SizedBox(height: 12),
                DefaultTextStyle.merge(
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 16,
                            color: streak > 0 ? tones.accent : colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              streak == 1
                                  ? '1 day streak'
                                  : '$streak day streak',
                            ),
                          ),
                        ],
                      ),
                      Text('Best ${stats.longestStreak}'),
                      Text(
                        '${(stats.completionRate() * 100).round()}% '
                        'last 30 days',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-tap action on a card: tick, add one, or start and stop the timer.
class _LogButton extends StatelessWidget {
  const _LogButton({
    required this.habit,
    required this.day,
    required this.stats,
  });

  final Habit habit;
  final DateTime day;
  final HabitStats stats;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final tones = HabitTones.of(context, habit.color);
    final done = stats.isDoneOn(day);
    final isToday = day == stats.today;
    final running = store.habitTimer?.habitId == habit.id;

    final (
      IconData icon,
      String tooltip,
      VoidCallback onTap,
    ) = switch (habit.kind) {
      HabitKind.check => (
        Icons.check_rounded,
        done ? 'Mark ${habit.name} not done' : 'Mark ${habit.name} done',
        () => store.toggleHabit(habit.id, day),
      ),
      HabitKind.count => (
        Icons.add_rounded,
        'Add one to ${habit.name}',
        () => store.addHabitAmount(habit.id, day, 1),
      ),
      HabitKind.timer when !isToday => (
        Icons.edit_calendar_rounded,
        'Log time for ${habit.name}',
        () => HabitDetailSheet.show(context, habit, day: day),
      ),
      HabitKind.timer => (
        running ? Icons.stop_rounded : Icons.play_arrow_rounded,
        running ? 'Stop ${habit.name} timer' : 'Start ${habit.name} timer',
        running ? store.stopHabitTimer : () => store.startHabitTimer(habit.id),
      ),
    };

    final filled = done || running;
    return Semantics(
      button: true,
      toggled: habit.kind == HabitKind.check ? done : null,
      child: Tooltip(
        message: tooltip,
        child: Material(
          shape: CircleBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: tones.accent, width: 2),
          ),
          color: filled ? tones.accent : tones.container.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                icon,
                size: 26,
                color: filled ? tones.onAccent : tones.onContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
