import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/descriptions.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'block_editor_sheet.dart';
import 'control_page.dart';
import 'expressive_progress.dart';
import 'focus_stats_sheet.dart';
import 'block_icon.dart';
import 'lock_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class BlocksPage extends StatelessWidget {
  const BlocksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    return ControlPage(
      title: 'Make room',
      eyebrow: 'CONTROL',
      subtitle: 'A little intention. More room for your day.',
      children: [
        if (!store.accessibilityEnabled) ...[
          _Warning(
            text:
                'Blocks are not being enforced. Turn on App blocking to apply '
                'your rules.',
            actionLabel: 'Fix',
            onAction: store.openAccessibilitySettings,
          ),
          const SizedBox(height: 12),
        ],
        if (store.clockTampered) ...[
          _Warning(
            text:
                'The device clock differs from Control\'s protection clock. '
                'Locks continue using elapsed time, not the changed clock.',
          ),
          const SizedBox(height: 12),
        ],
        const _BlocksHero(),
        const SizedBox(height: 24),
        const SectionLabel('Your rules'),
        if (store.blocks.isEmpty)
          ControlCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No blocks yet',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose what needs a little space. '
                  'Add an app, a category, or a website behind a rule.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => BlockEditorSheet.show(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create a block'),
                ),
              ],
            ),
          )
        else
          for (final block in store.blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: BlockCard(block: block),
            ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.medium),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: TextStyle(color: colors.textMuted)),
              ),
            ],
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class BlockCard extends StatelessWidget {
  const BlockCard({required this.block, super.key});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final decision = store.decisionFor(block.id);
    final locked = block.lock.kind != LockKind.none;

    return GestureDetector(
      // The whole card opens the editor. A locked block still opens, and shows
      // only what it will let you change.
      onTap: () => BlockEditorSheet.show(context, existing: block),
      behavior: HitTestBehavior.opaque,
      child: ControlCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlockIcon(block: block),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          block.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Pill(block.mode.name.toUpperCase()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  label: 'Enable ${block.name}',
                  child: Switch(
                    value: block.enabled,
                    onChanged: (value) => _toggle(context, value),
                  ),
                ),
                _LockButton(block: block, locked: locked),
                TextButton.icon(
                  onPressed: () =>
                      BlockEditorSheet.show(context, existing: block),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit rule'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              [
                '${block.apps.length} selected apps',
                if (block.categories.isNotEmpty)
                  'Categories: ${block.categories.join(', ')}',
                if (block.excludedApps.isNotEmpty)
                  '${block.excludedApps.length} category exclusions '
                      '(not exceptions to selected apps or other rules)',
                if (block.blockedDomains.isNotEmpty)
                  '${block.blockedDomains.length} websites',
              ].join(' / '),
              style: TextStyle(color: colors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            _DetailRow(block: block, decision: decision),
            if (ControlStore.hasFocusCondition(block)) ...[
              const SizedBox(height: 10),
              _FocusControls(block: block),
            ],
            for (final condition
                in block.conditions.whereType<PlaceCheckInCondition>()) ...[
              const SizedBox(height: 10),
              _CheckInButton(block: block, condition: condition),
            ],
            if (decision != null && decision.conditionProgress.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final progress in decision.conditionProgress)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_progressLabel(progress)}: '
                        '${(progress.progress.clamp(0.0, 1.0) * 100).round()}%',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      ExpressiveProgress(
                        value: progress.progress,
                        semanticsLabel: _progressLabel(progress),
                        trackColor: colors.cardRaised,
                        color: progress.met ? colors.light : colors.medium,
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _progressLabel(ConditionProgress progress) {
    final condition = block.conditions
        .where((condition) => condition.id == progress.conditionId)
        .firstOrNull;
    return condition == null ? 'Condition' : describeCondition(condition);
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final verdict = await store.setEnabled(block.id, value);

    if (verdict == LockVerdict.allowed) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          verdict == LockVerdict.refused
              ? '${block.name} is locked. It cannot be turned off yet.'
              : '${block.name} needs its password before it can be turned off.',
        ),
      ),
    );
  }
}

class _LockButton extends StatelessWidget {
  const _LockButton({required this.block, required this.locked});

  final Block block;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return IconButton.filledTonal(
      tooltip: locked ? 'Manage lock for ${block.name}' : 'Lock ${block.name}',
      onPressed: () => LockSheet.show(context, block),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: Icon(
        locked ? Icons.lock : Icons.lock_open,
        size: 20,
        color: locked ? colors.medium : colors.textMuted,
      ),
    );
  }
}

/// The focus timer's face on the card, plus the way into its statistics.
///
/// Only on blocks that are actually paid for with focus time: a start button on
/// a schedule block would do nothing and teach people to ignore it. Tapping it
/// opens the timer sheet rather than acting straight away, so a stray tap can
/// never end a session.
class _FocusControls extends StatelessWidget {
  const _FocusControls({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final (icon, label, live) = _state(store);

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonal(
            onPressed: () => FocusTimerSheet.show(context, block),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: live ? colors.light : null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: live ? colors.light : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Focus statistics',
          onPressed: () => FocusStatsSheet.show(context, block),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.insights_rounded),
        ),
      ],
    );
  }

  /// Icon, words, and whether something is counting right now.
  (IconData, String, bool) _state(ControlStore store) {
    final running = store.runningFocus;
    if (running != null && running.blockId == block.id) {
      final length = store.focusLengthOf(running);
      final planned = running.plannedWork;
      final clock = planned == null
          ? formatClock(length)
          : '${formatClock(planned - length < Duration.zero ? Duration.zero : planned - length)} left';
      return running.isPaused
          ? (Icons.pause_rounded, 'Paused  $clock', false)
          : (Icons.timer_outlined, clock, true);
    }

    final pause = store.focusBreak;
    if (pause != null && pause.blockId == block.id) {
      return (
        Icons.self_improvement_rounded,
        'Break  ${formatClock(pause.remainingAt(store.focusNow()))}',
        true,
      );
    }

    final finished = store.lastFinishedFocus;
    if (finished != null && finished.blockId == block.id) {
      return (
        Icons.check_circle_rounded,
        'Done  ${formatDuration(store.focusLengthOf(finished))} banked',
        false,
      );
    }

    if (running != null) {
      return (Icons.play_arrow_rounded, 'Another timer is running', false);
    }

    final target = block.conditions.whereType<FocusCondition>().first.target;
    final done = store.focusToday;
    if (done >= target) return (Icons.play_arrow_rounded, 'Target met', false);
    return (
      Icons.play_arrow_rounded,
      'Start  ${formatDuration(done)} / ${formatDuration(target)}',
      false,
    );
  }
}

/// Check in at a place, while the window is open.
///
/// Only shown when it can actually be used: a button that is dead for
/// twenty-three hours a day teaches people to stop looking at it.
class _CheckInButton extends StatefulWidget {
  const _CheckInButton({required this.block, required this.condition});

  final Block block;
  final PlaceCheckInCondition condition;

  @override
  State<_CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<_CheckInButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);

    final done = store.isCheckedIn(widget.condition);
    final open = store.isCheckInWindowOpen(widget.condition);
    if (!done && !open) return const SizedBox.shrink();

    final accent = done ? colors.light : colors.medium;

    return GestureDetector(
      onTap: done || _busy ? null : _checkIn,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent),
        ),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.place_rounded,
              size: 18,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                done
                    ? 'Checked in at ${widget.condition.zone.name}'
                    : 'Check in at ${widget.condition.zone.name}',
                style: TextStyle(fontWeight: FontWeight.w600, color: accent),
              ),
            ),
            if (_busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkIn() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    final result = await store.checkInPlace(widget.condition.id);
    if (!mounted) return;

    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }
}

/// The strip under the title: what the rule is, and whether it is biting.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.block, required this.decision});

  final Block block;
  final BlockDecision? decision;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final blocking = decision?.blocked ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 20, color: colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _summary(context),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Pill(
            block.enabled ? (blocking ? 'blocked' : 'unlocked') : 'off',
            color: !block.enabled
                ? colors.textMuted
                : blocking
                ? colors.heavy
                : colors.light,
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (block.mode) {
    LimitMode.time => Icons.schedule_rounded,
    LimitMode.condition => Icons.vpn_key_outlined,
    LimitMode.place => Icons.place_outlined,
    LimitMode.device => Icons.settings_remote_rounded,
  };

  String _summary(BuildContext context) => switch (block.mode) {
    LimitMode.time => _scheduleSummary(),
    LimitMode.condition => _conditionSummary(),
    LimitMode.place => block.zone?.name ?? 'No place set',
    LimitMode.device =>
      block.devices.isEmpty
          ? 'No device set'
          : block.devices.map((d) => d.label).join(', '),
  };

  String _scheduleSummary() {
    if (block.schedule.isEmpty) return 'No schedule set';

    final range = block.schedule.first;
    final window = describeWindow(range);
    final extra = block.schedule.length > 1
        ? ' +${block.schedule.length - 1}'
        : '';
    return '$window$extra  ${describeWeekdays(range.weekdays)}';
  }

  String _conditionSummary() {
    if (block.conditions.isEmpty) return 'No habit set';
    return block.conditions.map(describeCondition).join(' + ');
  }
}

/// The day in one compact row: focus time on the left, rules switched on at
/// the right. A summary above the rules, not a banner pushing them down.
class _BlocksHero extends StatelessWidget {
  const _BlocksHero();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimaryContainer;
    final enabled = store.blocks.where((block) => block.enabled).length;

    return HeroCard(
      tone: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time for what matters.',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(store.focusToday)} focused today',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            label: '$enabled rule${enabled == 1 ? '' : 's'} enabled',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.08),
                  borderRadius: Shapes.field,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded, size: 18, color: foreground),
                        const SizedBox(width: 4),
                        Text(
                          '$enabled',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      enabled == 1 ? 'rule on' : 'rules on',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
