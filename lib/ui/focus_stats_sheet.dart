import 'dart:async';
import 'dart:math' as math;

import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/focus.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'controls.dart';
import 'expressive_progress.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// The focus timer for one block: pick a session, watch it run, bank it, take
/// the break.
///
/// One sheet for the whole cycle rather than one per step, so starting a
/// session leads straight into watching it, and finishing one leads straight
/// into the break. What it shows follows the store, so a pomodoro that ends
/// while the sheet is open turns into the done view on its own.
class FocusTimerSheet extends StatefulWidget {
  const FocusTimerSheet({required this.block, super.key});

  final Block block;

  static Future<void> show(BuildContext context, Block block) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => FocusTimerSheet(block: block),
    );
  }

  @override
  State<FocusTimerSheet> createState() => _FocusTimerSheetState();
}

class _FocusTimerSheetState extends State<FocusTimerSheet> {
  FocusKind _kind = FocusKind.pomodoro;
  Duration _work = const Duration(minutes: 25);

  static const _lengths = [
    ('15 min', Duration(minutes: 15)),
    ('25 min', Duration(minutes: 25)),
    ('50 min', Duration(minutes: 50)),
    ('90 min', Duration(minutes: 90)),
  ];

  String get _blockId => widget.block.id;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final running = store.runningFocus;
    final pause = store.focusBreak;
    final finished = store.lastFinishedFocus;

    final Widget body;
    if (running != null && running.blockId == _blockId) {
      body = _running(store, running);
    } else if (pause != null && pause.blockId == _blockId) {
      body = _break(store, pause);
    } else if (finished != null && finished.blockId == _blockId) {
      body = _done(store, finished);
    } else {
      body = _start(store, running);
    }

    return SheetScaffold(
      title: 'Focus',
      leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
      trailing: SheetAction(
        'Stats',
        onPressed: () => FocusStatsSheet.show(context, widget.block),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
            ),
          ),
        ),
      ),
    );
  }

  // Start ---------------------------------------------------------------------

  Widget _start(ControlStore store, FocusSession? otherRunning) {
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final breakOver = store.breakOverFor == _blockId;

    return _StartPanel(
      children: [
        Text(widget.block.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (breakOver) ...[
          _Banner(
            icon: Icons.self_improvement_rounded,
            text: 'Break is over. Ready for the next one?',
          ),
          const SizedBox(height: 12),
        ],
        if (otherRunning != null) ...[
          _Banner(
            icon: Icons.info_outline_rounded,
            text:
                'A timer is running for '
                '${store.blockById(otherRunning.blockId)?.name ?? 'another block'}. '
                'Starting here finishes it and keeps its minutes.',
          ),
          const SizedBox(height: 12),
        ],
        _GoalCard(block: widget.block),
        const SizedBox(height: 20),
        ControlSegmented<FocusKind>(
          value: _kind,
          options: [for (final kind in FocusKind.values) (kind, kind.label)],
          onChanged: (kind) => setState(() => _kind = kind),
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
          _Hint(
            'Stops itself at ${formatDuration(_work)}, so the credit does not '
            'depend on you being there. Then a 5 minute break, and 15 after '
            'every fourth.',
          ),
        ] else
          const _Hint(
            'Counts up until you finish it. Closing the app does not stop it.',
          ),
        const SizedBox(height: 20),
        _BigButton(
          label: 'Start',
          icon: Icons.play_arrow_rounded,
          onPressed: () {
            if (breakOver) store.dismissFocusResult();
            unawaited(
              store.startFocus(_blockId, kind: _kind, plannedWork: _work),
            );
          },
        ),
        if (store.pomodorosToday > 0) ...[
          const SizedBox(height: 12),
          Text(
            '${store.pomodorosToday} pomodoro'
            '${store.pomodorosToday == 1 ? '' : 's'} finished today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  // Running -------------------------------------------------------------------

  Widget _running(ControlStore store, FocusSession running) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final now = store.focusNow();
    final length = store.focusLengthOf(running);
    final remaining = running.plannedWork == null
        ? null
        : running.plannedWork! - length;
    final paused = running.isPaused;

    final centre = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatClock(remaining != null ? _positive(remaining) : length),
          style: theme.textTheme.displayMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            color: paused ? colors.textMuted : null,
          ),
        ),
        Text(
          paused
              ? 'Paused'
              : remaining != null
              ? 'left'
              : 'focused',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.textMuted),
        ),
      ],
    );

    return Column(
      key: const ValueKey('running'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.block.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          running.kind == FocusKind.pomodoro
              ? 'Pomodoro, ${formatDuration(running.plannedWork!)}'
              : 'Stopwatch',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 20),
        Center(
          child: _TimerFace(
            semanticsLabel: remaining != null
                ? '${formatClock(_positive(remaining))} left'
                : '${formatClock(length)} focused',
            // A pomodoro has a finish line, so its face fills towards it. A
            // stopwatch has none: a filling ring would promise an end that is
            // not there, so it gets a dial whose seconds come round again.
            child: remaining != null
                ? _WavyRing(
                    progress:
                        length.inMilliseconds /
                        running.plannedWork!.inMilliseconds,
                    color: paused ? colors.textMuted : scheme.primary,
                    track: colors.cardRaised,
                    moving: !paused,
                    child: centre,
                  )
                : _StopwatchDial(
                    elapsed: length,
                    running: !paused,
                    color: paused ? colors.textMuted : scheme.primary,
                    track: colors.cardRaised,
                    child: centre,
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: _buttonStyle,
                onPressed: paused ? store.resumeFocus : store.pauseFocus,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                label: Text(paused ? 'Resume' : 'Pause'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: _buttonStyle,
                onPressed: store.stopFocus,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Finish'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Hint(
          paused
              ? 'Paused time is not counted. The session waits for you, even '
                    'with the app closed.'
              : remaining != null
              ? 'Finishing early keeps the ${formatDuration(length)} so far. '
                    'Ends by itself at ${TimeOfDay.fromDateTime(now.add(_positive(remaining))).format(context)}.'
              : 'Keeps counting with the app closed. The clock is in your '
                    'notifications too.',
          center: true,
        ),
        if (!store.notifications.enabled) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.notifications_off_outlined,
            text:
                'Notifications are off, so the end cannot be announced '
                'outside the app. Turn them on in Settings.',
          ),
        ],
        const SizedBox(height: 20),
        _GoalCard(block: widget.block),
      ],
    );
  }

  // Done ----------------------------------------------------------------------

  Widget _done(ControlStore store, FocusSession finished) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final banked = store.focusLengthOf(finished);
    final completed =
        finished.kind == FocusKind.pomodoro &&
        finished.isComplete(finished.endedAt ?? DateTime.now());

    return Column(
      key: const ValueKey('done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_rounded, size: 56, color: colors.light),
        const SizedBox(height: 12),
        Text(
          completed ? 'Pomodoro done' : 'Session finished',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          '${formatDuration(banked)} banked for ${widget.block.name}.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 20),
        _GoalCard(block: widget.block),
        const SizedBox(height: 20),
        if (finished.kind == FocusKind.pomodoro) ...[
          _BigButton(
            label: 'Take a ${formatDuration(store.nextBreakLength)} break',
            icon: Icons.self_improvement_rounded,
            onPressed: store.startBreak,
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            style: _buttonStyle,
            onPressed: () => store.startFocus(
              _blockId,
              kind: FocusKind.pomodoro,
              plannedWork: finished.plannedWork,
            ),
            icon: const Icon(Icons.skip_next_rounded),
            label: const Text('Skip the break, go again'),
          ),
        ] else
          _BigButton(
            label: 'Start another',
            icon: Icons.replay_rounded,
            onPressed: store.dismissFocusResult,
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () {
            store.dismissFocusResult();
            Navigator.pop(context);
          },
          child: const Text('Done for now'),
        ),
      ],
    );
  }

  // Break ---------------------------------------------------------------------

  Widget _break(ControlStore store, FocusBreak pause) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = ControlColors.of(context);
    final left = pause.remainingAt(store.focusNow());
    final progress =
        1 - left.inMilliseconds / math.max(1, pause.length.inMilliseconds);

    return Column(
      key: const ValueKey('break'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Break',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Stand up, look away from the screen, drink some water.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textMuted),
        ),
        const SizedBox(height: 20),
        Center(
          child: _TimerFace(
            semanticsLabel: '${formatClock(left)} of break left',
            child: _WavyRing(
              progress: progress,
              color: scheme.tertiary,
              track: colors.cardRaised,
              moving: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatClock(left),
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'break',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          style: _buttonStyle,
          onPressed: store.skipBreak,
          icon: const Icon(Icons.fast_forward_rounded),
          label: const Text('Skip break'),
        ),
      ],
    );
  }

  static Duration _positive(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;
}

Duration _target(Block block) =>
    block.conditions.whereType<FocusCondition>().firstOrNull?.target ??
    Duration.zero;

final _buttonStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, 56),
  padding: const EdgeInsets.symmetric(horizontal: 16),
);

class _StartPanel extends StatelessWidget {
  const _StartPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('start'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: _buttonStyle,
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: Shapes.field,
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onTertiaryContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's total against the goal that unlocks this block's apps.
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final target = _target(block);
    final today = store.focusToday;
    final left = target - today;

    return ControlCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wraps rather than squeezes: at large text the figures drop under
          // the label instead of pushing off the card.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                'Today, across all blocks',
                style: theme.textTheme.labelLarge,
              ),
              Text(
                '${formatDuration(today)} / ${formatDuration(target)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ExpressiveProgress(
            value: target <= Duration.zero
                ? 1.0
                : (today.inMicroseconds / target.inMicroseconds).clamp(
                    0.0,
                    1.0,
                  ),
            trackColor: colors.cardRaised,
            semanticsLabel:
                'Daily focus goal, ${formatDuration(today)} of '
                '${formatDuration(target)}',
          ),
          const SizedBox(height: 8),
          Text(
            left <= Duration.zero
                ? 'Goal met. These apps are unlocked'
                      '${block.blockAgainAfter == null ? ' until midnight' : ' for ${formatDuration(block.blockAgainAfter!)}'}.'
                : '${formatDuration(left)} more to unlock these apps.',
            style: TextStyle(color: colors.textMuted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Sizes a timer face to the sheet. The face draws itself and holds the clock.
class _TimerFace extends StatelessWidget {
  const _TimerFace({required this.semanticsLabel, required this.child});

  final String semanticsLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final size = math.min(260.0, math.max(180.0, width - 120));
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(dimension: size, child: child),
      ),
    );
  }
}

/// The clock in the middle of a face, kept clear of the rim.
class _FaceCentre extends StatelessWidget {
  const _FaceCentre({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: FittedBox(child: child),
    ),
  );
}

/// The pomodoro and break face: the app's wavy indicator, bent into a circle.
///
/// The value arrives once a second; it eases across each second so the arc
/// sweeps rather than ticks, while the wave travels along it at the speed set
/// in Settings.
class _WavyRing extends StatelessWidget {
  const _WavyRing({
    required this.progress,
    required this.color,
    required this.track,
    required this.moving,
    required this.child,
  });

  final double progress;
  final Color color;
  final Color track;

  /// False while paused: the wave holds still with the clock.
  final bool moving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      builder: (context, animated, centre) => ExpressiveCircularProgress(
        value: animated,
        color: color,
        trackColor: track,
        // Material's proportions for a large ring: a slim stroke and a gentle
        // wave, so it reads as a wave rather than a scribble.
        strokeWidth: 10,
        amplitude: 2.6,
        wavelength: 44,
        animate: moving,
        child: centre,
      ),
      child: _FaceCentre(child: child),
    );
  }
}

/// The stopwatch face: sixty second ticks round the rim.
///
/// The ticks light up as the minute passes and start again at the top of the
/// next, the newest brightest, with a hand sweeping smoothly between them. It
/// shows time moving without pretending there is an end. Paused, it holds its
/// place in a muted tone. With motion off in Settings, or reduced motion on
/// the device, the hand does not sweep and the ticks step once a second.
class _StopwatchDial extends StatefulWidget {
  const _StopwatchDial({
    required this.elapsed,
    required this.running,
    required this.color,
    required this.track,
    required this.child,
  });

  final Duration elapsed;
  final bool running;
  final Color color;
  final Color track;
  final Widget child;

  @override
  State<_StopwatchDial> createState() => _StopwatchDialState();
}

class _StopwatchDialState extends State<_StopwatchDial>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  /// The last whole-second reading, and when it arrived, so the hand can
  /// sweep across the second before the next one.
  late Duration _base = widget.elapsed;
  DateTime _baseAt = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(_StopwatchDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.elapsed != widget.elapsed) {
      _base = widget.elapsed;
      _baseAt = DateTime.now();
    }
    _configure();
  }

  void _configure() {
    final sweep =
        widget.running &&
        WaveMotionScope.of(context) != WaveMotion.off &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (sweep && !_ticker.isActive) {
      _ticker.start();
    } else if (!sweep && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var shown = widget.elapsed;
    if (_ticker.isActive) {
      // Never run ahead of the next real reading by more than a second.
      final since = DateTime.now().difference(_baseAt);
      shown =
          _base +
          (since > const Duration(milliseconds: 999)
              ? const Duration(milliseconds: 999)
              : since);
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DialPainter(
          seconds: (shown.inMilliseconds % 60000) / 1000,
          sweeping: _ticker.isActive,
          color: widget.color,
          track: widget.track,
        ),
        child: _FaceCentre(child: widget.child),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.seconds,
    required this.sweeping,
    required this.color,
    required this.track,
  });

  /// Into the current minute, 0 to just under 60, with a fraction.
  final double seconds;
  final bool sweeping;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final outer = math.min(size.width, size.height) / 2 - 3;
    if (outer <= 20) return;
    final current = seconds.floor() % 60;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < 60; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / 60;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final major = i % 5 == 0;
      final isCurrent = i == current;
      final lit = i <= current;
      final length = isCurrent ? 20.0 : (major ? 14.0 : 9.0);
      // The trail fades behind the newest tick, so the eye finds "now".
      final Color tick;
      if (!lit) {
        tick = track;
      } else if (isCurrent) {
        tick = color;
      } else {
        tick = color.withValues(alpha: 0.45 + 0.45 * (i + 1) / (current + 1));
      }
      paint
        ..color = tick
        ..strokeWidth = isCurrent ? 5 : (major ? 3.5 : 2.5);
      canvas.drawLine(
        centre + direction * (outer - length),
        centre + direction * outer,
        paint,
      );
    }

    // The hand: a dot just inside the ticks, sweeping between them.
    if (sweeping) {
      final angle = -math.pi / 2 + seconds * math.pi * 2 / 60;
      canvas.drawCircle(
        centre + Offset(math.cos(angle), math.sin(angle)) * (outer - 30),
        5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.seconds != seconds ||
      old.sweeping != sweeping ||
      old.color != color ||
      old.track != track;
}

/// Which view the statistics sheet is showing.
enum _StatsView { week, sixWeeks }

/// Statistics for the focus timer behind one block.
class FocusStatsSheet extends StatefulWidget {
  const FocusStatsSheet({required this.block, super.key});

  final Block block;

  static Future<void> show(BuildContext context, Block block) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
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
    final theme = Theme.of(context);

    // Statistics are per block, but the daily total that buys unlocks is
    // shared: an hour of study is an hour of study, and splitting the pool
    // would mean running two timers for the same hour.
    final stats = store.focusStats(blockId: block.id);
    final target = _target(block);
    return SheetScaffold(
      heightFactor: 0.94,
      title: 'Focus stats',
      leading: SheetAction('Close', onPressed: () => Navigator.pop(context)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(block.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(
                '${stats.streakDays} DAY STREAK',
                color: stats.streakDays > 0 ? colors.light : null,
              ),
              Pill(
                '${stats.completedPomodoros} POMODORO'
                '${stats.completedPomodoros == 1 ? '' : 'S'}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FocusHero(
            label: 'Today\'s focus, across all blocks',
            value: formatDuration(store.focusToday),
            focused: store.focusToday,
            target: target,
          ),
          const SizedBox(height: 24),
          const SectionLabel('For this block'),
          LayoutBuilder(
            builder: (context, constraints) {
              final minWidth = MediaQuery.textScalerOf(context).scale(140);
              final columns = ((constraints.maxWidth + 12) / (minWidth + 12))
                  .floor()
                  .clamp(1, 3);
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (icon, label, value) in [
                    (Icons.today_rounded, 'Today', formatDuration(stats.today)),
                    (
                      Icons.date_range_rounded,
                      'Last 7 days',
                      formatDuration(stats.week),
                    ),
                    (Icons.timer_outlined, 'Sessions', '${stats.sessionCount}'),
                    (
                      Icons.emoji_events_outlined,
                      'Longest session',
                      formatDuration(stats.longest),
                    ),
                    (
                      Icons.av_timer_rounded,
                      'Average session',
                      formatDuration(stats.average),
                    ),
                    (
                      Icons.local_fire_department_rounded,
                      'Streak',
                      stats.streakDays == 1
                          ? '1 day'
                          : '${stats.streakDays} days',
                    ),
                  ])
                    SizedBox(
                      width: width,
                      child: _Stat(icon: icon, label: label, value: value),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          // Title and switch on separate lines: side by side they run out of
          // room at large text sizes.
          Text(
            _view == _StatsView.week ? 'Last 7 days' : 'Last 6 weeks',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ControlSegmented<_StatsView>(
              compact: true,
              value: _view,
              options: const [
                (_StatsView.week, 'Week'),
                (_StatsView.sixWeeks, '6 weeks'),
              ],
              onChanged: (view) => setState(() => _view = view),
            ),
          ),
          const SizedBox(height: 12),
          ControlCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: _view == _StatsView.week
                ? _WeekChart(stats: stats, target: target)
                : _MonthHeatmap(stats: stats, target: target),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Recent sessions'),
          if (stats.recent.isEmpty)
            ControlCard(
              child: Text(
                'No sessions yet. Start one from the block card; anything '
                'over a minute shows up here.',
                style: TextStyle(color: colors.textMuted, height: 1.4),
              ),
            )
          else
            ControlCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < stats.recent.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 68, endIndent: 16),
                    _SessionRow(session: stats.recent[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '${stats.sessionCount} session${stats.sessionCount == 1 ? '' : 's'} '
            'recorded. Focus for ${formatDuration(target)} today to unlock '
            'these apps ${block.blockAgainAfter == null ? 'until midnight' : 'for ${formatDuration(block.blockAgainAfter!)}'}.',
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusHero extends StatelessWidget {
  const _FocusHero({
    required this.label,
    required this.value,
    required this.focused,
    required this.target,
  });

  final String label;
  final String value;
  final Duration focused;
  final Duration target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: Shapes.sheet,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onPrimaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(height: 12),
            Text(label),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.displaySmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ExpressiveProgress(
              value: target <= Duration.zero
                  ? 1.0
                  : (focused.inMicroseconds / target.inMicroseconds).clamp(
                      0.0,
                      1.0,
                    ),
              height: 20,
              color: scheme.onPrimaryContainer,
              trackColor: scheme.onPrimaryContainer.withValues(alpha: 0.14),
              semanticsLabel:
                  'Daily focus goal, ${formatDuration(focused)} of ${formatDuration(target)}',
            ),
            const SizedBox(height: 8),
            Text(
              '${formatDuration(focused)} of ${formatDuration(target)} daily goal',
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven columns, one a day, with the goal drawn across them.
///
/// Scaled to the goal unless a day beat it, so a day that met the goal reads
/// as reaching the line rather than as whatever the week's maximum was.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats, required this.target});

  final FocusStats stats;
  final Duration target;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _barArea = 128.0;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final today = stats.perDay.last.$1;

    var peak = target;
    for (final (_, focused) in stats.perDay) {
      if (focused > peak) peak = focused;
    }
    double share(Duration value) => peak <= Duration.zero
        ? 0
        : (value.inMicroseconds / peak.inMicroseconds).clamp(0.0, 1.0);
    final goalHeight = _barArea * share(target);

    return Column(
      children: [
        SizedBox(
          height: _barArea + 22,
          child: Stack(
            children: [
              if (target > Duration.zero)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: goalHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color: colors.textMuted.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'goal',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned.fill(
                right: 32,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (day, focused) in stats.perDay)
                      Expanded(
                        child: Semantics(
                          label:
                              '${_days[day.weekday - 1]} ${day.day}/${day.month}: '
                              '${formatDuration(focused)} focused',
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (focused > Duration.zero)
                                  FittedBox(
                                    child: Text(
                                      formatDuration(focused),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: colors.textMuted),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  key: ValueKey('focus-bar-${day.weekday}'),
                                  width: 22,
                                  height: math.max(
                                    4,
                                    _barArea * share(focused),
                                  ),
                                  decoration: BoxDecoration(
                                    color: focused == Duration.zero
                                        ? colors.cardRaised
                                        : target > Duration.zero &&
                                              focused >= target
                                        ? colors.light
                                        : colors.light.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 32),
          child: Row(
            children: [
              for (final (day, _) in stats.perDay)
                Expanded(
                  child: Text(
                    _days[day.weekday - 1],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: day == today ? null : colors.textMuted,
                      fontWeight: day == today
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
    final cellHeight = MediaQuery.textScalerOf(context).scale(12) + 12;

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
                    height: cellHeight,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
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
                              height: cellHeight,
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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Less',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final step in const [0.0, 0.35, 0.7, 1.0])
                  Container(
                    margin: const EdgeInsets.only(right: 3),
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
              ],
            ),
            Text(
              'Goal met',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.cell,
    required this.shade,
    required this.height,
  });

  final (DateTime, Duration)? cell;
  final Color Function(Duration) shade;
  final double height;

  @override
  Widget build(BuildContext context) {
    final entry = cell;
    if (entry == null) return SizedBox(height: height);

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message:
              '${entry.$1.day}/${entry.$1.month}: '
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

/// One past session: what kind, how long, and when.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    final length = store.focusLengthOf(session);
    final now = store.focusNow();
    final today = DateTime(now.year, now.month, now.day);
    final started = session.startedAt;
    final startDay = DateTime(started.year, started.month, started.day);
    final day = startDay == today
        ? 'Today'
        : startDay == DateTime(today.year, today.month, today.day - 1)
        ? 'Yesterday'
        : MaterialLocalizations.of(context).formatMediumDate(started);
    final from = TimeOfDay.fromDateTime(started).format(context);
    final until = session.endedAt == null
        ? 'now'
        : TimeOfDay.fromDateTime(session.endedAt!).format(context);
    final completed =
        session.kind == FocusKind.pomodoro &&
        !session.isRunning &&
        session.isComplete(session.endedAt!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.cardRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(
              session.kind == FocusKind.pomodoro
                  ? Icons.timer_outlined
                  : Icons.av_timer_rounded,
              size: 20,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${session.kind.label}, ${formatDuration(length)}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '$day, $from to $until',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (session.isPaused)
            const Pill('PAUSED')
          else if (session.isRunning)
            Pill('RUNNING', color: colors.light)
          else if (completed)
            Icon(Icons.check_circle_rounded, color: colors.light, size: 20),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: ControlCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: colors.light),
              const SizedBox(height: 10),
              Text(value, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: TextStyle(
      color: ControlColors.of(context).textMuted,
      fontSize: 12,
      height: 1.4,
    ),
  );
}
