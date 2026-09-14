import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../data/descriptions.dart';
import '../data/focus.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'block_editor_sheet.dart';
import 'control_page.dart';
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
      title: 'blocks',
      children: [
        if (!store.accessibilityEnabled) ...[
          _Warning(
            text: 'Blocks are not being enforced. Turn on App blocking to make '
                'them real.',
            actionLabel: 'Fix',
            onAction: store.openAccessibilitySettings,
          ),
          const SizedBox(height: 12),
        ],
        if (store.clockTampered) ...[
          _Warning(
            text: 'The device clock is behind time Control has already seen. '
                'Locks are being counted from the later time.',
          ),
          const SizedBox(height: 12),
        ],
        if (store.blocks.isEmpty)
          const EmptyState(
            message: 'No blocks yet.\nAdd one to put an app behind a rule.',
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
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: colors.textMuted)),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: block.enabled,
                    onChanged: (value) => _toggle(context, value),
                  ),
                  const SizedBox(width: 4),
                  _LockButton(block: block, locked: locked),
                ],
              ),
            ],
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 6,
                    backgroundColor: colors.cardRaised,
                    valueColor: AlwaysStoppedAnimation(
                      progress.met ? colors.light : colors.medium,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
      ),
    );
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
    return InkWell(
      onTap: () => LockSheet.show(context, block),
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: locked
              ? colors.medium.withValues(alpha: 0.22)
              : colors.cardRaised,
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          size: 17,
          color: locked ? colors.medium : colors.textMuted,
        ),
      ),
    );
  }
}

/// Start/stop for the focus timer, plus the way into its statistics.
///
/// Only on blocks that are actually paid for with focus time: a start button on
/// a schedule block would do nothing and teach people to ignore it.
class _FocusControls extends StatelessWidget {
  const _FocusControls({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final running = store.runningFocus;
    final isThisBlock = running != null && running.blockId == block.id;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _press(context, running, isThisBlock),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isThisBlock
                    ? colors.light.withValues(alpha: 0.16)
                    : colors.cardRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isThisBlock ? colors.light : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isThisBlock
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                    color: isThisBlock ? colors.light : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _label(store, running, isThisBlock),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isThisBlock ? colors.light : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => FocusStatsSheet.show(context, block),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.cardRaised,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.insights_rounded, size: 19, color: colors.textMuted),
          ),
        ),
      ],
    );
  }

  String _label(ControlStore store, FocusSession? running, bool isThisBlock) {
    if (isThisBlock) {
      return formatClock(running!.lengthAt(DateTime.now()));
    }
    if (running != null) return 'Timer busy';

    final target = block.conditions.whereType<FocusCondition>().first.target;
    final done = store.focusToday;
    if (done >= target) return 'Target met';
    return 'Start  ${formatDuration(done)} / ${formatDuration(target)}';
  }

  Future<void> _press(
    BuildContext context,
    FocusSession? running,
    bool isThisBlock,
  ) async {
    final store = StoreScope.of(context);
    if (isThisBlock) {
      await store.stopFocus();
      return;
    }
    if (running != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Another timer is already running. Stop it first.'),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await FocusStartSheet.show(context, block);
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
      child: Row(
        children: [
          Icon(_icon, size: 16, color: colors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _summary(context),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
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
        LimitMode.device => block.devices.isEmpty
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
