import 'package:flutter/material.dart';

/// The four looks offered in Settings.
///
/// Pitch black is a separate choice rather than a shade of dark because on an
/// OLED panel a true `#000000` turns pixels off: it is the difference between a
/// dim screen and no screen at all in a dark room, which is exactly when this
/// app gets opened.
enum AppThemeChoice {
  system('System'),
  light('Light'),
  black('Black'),
  pitchBlack('Pitch black');

  const AppThemeChoice(this.label);

  final String label;

  static AppThemeChoice fromName(String? name) =>
      AppThemeChoice.values.where((v) => v.name == name).firstOrNull ??
      AppThemeChoice.system;

  ThemeMode get themeMode => switch (this) {
    AppThemeChoice.system => ThemeMode.system,
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.black || AppThemeChoice.pitchBlack => ThemeMode.dark,
  };
}

/// The Material 3 shape scale.
///
/// Named rather than sprinkled as literals, because the whole point of a scale
/// is that a card and a sheet do not pick neighbouring-but-different radii.
abstract final class Shapes {
  static const extraSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 24.0;
  static const extraLarge = 32.0;

  static BorderRadius get chip => BorderRadius.circular(16);
  static BorderRadius get card => BorderRadius.circular(large);
  static BorderRadius get sheet => BorderRadius.circular(extraLarge);
  static BorderRadius get field => BorderRadius.circular(medium);
}

/// Surface and severity colours.
///
/// Every value is derived from the Material 3 [ColorScheme] rather than held
/// separately, so the two can never drift. The names stay app-specific because
/// they say what the colour is for here: `card` is a container, `heavy` is the
/// worst row on Insights, and neither is obvious from `surfaceContainer` or
/// `error` at the call site.
@immutable
class ControlColors extends ThemeExtension<ControlColors> {
  const ControlColors({
    required this.background,
    required this.card,
    required this.cardRaised,
    required this.textMuted,
    required this.divider,
    required this.heavy,
    required this.medium,
    required this.light,
  });

  /// Maps the app vocabulary onto M3 roles.
  ///
  /// The severity ramp is the one place that does not use a role directly:
  /// Insights needs three steps that read as a scale, and error/tertiary/primary
  /// happen to be exactly red, amber and green in this scheme.
  factory ControlColors.fromScheme(ColorScheme scheme) => ControlColors(
    background: scheme.surface,
    card: scheme.surfaceContainerLow,
    cardRaised: scheme.surfaceContainerHigh,
    textMuted: scheme.onSurfaceVariant,
    divider: scheme.outlineVariant,
    heavy: scheme.error,
    medium: scheme.tertiary,
    light: scheme.primary,
  );

  final Color background;
  final Color card;
  final Color cardRaised;
  final Color textMuted;
  final Color divider;

  /// Severity ramp, shared by the Insights bars and the block state dots.
  final Color heavy;
  final Color medium;
  final Color light;

  static ControlColors of(BuildContext context) =>
      Theme.of(context).extension<ControlColors>() ??
      ControlColors.fromScheme(Theme.of(context).colorScheme);

  /// Colours a duration by weight rather than by category, so the worst row on
  /// Insights is legible in one glance.
  Color forDuration(Duration duration, Duration worst) {
    if (worst == Duration.zero) return light;
    final share = duration.inSeconds / worst.inSeconds;
    if (share >= 0.5) return heavy;
    if (share >= 0.2) return medium;
    return light;
  }

  @override
  ControlColors copyWith({
    Color? background,
    Color? card,
    Color? cardRaised,
    Color? textMuted,
    Color? divider,
    Color? heavy,
    Color? medium,
    Color? light,
  }) => ControlColors(
    background: background ?? this.background,
    card: card ?? this.card,
    cardRaised: cardRaised ?? this.cardRaised,
    textMuted: textMuted ?? this.textMuted,
    divider: divider ?? this.divider,
    heavy: heavy ?? this.heavy,
    medium: medium ?? this.medium,
    light: light ?? this.light,
  );

  @override
  ControlColors lerp(ControlColors? other, double t) {
    if (other == null) return this;
    return ControlColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardRaised: Color.lerp(cardRaised, other.cardRaised, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      heavy: Color.lerp(heavy, other.heavy, t)!,
      medium: Color.lerp(medium, other.medium, t)!,
      light: Color.lerp(light, other.light, t)!,
    );
  }
}

/// The accent the tonal palettes are generated from.
const _seed = Color(0xFF365E49);

/// Amber, kept as its own seed so the middle of the severity ramp is a real
/// hue rather than whatever tertiary the green seed happened to produce.
const _warningSeed = Color(0xFFAA563A);

ColorScheme _schemeFor(Brightness brightness) {
  final generated = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final warning = ColorScheme.fromSeed(
    seedColor: _warningSeed,
    brightness: brightness,
  );

  return generated.copyWith(
    surface: brightness == Brightness.light
        ? const Color(0xFFF7F7F0)
        : const Color(0xFF111612),
    surfaceContainerLow: brightness == Brightness.light
        ? const Color(0xFFEEEEE6)
        : const Color(0xFF1A211B),
    primaryContainer: brightness == Brightness.light
        ? const Color(0xFFD8ECC2)
        : generated.primaryContainer,
    tertiary: warning.primary,
    onTertiary: warning.onPrimary,
    tertiaryContainer: warning.primaryContainer,
    onTertiaryContainer: warning.onPrimaryContainer,
  );
}

/// Pure-black surfaces for OLED, with the container steps compressed to match.
///
/// The M3 surface family still has to read as a family: containers stay
/// distinguishable from each other, they are just all much darker.
ColorScheme _pitchBlackScheme(ColorScheme dark) => dark.copyWith(
  surface: const Color(0xFF000000),
  surfaceDim: const Color(0xFF000000),
  surfaceBright: const Color(0xFF1A1A1D),
  surfaceContainerLowest: const Color(0xFF000000),
  surfaceContainerLow: const Color(0xFF0A0A0C),
  surfaceContainer: const Color(0xFF101012),
  surfaceContainerHigh: const Color(0xFF17171A),
  surfaceContainerHighest: const Color(0xFF1F1F22),
);

ThemeData buildControlTheme({
  required Brightness brightness,
  bool pitchBlack = false,
}) {
  final base = _schemeFor(brightness);
  final scheme = pitchBlack && brightness == Brightness.dark
      ? _pitchBlackScheme(base)
      : base;

  final colors = ControlColors.fromScheme(scheme);
  final typography = _typographyFor(scheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: typography,
    extensions: [colors],
    visualDensity: VisualDensity.standard,
    navigationBarTheme: NavigationBarThemeData(
      height: 80,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(typography.labelMedium),
      elevation: 0,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedLabelTextStyle: typography.labelLarge,
      unselectedLabelTextStyle: typography.labelMedium,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      extendedTextStyle: typography.labelLarge,
    ),

    // M3 leans on tonal surfaces instead of shadows, so the shadow is removed
    // rather than softened: a drop shadow under a container that is already
    // lighter than the page reads as two competing depth cues.
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: Shapes.card),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Shapes.sheet),
      titleTextStyle: typography.headlineSmall,
      contentTextStyle: typography.bodyMedium?.copyWith(height: 1.4),
    ),
    // The pickers are dialogs too, so they wear the same shape and buttons
    // as the app's own: a tonal header, and a filled pill to confirm.
    datePickerTheme: DatePickerThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Shapes.sheet),
      headerBackgroundColor: scheme.primaryContainer,
      headerForegroundColor: scheme.onPrimaryContainer,
      todayBorder: BorderSide(color: scheme.primary, width: 1.5),
      dividerColor: Colors.transparent,
      cancelButtonStyle: _pickerButton(
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      confirmButtonStyle: _pickerButton(scheme.primary, scheme.onPrimary),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: Shapes.sheet),
      dialBackgroundColor: scheme.surfaceContainerHighest,
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      cancelButtonStyle: _pickerButton(
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      confirmButtonStyle: _pickerButton(scheme.primary, scheme.onPrimary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Shapes.extraLarge),
        ),
      ),
      // Off: Flutter reserves a 48dp band for its handle and centres the
      // handle in it, leaving a visible gap above whatever follows. Sheets
      // draw a 36x4 grabber themselves, at iOS proportions.
      showDragHandle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: Shapes.field,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Shapes.field,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Shapes.field,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      hintStyle: typography.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      labelStyle: typography.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const StadiumBorder(),
        textStyle: typography.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: const StadiumBorder(),
        textStyle: typography.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: const CircleBorder()),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.secondaryContainer,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: Shapes.chip),
      labelStyle: typography.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      // Flutter reserves a tall touch box around a slider by default. Left
      // alone it reads as a gap above and below every slider in the editor,
      // which is what made those cards look badly spaced.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      trackHeight: 8,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 6,
      borderRadius: BorderRadius.circular(Shapes.extraSmall),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline,
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: Shapes.field),
      titleTextStyle: typography.bodyLarge,
      subtitleTextStyle: typography.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: typography.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: Shapes.field),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
    ),
  );
}

/// A picker's Cancel or OK as a pill, matching the app's dialog buttons.
ButtonStyle _pickerButton(Color background, Color foreground) =>
    TextButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: const StadiumBorder(),
    );

/// System typography stays available offline, including on the first launch.
TextTheme _typographyFor(ColorScheme scheme) {
  final base = ThemeData(brightness: scheme.brightness).textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -2.5,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -2,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    ),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}

/// Running-timer form: `04:31`, `1:12:05`. Seconds matter while a session is
/// live, and not at all anywhere else, which is why this is separate from
/// [formatDuration].
String formatClock(Duration duration) {
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60);
  if (duration.inHours == 0) {
    return '${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '${duration.inHours}:${minutes.toString().padLeft(2, '0')}:$seconds';
}

/// Formats a duration the way the Insights rows read: `6h 27m`, `59m`, `0m`.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
