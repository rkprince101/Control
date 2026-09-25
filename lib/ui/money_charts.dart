import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/habits.dart' show dateOnly;
import '../data/money.dart';
import 'habit_heatmap.dart' show ScrollFade;
import 'theme.dart';

/// A ring of category slices with a small gap between each, and whatever
/// [child] says in the hole.
class MoneyDonut extends StatelessWidget {
  const MoneyDonut({
    required this.segments,
    required this.track,
    required this.child,
    this.size = 116,
    super.key,
  });

  final List<(Color, double)> segments;
  final Color track;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _DonutPainter(segments: segments, track: track),
      // The hole is about 84 wide; a long amount shrinks rather than
      // spilling onto the ring.
      child: Center(
        child: SizedBox(width: size - 38, child: child),
      ),
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.track});

  final List<(Color, double)> segments;
  final Color track;

  static const _stroke = 16.0;

  /// Radians between slices.
  static const _gap = 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = (Offset.zero & size).center;
    final radius = (size.shortestSide - _stroke) / 2;
    final total = segments.fold(0.0, (sum, segment) => sum + segment.$2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    if (total <= 0) {
      canvas.drawCircle(centre, radius, paint..color = track);
      return;
    }

    final rect = Rect.fromCircle(center: centre, radius: radius);
    final slices = segments.where((segment) => segment.$2 > 0).toList();
    // A lone slice is the whole ring; a gap in it would read as a sliver
    // missing.
    if (slices.length == 1) {
      canvas.drawCircle(centre, radius, paint..color = slices.single.$1);
      return;
    }
    var start = -math.pi / 2;
    for (final (color, value) in slices) {
      final sweep = value / total * (2 * math.pi - _gap * slices.length);
      canvas.drawArc(
        rect,
        start + _gap / 2,
        sweep,
        false,
        paint
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      start += sweep + _gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.track != track || !_sameSegments(old.segments);

  bool _sameSegments(List<(Color, double)> other) {
    if (other.length != segments.length) return false;
    for (var i = 0; i < segments.length; i++) {
      if (other[i] != segments[i]) return false;
    }
    return true;
  }
}

/// Every day's spending as a contribution graph, shaded against the busiest
/// day, with a frame around any day money came in.
///
/// Built like the habit heatmap: painted in one pass, scrolling sideways
/// through at least a year, opening on the latest week, and a semantics node
/// per day. Tapping a day opens what happened on it.
class MoneyHeatmap extends StatelessWidget {
  const MoneyHeatmap({
    required this.book,
    required this.today,
    required this.spendColor,
    required this.incomeColor,
    required this.onSelect,
    super.key,
  });

  final MoneyBook book;
  final DateTime today;
  final Color spendColor;
  final Color incomeColor;
  final ValueChanged<DateTime> onSelect;

  static const _cell = 18.0;
  static const _gap = 4.0;
  static const _pitch = _cell + _gap;
  static const _monthBand = 20.0;
  static const _minWeeks = 53;
  static const _maxWeeks = 160;
  static const _weekdayLabels = ['Mon', '', 'Wed', '', 'Fri', '', ''];

  /// Four steps rather than a continuous ramp, so neighbouring days stay
  /// distinguishable.
  static int _level(double spent, double busiest) {
    if (spent <= 0) return 0;
    return (spent / busiest * 4).ceil().clamp(1, 4);
  }

  static Color _shade(int level, Color accent, Color track) => switch (level) {
    0 => track,
    1 => Color.lerp(track, accent, 0.3)!,
    2 => Color.lerp(track, accent, 0.55)!,
    3 => Color.lerp(track, accent, 0.78)!,
    _ => accent,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final localizations = MaterialLocalizations.of(context);
    final track = theme.colorScheme.surfaceContainerHighest;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.textMuted,
    );
    final day0 = dateOnly(today);
    final lastMonday = DateTime(
      day0.year,
      day0.month,
      day0.day - day0.weekday + 1,
    );
    final busiest = book.busiestDaySpend > 0 ? book.busiestDaySpend : 1.0;
    final oldest = book.entries.isEmpty ? day0 : book.entries.last.date;

    return LayoutBuilder(
      builder: (context, constraints) {
        final labelColumn = MediaQuery.textScalerOf(context).scale(28);
        final viewport = math.max(
          _pitch,
          constraints.maxWidth - labelColumn - 6,
        );
        final sinceOldest =
            DateTime.utc(lastMonday.year, lastMonday.month, lastMonday.day)
                    .difference(
                      DateTime.utc(oldest.year, oldest.month, oldest.day),
                    )
                    .inDays ~/
                7 +
            1;
        final weeks = math
            .max(math.max(sinceOldest, _minWeeks), (viewport + _gap) ~/ _pitch)
            .clamp(1, _maxWeeks);
        final start = DateTime(
          lastMonday.year,
          lastMonday.month,
          lastMonday.day - 7 * (weeks - 1),
        );

        final days = <_MoneyDay>[];
        for (var i = 0; i < weeks * 7; i++) {
          final day = DateTime(start.year, start.month, start.day + i);
          if (day.isAfter(day0)) break;
          final spent = book.expenseOn(day);
          final earned = book.incomeOn(day);
          days.add(
            _MoneyDay(
              day: day,
              column: i ~/ 7,
              row: i % 7,
              level: _level(spent, busiest),
              earned: earned > 0,
              label: [
                localizations.formatFullDate(day),
                spent > 0 ? '${book.format(spent)} spent' : 'no spending',
                if (earned > 0) '${book.format(earned)} in',
              ].join(', '),
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
                      reverse: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final day = _dayAt(details.localPosition, days);
                          if (day != null) onSelect(day);
                        },
                        child: CustomPaint(
                          size: gridSize,
                          painter: _MoneyHeatmapPainter(
                            days: days,
                            today: day0,
                            spend: spendColor,
                            income: incomeColor,
                            track: track,
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
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: track,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: incomeColor, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('Money came in', style: labelStyle),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Less', style: labelStyle),
                    const SizedBox(width: 4),
                    for (var level = 0; level <= 4; level++)
                      Container(
                        width: 11,
                        height: 11,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: _shade(level, spendColor, track),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text('More', style: labelStyle),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  DateTime? _dayAt(Offset position, List<_MoneyDay> days) {
    if (position.dy < _monthBand) return null;
    final column = (position.dx / _pitch).floor();
    final row = ((position.dy - _monthBand) / _pitch).floor();
    for (final day in days) {
      if (day.column == column && day.row == row) return day.day;
    }
    return null;
  }
}

class _MoneyDay {
  const _MoneyDay({
    required this.day,
    required this.column,
    required this.row,
    required this.level,
    required this.earned,
    required this.label,
  });

  final DateTime day;
  final int column;
  final int row;
  final int level;
  final bool earned;
  final String label;
}

class _MoneyHeatmapPainter extends CustomPainter {
  _MoneyHeatmapPainter({
    required this.days,
    required this.today,
    required this.spend,
    required this.income,
    required this.track,
    required this.labelStyle,
    required this.direction,
    required this.onSelect,
  });

  final List<_MoneyDay> days;
  final DateTime today;
  final Color spend;
  final Color income;
  final Color track;
  final TextStyle labelStyle;
  final TextDirection direction;
  final ValueChanged<DateTime> onSelect;

  static const _cell = MoneyHeatmap._cell;
  static const _pitch = MoneyHeatmap._pitch;
  static const _band = MoneyHeatmap._monthBand;
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

  Rect _rectOf(_MoneyDay day) => Rect.fromLTWH(
    day.column * _pitch,
    _band + day.row * _pitch,
    _cell,
    _cell,
  );

  @override
  void paint(Canvas canvas, Size size) {
    var lastLabelEnd = double.negativeInfinity;
    for (final day in days) {
      if (day.day.day != 1 && day != days.first) continue;
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

    final fill = Paint();
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = income;
    for (final day in days) {
      final rect = RRect.fromRectAndRadius(
        _rectOf(day),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        rect,
        fill..color = MoneyHeatmap._shade(day.level, spend, track),
      );
      if (day.earned) canvas.drawRRect(rect.deflate(1), frame);
      if (day.day == today) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            _rectOf(day).inflate(2),
            const Radius.circular(6),
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = labelStyle.color ?? spend,
        );
      }
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
              button: true,
              onTap: () => onSelect(day.day),
            ),
          ),
      ];

  @override
  bool shouldRepaint(_MoneyHeatmapPainter old) =>
      old.today != today ||
      old.spend != spend ||
      old.income != income ||
      old.track != track ||
      old.days.length != days.length ||
      !_sameDays(old.days);

  @override
  bool shouldRebuildSemantics(_MoneyHeatmapPainter old) => shouldRepaint(old);

  bool _sameDays(List<_MoneyDay> other) {
    for (var i = 0; i < days.length; i++) {
      if (days[i].level != other[i].level ||
          days[i].earned != other[i].earned ||
          days[i].day != other[i].day ||
          days[i].label != other[i].label) {
        return false;
      }
    }
    return true;
  }
}
