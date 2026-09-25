import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/habits.dart';

/// A habit's colour, resolved for the current theme.
///
/// The fidelity variant keeps each seed's own colourfulness. Tonal spot, which
/// the app scheme uses, flattens every seed to one chroma: fine for a single
/// accent, but it turned grey and sand into two more blues. The seeds are
/// already muted, so this keeps them distinct without letting them shout.
@immutable
class HabitTones {
  const HabitTones({
    required this.accent,
    required this.onAccent,
    required this.container,
    required this.onContainer,
  });

  final Color accent;
  final Color onAccent;
  final Color container;
  final Color onContainer;

  static final _cache = <(int, Brightness), HabitTones>{};

  static HabitTones of(BuildContext context, int seed) {
    final brightness = Theme.of(context).brightness;
    return _cache.putIfAbsent((seed, brightness), () {
      final scheme = ColorScheme.fromSeed(
        seedColor: Color(seed),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      return HabitTones(
        accent: scheme.primary,
        onAccent: scheme.onPrimary,
        container: scheme.primaryContainer,
        onContainer: scheme.onPrimaryContainer,
      );
    });
  }
}

/// The glyph a kind of habit falls back to when it has no icon of its own.
IconData habitKindIcon(HabitKind kind) => switch (kind) {
  HabitKind.check => Icons.check_rounded,
  HabitKind.count => Icons.add_rounded,
  HabitKind.timer => Icons.timer_outlined,
};

/// The tile at the left of a habit card, in the habit's own colour.
class HabitIconTile extends StatelessWidget {
  const HabitIconTile({required this.habit, this.size = 52, super.key});

  final Habit habit;
  final double size;

  @override
  Widget build(BuildContext context) => HabitIconSwatch(
    asset: habit.iconAsset,
    color: habit.color,
    kind: habit.kind,
    size: size,
  );
}

/// [HabitIconTile] from loose parts, for the editor's live preview.
class HabitIconSwatch extends StatelessWidget {
  const HabitIconSwatch({
    required this.asset,
    required this.color,
    required this.kind,
    this.size = 52,
    super.key,
  });

  final String? asset;
  final int color;
  final HabitKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tones = HabitTones.of(context, color);
    final asset = this.asset;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tones.container,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: asset == null
          ? FittedBox(
              child: Icon(habitKindIcon(kind), color: tones.onContainer),
            )
          : SvgPicture.asset(
              asset,
              colorFilter: ColorFilter.mode(tones.onContainer, BlendMode.srcIn),
              placeholderBuilder: (_) => const SizedBox.shrink(),
            ),
    );
  }
}

/// Weeks of days as tiles, newest week on the right: the grid that makes a
/// streak something you can see.
///
/// Painted rather than built from a hundred containers, because every card on
/// the page carries one.
class HabitGrid extends StatelessWidget {
  const HabitGrid({
    required this.stats,
    this.cell = 12,
    this.gap = 3,
    super.key,
  });

  final HabitStats stats;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final tones = HabitTones.of(context, stats.habit.color);
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final weeks = math.max(1, ((width + gap) / (cell + gap)).floor());
        final size = (width - gap * (weeks - 1)) / weeks;
        final today = stats.today;
        // Monday of the current week, then back to the first column.
        final start = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1) - (weeks - 1) * 7,
        );

        final days = <_GridDay>[];
        var due = 0;
        var done = 0;
        for (var i = 0; i < weeks * 7; i++) {
          final day = DateTime(start.year, start.month, start.day + i);
          if (day.isAfter(today)) break;
          final isDue =
              stats.habit.isDueOn(day) && !day.isBefore(stats.firstDay);
          final isDone = stats.isDoneOn(day);
          if (isDue && (day != today || isDone)) {
            due++;
            if (isDone) done++;
          }
          days.add(
            _GridDay(
              column: i ~/ 7,
              row: i % 7,
              progress: stats.progressOn(day),
              due: isDue,
              today: day == today,
            ),
          );
        }

        return Semantics(
          label:
              '${stats.habit.name}, last $weeks weeks: '
              '$done of $due due days done',
          child: ExcludeSemantics(
            child: CustomPaint(
              size: Size(width, size * 7 + gap * 6),
              painter: _GridPainter(
                days: days,
                cell: size,
                gap: gap,
                accent: tones.accent,
                track: scheme.surfaceContainerHighest,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridDay {
  const _GridDay({
    required this.column,
    required this.row,
    required this.progress,
    required this.due,
    required this.today,
  });

  final int column;
  final int row;
  final double progress;
  final bool due;
  final bool today;
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.days,
    required this.cell,
    required this.gap,
    required this.accent,
    required this.track,
  });

  final List<_GridDay> days;
  final double cell;
  final double gap;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(math.min(4, cell * 0.3));
    final fill = Paint();
    for (final day in days) {
      final rect = Rect.fromLTWH(
        day.column * (cell + gap),
        day.row * (cell + gap),
        cell,
        cell,
      );
      final Color color;
      if (day.progress >= 1) {
        color = accent;
      } else if (day.progress > 0) {
        color = Color.lerp(track, accent, 0.25 + day.progress * 0.45)!;
      } else {
        // Days off recede, so the eye reads the due days as the grid.
        color = day.due ? track : track.withValues(alpha: 0.45);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        fill..color = color,
      );
      if (day.today) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.75), radius),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = day.progress >= 1 ? track : accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cell != cell ||
      old.gap != gap ||
      old.accent != accent ||
      old.track != track ||
      old.days.length != days.length ||
      !_sameDays(old.days, days);

  static bool _sameDays(List<_GridDay> a, List<_GridDay> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].progress != b[i].progress ||
          a[i].due != b[i].due ||
          a[i].today != b[i].today) {
        return false;
      }
    }
    return true;
  }
}
