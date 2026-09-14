import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/focus.dart';
import '../main.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

/// Picks how to run the next session.
class FocusStartSheet extends StatefulWidget {
  const FocusStartSheet({required this.block, super.key});

  final Block block;

  static Future<void> show(BuildContext context, Block block) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // This sheet paints its own floating card, so the theme drag handle
      // would hover in the empty space above it.
      showDragHandle: false,
      builder: (_) => FocusStartSheet(block: block),
    );
  }

  @override
  State<FocusStartSheet> createState() => _FocusStartSheetState();
}

class _FocusStartSheetState extends State<FocusStartSheet> {
  FocusKind _kind = FocusKind.pomodoro;
  Duration _work = const Duration(minutes: 25);

  static const _lengths = [
    ('25 min', Duration(minutes: 25)),
    ('50 min', Duration(minutes: 50)),
    ('90 min', Duration(minutes: 90)),
  ];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final target = widget.block.conditions
        .whereType<FocusCondition>()
        .first
        .target;
    final remaining = target - store.focusToday;

    return _SheetShell(
      children: [
        Text(
          widget.block.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          remaining <= Duration.zero
              ? 'You have already put in ${formatDuration(store.focusToday)} '
                  'today. Anything more is credit for the streak.'
              : '${formatDuration(remaining)} left of '
                  '${formatDuration(target)} to unlock these apps.',
          style: TextStyle(color: colors.textMuted, height: 1.35),
        ),
        const SizedBox(height: 18),
        ControlSegmented<FocusKind>(
          value: _kind,
          options: [
            for (final kind in FocusKind.values) (kind, kind.label),
          ],
          onChanged: (value) => setState(() => _kind = value),
        ),
        const SizedBox(height: 14),
        if (_kind == FocusKind.pomodoro) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, length) in _lengths)
                ControlChip(
                  label: label,
                  selected: _work == length,
                  onTap: () => setState(() => _work = length),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Stops itself when the time is up, so the credit does not depend on '
            'you being there to press stop.',
            style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
          ),
        ] else
          Text(
            'Runs until you stop it. Closing the app does not stop it.',
            style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
          ),
        const SizedBox(height: 18),
        _PrimaryButton(
          label: 'Start',
          icon: Icons.play_arrow_rounded,
          onTap: () async {
            final navigator = Navigator.of(context);
            await store.startFocus(
              widget.block.id,
              kind: _kind,
              plannedWork: _work,
            );
            navigator.pop();
          },
        ),
      ],
    );
  }
}

/// Which view the statistics sheet is showing.
enum _StatsView { week, month }

/// Statistics for the focus timer behind one block.
class FocusStatsSheet extends StatefulWidget {
  const FocusStatsSheet({required this.block, super.key});

  final Block block;

  static Future<void> show(BuildContext context, Block block) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // This sheet paints its own floating card, so the theme drag handle
      // would hover in the empty space above it.
      showDragHandle: false,
      builder: (_) => FocusStatsSheet(block: block),
    );
  }

  @override
  State<FocusStatsSheet> createState() => _FocusStatsSheetState();
}

class _FocusStatsSheetState extends State<FocusStatsSheet> {
  _StatsView _view = _StatsView.week;

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    // Statistics are per block, but the daily total that buys unlocks is
    // shared: an hour of study is an hour of study, and splitting the pool
    // would mean running two timers for the same hour.
    final stats = store.focusStats(blockId: block.id);
    final target =
        block.conditions.whereType<FocusCondition>().first.target;

    return _SheetShell(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                block.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Pill('${stats.streakDays} day streak', color: colors.light),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _Stat(
              label: 'Today',
              value: formatDuration(stats.today),
              accent: stats.today >= target ? colors.light : null,
            ),
            _Stat(label: 'This week', value: formatDuration(stats.week)),
            _Stat(label: 'Longest', value: formatDuration(stats.longest)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _view == _StatsView.week ? 'Last 7 days' : 'Last 6 weeks',
                style: TextStyle(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ControlSegmented<_StatsView>(
              compact: true,
              value: _view,
              options: const [
                (_StatsView.week, 'Week'),
                (_StatsView.month, 'Month'),
              ],
              onChanged: (value) => setState(() => _view = value),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_view == _StatsView.week)
          _WeekChart(stats: stats, target: target)
        else
          _MonthHeatmap(stats: stats, target: target),
        const SizedBox(height: 16),
        Text(
          '${stats.sessionCount} session${stats.sessionCount == 1 ? '' : 's'} '
          'recorded. Today buys ${formatDuration(block.blockAgainAfter ?? Duration.zero)} '
          'of the apps this block covers, once ${formatDuration(target)} is done.',
          style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats, required this.target});

  final FocusStats stats;
  final Duration target;

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    // Scale to the target when nothing beats it, so a good day reads as a full
    // bar rather than as whatever happened to be the week's maximum.
    var peak = target;
    for (final (_, focused) in stats.perDay) {
      if (focused > peak) peak = focused;
    }

    return SizedBox(
      height: 116,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (day, focused) in stats.perDay)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      focused == Duration.zero ? '' : formatDuration(focused),
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: peak == Duration.zero
                          ? 4
                          : (72 * focused.inSeconds / peak.inSeconds)
                              .clamp(4, 72)
                              .toDouble(),
                      decoration: BoxDecoration(
                        color: focused >= target
                            ? colors.light
                            : focused == Duration.zero
                                ? colors.cardRaised
                                : colors.medium,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayLetters[day.weekday - 1],
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Six weeks of days, one square each, brighter with more focus.
///
/// A bar chart answers how much happened yesterday. This answers whether the
/// habit is actually happening, which is the question a streak is really about.
/// Columns are weeks and rows are weekdays, so a habit that only happens at
/// weekends shows as two bright rows rather than as noise.
class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({required this.stats, required this.target});

  final FocusStats stats;
  final Duration target;

  static const _rowLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final days = stats.daily;

    // Pad the front so the first column starts on a Monday, otherwise the rows
    // stop meaning weekdays.
    final leading = days.first.$1.weekday - 1;
    final cells = <(DateTime, Duration)?>[
      ...List<(DateTime, Duration)?>.filled(leading, null),
      ...days,
    ];
    final weeks = (cells.length / 7).ceil();

    Color shade(Duration focused) {
      if (focused == Duration.zero) return colors.cardRaised;
      if (target == Duration.zero || focused >= target) return colors.light;

      final share = focused.inSeconds / target.inSeconds;
      return Color.lerp(
        colors.light.withValues(alpha: 0.22),
        colors.light,
        share.clamp(0.0, 1.0),
      )!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                for (final label in _rowLabels)
                  SizedBox(
                    height: 20,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 9, color: colors.textMuted),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  for (var week = 0; week < weeks; week++)
                    Expanded(
                      child: Column(
                        children: [
                          for (var day = 0; day < 7; day++)
                            _HeatCell(
                              cell: (week * 7 + day) < cells.length
                                  ? cells[week * 7 + day]
                                  : null,
                              shade: shade,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('Less', style: TextStyle(fontSize: 10, color: colors.textMuted)),
            const SizedBox(width: 6),
            for (final step in const [0.0, 0.35, 0.7, 1.0])
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: step == 0
                        ? colors.cardRaised
                        : Color.lerp(
                            colors.light.withValues(alpha: 0.22),
                            colors.light,
                            step,
                          ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            const SizedBox(width: 3),
            Text(
              'Target met',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.cell, required this.shade});

  final (DateTime, Duration)? cell;
  final Color Function(Duration) shade;

  @override
  Widget build(BuildContext context) {
    final entry = cell;
    if (entry == null) return const SizedBox(height: 20);

    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message: '${entry.$1.day}/${entry.$1.month}: '
              '${formatDuration(entry.$2)}',
          child: Container(
            decoration: BoxDecoration(
              color: shade(entry.$2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.light.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.light),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: colors.light),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: colors.light,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
