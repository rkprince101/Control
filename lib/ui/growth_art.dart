import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'expressive_progress.dart';

/// The garden, drawn: one picture per growth stage, from a seed in the soil
/// to an old tree with fireflies.
///
/// [growth] is how far into the stage the habits are, 0 to 1, and the plant
/// grows with it: a sprout gets taller on its way to becoming a sapling, so
/// every check-in shows. It sways a little in the wind at the speed of the
/// Motion setting, and holds still for Off, for reduced motion, while off
/// screen, and when [animate] is false. A [locked] stage is drawn as a flat
/// silhouette, for stages not reached yet.
class GrowthArt extends StatefulWidget {
  const GrowthArt({
    required this.stage,
    this.growth = 1,
    this.size = 120,
    this.animate = true,
    this.locked = false,
    super.key,
  });

  /// Index into the rank ladder: 0 seed to 6 old growth.
  final int stage;
  final double growth;
  final double size;
  final bool animate;
  final bool locked;

  @override
  State<GrowthArt> createState() => _GrowthArtState();
}

class _GrowthArtState extends State<GrowthArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wind = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(GrowthArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final moving =
        widget.animate &&
        !widget.locked &&
        WaveMotionScope.of(context) != WaveMotion.off &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (moving && !_wind.isAnimating) {
      _wind.repeat();
    } else if (!moving && _wind.isAnimating) {
      _wind.stop();
    }
  }

  @override
  void dispose() {
    _wind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.locked
        ? GrowthPalette.silhouette(Theme.of(context).colorScheme.outlineVariant)
        : GrowthPalette.of(Theme.of(context).brightness);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        // New growth eases in, with a small overshoot, like a stem settling.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: widget.growth.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, growth, _) => AnimatedBuilder(
            animation: _wind,
            builder: (context, _) => CustomPaint(
              painter: GrowthPainter(
                stage: widget.stage,
                growth: growth,
                wind: _wind.value,
                palette: palette,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Earth and leaf colours, one set per brightness, chosen to sit beside the
/// app's evergreen rather than compete with it.
@immutable
class GrowthPalette {
  const GrowthPalette({
    required this.leafDeep,
    required this.leaf,
    required this.leafLight,
    required this.trunk,
    required this.soil,
    required this.soilDeep,
    required this.seed,
    required this.glow,
  });

  factory GrowthPalette.of(Brightness brightness) =>
      brightness == Brightness.light
      ? const GrowthPalette(
          leafDeep: Color(0xFF2F6B45),
          leaf: Color(0xFF4C8B57),
          leafLight: Color(0xFF86B872),
          trunk: Color(0xFF7A5536),
          soil: Color(0xFFB88A5E),
          soilDeep: Color(0xFF94694A),
          seed: Color(0xFFC89B5E),
          glow: Color(0xFFF2C94C),
        )
      : const GrowthPalette(
          leafDeep: Color(0xFF4F8E62),
          leaf: Color(0xFF6FAE78),
          leafLight: Color(0xFFA7D597),
          trunk: Color(0xFFA57B55),
          soil: Color(0xFF8A6446),
          soilDeep: Color(0xFF6E4E37),
          seed: Color(0xFFD6AB72),
          glow: Color(0xFFFFDF7A),
        );

  /// Every part in one flat tone, for a stage still ahead.
  factory GrowthPalette.silhouette(Color tone) => GrowthPalette(
    leafDeep: tone,
    leaf: tone,
    leafLight: tone,
    trunk: tone,
    soil: tone,
    soilDeep: tone,
    seed: tone,
    glow: Colors.transparent,
  );

  final Color leafDeep;
  final Color leaf;
  final Color leafLight;
  final Color trunk;
  final Color soil;
  final Color soilDeep;
  final Color seed;
  final Color glow;
}

/// Draws a stage on a 100 x 100 canvas, scaled to fit.
class GrowthPainter extends CustomPainter {
  const GrowthPainter({
    required this.stage,
    required this.growth,
    required this.wind,
    required this.palette,
  });

  final int stage;

  /// 0..1 through the stage. Overshoots a little while easing in.
  final double growth;

  /// 0..1 round the wind's cycle.
  final double wind;
  final GrowthPalette palette;

  double get _sway => math.sin(wind * math.pi * 2);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 100;
    if (unit <= 0) return;
    canvas.save();
    canvas.translate(
      (size.width - 100 * unit) / 2,
      (size.height - 100 * unit) / 2,
    );
    canvas.scale(unit);
    final g = growth.clamp(0.0, 1.15);

    switch (stage.clamp(0, 6)) {
      case 0:
        _seed(canvas, g);
      case 1:
        _soil(canvas, 50, 58);
        _sprout(canvas, const Offset(50, 84), 16 + 12 * g, 7 + 4 * g, 0.09);
      case 2:
        _soil(canvas, 50, 62);
        _sapling(canvas, const Offset(50, 85), 34 + 12 * g);
      case 3:
        _soil(canvas, 50, 70);
        _roundTree(canvas, const Offset(50, 86), 48 + 8 * g, 19 + 4 * g);
      case 4:
        _soil(canvas, 50, 90);
        _roundTree(
          canvas,
          const Offset(24, 84),
          36 + 4 * g,
          12 + 2 * g,
          shade: 0.2,
        );
        _roundTree(
          canvas,
          const Offset(77, 84),
          40 + 5 * g,
          14 + 2 * g,
          shade: 0.1,
        );
        _roundTree(canvas, const Offset(50, 87), 48 + 6 * g, 17 + 3 * g);
      case 5:
        _soil(canvas, 50, 96);
        _pine(canvas, const Offset(18, 80), 40 + 4 * g, 18, far: true);
        _pine(canvas, const Offset(84, 79), 44 + 4 * g, 20, far: true);
        _pine(canvas, const Offset(52, 77), 36 + 4 * g, 16, far: true);
        _roundTree(canvas, const Offset(32, 87), 42 + 5 * g, 14 + 2 * g);
        _pine(canvas, const Offset(64, 88), 52 + 6 * g, 24);
        _roundTree(
          canvas,
          const Offset(86, 89),
          30 + 4 * g,
          10 + 2 * g,
          shade: 0.15,
        );
      default:
        _soil(canvas, 50, 98);
        _sprout(canvas, const Offset(84, 88), 12, 6, 0.1);
        _oldTree(canvas, const Offset(46, 88), g);
        _fireflies(canvas, g);
    }
    canvas.restore();
  }

  // Pieces ---------------------------------------------------------------

  void _soil(Canvas canvas, double centre, double width) {
    final mound = Rect.fromCenter(
      center: Offset(centre, 89),
      width: width,
      height: 12,
    );
    canvas.drawOval(mound, Paint()..color = palette.soil);
    // A darker lip underneath gives the mound some weight.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 89, 100, 100));
    canvas.drawOval(mound, Paint()..color = palette.soilDeep);
    canvas.restore();
  }

  void _seed(Canvas canvas, double g) {
    final wobble = _sway * 0.06;
    canvas.save();
    canvas.translate(50, 82);
    canvas.rotate(-0.35 + wobble);
    final seed = Path()
      ..moveTo(0, -11)
      ..quadraticBezierTo(9, -2, 0, 11)
      ..quadraticBezierTo(-9, -2, 0, -11)
      ..close();
    canvas.drawPath(seed, Paint()..color = palette.seed);
    // The seam down the middle.
    canvas.drawLine(
      const Offset(0, -8),
      const Offset(0, 8),
      Paint()
        ..color = palette.soilDeep.withValues(alpha: 0.6)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    // Close to sprouting: a first green tip pushes out of the top.
    if (g > 0.5) {
      final tip = (g - 0.5) * 2 * 7;
      canvas.drawLine(
        const Offset(0, -10),
        Offset(1.5, -10 - tip),
        Paint()
          ..color = palette.leaf
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
    // Soil over the lower half, so the seed sits in the ground, not on it.
    _soil(canvas, 50, 56);
  }

  void _leaf(
    Canvas canvas,
    Offset at,
    double length,
    double angle,
    Color color,
  ) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final leaf = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.5, -length * 0.42, length, 0)
      ..quadraticBezierTo(length * 0.5, length * 0.42, 0, 0)
      ..close();
    canvas.drawPath(leaf, Paint()..color = color);
    canvas.restore();
  }

  void _sprout(
    Canvas canvas,
    Offset base,
    double height,
    double leaf,
    double bend,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(_sway * bend);
    final top = Offset(0, -height);
    final stem = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-3, -height * 0.5, top.dx, top.dy);
    canvas.drawPath(
      stem,
      Paint()
        ..color = palette.leafDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    _leaf(canvas, top, leaf, -math.pi + 0.7, palette.leaf);
    _leaf(canvas, top, leaf * 1.1, -0.6, palette.leafLight);
    canvas.restore();
  }

  void _sapling(Canvas canvas, Offset base, double height) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(_sway * 0.05);
    final stem = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(3, -height * 0.55, -1, -height);
    canvas.drawPath(
      stem,
      Paint()
        ..color = palette.trunk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
    // Alternating leaves up the stem, smaller towards the top.
    for (final (t, left) in const [
      (0.38, true),
      (0.52, false),
      (0.66, true),
      (0.8, false),
    ]) {
      final at = Offset(t < 0.5 ? 1.5 : 0.5, -height * t);
      _leaf(
        canvas,
        at,
        13 * (1.1 - t * 0.5),
        left ? -math.pi + 0.55 : -0.55,
        left ? palette.leaf : palette.leafLight,
      );
    }
    _leaf(canvas, Offset(-1, -height), 9, -math.pi / 2 - 0.4, palette.leaf);
    _leaf(
      canvas,
      Offset(-1, -height),
      8,
      -math.pi / 2 + 0.5,
      palette.leafLight,
    );
    canvas.restore();
  }

  void _roundTree(
    Canvas canvas,
    Offset base,
    double height,
    double canopy, {
    double shade = 0,
  }) {
    Color tint(Color c) => Color.lerp(c, palette.leafLight, shade)!;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(_sway * 0.025);
    final trunkWidth = canopy * 0.32;
    final crownY = -height + canopy * 0.55;
    final trunk = Path()
      ..moveTo(-trunkWidth / 2, 0)
      ..lineTo(-trunkWidth * 0.3, crownY)
      ..lineTo(trunkWidth * 0.3, crownY)
      ..lineTo(trunkWidth / 2, 0)
      ..close();
    canvas.drawPath(trunk, Paint()..color = palette.trunk);
    // The crown: two darker lobes behind, the full crown, a lit side.
    final centre = Offset(_sway * canopy * 0.05, crownY - canopy * 0.35);
    canvas.drawCircle(
      centre + Offset(-canopy * 0.45, canopy * 0.2),
      canopy * 0.68,
      Paint()..color = tint(palette.leafDeep),
    );
    canvas.drawCircle(
      centre + Offset(canopy * 0.48, canopy * 0.15),
      canopy * 0.64,
      Paint()..color = tint(palette.leafDeep),
    );
    canvas.drawCircle(centre, canopy, Paint()..color = tint(palette.leaf));
    canvas.drawCircle(
      centre + Offset(-canopy * 0.3, -canopy * 0.32),
      canopy * 0.48,
      Paint()..color = tint(palette.leafLight).withValues(alpha: 0.9),
    );
    canvas.restore();
  }

  void _pine(
    Canvas canvas,
    Offset base,
    double height,
    double width, {
    bool far = false,
  }) {
    final deep = far
        ? Color.lerp(palette.leafDeep, palette.leafLight, 0.45)!
        : palette.leafDeep;
    final mid = far
        ? Color.lerp(palette.leaf, palette.leafLight, 0.45)!
        : palette.leaf;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(_sway * 0.02);
    canvas.drawRect(
      Rect.fromLTWH(-width * 0.08, -height * 0.18, width * 0.16, height * 0.18),
      Paint()..color = palette.trunk,
    );
    // Three tiers, each narrower and higher.
    for (var tier = 0; tier < 3; tier++) {
      final bottom = -height * (0.14 + tier * 0.24);
      final top = bottom - height * 0.42;
      final half = width / 2 * (1 - tier * 0.24);
      final path = Path()
        ..moveTo(-half, bottom)
        ..quadraticBezierTo(0, bottom + 3, half, bottom)
        ..lineTo(_sway * 0.6, top)
        ..close();
      canvas.drawPath(path, Paint()..color = tier.isEven ? deep : mid);
    }
    canvas.restore();
  }

  void _oldTree(Canvas canvas, Offset base, double g) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(_sway * 0.015);
    // A broad trunk with roots flaring into the ground.
    final trunk = Path()
      ..moveTo(-16, 0)
      ..quadraticBezierTo(-8, -3, -7, -16)
      ..lineTo(-5, -40)
      ..lineTo(5, -40)
      ..lineTo(7, -16)
      ..quadraticBezierTo(8, -3, 16, 0)
      ..close();
    canvas.drawPath(trunk, Paint()..color = palette.trunk);
    // Two limbs reaching into the crown.
    final limb = Paint()
      ..color = palette.trunk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-2, -34), const Offset(-16, -50), limb);
    canvas.drawLine(const Offset(2, -36), const Offset(18, -52), limb);
    // A wide crown of clustered lobes, deep behind and lit in front.
    final spread = 1 + 0.08 * g;
    final drift = Offset(_sway * 1.2, 0);
    for (final (x, y, r) in const [
      (-24.0, -52.0, 13.0),
      (24.0, -54.0, 13.0),
      (-10.0, -66.0, 14.0),
      (12.0, -67.0, 14.0),
    ]) {
      canvas.drawCircle(
        Offset(x * spread, y) + drift,
        r,
        Paint()..color = palette.leafDeep,
      );
    }
    for (final (x, y, r) in const [
      (-16.0, -56.0, 13.0),
      (16.0, -58.0, 13.0),
      (0.0, -64.0, 16.0),
    ]) {
      canvas.drawCircle(
        Offset(x * spread, y) + drift,
        r,
        Paint()..color = palette.leaf,
      );
    }
    canvas.drawCircle(
      const Offset(-8, -70) + drift,
      9,
      Paint()..color = palette.leafLight.withValues(alpha: 0.9),
    );
    canvas.restore();
  }

  /// Four lights round the old tree, each on its own beat. None on a
  /// silhouette: a locked stage has no light in it yet.
  void _fireflies(Canvas canvas, double g) {
    if (palette.glow.a == 0) return;
    for (final (index, (x, y)) in const [
      (16.0, 40.0),
      (82.0, 30.0),
      (74.0, 58.0),
      (24.0, 62.0),
    ].indexed) {
      final beat = 0.5 + 0.5 * math.sin((wind + index / 4) * math.pi * 2);
      canvas.drawCircle(
        Offset(x, y + math.sin((wind + index / 3) * math.pi * 2) * 1.5),
        1.4 + beat * 0.6,
        Paint()..color = palette.glow.withValues(alpha: 0.35 + 0.65 * beat),
      );
    }
  }

  @override
  bool shouldRepaint(GrowthPainter old) =>
      old.stage != stage ||
      old.growth != growth ||
      old.wind != wind ||
      old.palette != palette;
}

/// Leaves rising and fading: the moment a new stage is reached.
class GrowthBurst extends StatelessWidget {
  const GrowthBurst({required this.progress, required this.color, super.key});

  /// 0..1 through the burst.
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _BurstPainter(progress: progress, color: color),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final centre = size.center(Offset.zero);
    final fade = 1 - Curves.easeIn.transform(progress);
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + (i - 3.5) * 0.32;
      final distance = size.shortestSide * (0.2 + 0.45 * progress);
      final at = centre + Offset(math.cos(angle), math.sin(angle)) * distance;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle + progress * math.pi * (i.isEven ? 1 : -1));
      final length = size.shortestSide * 0.09;
      final leaf = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(length * 0.5, -length * 0.4, length, 0)
        ..quadraticBezierTo(length * 0.5, length * 0.4, 0, 0)
        ..close();
      canvas.drawPath(leaf, Paint()..color = color.withValues(alpha: fade));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
