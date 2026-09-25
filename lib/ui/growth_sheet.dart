import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/habits.dart';
import '../main.dart';
import 'expressive_progress.dart';
import 'growth_art.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// The garden at a glance, for the Habits page: the plant, its stage, and how
/// close the next one is. Tapping opens [GrowthSheet].
///
/// When the habits carry it into a new stage, it celebrates once: a burst of
/// leaves, a buzz, and a "New stage" tag until the sheet is opened.
class GrowthCard extends StatefulWidget {
  const GrowthCard({super.key});

  @override
  State<GrowthCard> createState() => _GrowthCardState();
}

class _GrowthCardState extends State<GrowthCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _celebrating = false;

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _celebrate(int stage) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = StoreScope.of(context);
      setState(() => _celebrating = true);
      if (!MediaQuery.disableAnimationsOf(context)) _burst.forward(from: 0);
      unawaited(HapticFeedback.mediumImpact());
      unawaited(store.markGrowthSeen(stage));
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final growth = store.habitGrowth;
    final next = growth.next;

    if (growth.stage > store.growthStageSeen && !_celebrating) {
      _celebrate(growth.stage);
    }

    final summary = next == null
        ? '${growth.points} check-ins. The top of the ladder'
        : '${growth.points} check-ins, ${growth.toNext} more to ${next.name}';

    return Semantics(
      button: true,
      label: 'Your growth: ${growth.rank.name}. $summary. Opens the details.',
      child: ExcludeSemantics(
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: Shapes.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              setState(() => _celebrating = false);
              GrowthSheet.show(context);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GrowthArt(
                            stage: growth.stage,
                            growth: growth.withinStage,
                            size: 76,
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _burst,
                            builder: (context, _) => GrowthBurst(
                              progress: _burst.value,
                              color: colors.light,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              growth.rank.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_celebrating)
                              Pill('NEW STAGE', color: colors.light)
                            else
                              Pill(
                                'STAGE ${growth.stage + 1} OF '
                                '${HabitRank.ladder.length}',
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ExpressiveProgress(
                          value: growth.withinStage,
                          height: 16,
                          color: colors.light,
                          trackColor: colors.cardRaised,
                          semanticsLabel: 'Growth towards the next stage',
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The garden in full: the plant large, the pace, the whole journey from seed
/// to old growth, and how it grows.
class GrowthSheet extends StatelessWidget {
  const GrowthSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => const GrowthSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final growth = store.habitGrowth;
    final next = growth.next;

    return SheetScaffold(
      heightFactor: 0.92,
      title: 'Your growth',
      leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _Scene(growth: growth),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    growth.rank.name,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ),
              Pill('STAGE ${growth.stage + 1} OF ${HabitRank.ladder.length}'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            growth.rank.blurb,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          ExpressiveProgress(
            value: growth.withinStage,
            color: colors.light,
            trackColor: colors.cardRaised,
            semanticsLabel: next == null
                ? 'Top stage reached'
                : 'Growth towards ${next.name}',
          ),
          const SizedBox(height: 8),
          Text(
            next == null
                ? 'The top of the ladder. Every check-in from here is another '
                      'ring in the old wood.'
                : '${growth.toNext} more check-in'
                      '${growth.toNext == 1 ? '' : 's'} to ${next.name}.',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 16),
          _PaceCard(growth: growth),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Tile(value: '${growth.lastWeek}', label: 'Last 7 days'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  value: '${growth.lastMonth}',
                  label: 'Last 30 days',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(value: '${growth.points}', label: 'All time'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionLabel('The journey'),
          ControlCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < HabitRank.ladder.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 84),
                  _StageRow(index: i, growth: growth),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('How it grows'),
          const ControlCard(
            child: Column(
              children: [
                _Rule(
                  icon: Icons.check_circle_outline_rounded,
                  text:
                      'Every habit you finish on a day is one check-in. Three '
                      'habits done today are three.',
                ),
                SizedBox(height: 14),
                _Rule(
                  icon: Icons.eco_outlined,
                  text:
                      'The plant grows a little with each one, not only when '
                      'it reaches a new stage.',
                ),
                SizedBox(height: 14),
                _Rule(
                  icon: Icons.spa_outlined,
                  text:
                      'A missed day never takes anything away. Nothing wilts '
                      'here; it just waits for you.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The plant, large, with a sky and a sun behind it.
class _Scene extends StatelessWidget {
  const _Scene({required this.growth});

  final HabitGrowth growth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${growth.rank.name}, drawn',
      child: ExcludeSemantics(
        child: Container(
          height: 236,
          decoration: BoxDecoration(
            borderRadius: Shapes.card,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [scheme.secondaryContainer, scheme.surfaceContainerLow],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                right: 28,
                top: 24,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GrowthArt(
                  stage: growth.stage,
                  growth: growth.withinStage,
                  size: 216,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// When the next stage comes, at the recent pace.
class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.growth});

  final HabitGrowth growth;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final next = growth.next;
    final days = growth.daysToNext;
    final pace = growth.pacePerDay;
    final paceText = pace >= 10
        ? pace.round().toString()
        : pace.toStringAsFixed(1);

    final text = next == null
        ? 'You have climbed the whole ladder. The garden keeps every day you '
              'add to it.'
        : days == null
        ? 'No check-ins in the last two weeks. Finish one habit today and it '
              'starts growing again.'
        : days <= 1
        ? '${next.name} by tomorrow, at your pace of $paceText check-ins a '
              'day over the last two weeks.'
        : 'About $days days to ${next.name}, at your pace of $paceText '
              'check-ins a day over the last two weeks.';

    return ControlCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            days == null && next != null
                ? Icons.water_drop_outlined
                : Icons.trending_up_rounded,
            color: colors.light,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value check-ins',
      child: ExcludeSemantics(
        child: ControlCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              FittedBox(child: Text(value, style: theme.textTheme.titleLarge)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ControlColors.of(context).textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One stage of the journey: its picture, what it means, and when it came or
/// how far off it is.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.index, required this.growth});

  final int index;
  final HabitGrowth growth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final rank = HabitRank.ladder[index];
    final reached = index <= growth.stage;
    final current = index == growth.stage;
    final on = growth.reachedOn[index];

    final status = current
        ? 'Growing now'
        : reached
        ? (on == null
              ? 'Reached'
              : 'Reached ${MaterialLocalizations.of(context).formatMediumDate(on)}')
        : '${rank.threshold - growth.points} to go';

    return Semantics(
      label:
          '${rank.name}, ${rank.threshold} check-ins. ${rank.blurb} $status.',
      selected: current,
      child: ExcludeSemantics(
        child: Container(
          color: current
              ? scheme.secondaryContainer.withValues(alpha: 0.5)
              : null,
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: reached
                      ? scheme.secondaryContainer
                      : colors.cardRaised,
                  shape: BoxShape.circle,
                ),
                child: GrowthArt(
                  stage: index,
                  growth: current ? growth.withinStage : 1,
                  size: 56,
                  animate: current,
                  locked: !reached,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rank.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: reached ? null : colors.textMuted,
                        fontWeight: current ? FontWeight.w800 : null,
                      ),
                    ),
                    Text(
                      '${rank.threshold} check-ins. ${rank.blurb}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: current
                            ? colors.light
                            : reached
                            ? null
                            : colors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (reached && !current)
                Icon(Icons.check_circle_rounded, color: colors.light, size: 20)
              else if (!reached)
                Icon(
                  Icons.lock_outline_rounded,
                  color: colors.textMuted,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: ControlColors.of(context).light),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
    ],
  );
}
