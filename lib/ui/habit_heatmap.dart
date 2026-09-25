import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/habits.dart';
import 'habit_widgets.dart';
import 'theme.dart';

/// A habit's whole history as a contribution graph: a column per week, a row
/// per weekday, each day shaded by how much of it got done.
///
/// It reaches back to the day the habit started, scrolls sideways through
/// it, and opens on the latest week. Tapping any day up to today selects it,
/// which is how a missed day gets filled in.
///
/// Painted in one pass rather than built from a widget per day: a habit kept
/// for a few years is a thousand cells. Each cell is still its own semantics
/// node, with its date, its state, and a tap action.
class HabitHeatmap extends StatelessWidget {
  const HabitHeatmap({
    required this.stats,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final HabitStats stats;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  static const _cell = 18.0;
  static const _gap = 4.0;
  static const _pitch = _cell + _gap;
  static const _monthBand = 20.0;

  /// About three years. Older days are still in the log and the stats; the
  /// graph simply stops scrolling there.
  static const _maxWeeks = 160;

  /// A year and a bit: every weekday of the last twelve months has a cell.
  static const _minWeeks = 53;

  static const _weekdayLabels = ['Mon', '', 'Wed', '', 'Fri', '', ''];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final tones = HabitTones.of(context, stats.habit.color);
    final localizations = MaterialLocalizations.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.textMuted,
    );
    final today = stats.today;
    final lastMonday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelColumn = MediaQuery.textScalerOf(context).scale(28);
        final viewport = math.max(
          _pitch,
          constraints.maxWidth - labelColumn - 6,
        );
        final firstMonday = DateTime(
          stats.firstDay.year,
          stats.firstDay.month,
          stats.firstDay.day - stats.firstDay.weekday + 1,
        );
        final sinceStart = _daysBetween(firstMonday, lastMonday) ~/ 7 + 1;
        // Always at least a year, as GitHub shows, so even a habit started
        // this week has a graph to scroll through, with its start marked,
        // rather than three lonely columns that go nowhere.
        final weeks = math
            .max(math.max(sinceStart, _minWeeks), (viewport + _gap) ~/ _pitch)
            .clamp(1, _maxWeeks);
        final start = DateTime(
          lastMonday.year,
          lastMonday.month,
          lastMonday.day - 7 * (weeks - 1),
        );

        final days = <_HeatDay>[];
        for (var i = 0; i < weeks * 7; i++) {
          final day = DateTime(start.year, start.month, start.day + i);
          if (day.isAfter(today)) break;
          final before = day.isBefore(stats.firstDay);
          final progress = stats.progressOn(day);
          days.add(
            _HeatDay(
              day: day,
              column: i ~/ 7,
              row: i % 7,
              level: _level(progress),
              due: stats.habit.isDueOn(day),
              beforeStart: before,
              label: _describe(localizations, day, progress, before),
            ),
          );
        }

        final gridSize = Size(
          weeks * _pitch - _gap,
          _monthBand + 7 * _pitch - _gap,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelColumn,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: _monthBand),
                      for (final label in _weekdayLabels)
                        SizedBox(
                          height: _pitch,
                          child: Align(
                            alignment: const Alignment(-1, -0.4),
                            child: FittedBox(
                              child: Text(label, style: labelStyle),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ScrollFade(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      // Anchored at the end, so the latest week is what opens.
                      reverse: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final day = _dayAt(details.localPosition, days);
                          if (day != null) onSelect(day);
                        },
                        child: CustomPaint(
                          size: gridSize,
                          painter: _HeatmapPainter(
                            days: days,
                            selected: selected,
                            today: today,
                            accent: tones.accent,
                            track: theme.colorScheme.surfaceContainerHighest,
                            ring: theme.colorScheme.onSurface,
                            labelStyle: labelStyle ?? const TextStyle(),
                            direction: Directionality.of(context),
                            onSelect: onSelect,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The selected day on its own line, so large text never squeezes
            // it against the legend.
            Text(
              _selectedLine(localizations),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less', style: labelStyle),
                const SizedBox(width: 4),
                for (var level = 0; level <= 4; level++)
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: _shade(
                        level,
                        tones.accent,
                        theme.colorScheme.surfaceContainerHighest,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const SizedBox(width: 4),
                Text('More', style: labelStyle),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Whole calendar days between two dates, free of daylight-saving hours.
  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  /// Nothing, a start, about half, most, done.
  static int _level(double progress) {
    if (progress >= 1) return 4;
    if (progress <= 0) return 0;
    if (progress < 0.34) return 1;
    if (progress < 0.67) return 2;
    return 3;
  }

  static Color _shade(int level, Color accent, Color track) => switch (level) {
    0 => track,
    1 => Color.lerp(track, accent, 0.3)!,
    2 => Color.lerp(track, accent, 0.55)!,
    3 => Color.lerp(track, accent, 0.78)!,
    _ => accent,
  };

  DateTime? _dayAt(Offset position, List<_HeatDay> days) {
    if (position.dy < _monthBand) return null;
    final column = (position.dx / _pitch).floor();
    final row = ((position.dy - _monthBand) / _pitch).floor();
    for (final day in days) {
      // Days before the habit began are shown, faint, but cannot be picked.
      if (day.column == column && day.row == row && !day.beforeStart) {
        return day.day;
      }
    }
    return null;
  }

  String _amount(int value) => switch (stats.habit.kind) {
    HabitKind.check => value > 0 ? 'done' : 'not done',
    HabitKind.count =>
      '$value of ${stats.habit.target} '
          '${stats.habit.unit.isEmpty ? 'times' : stats.habit.unit}',
    HabitKind.timer => '${value ~/ 60} of ${stats.habit.target} min',
  };

  String _describe(
    MaterialLocalizations localizations,
    DateTime day,
    double progress,
    bool beforeStart,
  ) {
    final date = localizations.formatFullDate(day);
    if (beforeStart) return '$date, before the habit began';
    if (!stats.habit.isDueOn(day) && progress <= 0) return '$date, day off';
    return '$date, ${_amount(stats.amountOn(day))}';
  }

  String _selectedLine(MaterialLocalizations localizations) {
    final day = selected;
    final when = day == stats.today
        ? 'Today'
        : localizations.formatMediumDate(day);
    if (!stats.habit.isDueOn(day) && stats.amountOn(day) <= 0) {
      return '$when: day off';
    }
    return '$when: ${_amount(stats.amountOn(day))}';
  }
}

class _HeatDay {
  const _HeatDay({
    required this.day,
    required this.column,
    required this.row,
    required this.level,
    required this.due,
    required this.beforeStart,
    required this.label,
  });

  final DateTime day;
  final int column;
  final int row;
  final int level;
  final bool due;
  final bool beforeStart;
  final String label;
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.days,
    required this.selected,
    required this.today,
    required this.accent,
    required this.track,
    required this.ring,
    required this.labelStyle,
    required this.direction,
    required this.onSelect,
  });

  final List<_HeatDay> days;
  final DateTime selected;
  final DateTime today;
  final Color accent;
  final Color track;
  final Color ring;
  final TextStyle labelStyle;
  final TextDirection direction;
  final ValueChanged<DateTime> onSelect;

  static const _cell = HabitHeatmap._cell;
  static const _pitch = HabitHeatmap._pitch;
  static const _band = HabitHeatmap._monthBand;
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

  Rect _rectOf(_HeatDay day) => Rect.fromLTWH(
    day.column * _pitch,
    _band + day.row * _pitch,
    _cell,
    _cell,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(4);
    final fill = Paint();

    // Month names over the first column that holds the 1st, as GitHub does,
    // skipping any that would crowd the previous label.
    var lastLabelEnd = double.negativeInfinity;
    for (final day in days) {
      if (day.day.day != 1 && !(day == days.first)) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: day.day.month == 1 || day == days.first
              ? '${_months[day.day.month - 1]} ${day.day.year}'
              : _months[day.day.month - 1],
          style: labelStyle,
        ),
        textDirection: direction,
      )..layout();
      final x = day.column * _pitch;
      if (x < lastLabelEnd + 6) continue;
      painter.paint(canvas, Offset(x, (_band - painter.height) / 2 - 2));
      lastLabelEnd = x + painter.width;
    }

    for (final day in days) {
      final rect = _rectOf(day);
      final Color color;
      if (day.level > 0) {
        color = HabitHeatmap._shade(day.level, accent, track);
      } else if (day.beforeStart) {
        color = track.withValues(alpha: 0.25);
      } else if (!day.due) {
        color = track.withValues(alpha: 0.5);
      } else {
        color = track;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        fill..color = color,
      );
    }

    // Today gets a thin ring of its own; the selection a bolder one.
    for (final day in days) {
      final isSelected = day.day == selected;
      final isToday = day.day == today;
      if (!isSelected && !isToday) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _rectOf(day).inflate(isSelected ? 2 : 0.5),
          const Radius.circular(6),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2 : 1.5
          ..color = isSelected ? ring : (day.level == 4 ? track : accent),
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final day in days)
          CustomPainterSemantics(
            rect: _rectOf(day),
            properties: SemanticsProperties(
              label: day.label,
              textDirection: direction,
              selected: day.day == selected,
              button: !day.beforeStart,
              onTap: day.beforeStart ? null : () => onSelect(day.day),
            ),
          ),
      ];

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.selected != selected ||
      old.today != today ||
      old.accent != accent ||
      old.track != track ||
      old.ring != ring ||
      old.days.length != days.length ||
      !_sameDays(old.days);

  @override
  bool shouldRebuildSemantics(_HeatmapPainter old) => shouldRepaint(old);

  bool _sameDays(List<_HeatDay> other) {
    for (var i = 0; i < days.length; i++) {
      if (days[i].level != other[i].level ||
          days[i].day != other[i].day ||
          days[i].label != other[i].label) {
        return false;
      }
    }
    return true;
  }
}

/// Fades whichever edge still has more to scroll to, so the graph says it
/// scrolls before anyone tries.
class ScrollFade extends StatefulWidget {
  const ScrollFade({required this.child, super.key});

  final Widget child;

  @override
  State<ScrollFade> createState() => _ScrollFadeState();
}

class _ScrollFadeState extends State<ScrollFade> {
  /// More to the left: older weeks.
  bool _older = false;

  /// More to the right: newer weeks, after scrolling back.
  bool _newer = false;

  bool _track(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal) return false;
    // The view is reversed: scrolling forward moves back in time.
    final older = metrics.extentAfter > 0.5;
    final newer = metrics.extentBefore > 0.5;
    if (older != _older || newer != _newer) {
      // Metrics arrive mid-layout; the fade can wait for the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _older = older;
          _newer = newer;
        });
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => _track(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => _track(notification.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [
              _older ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              _newer ? Colors.transparent : Colors.black,
            ],
            stops: const [0, 0.07, 0.93, 1],
          ).createShader(rect),
          child: widget.child,
        ),
      ),
    );
  }
}
