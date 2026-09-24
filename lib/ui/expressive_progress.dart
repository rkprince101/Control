import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How the wave on an [ExpressiveProgress] moves. Chosen in Settings.
enum WaveMotion {
  off('Off'),
  calm('Calm'),
  lively('Lively');

  const WaveMotion(this.label);

  final String label;

  static WaveMotion fromName(String? name) =>
      WaveMotion.values.where((motion) => motion.name == name).firstOrNull ??
      WaveMotion.calm;

  /// Time for the wave to travel one wavelength, or null when it stands still.
  ///
  /// Lively is the Material 3 Expressive default of one wavelength a second,
  /// give or take; calm is half that, for a screen that is looked at for long
  /// stretches.
  Duration? get period => switch (this) {
    WaveMotion.off => null,
    WaveMotion.calm => const Duration(milliseconds: 1400),
    WaveMotion.lively => const Duration(milliseconds: 700),
  };
}

/// Hands the Settings choice to every progress bar below it, sheets included.
class WaveMotionScope extends InheritedWidget {
  const WaveMotionScope({
    required this.motion,
    required super.child,
    super.key,
  });

  final WaveMotion motion;

  /// Calm when nothing above says otherwise.
  static WaveMotion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WaveMotionScope>()?.motion ??
      WaveMotion.calm;

  @override
  bool updateShouldNotify(WaveMotionScope oldWidget) =>
      motion != oldWidget.motion;
}

/// A rounded, wavy linear indicator.
///
/// The wave travels along the filled part for as long as there is something
/// partly done, at the speed set by [WaveMotion]. A value change eases to the
/// new length. Both stop for Off, for the system's reduced-motion setting, for
/// [animate] false, and while the page is not visible; an empty or a finished
/// bar has no wave to move and stops on its own.
class ExpressiveProgress extends StatefulWidget {
  const ExpressiveProgress({
    this.value,
    this.color,
    this.trackColor,
    this.height = 20,
    this.semanticsLabel,
    this.animate = true,
    this.motion,
    super.key,
  });

  final double? value;
  final Color? color;
  final Color? trackColor;
  final double height;
  final String? semanticsLabel;
  final bool animate;

  /// Overrides the [WaveMotionScope] choice, for the Settings preview.
  final WaveMotion? motion;

  @override
  State<ExpressiveProgress> createState() => _ExpressiveProgressState();
}

class _ExpressiveProgressState extends State<ExpressiveProgress>
    with TickerProviderStateMixin {
  /// Eases the filled length from one value to the next.
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  /// The wave's phase, 0..1 per wavelength, looping while it travels.
  late final AnimationController _wave = AnimationController(vsync: this);

  double _from = 0;
  double _to = 0;

  double? get _value {
    final value = widget.value;
    if (value == null) return null;
    return value.isNaN ? 0 : value.clamp(0.0, 1.0);
  }

  double get _displayed =>
      _from + (_to - _from) * Curves.easeInOut.transform(_transition.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure(transition: false);
  }

  @override
  void didUpdateWidget(ExpressiveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.animate != widget.animate ||
        oldWidget.motion != widget.motion) {
      _configure(transition: oldWidget.value != null);
    }
  }

  void _configure({required bool transition}) {
    final motion = widget.motion ?? WaveMotionScope.of(context);
    // Settings and accessibility say whether anything may move at all.
    final permitted =
        widget.animate &&
        motion != WaveMotion.off &&
        !MediaQuery.disableAnimationsOf(context);
    // A page in the background keeps its place and resumes where it was.
    final visible = TickerMode.valuesOf(context).enabled;
    final value = _value;

    if (value != null && (value != _to || !transition)) {
      final current = _displayed;
      _transition.stop();
      _from = transition && permitted && visible ? current : value;
      _to = value;
      _transition.value = 0;
      if (_from != _to) _transition.forward();
    }

    final period = motion.period;
    final hasWave = value == null || (value > 0 && value < 1);
    if (permitted && visible && hasWave && period != null) {
      if (!_wave.isAnimating || _wave.duration != period) {
        // From the current phase, so a speed change never jumps the wave.
        _wave.repeat(period: period);
      }
    } else {
      _wave.stop();
      // Stopped on purpose: settle on the resting shape, the same every time.
      if (!permitted) _wave.value = 0;
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = _value;
    return Semantics(
      label: widget.semanticsLabel,
      value: value == null ? 'Loading' : '${(value * 100).round()}%',
      child: SizedBox(
        height: widget.height.isFinite ? math.max(0, widget.height) : 20,
        width: double.infinity,
        // A travelling wave repaints every frame; the boundary keeps that to
        // the bar rather than the whole card around it.
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_transition, _wave]),
            builder: (context, _) => CustomPaint(
              painter: _WavePainter(
                value: value == null ? 0.42 : _displayed,
                phase: _wave.value,
                color: widget.color ?? scheme.primary,
                trackColor: widget.trackColor ?? scheme.surfaceContainerHighest,
                direction: Directionality.of(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.value,
    required this.phase,
    required this.color,
    required this.trackColor,
    required this.direction,
  });

  final double value;
  final double phase;
  final Color color;
  final Color trackColor;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (direction == TextDirection.rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final stroke = math.min(4.0, math.min(size.width, size.height));
    final radius = stroke / 2;
    final start = radius;
    final end = size.width - radius;
    final length = end - start;
    final y = size.height / 2;
    if (length <= 0) {
      canvas.drawCircle(Offset(start, y), radius, Paint()..color = color);
      canvas.restore();
      return;
    }
    final activeEnd = start + length * value;
    final paint = Paint()
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Rounded caps consume half a stroke on each side of the visible 4dp gap.
    final trackStart = value == 0 ? start : activeEnd + stroke + 4;
    if (value < 1 && trackStart <= end) {
      canvas.drawLine(
        Offset(trackStart, y),
        Offset(end, y),
        paint..color = trackColor,
      );
    }
    if (value > 0 && activeEnd > start) {
      final taper = math.min(1.0, math.min(value, 1 - value) / 0.1);
      final amplitude = math.min(3.0, math.max(0.0, y - radius)) * taper;
      final path = Path();
      for (double x = start; x < activeEnd; x += 1) {
        final dy =
            amplitude *
            math.sin((x - start) / 28 * math.pi * 2 - phase * math.pi * 2);
        if (x == start) {
          path.moveTo(x, y + dy);
        } else {
          path.lineTo(x, y + dy);
        }
      }
      path.lineTo(
        activeEnd,
        y +
            amplitude *
                math.sin(
                  (activeEnd - start) / 28 * math.pi * 2 - phase * math.pi * 2,
                ),
      );
      canvas.drawPath(path, paint..color = color);
    }
    // Hide the stop only when the active stroke would collide with it.
    if (value == 0 || end - activeEnd >= stroke + 4) {
      canvas.drawCircle(Offset(end, y), radius, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      value != oldDelegate.value ||
      phase != oldDelegate.phase ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor ||
      direction != oldDelegate.direction;
}
