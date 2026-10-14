import 'dart:io';

import 'package:control/data/focus.dart';
import 'package:control/platform/platform_models.dart';
import 'package:control/state/control_store.dart';
import 'package:control/ui/expressive_progress.dart';
import 'package:control/ui/theme.dart';
import 'package:control_core/control_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Preview-only fixtures; never hydrate storage or publish enforcement plans.
class PreviewStore extends ControlStore {
  PreviewStore() {
    usageAccessGranted = true;
    accessibilityEnabled = true;
    theme = AppThemeChoice.light;
    // Screenshots are single frames; a travelling wave would never settle.
    waveMotion = WaveMotion.off;
    final start = DateTime(2026, 9, 23);
    // Actual hourly history through 14:00, without invented future buckets.
    const minutes = [0, 0, 0, 0, 0, 0, 5, 12, 25, 32, 18, 41, 30, 41];
    const pickups = [0, 0, 0, 0, 0, 0, 1, 2, 4, 5, 3, 6, 5, 6];
    usage = UsageSnapshot(
      apps: const [
        AppUsage(
          id: 'com.android.chrome',
          label: 'Browser',
          duration: Duration(minutes: 90),
        ),
        AppUsage(
          id: 'com.google.android.apps.messaging',
          label: 'Messages',
          duration: Duration(minutes: 45),
        ),
        AppUsage(
          id: 'com.google.android.youtube',
          label: 'Video',
          duration: Duration(minutes: 69),
        ),
      ],
      screenTime: const Duration(minutes: 204),
      pickups: pickups.fold(0, (total, count) => total + count),
      start: start,
      end: now,
      firstEventAt: start.add(const Duration(hours: 6)),
      buckets: [
        for (var hour = 0; hour < minutes.length; hour++)
          UsageBucket(
            start: start.add(Duration(hours: hour)),
            end: start.add(Duration(hours: hour + 1)),
            screenTime: Duration(minutes: minutes[hour]),
            pickups: pickups[hour],
          ),
      ],
    );
    insightsUsage = usage;
    insightsUpdatedAt = now;
  }

  static final now = DateTime(2026, 9, 23, 14);

  @override
  Future<void> init() async {}

  @override
  List<Block> get blocks => const [
    Block(
      id: 'preview-focus',
      name: 'Focus first',
      mode: LimitMode.condition,
      apps: {'com.google.android.youtube'},
      conditions: [
        FocusCondition(id: 'preview-focus-time', target: Duration(hours: 2)),
      ],
      blockAgainAfter: Duration(minutes: 30),
    ),
    Block(
      id: 'preview-browsers',
      name: 'Mindful browsing',
      mode: LimitMode.time,
      apps: {'com.android.chrome'},
      categories: {'browsers'},
      schedule: [TimeRange(startMinute: 9 * 60, endMinute: 17 * 60)],
    ),
  ];

  @override
  Duration get focusToday => const Duration(minutes: 75);

  @override
  Signals get signals => Signals(
    focusToday: focusToday,
    appUsageToday: {for (final app in usage.apps) app.id: app.duration},
  );

  @override
  BlockDecision? decisionFor(String blockId) {
    final block = blocks.where((block) => block.id == blockId).firstOrNull;
    return block == null
        ? null
        : const RuleEngine().evaluate(block: block, signals: signals, now: now);
  }

  /// A session to show on the running timer, when a test wants one.
  FocusSession? previewRunning;

  void notifyListenersForPreview() => notifyListeners();

  @override
  FocusSession? get runningFocus => previewRunning;

  @override
  DateTime focusNow() => now;

  @override
  Duration focusLengthOf(FocusSession session) => session.lengthAt(now);

  /// A plausible fortnight: most days a session or two, a few gaps.
  static final List<FocusSession> _focusHistory = [
    for (var day = 0; day < 20; day++)
      if (day % 5 != 3)
        FocusSession(
          blockId: 'preview-focus',
          startedAt: DateTime(2026, 9, 23 - day, 9, 10),
          endedAt: DateTime(2026, 9, 23 - day, 9, 10 + 25 + (day % 3) * 20),
          kind: day.isEven ? FocusKind.pomodoro : FocusKind.stopwatch,
          plannedWork: day.isEven
              ? Duration(minutes: 25 + (day % 3) * 20)
              : null,
        ),
    FocusSession(
      blockId: 'preview-focus',
      startedAt: DateTime(2026, 9, 23, 11),
      endedAt: DateTime(2026, 9, 23, 11, 50),
      kind: FocusKind.stopwatch,
    ),
  ];

  @override
  FocusStats focusStats({String? blockId}) =>
      FocusStats.from(_focusHistory, now, blockId: blockId);

  /// Same as the real one, minus the file write the preview never opens.
  @override
  Future<void> setWaveMotion(WaveMotion motion) async {
    waveMotion = motion;
    notifyListeners();
  }
}

/// Roboto and Material Icons from Flutter's own cache: real glyphs in
/// screenshots, with no network font service.
Future<void> loadPreviewFonts() async {
  final fonts = Directory(
    '${Platform.environment['FLUTTER_ROOT']!}/bin/cache/artifacts/material_fonts',
  );
  final loader = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold', 'black']) {
    loader.addFont(
      File.fromUri(
        fonts.uri.resolve('roboto-$weight.ttf'),
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
