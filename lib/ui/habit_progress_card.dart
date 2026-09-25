import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/habits.dart';
import 'controls.dart';
import 'habit_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// A habit's progress by week, month or year: a bar per day (or per month),
/// the period's goal, what is done, and the share of it.
///
/// Opens on the period holding today, marked as such, and steps back through
/// earlier ones as far as the habit goes.
class HabitProgressCard extends StatefulWidget {
  const HabitProgressCard({required this.stats, super.key});

  final HabitStats stats;

  @override
  State<HabitProgressCard> createState() => _HabitProgressCardState();
}

class _HabitProgressCardState extends State<HabitProgressCard> {
  HabitPeriod _period = HabitPeriod.week;

  /// Any day inside the period shown. Today until someone steps back.
  DateTime? _anchor;

  /// About a sixth shorter than a square card would suggest: tall bars
  /// crowd the figures under them.
  static const _barArea = 112.0;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final habit = stats.habit;
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final tones = HabitTones.of(context, habit.color);

    final summary = HabitPeriodSummary.of(
      stats,
      _period,
      _anchor ?? stats.today,
    );
    final canGoBack = summary.start.isAfter(stats.firstDay);
    final percent = (summary.completion * 100).round();

    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ControlSegmented<HabitPeriod>(
            expand: true,
            value: _period,
            options: [
              for (final period in HabitPeriod.values) (period, period.label),
            ],
            onChanged: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _periodLabel(context, summary),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    if (summary.isCurrent)
                      Pill(
                        'THIS ${_period.label.toUpperCase()}',
                        color: tones.accent,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Previous ${_period.label.toLowerCase()}',
                onPressed: canGoBack
                    ? () => setState(
                        () => _anchor = _period.shift(summary.start, -1),
                      )
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next ${_period.label.toLowerCase()}',
                onPressed: summary.isCurrent
                    ? null
                    : () => setState(() {
                        final next = _period.shift(summary.start, 1);
                        _anchor = next.isAfter(stats.today) ? null : next;
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Bars(
            summary: summary,
            habit: habit,
            accent: tones.accent,
            track: theme.colorScheme.surfaceContainerHighest,
            height: _barArea,
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  value: _amount(habit, summary.goal),
                  label: '${_period.label.toUpperCase()} GOAL',
                ),
              ),
              Expanded(
                child: _Figure(
                  value: _amount(habit, summary.completed),
                  label: 'COMPLETED',
                ),
              ),
              Expanded(
                child: _Figure(
                  value: '$percent%',
                  label: 'COMPLETION',
                  color: percent >= 100 ? tones.accent : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _periodLabel(BuildContext context, HabitPeriodSummary summary) {
    final localizations = MaterialLocalizations.of(context);
    return switch (summary.period) {
      HabitPeriod.week =>
        summary.start.year == summary.lastDay.year
            ? '${localizations.formatShortMonthDay(summary.start)} – '
                  '${localizations.formatShortMonthDay(summary.lastDay)}, '
                  '${summary.start.year}'
            : '${localizations.formatShortDate(summary.start)} – '
                  '${localizations.formatShortDate(summary.lastDay)}',
      HabitPeriod.month => localizations.formatMonthYear(summary.start),
      HabitPeriod.year => localizations.formatYear(summary.start),
    };
  }
}

/// A logged amount in the habit's own terms: days, units, or time.
String _amount(Habit habit, int value) => switch (habit.kind) {
  HabitKind.check => '$value ${value == 1 ? 'day' : 'days'}',
  HabitKind.count => '$value ${habit.unit.isEmpty ? 'times' : habit.unit}',
  HabitKind.timer => formatDuration(Duration(seconds: value)),
};

/// One column of the figures row: a number over its caption.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${label.toLowerCase()}: $value',
      child: ExcludeSemantics(
        child: Column(
          children: [
            // Shrinks rather than wraps: "1,300 pages" on one line reads as a
            // figure, split over two it reads as a sentence.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ControlColors.of(context).textMuted,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bars and their captions.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.summary,
    required this.habit,
    required this.accent,
    required this.track,
    required this.height,
  });

  final HabitPeriodSummary summary;
  final Habit habit;
  final Color accent;
  final Color track;
  final double height;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final localizations = MaterialLocalizations.of(context);
    final bars = summary.bars;
    final today = bars.where((bar) => bar.isCurrent).firstOrNull?.start;

    return LayoutBuilder(
      builder: (context, constraints) {
        final slot = constraints.maxWidth / bars.length;
        // Thin for a month of days, chunkier for a week; never so wide the
        // bars touch.
        final width = math.min(26.0, slot * (bars.length > 12 ? 0.62 : 0.5));

        String caption(HabitBar bar) => switch (summary.period) {
          HabitPeriod.week => _weekdays[bar.start.weekday - 1],
          HabitPeriod.year =>
            slot >= 30
                ? _months[bar.start.month - 1]
                : _months[bar.start.month - 1].substring(0, 1),
          // A month of days is labelled every week, so the eye can count,
          // and today always. A weekly label right beside today's gives way
          // rather than running into it.
          HabitPeriod.month =>
            bar.isCurrent ||
                    (bar.start.day % 7 == 1 &&
                        (today == null ||
                            (bar.start.day - today.day).abs() > 2))
                ? '${bar.start.day}'
                : '',
        };

        String describe(HabitBar bar) {
          final when = summary.period == HabitPeriod.year
              ? localizations.formatMonthYear(bar.start)
              : localizations.formatMediumDate(bar.start);
          if (bar.isFuture) return '$when: still to come';
          return '$when: ${_amount(habit, bar.amount)}'
              '${bar.goal > 0 ? ' of ${_amount(habit, bar.goal)}' : ''}';
        }

        return Column(
          children: [
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final bar in bars)
                    Expanded(
                      child: Tooltip(
                        message: describe(bar),
                        triggerMode: TooltipTriggerMode.tap,
                        child: Semantics(
                          label: describe(bar),
                          selected: bar.isCurrent,
                          child: ExcludeSemantics(
                            child: Center(
                              child: _Bar(
                                bar: bar,
                                width: width,
                                height: height,
                                accent: accent,
                                track: track,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final bar in bars)
                  Expanded(
                    child: Text(
                      caption(bar),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: bar.isCurrent ? accent : colors.textMuted,
                        fontWeight: bar.isCurrent
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A rounded track, filled from the bottom; the current one outlined.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.bar,
    required this.width,
    required this.height,
    required this.accent,
    required this.track,
  });

  final HabitBar bar;
  final double width;
  final double height;
  final Color accent;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width / 2);
    final fill = bar.fill;
    // Anything logged shows at least as a dot at the bottom of the track.
    final filled = fill <= 0 ? 0.0 : math.max(width, height * fill);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Days off, and days before the habit, recede behind the due days.
        color: bar.goal == 0 && !bar.isCurrent
            ? track.withValues(alpha: 0.45)
            : track,
        borderRadius: radius,
      ),
      foregroundDecoration: bar.isCurrent
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: accent, width: width < 10 ? 1.5 : 2),
            )
          : null,
      alignment: Alignment.bottomCenter,
      child: filled == 0
          ? null
          : Container(
              width: width,
              height: filled,
              decoration: BoxDecoration(color: accent, borderRadius: radius),
            ),
    );
  }
}
