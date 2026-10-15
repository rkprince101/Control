// Named parameters cannot be private in Dart, so the injected collaborators
// below cannot be initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:control_core/control_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/activity.dart';
import '../data/descriptions.dart';
import '../data/focus.dart';
import '../data/local_store.dart';
import '../data/page_lock.dart';
import '../data/thoughts.dart';
import '../data/password.dart';
import '../platform/enforcement_channel.dart';
import '../platform/platform_models.dart';
import '../ui/expressive_progress.dart';
import '../ui/theme.dart';

/// Why a place check-in was or was not accepted.
///
/// Distinct cases rather than a bool: "you are 40 m too far" and "the GPS is
/// not sure where you are" need different things from the user, and a single
/// failure message would send them the wrong way.
enum CheckInResult {
  success,
  outsideWindow,
  tooFar,
  fixTooVague,
  noFix,
  noPermission,
  approximateOnly,
  mockLocation,
  locationOff,
  unknownCondition;

  String get message => switch (this) {
    CheckInResult.success => 'Checked in. Apps unlocked for today.',
    CheckInResult.outsideWindow => 'Not during the window for this habit.',
    CheckInResult.tooFar => 'Not close enough to the place yet.',
    CheckInResult.fixTooVague =>
      'The fix is too vague to prove you are there. Step outside and try '
          'again in a moment.',
    CheckInResult.noFix => 'No location fix yet. Try again in a moment.',
    CheckInResult.noPermission => 'Control needs location access for this.',
    CheckInResult.approximateOnly =>
      'Control only has approximate location, which cannot prove you are '
          'there. Allow precise location.',
    CheckInResult.mockLocation =>
      'That location comes from a mock-location app, so it cannot prove you '
          'are there.',
    CheckInResult.locationOff => 'Turn on location services first.',
    CheckInResult.unknownCondition => 'That habit no longer exists.',
  };
}

/// Window the Insights screen is showing.
enum InsightsRange {
  day('Day'),
  week('Week'),
  month('Month');

  const InsightsRange(this.label);

  final String label;

  /// Inclusive start of the window, counting back from the start of today.
  DateTime startFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      InsightsRange.day => today,
      InsightsRange.week => DateTime(now.year, now.month, now.day - 6),
      InsightsRange.month => DateTime(now.year, now.month, now.day - 29),
    };
  }

  int get days => switch (this) {
    InsightsRange.day => 1,
    InsightsRange.week => 7,
    InsightsRange.month => 30,
  };
}

/// Holds the blocks, drives the engine, and keeps the native enforcer in sync.
class ControlStore extends ChangeNotifier {
  ControlStore({
    EnforcementChannel channel = const EnforcementChannel(),
    RuleEngine engine = const RuleEngine(),
    Directory? storageDirectory,
  }) : _channel = channel,
       _engine = engine,
       _storageDirectory = storageDirectory;

  final EnforcementChannel _channel;
  final RuleEngine _engine;
  final Directory? _storageDirectory;
  final LockPolicy _lockPolicy = const LockPolicy();
  final TamperResistantClock _clock = const TamperResistantClock();
  DateTime? _timeAnchor;
  final Stopwatch _timeElapsed = Stopwatch();

  /// Opened once. Every write goes through [_store] rather than a nullable
  /// field, so a save that happens while the app is still starting waits for
  /// storage instead of being silently dropped.
  Future<LocalStore>? _opening;
  LocalStore? _local;

  Future<LocalStore> get _store => _opening ??= LocalStore.open(
    directory: _storageDirectory,
  ).then((store) => _local = store);

  final List<Block> _blocks = [];
  List<Block> get blocks => List.unmodifiable(_blocks);

  Signals _signals = const Signals();
  DateTime? _signalsDay;
  Signals get signals => _signals;

  EnforcementPlan? _plan;
  EnforcementPlan? get plan => _plan;

  bool accessibilityEnabled = false;
  bool usageAccessGranted = false;
  StepsStatus stepsStatus = const StepsStatus.unknown();
  LocationStatus locationStatus = const LocationStatus.unknown();
  ProtectionStatus protection = const ProtectionStatus.none();
  NotificationStatus notifications = const NotificationStatus.unknown();

  /// When Android last refused to show the block screen and Control sent the
  /// phone Home instead. On MIUI and HyperOS that means the pop-up permission
  /// is off.
  DateTime? shieldFallbackAt;

  /// Today's usage only; shared by enforcement signals and outside summaries.
  UsageSnapshot usage = const UsageSnapshot.empty();
  UsageSnapshot insightsUsage = const UsageSnapshot.empty();
  bool insightsLoading = false;
  String? insightsError;
  DateTime? insightsUpdatedAt;
  int _insightsGeneration = 0;
  bool _disposed = false;
  InsightsRange insightsRange = InsightsRange.day;
  List<InstalledApp> installedApps = const [];

  EmergencyUnlocks emergencyUnlocks = const EmergencyUnlocks.fresh();
  AppThemeChoice theme = AppThemeChoice.system;

  /// How the wave on progress bars moves.
  WaveMotion waveMotion = WaveMotion.calm;

  /// Tamper guard: the accessibility service backs out of the screens used to
  /// uninstall or disable Control.
  bool hardMode = false;

  /// Sunday-evening summary notification.
  bool weeklyReport = false;

  /// Guards uninstall protection itself.
  ///
  /// Without it the whole scheme has an obvious hole: open Control, switch Hard
  /// mode off, delete the app, and every block goes with it. Locking this is
  /// what turns a preference into a commitment.
  Lock protectionLock = const Lock.none();

  Duration? get protectionLockRemaining =>
      _lockPolicy.remaining(block: _protectionCarrier, now: _now());

  /// True while protection settings are held shut.
  bool get protectionLocked =>
      _lockPolicy.verdict(
        block: _protectionCarrier,
        change: BlockChange.weaken,
        now: _now(),
      ) !=
      LockVerdict.allowed;

  /// [LockPolicy] reasons about blocks, and protection is not one. Wrapping it
  /// in a throwaway block keeps a single implementation of the lock rules
  /// rather than a second, subtly different copy.
  Block get _protectionCarrier => Block(
    id: '__protection__',
    name: 'App deletion blocked',
    mode: LimitMode.time,
    lock: protectionLock,
  );

  final List<FocusSession> _focusSessions = [];
  List<FocusSession> get focusSessions => List.unmodifiable(_focusSessions);

  /// Ticks once a second while a session or a break counts, so the card and
  /// the timer sheet stay live without polling anything else.
  Timer? _focusTicker;

  /// A break between pomodoros, if one is running.
  FocusBreak? focusBreak;

  /// The session that just ended, until the next one starts or the result is
  /// dismissed. Drives the timer sheet's done view.
  FocusSession? lastFinishedFocus;

  /// The block whose break just ran out, for the same reason.
  String? breakOverFor;

  bool _askedFocusNotifications = false;

  FocusSession? get runningFocus =>
      _focusSessions.where((session) => session.isRunning).firstOrNull;

  Duration get focusToday {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return _focusSessions.fold(
      Duration.zero,
      (total, session) => total + session.lengthOnDay(today, now),
    );
  }

  FocusStats focusStats({String? blockId}) =>
      FocusStats.from(_focusSessions, _now(), blockId: blockId);

  /// The clock focus sessions are stamped with. Screens measure against it
  /// too, so a timer never disagrees with the credit it is earning.
  DateTime focusNow() => _now();

  Duration focusLengthOf(FocusSession session) => session.lengthAt(_now());

  /// Blocks whose unlock is bought with focus time, which is what puts the
  /// timer and stats buttons on a card.
  static bool hasFocusCondition(Block block) =>
      block.conditions.any((condition) => condition is FocusCondition);

  /// True when the device clock has been wound back behind time this app has
  /// already seen. Surfaced rather than silently corrected: unexplained
  /// over-blocking reads as a bug, a named warning reads as the product working.
  bool clockTampered = false;

  BlockDecision? decisionFor(String blockId) =>
      _plan?.decisions.where((d) => d.blockId == blockId).firstOrNull;

  Block? blockById(String id) =>
      _blocks.where((block) => block.id == id).firstOrNull;

  // Lifecycle ----------------------------------------------------------------

  Future<void> init() async {
    final local = await _store;

    // Merge rather than replace. A block created while storage was still
    // opening is already in memory and has no copy on disk yet; clearing the
    // list here is exactly how it used to disappear.
    final stored = local.loadBlocks();
    final known = _blocks.map((block) => block.id).toSet();
    _blocks.insertAll(0, stored.where((block) => !known.contains(block.id)));

    _signals = _signals.copyWith(grants: local.loadGrants());
    emergencyUnlocks = local.loadEmergencyUnlocks();
    theme = AppThemeChoice.fromName(local.loadThemeChoice());
    // Only a saved choice replaces the default; nothing saved keeps it.
    if (local.loadWaveMotion() case final saved?) {
      waveMotion = WaveMotion.fromName(saved);
    }
    hardMode = local.loadHardMode();
    protectionLock = local.loadProtectionLock();

    _focusSessions
      ..clear()
      ..addAll(local.loadFocusSessions());
    _activitySessions
      ..clear()
      ..addAll(local.loadActivitySessions());

    pageLock = local.loadPageLock();
    // Hydrate persisted commitments before yielding: a concurrent add must not
    // save a partial block or grant list over the loaded state.
    await _refreshClock();
    _signals = _signals.copyWith(
      placeCheckIns: local.loadPlaceCheckIns(_now()),
    );
    weeklyReport = await _channel.weeklyReportEnabled();
    try {
      installInfo = await _channel.installInfo();
    } catch (error) {
      debugPrint('control: could not read install source: $error');
    }
    // A session that was running when the app died keeps running: the clock
    // did not stop just because the process did. A pomodoro that finished in
    // the meantime is closed at its finish line.
    final carried = runningFocus;
    if (carried != null && carried.isComplete(_now())) {
      lastFinishedFocus = _closeFocus(carried, _now());
      await _persistFocus();
    }
    _updateTicker();
    _updateActivityTicker();
    unawaited(_syncFocusNotification());
    await _channel.setHardMode(hardMode);

    notifyListeners();
    if (_blocks.length != stored.length) await _persistBlocks();
    await refreshAll();
  }

  /// Everything that can change while the app was in the background.
  Future<void> refreshAll() async {
    await _refreshClock();
    await refreshPermissions();
    await refreshSignals();
    await refreshThoughts();
    await refreshInsights();
  }

  // Parked thoughts ------------------------------------------------------------
  //
  // Written on the block screen with Flutter asleep, so the native store is
  // the only copy; this is a view of it, re-read on resume and every few
  // seconds while the app is open, which is how a thought moves to Ready the
  // moment its block lifts.

  List<ParkedThought> thoughts = const [];

  /// Open thoughts, the number beside Thoughts in the drawer.
  int get openThoughtCount =>
      thoughts.where((thought) => !thought.isDone).length;

  Future<void> refreshThoughts() async {
    try {
      final next = await _channel.thoughts();
      if (listEquals(next, thoughts)) return;
      thoughts = next;
      notifyListeners();
    } catch (error) {
      debugPrint('control: could not read parked thoughts: $error');
    }
  }

  Future<void> _thoughtChange(Future<void> Function() change) async {
    try {
      await change();
    } catch (error) {
      debugPrint('control: could not change a parked thought: $error');
    }
    await refreshThoughts();
  }

  Future<void> addThought(String text) {
    if (text.trim().isEmpty) return Future.value();
    return _thoughtChange(() => _channel.addThought(text.trim()));
  }

  Future<void> updateThought(String id, String text) {
    if (text.trim().isEmpty) return Future.value();
    return _thoughtChange(() => _channel.updateThought(id, text.trim()));
  }

  /// Ticked off, or back to open.
  Future<void> setThoughtDone(String id, {required bool done}) {
    // Moves at once; the write follows.
    thoughts = [
      for (final thought in thoughts)
        thought.id == id
            ? ParkedThought.fromChannel({
                    'json': _withDoneAt(thought.raw, done ? wallClock() : null),
                    'blockedNow': thought.blockedNow,
                    'status': thought.status,
                  }) ??
                  thought
            : thought,
    ];
    notifyListeners();
    return _thoughtChange(() => _channel.setThoughtDone(id, done: done));
  }

  Future<void> deleteThought(ParkedThought thought) {
    thoughts = thoughts.where((other) => other.id != thought.id).toList();
    notifyListeners();
    return _thoughtChange(() => _channel.deleteThought(thought.id));
  }

  Future<void> restoreThought(ParkedThought thought) =>
      _thoughtChange(() => _channel.restoreThought(thought));

  Future<void> clearDoneThoughts() {
    thoughts = thoughts.where((thought) => !thought.isDone).toList();
    notifyListeners();
    return _thoughtChange(_channel.clearDoneThoughts);
  }

  Future<bool> openThoughtTarget(ParkedThought thought) async {
    try {
      return await _channel.openThoughtTarget(thought);
    } catch (error) {
      debugPrint('control: could not open ${thought.label}: $error');
      return false;
    }
  }

  /// The wall clock, for stamps the user reads. Overridable in previews.
  DateTime wallClock() => DateTime.now();

  static String _withDoneAt(String raw, DateTime? at) {
    try {
      final map = Map<String, Object?>.from(jsonDecode(raw) as Map);
      map['doneAt'] = at?.millisecondsSinceEpoch ?? 0;
      return jsonEncode(map);
    } catch (_) {
      return raw;
    }
  }

  Future<void> refreshPermissions() async {
    accessibilityEnabled = await _channel.isAccessibilityEnabled();
    usageAccessGranted = await _channel.hasUsageAccess();
    stepsStatus = await _channel.stepsStatus();
    locationStatus = await _channel.locationStatus();
    protection = await _channel.protectionStatus();
    try {
      notifications = await _channel.notificationStatus();
    } catch (error) {
      debugPrint('control: could not read notification access: $error');
    }
    try {
      health = await _channel.healthStatus();
    } catch (error) {
      debugPrint('control: could not read Health Connect: $error');
    }
    try {
      shieldFallbackAt = await _channel.lastShieldFallback();
    } catch (error) {
      debugPrint('control: could not read block screen health: $error');
    }

    // The guard keeps its own copy of the flag so it works with this isolate
    // dead. If the two ever disagree, the stored setting is the user's intent
    // and wins: a guard stuck on would make Settings unusable, and one stuck
    // off would be a silent hole.
    if (protection.hardMode != hardMode) {
      await _channel.setHardMode(hardMode);
      protection = await _channel.protectionStatus();
    }

    notifyListeners();
  }

  /// Re-reads every measured signal, then republishes.
  ///
  /// The engine always sees today, whatever window Insights happens to be
  /// showing: a condition earned this morning must not be satisfied by last
  /// week's usage.
  Future<void> refreshSignals() async {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);

    final todayUsage = usageAccessGranted
        ? await _channel.usageSnapshot(
            start: today,
            end: DateTime(now.year, now.month, now.day + 1),
          )
        : const UsageSnapshot.empty();

    // Insights and the widget describe the wall-calendar day. A protection
    // clock may intentionally differ after a clock edit; don't feed that
    // display-only adjustment back into habit measurements.
    final wallNow = DateTime.now();
    final wallToday = DateTime(wallNow.year, wallNow.month, wallNow.day);
    usage = usageAccessGranted && wallToday != today
        ? await _channel.usageSnapshot(
            start: wallToday,
            end: DateTime(wallNow.year, wallNow.month, wallNow.day + 1),
          )
        : todayUsage;

    final steps = stepsStatus.usable ? await _channel.stepsToday() : 0;
    final shortcuts = await _channel.shortcutCounts();
    await _refreshHealthSessions(now);
    final local = await _store;

    _signals = _signals.copyWith(
      appUsageToday: {for (final app in todayUsage.apps) app.id: app.duration},
      stepsToday: steps,
      shortcutCounts: shortcuts,
      focusToday: focusToday,
      workoutToday: activityToday(ActivityKind.workout),
      mindfulToday: activityToday(ActivityKind.meditate),
      // Reloaded rather than kept, so a check-in stops counting at midnight
      // even if the app was never closed.
      placeCheckIns: local.loadPlaceCheckIns(now),
    );
    _signalsDay = today;

    notifyListeners();
    await publish();
  }

  /// Steps alone, for a live count while the app is open: cheaper than
  /// [refreshSignals], which re-reads usage too. Only when a rule counts steps.
  Future<void> refreshSteps() async {
    if (!stepsStatus.usable || !_blocks.any(_countsSteps)) return;
    final now = _now();
    if (_signalsDay != DateTime(now.year, now.month, now.day)) {
      // A new day resets every daily signal; that is the full refresh's job.
      await refreshSignals();
      return;
    }
    final steps = await _channel.stepsToday();
    if (steps == _signals.stepsToday) return;
    _signals = _signals.copyWith(stepsToday: steps);
    notifyListeners();
    await publish();
  }

  /// What the open app re-reads every few seconds: steps, and whether a
  /// check-in window has just opened or closed, which shows or hides its
  /// button with nothing else changing.
  Future<void> refreshLive() async {
    await refreshSteps();
    await refreshThoughts();
    final windows = [
      for (final (_, condition) in placeConditions())
        isCheckInWindowOpen(condition),
    ];
    if (!listEquals(windows, _checkInWindows)) {
      _checkInWindows = windows;
      notifyListeners();
    }
  }

  List<bool> _checkInWindows = const [];

  static bool _countsSteps(Block block) =>
      block.enabled &&
      block.conditions.any((condition) => condition is StepsCondition);

  /// Clears the block-screen warning once its fix has been looked at.
  Future<void> dismissShieldFallback() async {
    shieldFallbackAt = null;
    notifyListeners();
    try {
      await _channel.clearShieldHealth();
    } catch (error) {
      debugPrint('control: could not clear block screen health: $error');
    }
  }

  Future<void> setInsightsRange(InsightsRange range) async {
    if (range == insightsRange) return;
    insightsRange = range;
    insightsUsage = const UsageSnapshot.empty();
    insightsUpdatedAt = null;
    await refreshInsights();
  }

  Future<void> refreshInsights() async {
    if (_disposed) return;
    final generation = ++_insightsGeneration;
    final range = insightsRange;
    insightsError = null;
    if (!usageAccessGranted) {
      insightsUsage = const UsageSnapshot.empty();
      insightsUpdatedAt = null;
      insightsLoading = false;
      insightsError = 'Grant usage access to see screen time.';
      notifyListeners();
      return;
    }

    insightsLoading = true;
    notifyListeners();
    try {
      // Android event timestamps follow wall time, not the protection clock.
      final now = DateTime.now();
      final snapshot = await _channel.usageTimeline(
        start: range.startFrom(now),
        end: now,
        bucket: range == InsightsRange.day ? 'hour' : 'day',
      );
      if (_disposed || generation != _insightsGeneration) return;
      insightsUsage = snapshot;
      insightsUpdatedAt = DateTime.now();
    } catch (error) {
      if (_disposed || generation != _insightsGeneration) return;
      insightsUsage = const UsageSnapshot.empty();
      insightsUpdatedAt = null;
      if (error is PlatformException && error.code == 'permission_denied') {
        usageAccessGranted = false;
        insightsError = 'Grant usage access to see screen time.';
      } else {
        insightsError = 'Could not load screen time. Please try again.';
        debugPrint('control: could not load usage history: $error');
      }
    } finally {
      if (!_disposed && generation == _insightsGeneration) {
        insightsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadInstalledApps() async {
    installedApps = await _channel.installedApps();
    notifyListeners();
  }

  // Blocks -------------------------------------------------------------------

  Future<void> addBlock(Block block) async {
    _blocks.add(block);
    await _persistBlocks();
    await publish();
  }

  /// Applies an edit, refusing the parts a lock protects.
  ///
  /// A locked block can still be renamed and re-iconed: those change nothing
  /// about what it blocks, and refusing them would be pedantry rather than
  /// commitment. Everything else waits for the lock.
  Future<LockVerdict> updateBlock(Block updated) async {
    final existing = blockById(updated.id);
    if (existing == null) return LockVerdict.allowed;

    if (!_isAllowedWhileLocked(existing, updated)) {
      final verdict = _lockPolicy.verdict(
        block: existing,
        change: BlockChange.weaken,
        now: _now(),
      );
      if (verdict != LockVerdict.allowed) return verdict;
    }

    // The lock itself is never carried in from the editor.
    _replace(existing, updated.copyWith(lock: existing.lock));
    await _persistBlocks();
    await publish();
    return LockVerdict.allowed;
  }

  /// Whether an edit is safe to apply to a locked block.
  ///
  /// Name and icon change nothing about the commitment. Adding apps or sites
  /// makes the block stricter, and refusing that would be perverse: locking a
  /// block should never be a reason you cannot tighten it further. Removing
  /// either is the escape hatch, so that still waits for the lock.
  static bool _isAllowedWhileLocked(Block before, Block after) =>
      before.mode == after.mode &&
      before.enabled == after.enabled &&
      after.apps.containsAll(before.apps) &&
      after.blockedDomains.containsAll(before.blockedDomains) &&
      after.categories.containsAll(before.categories) &&
      before.excludedApps.containsAll(after.excludedApps) &&
      before.blockAgainAfter == after.blockAgainAfter &&
      before.schedulePolarity == after.schedulePolarity &&
      before.zonePolarity == after.zonePolarity &&
      before.devicePolarity == after.devicePolarity &&
      before.zone == after.zone &&
      listEquals(before.devices, after.devices) &&
      listEquals(
        before.schedule.map(_rangeKey).toList(),
        after.schedule.map(_rangeKey).toList(),
      ) &&
      listEquals(
        before.conditions.map(_conditionKey).toList(),
        after.conditions.map(_conditionKey).toList(),
      );

  static String _rangeKey(TimeRange range) =>
      '${range.startMinute}-${range.endMinute}-'
      '${(range.weekdays.toList()..sort()).join(',')}';

  static String _conditionKey(UnlockCondition condition) => switch (condition) {
    StepsCondition() => 'steps:${condition.targetSteps}',
    WorkoutCondition() => 'workout:${condition.target.inSeconds}',
    MeditateCondition() => 'meditate:${condition.target.inSeconds}',
    AppTimeCondition() =>
      'appTime:${condition.target.inSeconds}:'
          '${(condition.apps.toList()..sort()).join(',')}',
    FocusCondition() => 'focus:${condition.target.inSeconds}',
    PlaceCheckInCondition() =>
      'place:${condition.zone.center.latitude}:'
          '${condition.zone.center.longitude}:${condition.zone.radiusMeters}:'
          '${_rangeKey(condition.window)}',
    ShortcutCondition() =>
      'shortcut:${condition.channel}:${condition.requiredCount}',
  };

  /// Deleting is a weakening change, so a locked block refuses it.
  Future<LockVerdict> removeBlock(String id) async {
    final block = blockById(id);
    if (block == null) return LockVerdict.allowed;

    final verdict = _lockPolicy.verdict(
      block: block,
      change: BlockChange.weaken,
      now: _now(),
    );
    if (verdict != LockVerdict.allowed) return verdict;

    _blocks.removeWhere((b) => b.id == id);
    await _persistBlocks();
    await publish();
    return LockVerdict.allowed;
  }

  /// Turning a block off is the easiest possible bypass, so it runs through the
  /// same lock check as deleting one. Turning a block back on always works.
  Future<LockVerdict> setEnabled(String id, bool enabled) async {
    final block = blockById(id);
    if (block == null) return LockVerdict.allowed;

    if (!enabled) {
      final verdict = _lockPolicy.verdict(
        block: block,
        change: BlockChange.weaken,
        now: _now(),
      );
      if (verdict != LockVerdict.allowed) return verdict;
    }

    _replace(block, block.copyWith(enabled: enabled));
    await _persistBlocks();
    await publish();
    return LockVerdict.allowed;
  }

  // Locks --------------------------------------------------------------------

  /// Arms an unlocked block. An existing lock must be released first; replacing
  /// it with a shorter deadline or a known password would weaken protection.
  Future<void> lockBlock(
    String id, {
    Duration? duration,
    String? password,
  }) async {
    final block = blockById(id);
    if (block == null || isLocked(block)) return;
    if (duration != null && duration <= Duration.zero) return;

    final lock = duration != null
        ? Lock.timed(
            until: _now().add(duration),
            passwordHash: password == null ? null : Password.hash(password),
          )
        : Lock.password(Password.hash(password!));

    _replace(block, block.copyWith(lock: lock));
    await _persistBlocks();
  }

  /// Releases a password lock. Returns false on a wrong password, and also on a
  /// timed lock that has not expired, where no password is the right one.
  Future<bool> unlockBlock(String id, String password) async {
    final block = blockById(id);
    if (block == null) return false;

    final verdict = _lockPolicy.verdict(
      block: block,
      change: BlockChange.unlock,
      now: _now(),
    );
    if (verdict == LockVerdict.refused) return false;
    if (verdict == LockVerdict.needsPassword &&
        !Password.verify(password, block.lock.passwordHash)) {
      return false;
    }

    _replace(block, block.copyWith(lock: const Lock.none()));
    await _persistBlocks();
    return true;
  }

  /// Spends one emergency unlock to break a timed lock.
  ///
  /// The pool never refills, which is the whole design: an escape hatch that
  /// renews just teaches you to wait for it.
  Future<bool> useEmergencyUnlock(String id) async {
    final block = blockById(id);
    if (block == null) return false;

    final result = emergencyUnlocks.consume();
    if (!result.granted) return false;

    emergencyUnlocks = result.pool;
    _replace(block, block.copyWith(lock: const Lock.none()));

    final local = await _store;
    await local.saveEmergencyUnlocks(emergencyUnlocks);
    await _persistBlocks();
    return true;
  }

  Duration? lockRemaining(Block block) =>
      _lockPolicy.remaining(block: block, now: _now());

  /// Whether an edit sheet should hold everything but name and icon shut.
  bool isLocked(Block block) =>
      _lockPolicy.verdict(
        block: block,
        change: BlockChange.weaken,
        now: _now(),
      ) !=
      LockVerdict.allowed;

  // Focus timer --------------------------------------------------------------
  //
  // Every method changes memory and notifies before its first await, so a
  // button can act and a sheet can move on at once; the file write, the
  // notification and the enforcement publish follow on their own.

  /// Starts a session. Only one runs at a time: two timers counting the same
  /// minutes would be a way to buy an unlock twice over.
  Future<void> startFocus(
    String blockId, {
    required FocusKind kind,
    Duration? plannedWork,
  }) async {
    final previous = runningFocus;
    if (previous != null) _closeFocus(previous, _now());
    focusBreak = null;
    breakOverFor = null;
    lastFinishedFocus = null;

    _focusSessions.add(
      FocusSession(
        blockId: blockId,
        startedAt: _now(),
        kind: kind,
        plannedWork: kind == FocusKind.pomodoro
            ? (plannedWork ?? const Duration(minutes: 25))
            : null,
      ),
    );
    _updateTicker();
    if (!_askedFocusNotifications) {
      _askedFocusNotifications = true;
      _askForNotifications();
    }
    notifyListeners();
    await _persistFocus();
    await _syncFocusNotification();
    await publish();
  }

  /// Holds the running session. Paused time is not credited.
  Future<void> pauseFocus() async {
    final running = runningFocus;
    if (running == null || running.isPaused) return;
    _replaceFocus(running, running.pausedAt(_now()));
    _updateTicker();
    notifyListeners();
    await _persistFocus();
    await _syncFocusNotification();
  }

  Future<void> resumeFocus() async {
    final running = runningFocus;
    if (running == null || !running.isPaused) return;
    _replaceFocus(running, running.resumedAt(_now()));
    _updateTicker();
    notifyListeners();
    await _persistFocus();
    await _syncFocusNotification();
  }

  /// Ends the running session and keeps it as the one just finished, so the
  /// timer sheet can show what was banked.
  Future<void> stopFocus() async {
    final running = runningFocus;
    if (running == null) return;
    lastFinishedFocus = _closeFocus(running, _now());
    notifyListeners();
    await _persistFocus();
    await _syncFocusNotification();
    // The finished minutes may have just bought an unlock.
    await refreshSignals();
  }

  /// Pomodoros finished today, across blocks. Every fourth earns a long break.
  int get pomodorosToday {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return _focusSessions
        .where(
          (session) =>
              session.kind == FocusKind.pomodoro &&
              !session.isRunning &&
              session.isComplete(now) &&
              !session.startedAt.isBefore(today),
        )
        .length;
  }

  /// Five minutes, or fifteen after every fourth pomodoro of the day.
  Duration get nextBreakLength {
    final done = pomodorosToday;
    return done > 0 && done % 4 == 0
        ? const Duration(minutes: 15)
        : const Duration(minutes: 5);
  }

  Future<void> startBreak() async {
    final blockId = lastFinishedFocus?.blockId ?? runningFocus?.blockId;
    if (blockId == null) return;
    focusBreak = FocusBreak(
      blockId: blockId,
      startedAt: _now(),
      length: nextBreakLength,
    );
    lastFinishedFocus = null;
    breakOverFor = null;
    _updateTicker();
    notifyListeners();
    await _syncFocusNotification();
  }

  Future<void> skipBreak() async {
    focusBreak = null;
    dismissFocusResult();
    _updateTicker();
    await _syncFocusNotification();
  }

  /// Clears the finished-session and break-over messages.
  void dismissFocusResult() {
    lastFinishedFocus = null;
    breakOverFor = null;
    notifyListeners();
  }

  FocusSession _closeFocus(FocusSession running, DateTime now) {
    // A pomodoro that finished while nobody was watching closes at its finish
    // line, so its minutes land on the day they were actually worked.
    final closed = running.stoppedAt(running.completedAt(now) ?? now);
    _replaceFocus(running, closed);
    _updateTicker();
    return closed;
  }

  void _replaceFocus(FocusSession before, FocusSession after) {
    final index = _focusSessions.indexOf(before);
    if (index >= 0) _focusSessions[index] = after;
  }

  /// Ticks while something is counting: a session that is not paused, or a
  /// break. A paused session has nothing to redraw.
  void _updateTicker() {
    final running = runningFocus;
    final needed = (running != null && !running.isPaused) || focusBreak != null;
    if (!needed) {
      _stopTicker();
      return;
    }
    _focusTicker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = _now();
    final running = runningFocus;
    if (running != null && running.isComplete(now)) {
      // A pomodoro closes itself the moment it has served its time, so the
      // reward does not depend on the user being there to press stop.
      unawaited(_completePomodoro(running, now));
      return;
    }
    if (running != null && _crossedFocusTarget()) {
      // Unlock the moment the goal is met, not when stop is finally pressed.
      unawaited(_publishFocusProgress());
    } else if (running != null && !running.isPaused) {
      _refreshLiveProgress();
    }
    final pause = focusBreak;
    if (pause != null && pause.isOver(now)) {
      focusBreak = null;
      breakOverFor = pause.blockId;
      _updateTicker();
      unawaited(HapticFeedback.heavyImpact());
      unawaited(_finishFocusNotification());
    }
    notifyListeners();
  }

  Future<void> _completePomodoro(FocusSession running, DateTime now) async {
    final closed = _closeFocus(running, now);
    lastFinishedFocus = closed;
    unawaited(HapticFeedback.heavyImpact());
    notifyListeners();
    // Android may have announced it already, from the foreground service or
    // its alarm; this announces it only if not, and takes the timer down.
    await _finishFocusNotification();
    await _persistFocus();
    await refreshSignals();
  }

  /// Focus totals already handed to the engine, for spotting a goal crossed
  /// mid-session.
  Duration _publishedFocus = Duration.zero;

  bool _crossedFocusTarget() {
    final today = focusToday;
    return _blocks.any(
      (block) =>
          block.enabled &&
          block.conditions.whereType<FocusCondition>().any(
            (condition) =>
                _publishedFocus < condition.target && today >= condition.target,
          ),
    );
  }

  Future<void> _publishFocusProgress() async {
    _publishedFocus = focusToday;
    _signals = _signals.copyWith(focusToday: _publishedFocus);
    await publish();
  }

  void _stopTicker() {
    _focusTicker?.cancel();
    _focusTicker = null;
  }

  Future<void> _persistFocus() async {
    _publishedFocus = focusToday;
    _signals = _signals.copyWith(focusToday: _publishedFocus);
    notifyListeners();
    final local = await _store;
    await local.saveFocusSessions(_focusSessions, _now());
  }

  /// Mirrors the timer into Android: a foreground service with a clock Android
  /// runs itself, counting down for a pomodoro or a break and up for a
  /// stopwatch, and the words for announcing the end, so the end is announced
  /// on time whether or not this isolate is still alive.
  Future<void> _syncFocusNotification() async {
    final running = runningFocus;
    final pause = focusBreak;
    final now = _now();
    // The notification clock is the wall clock, whatever the protection clock
    // says; only the remaining span comes from the session.
    final wall = DateTime.now();
    try {
      if (running != null) {
        final name = blockById(running.blockId)?.name ?? 'Focus';
        final length = running.lengthAt(now);
        final remaining = running.remainingAt(now);
        if (running.isPaused) {
          await _channel.showFocusTimer(
            title: 'Paused: $name',
            text: '${formatClock(length)} focused so far. Open to resume.',
          );
        } else if (remaining != null) {
          await _channel.showFocusTimer(
            title: name,
            text: 'Pomodoro, ${formatDuration(running.plannedWork!)}',
            clockAt: wall.add(remaining),
            countDown: true,
            endsAt: wall.add(remaining),
            doneTitle: 'Pomodoro done',
            doneText:
                '${formatDuration(running.plannedWork!)} banked for $name. '
                'Time for a break.',
          );
        } else {
          await _channel.showFocusTimer(
            title: name,
            text: 'Stopwatch',
            clockAt: wall.subtract(length),
          );
        }
      } else if (pause != null) {
        final name = blockById(pause.blockId)?.name ?? 'focus';
        final ends = wall.add(pause.remainingAt(now));
        await _channel.showFocusTimer(
          title: 'Break',
          text: 'Back to $name after.',
          clockAt: ends,
          countDown: true,
          endsAt: ends,
          doneTitle: 'Break over',
          doneText: 'Ready for the next $name session.',
        );
      } else if (runningActivity case final activity?) {
        // The workout or meditation timer shares the one ongoing
        // notification; a focus session, when there is one, comes first.
        await _channel.showFocusTimer(
          title: activity.kind.label,
          text: 'Timer running. Open Control to stop it.',
          clockAt: wall.subtract(activity.lengthAt(now)),
        );
      } else {
        await _channel.cancelFocusTimer();
      }
    } catch (error) {
      debugPrint('control: could not update the focus notification: $error');
    }
  }

  Future<void> _finishFocusNotification() async {
    try {
      await _channel.finishFocusTimer();
    } catch (error) {
      debugPrint('control: could not finish the focus notification: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _insightsGeneration++;
    _stopTicker();
    _activityTicker?.cancel();
    super.dispose();
  }

  // Page lock ----------------------------------------------------------------
  //
  // A PIN in front of chosen pages. What has been unlocked is remembered for
  // this session only: leaving the app, or Lock now, closes every page again.

  PageLock pageLock = const PageLock();
  final Set<String> _unlockedPages = {};

  /// Key for the lock's own controls in Settings, which need the PIN too.
  static const _lockSettingsKey = '#settings';

  /// Whether [page] is behind the PIN right now.
  bool isPageLocked(String page) =>
      pageLock.enabled &&
      pageLock.pages.contains(page) &&
      !_unlockedPages.contains(page);

  /// True when a locked page is open, which is when Lock now has work to do.
  bool get hasUnlockedPages => _unlockedPages.any(pageLock.pages.contains);

  /// Opens [page] if [pin] is right.
  bool unlockPage(String page, String pin) {
    if (!pageLock.verify(pin)) return false;
    _unlockedPages.add(page);
    notifyListeners();
    return true;
  }

  /// Closes every page again, and the lock's settings with them.
  void lockPages() {
    if (_unlockedPages.isEmpty) return;
    _unlockedPages.clear();
    notifyListeners();
  }

  /// With no PIN set there is nothing to guard the settings with.
  bool get lockSettingsOpen =>
      !pageLock.enabled || _unlockedPages.contains(_lockSettingsKey);

  bool unlockLockSettings(String pin) => unlockPage(_lockSettingsKey, pin);

  /// Sets or changes the PIN. Whoever just chose it has proved they know it,
  /// so the settings stay open.
  Future<void> setPin(String pin) async {
    pageLock = pageLock.withPin(pin);
    _unlockedPages.add(_lockSettingsKey);
    notifyListeners();
    final local = await _store;
    await local.savePageLock(pageLock);
  }

  /// Removes the PIN, and with it every page's lock.
  Future<void> clearPin() async {
    pageLock = const PageLock();
    _unlockedPages.clear();
    notifyListeners();
    final local = await _store;
    await local.savePageLock(pageLock);
  }

  Future<void> setPageLocked(String page, {required bool locked}) async {
    if (!pageLock.enabled) return;
    pageLock = pageLock.withPage(page, locked: locked);
    notifyListeners();
    final local = await _store;
    await local.savePageLock(pageLock);
  }

  void _askForNotifications() => unawaited(
    _channel.requestNotificationPermission().catchError((Object error) {
      debugPrint('control: could not ask for notifications: $error');
    }),
  );

  // Place check-ins ----------------------------------------------------------

  /// Every place condition on every enabled block, with the block it came from.
  List<(Block, PlaceCheckInCondition)> placeConditions() => [
    for (final block in _blocks)
      for (final condition in block.conditions)
        if (condition is PlaceCheckInCondition) (block, condition),
  ];

  bool isCheckedIn(PlaceCheckInCondition condition) =>
      _signals.placeCheckIns.contains(condition.id);

  /// True while the window is open, whatever the location is. Drives whether
  /// the button on the card is worth showing at all.
  bool isCheckInWindowOpen(PlaceCheckInCondition condition) =>
      condition.window.contains(_now());

  Future<CheckInResult> checkInPlace(String conditionId) async {
    final condition = placeConditions()
        .map((entry) => entry.$2)
        .where((c) => c.id == conditionId)
        .firstOrNull;
    if (condition == null) return CheckInResult.unknownCondition;

    final now = _now();
    if (!condition.window.contains(now)) return CheckInResult.outsideWindow;

    // Read now, not at the last resume: location is often switched on from
    // the quick settings without ever leaving the app.
    try {
      locationStatus = await _channel.locationStatus();
    } catch (error) {
      debugPrint('control: could not read location status: $error');
    }
    if (locationStatus.approximateOnly) return CheckInResult.approximateOnly;
    if (!locationStatus.granted) return CheckInResult.noPermission;
    if (!locationStatus.enabled) return CheckInResult.locationOff;

    final fix = await _channel.currentLocation();
    lastCheckInFix = fix;
    if (fix == null) return CheckInResult.noFix;
    if (fix.mock) return CheckInResult.mockLocation;
    final reading = fix.reading;

    // The condition decides, not this method: the same rule has to hold
    // wherever it is asked.
    if (!condition.canCheckIn(reading, now)) {
      // Too far only when even the nearest edge of the error circle is
      // outside. A cell-tower fix accurate to 800 m whose centre lands 500 m
      // off says nothing about where you are; calling that "too far" sent
      // people walking when the fix was the problem.
      final distance = condition.zone.center.distanceTo(reading.point);
      return distance - reading.accuracyMeters > condition.zone.radiusMeters
          ? CheckInResult.tooFar
          : CheckInResult.fixTooVague;
    }

    final checkIns = {..._signals.placeCheckIns, condition.id};
    _signals = _signals.copyWith(placeCheckIns: checkIns);

    final local = await _store;
    await local.savePlaceCheckIns(checkIns, now);
    await refreshSignals();
    return CheckInResult.success;
  }

  /// The fix the last check-in was judged on, so a refusal can say how far
  /// off it was rather than just that it failed.
  LocationFix? lastCheckInFix;

  Future<void> requestLocationPermission() =>
      _channel.requestLocationPermission();

  /// One fix for the editor, so a zone can be dropped where the user is
  /// standing without a map.
  Future<GeoReading?> currentLocation() async =>
      (await _channel.currentLocation())?.reading;

  // Workout and meditation ---------------------------------------------------
  //
  // Two sources, merged: sessions other apps recorded in Health Connect, and
  // Control's own timer. Merged as time intervals, so a workout recorded in
  // both at once counts once.

  HealthStatus health = const HealthStatus.unknown();
  List<(DateTime, DateTime)> _healthWorkout = const [];
  List<(DateTime, DateTime)> _healthMindful = const [];

  final List<ActivitySession> _activitySessions = [];
  Timer? _activityTicker;

  ActivitySession? get runningActivity =>
      _activitySessions.where((session) => session.isRunning).firstOrNull;

  /// Blocks with a Workout or Meditate condition.
  static bool usesActivity(Block block, ActivityKind kind) =>
      block.conditions.any(
        (condition) => switch (kind) {
          ActivityKind.workout => condition is WorkoutCondition,
          ActivityKind.meditate => condition is MeditateCondition,
        },
      );

  bool get _anyActivityRule => _blocks.any(
    (block) =>
        block.enabled &&
        (usesActivity(block, ActivityKind.workout) ||
            usesActivity(block, ActivityKind.meditate)),
  );

  /// Today's minutes of [kind], from both sources, overlap counted once.
  Duration activityToday(ActivityKind kind) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return coveredTime(
      [
        for (final session in _activitySessions)
          if (session.kind == kind) (session.startedAt, session.end(now)),
        ...switch (kind) {
          ActivityKind.workout => _healthWorkout,
          ActivityKind.meditate => _healthMindful,
        },
      ],
      today,
      now,
    );
  }

  /// Today's minutes of [kind] recorded in Health Connect alone.
  Duration healthToday(ActivityKind kind) {
    final now = _now();
    return coveredTime(
      switch (kind) {
        ActivityKind.workout => _healthWorkout,
        ActivityKind.meditate => _healthMindful,
      },
      DateTime(now.year, now.month, now.day),
      now,
    );
  }

  Duration activityLengthOf(ActivitySession session) =>
      session.lengthAt(_now());

  Future<void> _refreshHealthSessions(DateTime now) async {
    if (!health.connected || !_anyActivityRule) {
      _healthWorkout = const [];
      _healthMindful = const [];
      return;
    }
    try {
      final sessions = await _channel.healthSessions(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime.now(),
      );
      _healthWorkout = sessions.workout;
      _healthMindful = sessions.mindful;
    } catch (error) {
      // A Health Connect hiccup must not take the other signals down with it.
      debugPrint('control: could not read Health Connect sessions: $error');
    }
  }

  /// Starts the timer for [kind]. One at a time: starting one stops another.
  Future<void> startActivity(ActivityKind kind) async {
    final now = _now();
    final previous = runningActivity;
    if (previous != null) _replaceActivity(previous, previous.stoppedAt(now));
    _activitySessions.add(ActivitySession(kind: kind, startedAt: now));
    _updateActivityTicker();
    if (!_askedFocusNotifications) {
      _askedFocusNotifications = true;
      _askForNotifications();
    }
    notifyListeners();
    await _persistActivities();
    await _syncFocusNotification();
  }

  /// Banks the running timer and publishes, since it may have earned an
  /// unlock.
  Future<void> stopActivity() async {
    final running = runningActivity;
    if (running == null) return;
    _replaceActivity(running, running.stoppedAt(_now()));
    _updateActivityTicker();
    notifyListeners();
    await _persistActivities();
    await _syncFocusNotification();
    await _publishActivityProgress();
  }

  void _replaceActivity(ActivitySession before, ActivitySession after) {
    final index = _activitySessions.indexOf(before);
    if (index >= 0) _activitySessions[index] = after;
  }

  void _updateActivityTicker() {
    if (runningActivity == null) {
      _activityTicker?.cancel();
      _activityTicker = null;
      return;
    }
    _activityTicker ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _activityTick(),
    );
  }

  void _activityTick() {
    final running = runningActivity;
    if (running == null) {
      _updateActivityTicker();
      return;
    }
    final now = _now();
    if (running.lengthAt(now) >= ActivitySession.maxLength) {
      // Forgotten, not a four-hour workout: close it at its cap.
      unawaited(stopActivity());
      return;
    }
    if (_crossedActivityTarget()) {
      unawaited(_publishActivityProgress());
    } else {
      _refreshLiveProgress();
    }
    notifyListeners();
  }

  /// Progress bars follow a running timer second by second. Decisions are
  /// re-evaluated in memory only: without a grant a block stays blocked, so
  /// nothing is unlocked or handed to Android until a goal is crossed, which
  /// publishes properly.
  void _refreshLiveProgress() {
    final now = _now();
    if (_signalsDay != DateTime(now.year, now.month, now.day)) return;
    _signals = _signals.copyWith(
      focusToday: focusToday,
      workoutToday: activityToday(ActivityKind.workout),
      mindfulToday: activityToday(ActivityKind.meditate),
    );
    _plan = _engine.plan(blocks: _blocks, signals: _signals, now: now);
  }

  /// The signals as last handed to the engine for real. Live progress moves
  /// [_signals] every second; crossings are measured against this.
  Signals _published = const Signals();

  /// A Workout or Meditate goal reached by the running timer just now: unlock
  /// at once, not when stop is finally pressed.
  bool _crossedActivityTarget() {
    final workout = activityToday(ActivityKind.workout);
    final mindful = activityToday(ActivityKind.meditate);
    return _blocks.any(
      (block) =>
          block.enabled &&
          block.conditions.any(
            (condition) => switch (condition) {
              WorkoutCondition() =>
                _published.workoutToday < condition.target &&
                    workout >= condition.target,
              MeditateCondition() =>
                _published.mindfulToday < condition.target &&
                    mindful >= condition.target,
              _ => false,
            },
          ),
    );
  }

  Future<void> _publishActivityProgress() async {
    _signals = _signals.copyWith(
      workoutToday: activityToday(ActivityKind.workout),
      mindfulToday: activityToday(ActivityKind.meditate),
    );
    notifyListeners();
    await publish();
  }

  Future<void> _persistActivities() async {
    final local = await _store;
    await local.saveActivitySessions(_activitySessions, _now());
  }

  Future<bool> requestHealthPermissions() async {
    try {
      return await _channel.requestHealthPermissions();
    } catch (error) {
      debugPrint('control: could not ask Health Connect: $error');
      return false;
    }
  }

  Future<bool> openHealthConnect() async {
    try {
      return await _channel.openHealthConnect();
    } catch (error) {
      debugPrint('control: could not open Health Connect: $error');
      return false;
    }
  }

  // Protection ---------------------------------------------------------------

  /// Hard mode makes the accessibility service back out of the settings screens
  /// that lead to uninstalling or disabling Control.
  ///
  /// Turning it off is refused while any lock is active, for the same
  /// reason releasing device admin is: it is the first step of getting rid of
  /// the block.
  Future<bool> setHardMode(bool enabled) async {
    if (!enabled && (protectionLocked || _hasLiveLock())) return false;

    hardMode = enabled;
    notifyListeners();
    await _channel.setHardMode(enabled);
    final local = await _store;
    await local.saveHardMode(enabled);
    return true;
  }

  bool _hasLiveLock() => _blocks.any(isLocked);

  Future<DeviceOwnerStatus> deviceOwnerStatus() => _channel.deviceOwnerStatus();

  Future<void> requestDeviceAdmin() async {
    await _channel.requestDeviceAdmin();
  }

  Future<void> setUninstallBlocked(bool blocked) async {
    if (!blocked && (protectionLocked || _hasLiveLock())) return;
    await _channel.setUninstallBlocked(blocked);
    await refreshPermissions();
  }

  /// Refuses while any block is still locked. Releasing protection
  /// is the first step of uninstalling, which would clear every block: allowing
  /// it here would make the timed lock decorative.
  Future<bool> releaseProtection() async {
    if (protectionLocked || _hasLiveLock()) return false;

    await _channel.releaseProtection();
    await refreshPermissions();
    return true;
  }

  /// Arms the lock on uninstall protection. Turning protection on at the same
  /// time, if it is not already: locking an unarmed setting would be a promise
  /// with nothing behind it.
  Future<void> lockProtection({Duration? duration, String? password}) async {
    if (protectionLocked) return;
    if (duration != null && duration <= Duration.zero) return;
    protectionLock = duration != null
        ? Lock.timed(
            until: _now().add(duration),
            passwordHash: password == null ? null : Password.hash(password),
          )
        : Lock.password(Password.hash(password!));

    if (!hardMode) {
      hardMode = true;
      await _channel.setHardMode(true);
    }

    notifyListeners();
    final local = await _store;
    await local.saveHardMode(hardMode);
    await local.saveProtectionLock(protectionLock);
  }

  Future<bool> unlockProtection(String password) async {
    final verdict = _lockPolicy.verdict(
      block: _protectionCarrier,
      change: BlockChange.unlock,
      now: _now(),
    );
    if (verdict == LockVerdict.refused) return false;
    if (verdict == LockVerdict.needsPassword &&
        !Password.verify(password, protectionLock.passwordHash)) {
      return false;
    }

    await _clearProtectionLock();
    return true;
  }

  Future<bool> emergencyUnlockProtection() async {
    final result = emergencyUnlocks.consume();
    if (!result.granted) return false;

    emergencyUnlocks = result.pool;
    final local = await _store;
    await local.saveEmergencyUnlocks(emergencyUnlocks);
    await _clearProtectionLock();
    return true;
  }

  Future<void> _clearProtectionLock() async {
    protectionLock = const Lock.none();
    notifyListeners();
    final local = await _store;
    await local.saveProtectionLock(protectionLock);
  }

  // Preferences --------------------------------------------------------------

  Future<void> setTheme(AppThemeChoice choice) async {
    theme = choice;
    notifyListeners();
    final local = await _store;
    await local.saveThemeChoice(choice.name);
  }

  Future<void> setWaveMotion(WaveMotion motion) async {
    waveMotion = motion;
    notifyListeners();
    final local = await _store;
    await local.saveWaveMotion(motion.name);
  }

  Future<void> requestStepsPermission() => _channel.requestStepsPermission();

  /// The Settings row: prompt if Android still will, otherwise open the app's
  /// notification settings. Read back on the next resume.
  Future<void> fixNotifications() => _channel.fixNotifications();

  Future<void> openExactAlarmSettings() => _channel.openExactAlarmSettings();

  Future<int> fireShortcut(String channel) async {
    final count = await _channel.fireShortcut(channel);
    await refreshSignals();
    return count;
  }

  /// Opens the Accessibility screen. With [watch], a return to the app with
  /// App blocking still off is noticed: see [takeMissedAccess].
  Future<void> openAccessibilitySettings({bool watch = true}) {
    if (watch) _awaitingAccess = SpecialAccess.appBlocking;
    return _channel.openAccessibilitySettings();
  }

  Future<void> openUsageAccessSettings({bool watch = true}) {
    if (watch) _awaitingAccess = SpecialAccess.usageAccess;
    return _channel.openUsageAccessSettings();
  }

  Future<void> openSpecialAccess(SpecialAccess access, {bool watch = true}) =>
      switch (access) {
        SpecialAccess.appBlocking => openAccessibilitySettings(watch: watch),
        SpecialAccess.usageAccess => openUsageAccessSettings(watch: watch),
      };

  bool hasSpecialAccess(SpecialAccess access) => switch (access) {
    SpecialAccess.appBlocking => accessibilityEnabled,
    SpecialAccess.usageAccess => usageAccessGranted,
  };

  /// How Control was installed, which decides whether Android greys out its
  /// special-access switches. Read once at start.
  InstallInfo installInfo = const InstallInfo.unknown();

  /// The switch the user was just sent to Settings for.
  SpecialAccess? _awaitingAccess;

  /// After coming back to the app: the switch the user went to turn on and
  /// is still off, where restricted settings may be why. Reported once.
  SpecialAccess? takeMissedAccess() {
    final access = _awaitingAccess;
    _awaitingAccess = null;
    if (access == null || !installInfo.restrictedSettingsPossible) return null;
    return hasSpecialAccess(access) ? null : access;
  }

  Future<void> openAppInfo() => _channel.openAppInfo();

  Future<bool> openSystemScreen(SystemScreen screen) =>
      _channel.openSystemScreen(screen);

  // Engine -------------------------------------------------------------------

  /// Recomputes every decision and hands the union to the platform enforcer.
  ///
  /// Grants are minted first: a satisfied condition only frees apps once its
  /// grant exists, and the grant is what starts the re-arm clock.
  Future<void> publish({DateTime? at}) async {
    final now = at ?? _now();
    final today = DateTime(now.year, now.month, now.day);
    if (_signalsDay != today) {
      // Edits can publish without reading sensors. Yesterday's daily totals
      // must never mint today's allowance while those measurements are stale.
      _signals = _signals.copyWith(
        stepsToday: 0,
        workoutToday: Duration.zero,
        mindfulToday: Duration.zero,
        focusToday: Duration.zero,
        appUsageToday: {},
        placeCheckIns: {},
        shortcutCounts: {},
      );
      _signalsDay = today;
    }

    final grants = Map<String, UnlockGrant>.from(_signals.grants);
    // Android mints a steps allowance itself while this isolate is not
    // running. Adopted first, so the same walk is never paid out twice and
    // the allowance runs from when it was really earned.
    for (final MapEntry(key: id, value: native)
        in (await _nativeGrants()).entries) {
      final existing = grants[id];
      if (existing == null ||
          existing.grantedAt.isBefore(today) ||
          native.grantedAt.isBefore(existing.grantedAt)) {
        grants[id] = native;
      }
    }
    _signals = _signals.copyWith(grants: grants);
    for (final block in _blocks) {
      final grant = _engine.mintGrantIfEarned(
        block: block,
        signals: _signals,
        now: now,
      );
      if (grant != null) grants[block.id] = grant;
    }
    // Retain today's spent grants across restart so reopening Control cannot
    // mint another reward from the same cumulative habit measurements.
    grants.removeWhere(
      (id, grant) =>
          blockById(id) == null ||
          (!grant.isActive(now) && grant.grantedAt.isBefore(today)),
    );
    _signals = _signals.copyWith(grants: grants);

    final plan = _engine.plan(blocks: _blocks, signals: _signals, now: now);
    _plan = plan;
    _published = _signals;

    await _channel.applyPlan(
      plan,
      details: _detailsFor(plan),
      blocks: _blocks,
      grants: grants,
      stepGates: _stepGates(grants, today),
    );
    await _pushSummary(plan);
    notifyListeners();

    final local = await _store;
    await local.saveGrants(grants);
  }

  Future<Map<String, UnlockGrant>> _nativeGrants() async {
    try {
      return await _channel.nativeGrants();
    } catch (error) {
      debugPrint('control: could not read native allowances: $error');
      return const {};
    }
  }

  /// Blocks Android may unlock on its own by counting steps, with the steps
  /// it takes: those whose every other condition is already met today and
  /// that have not had today's allowance yet. The other conditions are daily
  /// totals that only grow, so they cannot come undone before midnight.
  Map<String, int> _stepGates(Map<String, UnlockGrant> grants, DateTime today) {
    final gates = <String, int>{};
    for (final block in _blocks) {
      if (!block.enabled || block.mode != LimitMode.condition) continue;
      final steps = block.conditions.whereType<StepsCondition>().toList();
      if (steps.isEmpty) continue;
      final grant = grants[block.id];
      if (grant != null && !grant.grantedAt.isBefore(today)) continue;
      final othersMet = block.conditions
          .where((condition) => condition is! StepsCondition)
          .every((condition) => condition.isMet(_signals));
      if (!othersMet) continue;
      gates[block.id] = steps
          .map((condition) => condition.targetSteps)
          .reduce(math.max);
    }
    return gates;
  }

  /// Feeds the widget, the tile and the weekly notification.
  ///
  /// Never allowed to fail anything. These are decorations on other surfaces:
  /// a widget that failed to refresh is worth a log line, and is not worth
  /// failing the save that triggered it. This threw once and left the editor
  /// sheet stuck open over a block that had already been created.
  Future<void> _pushSummary(EnforcementPlan plan) async {
    final stats = focusStats();

    try {
      await _channel.updateSummary(
        screenTime: formatDuration(usage.screenTime),
        focusToday: formatDuration(stats.today),
        blockedCount: plan.blockedApps.length,
        activeBlocks: _blocks.where((block) => block.enabled).length,
        weeklyReport: _weeklyLine(stats),
      );
    } catch (error) {
      debugPrint('control: could not update the widget summary: $error');
    }
  }

  /// One sentence, written here because the wording is a product decision and
  /// the receiver that shows it has no way to make one.
  String _weeklyLine(FocusStats stats) {
    final focus = formatDuration(stats.week);
    final blocks = _blocks.where((block) => block.enabled).length;

    if (stats.week == Duration.zero) {
      return 'No focus time logged this week. '
          '$blocks block${blocks == 1 ? '' : 's'} still standing.';
    }
    return '$focus focused this week, '
        'a ${stats.streakDays} day streak, and '
        '$blocks block${blocks == 1 ? '' : 's'} holding.';
  }

  Future<void> setWeeklyReport(bool enabled) async {
    weeklyReport = enabled;
    notifyListeners();
    if (enabled) await _channel.requestNotificationPermission();
    await _channel.setWeeklyReport(enabled);
  }

  Future<void> _refreshClock() async {
    final native = await _channel.enforcementTime();
    _timeAnchor = native ?? _now();
    _timeElapsed
      ..reset()
      ..start();
  }

  /// Share Android's persisted uptime anchor; wall-clock edits must not expire
  /// a lock in Flutter while native enforcement still considers it active.
  DateTime _now() {
    final systemNow = DateTime.now();
    final local = _local;
    if (local == null) return systemNow;

    final resolved = _clock.resolve(
      systemNow: _timeAnchor?.add(_timeElapsed.elapsed) ?? systemNow,
      highWaterMark: local.loadClockHighWaterMark(),
    );
    clockTampered =
        systemNow.difference(resolved).abs() > const Duration(minutes: 2);
    local.noteClockHighWaterMark(resolved);
    return resolved;
  }

  void _replace(Block original, Block updated) {
    final index = _blocks.indexWhere((block) => block.id == original.id);
    if (index >= 0) _blocks[index] = updated;
  }

  Future<void> _persistBlocks() async {
    notifyListeners();
    final local = await _store;
    await local.saveBlocks(_blocks);
  }

  /// What the block screen shows over a blocked app.
  ///
  /// Built here rather than natively because only Dart knows the rules. The
  /// screen has to explain itself the instant it appears, and the enforcer
  /// cannot evaluate anything on its own.
  Map<String, Map<String, Object?>> _detailsFor(EnforcementPlan plan) {
    final details = <String, Map<String, Object?>>{};

    for (final decision in plan.decisions) {
      if (!decision.blocked) continue;
      final block = blockById(decision.blockId);
      if (block == null) continue;

      final detail = <String, Object?>{
        'title': block.name,
        'status': _status(block, decision),
        'progress': _progressPercent(decision),
        'unlockAt': decision.nextEvaluationAt?.millisecondsSinceEpoch ?? 0,
      };

      for (final key in [...decision.blockedApps, ...decision.blockedDomains]) {
        details.putIfAbsent(key, () => detail);
      }
    }
    return details;
  }

  /// The least complete condition, because that is the one still gating the
  /// unlock. Averaging would show 50% for someone who has finished one habit
  /// and not started the other, which overstates how close they are.
  int _progressPercent(BlockDecision decision) {
    if (decision.conditionProgress.isEmpty) return -1;

    var lowest = 1.0;
    for (final progress in decision.conditionProgress) {
      if (progress.progress < lowest) lowest = progress.progress;
    }
    return (lowest * 100).round().clamp(0, 100);
  }

  String _status(Block block, BlockDecision decision) =>
      switch (decision.reason) {
        BlockReason.schedule => _scheduleStatus(decision),
        BlockReason.zone => 'Blocked while you are at ${block.zone?.name}.',
        BlockReason.device => 'Blocked while that device is connected.',
        BlockReason.conditionUnmet => describeRemaining(block.conditions),
        BlockReason.signalUnavailable =>
          'Control cannot read the signal this block needs, so it stays on.',
        BlockReason.disabled ||
        BlockReason.noTargets ||
        BlockReason.grantActive => 'Blocked right now.',
      };

  String _scheduleStatus(BlockDecision decision) {
    final until = decision.nextEvaluationAt;
    if (until == null) return 'Blocked on a schedule.';

    final sameDay = until.difference(_now()).inHours < 20;
    return sameDay
        ? 'Unlocks at ${formatTimeOfDay(until)}.'
        : 'Unlocks ${formatTimeOfDay(until)} on ${_weekdayName(until)}.';
  }

  static String _weekdayName(DateTime moment) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][moment.weekday - 1];
}
