// Named parameters cannot be private in Dart, so the injected collaborators
// below cannot be initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:control_core/control_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/descriptions.dart';
import '../data/focus.dart';
import '../data/habits.dart';
import '../data/local_store.dart';
import '../data/money.dart';
import '../data/notes.dart';
import '../data/page_lock.dart';
import '../data/todos.dart';
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

  final List<Habit> _habits = [];
  List<Habit> get habits => List.unmodifiable(_habits);

  /// Habit id to [dayKey] to amount: units for a count, seconds for a timer.
  final Map<String, Map<int, int>> _habitLog = {};

  /// The timer habit being timed right now, if any. One at a time, like focus.
  HabitTimer? habitTimer;
  Timer? _habitTicker;

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

    final knownHabits = _habits.map((habit) => habit.id).toSet();
    _habits.insertAll(
      0,
      local.loadHabits().where((habit) => !knownHabits.contains(habit.id)),
    );
    for (final entry in local.loadHabitLog().entries) {
      _habitLog.putIfAbsent(entry.key, () => entry.value);
    }
    habitTimer ??= local.loadHabitTimer();
    final knownTodos = _todos.map((todo) => todo.id).toSet();
    _todos.insertAll(
      0,
      local.loadTodos().where((todo) => !knownTodos.contains(todo.id)),
    );
    final knownNotes = _notes.map((note) => note.id).toSet();
    _notes.insertAll(
      0,
      local.loadNotes().where((note) => !knownNotes.contains(note.id)),
    );
    growthStageSeen = local.loadGrowthStageSeen();
    final knownEntries = _moneyEntries.map((entry) => entry.id).toSet();
    _moneyEntries.addAll(
      local.loadMoneyEntries().where((e) => !knownEntries.contains(e.id)),
    );
    final knownBudgets = _budgets.map((budget) => budget.id).toSet();
    _budgets.addAll(
      local.loadBudgets().where((b) => !knownBudgets.contains(b.id)),
    );
    final knownLoans = _loans.map((loan) => loan.id).toSet();
    _loans.addAll(local.loadLoans().where((l) => !knownLoans.contains(l.id)));
    if (local.loadCurrency() case final code?) {
      currency = Currency.byCode(code);
    }
    _moneyBook = null;
    pageLock = local.loadPageLock();
    if (habitTimer != null) _startHabitTicker();
    // Hydrate persisted commitments before yielding: a concurrent add must not
    // save a partial block or grant list over the loaded state.
    await _refreshClock();
    _signals = _signals.copyWith(
      placeCheckIns: local.loadPlaceCheckIns(_now()),
    );
    weeklyReport = await _channel.weeklyReportEnabled();
    // A session that was running when the app died keeps running: the clock
    // did not stop just because the process did. A pomodoro that finished in
    // the meantime is closed at its finish line.
    final carried = runningFocus;
    if (carried != null && carried.isComplete(_now())) {
      lastFinishedFocus = _closeFocus(carried, _now());
      await _persistFocus();
    }
    _updateTicker();
    unawaited(_syncFocusNotification());
    await _channel.setHardMode(hardMode);

    notifyListeners();
    if (_blocks.length != stored.length) await _persistBlocks();
    unawaited(_syncHabitReminders());
    await refreshAll();
  }

  /// Everything that can change while the app was in the background.
  Future<void> refreshAll() async {
    await _refreshClock();
    await refreshPermissions();
    await refreshSignals();
    await refreshInsights();
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
    final local = await _store;

    _signals = _signals.copyWith(
      appUsageToday: {for (final app in todayUsage.apps) app.id: app.duration},
      stepsToday: steps,
      shortcutCounts: shortcuts,
      focusToday: focusToday,
      // Reloaded rather than kept, so a check-in stops counting at midnight
      // even if the app was never closed.
      placeCheckIns: local.loadPlaceCheckIns(now),
    );
    _signalsDay = today;

    notifyListeners();
    await publish();
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
    final needed =
        (running != null && !running.isPaused) || focusBreak != null;
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
    _habitTicker?.cancel();
    super.dispose();
  }

  // Habits -------------------------------------------------------------------
  //
  // Habits run on the wall clock, not the protection clock. They are
  // self-reported and unlock nothing, so there is nothing to defend, and the
  // day someone ticks off has to be the day on their calendar.

  /// The wall clock habits are logged against. Overridable so previews and
  /// tests can stand on a fixed day.
  DateTime wallNow() => DateTime.now();

  Habit? habitById(String id) =>
      habits.where((habit) => habit.id == id).firstOrNull;

  /// The stored log for a habit, with a running timer's seconds folded in so
  /// every screen shows the live total.
  Map<int, int> habitLogFor(String id, {DateTime? now}) {
    final log = {...?_habitLog[id]};
    final timer = habitTimer;
    if (timer != null && timer.habitId == id) {
      for (final entry in timer.secondsByDay(now ?? wallNow()).entries) {
        log[entry.key] = (log[entry.key] ?? 0) + entry.value;
      }
    }
    return log;
  }

  HabitStats habitStats(Habit habit, {DateTime? now}) {
    final moment = now ?? wallNow();
    return HabitStats.of(habit, habitLogFor(habit.id, now: moment), moment);
  }

  /// Days any habit was done. The rank ladder climbs on these.
  int get habitPoints =>
      habits.fold(0, (total, habit) => total + habitStats(habit).totalDone);

  /// The garden: stage, progress, dates reached, pace. Grows from the same
  /// check-ins as [habitPoints].
  HabitGrowth get habitGrowth =>
      HabitGrowth.of(habits.map(habitStats), wallNow());

  // Todos --------------------------------------------------------------------
  //
  // Like habits, todos run on the wall clock: a todo is due on the day on the
  // user's calendar. Each change lands in memory before the first await.

  final List<Todo> _todos = [];
  List<Todo> get todos => List.unmodifiable(_todos);
  TodoBook get todoBook => TodoBook(_todos);

  Todo? todoById(String id) =>
      _todos.where((todo) => todo.id == id).firstOrNull;

  int _idSequence = 0;

  /// Unique within a session even for two ids made in the same microsecond,
  /// which quick multi-add does.
  String _newId(String kind) =>
      '$kind-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

  Future<void> addTodo(String title, DateTime? date) async {
    final text = title.trim();
    if (text.isEmpty) return;
    _todos.insert(
      0,
      Todo(
        id: _newId('todo'),
        title: text,
        date: date == null ? null : dateOnly(date),
        createdAt: wallNow(),
      ),
    );
    await _persistTodos();
  }

  /// Done becomes undone and the other way round. A todo's steps follow it:
  /// checking the todo checks every step.
  Future<void> toggleTodo(String id) async {
    final index = _todos.indexWhere((todo) => todo.id == id);
    if (index < 0) return;
    final todo = _todos[index];
    final done = !todo.isDone;
    _todos[index] = todo.copyWith(
      isDone: done,
      completedAt: done ? wallNow() : null,
      clearCompletedAt: !done,
      subTodos: [for (final step in todo.subTodos) step.copyWith(isDone: done)],
    );
    await _persistTodos();
  }

  Future<void> updateTodo(
    String id, {
    String? title,
    DateTime? date,
    bool clearDate = false,
  }) async {
    final index = _todos.indexWhere((todo) => todo.id == id);
    if (index < 0) return;
    final text = title?.trim();
    _todos[index] = _todos[index].copyWith(
      title: text == null || text.isEmpty ? null : text,
      date: date == null ? null : dateOnly(date),
      clearDate: clearDate,
    );
    await _persistTodos();
  }

  Future<void> removeTodo(String id) async {
    _todos.removeWhere((todo) => todo.id == id);
    await _persistTodos();
  }

  Future<void> addSubTodo(String todoId, String title) async {
    final text = title.trim();
    if (text.isEmpty) return;
    await _editSteps(
      todoId,
      (steps) => [...steps, SubTodo(id: _newId('step'), title: text)],
    );
  }

  Future<void> toggleSubTodo(String todoId, String stepId) => _editSteps(
    todoId,
    (steps) => [
      for (final step in steps)
        step.id == stepId ? step.copyWith(isDone: !step.isDone) : step,
    ],
  );

  Future<void> updateSubTodo(String todoId, String stepId, String title) {
    final text = title.trim();
    if (text.isEmpty) return Future.value();
    return _editSteps(
      todoId,
      (steps) => [
        for (final step in steps)
          step.id == stepId ? step.copyWith(title: text) : step,
      ],
    );
  }

  Future<void> removeSubTodo(String todoId, String stepId) => _editSteps(
    todoId,
    (steps) => steps.where((step) => step.id != stepId).toList(),
  );

  /// Changes a todo's steps, then keeps the todo's own state in line with
  /// them: done exactly when every step is. Adding an unfinished step reopens
  /// a finished todo.
  Future<void> _editSteps(
    String todoId,
    List<SubTodo> Function(List<SubTodo>) change,
  ) async {
    final index = _todos.indexWhere((todo) => todo.id == todoId);
    if (index < 0) return;
    var todo = _todos[index].copyWith(subTodos: change(_todos[index].subTodos));
    if (todo.hasSubTodos) {
      final allDone = todo.subTodos.every((step) => step.isDone);
      if (allDone != todo.isDone) {
        todo = todo.copyWith(
          isDone: allDone,
          completedAt: allDone ? wallNow() : null,
          clearCompletedAt: !allDone,
        );
      }
    }
    _todos[index] = todo;
    await _persistTodos();
  }

  Future<void> _persistTodos() async {
    notifyListeners();
    final local = await _store;
    await local.saveTodos(_todos);
  }

  // Notes --------------------------------------------------------------------

  final List<Note> _notes = [];

  /// Pinned first, then most recently edited.
  List<Note> get notes => sortNotes(_notes);

  Note? noteById(String id) =>
      _notes.where((note) => note.id == id).firstOrNull;

  String newNoteId() => _newId('note');

  /// Adds a note, or replaces the one with the same id.
  Future<void> upsertNote(Note note) async {
    final index = _notes.indexWhere((existing) => existing.id == note.id);
    if (index < 0) {
      _notes.insert(0, note);
    } else {
      _notes[index] = note;
    }
    await _persistNotes();
  }

  Future<void> removeNote(String id) async {
    _notes.removeWhere((note) => note.id == id);
    await _persistNotes();
  }

  /// Pinning is not an edit, so the note keeps its place among the others.
  Future<void> toggleNotePin(String id) async {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0) return;
    final note = _notes[index];
    _notes[index] = note.copyWith(
      pinned: !note.pinned,
      updatedAt: note.updatedAt,
    );
    await _persistNotes();
  }

  Future<void> _persistNotes() async {
    notifyListeners();
    final local = await _store;
    await local.saveNotes(_notes);
  }

  // Money --------------------------------------------------------------------
  //
  // An income and expense log with budgets and loans. Amounts land on the
  // user's calendar day, so it runs on the wall clock like todos.

  final List<ExpenseEntry> _moneyEntries = [];
  final List<Budget> _budgets = [];
  final List<LoanEntry> _loans = [];
  Currency currency = Currency.all.first;

  static const maxMoneyEntries = 5000;
  static const maxBudgets = 200;
  static const maxLoans = 1000;

  MoneyBook? _moneyBook;

  /// The whole ledger, sorted and indexed once per change.
  MoneyBook get moneyBook => _moneyBook ??= MoneyBook(
    entries: _moneyEntries,
    budgets: _budgets,
    loans: _loans,
    currency: currency,
  );

  Future<void> setCurrency(Currency next) async {
    if (next.code == currency.code) return;
    currency = next;
    _moneyBook = null;
    notifyListeners();
    final local = await _store;
    await local.saveCurrency(next.code);
  }

  static String _cap(String text, int length) {
    final trimmed = text.trim();
    return trimmed.length > length ? trimmed.substring(0, length) : trimmed;
  }

  /// A detail only belongs to an Other entry.
  static String _detailFor(String category, String detail) =>
      category == ExpenseCategory.otherName ? detail.trim() : '';

  Future<void> addMoneyEntry({
    required EntryType type,
    required double amount,
    required String category,
    required DateTime date,
    String title = '',
    String detail = '',
  }) async {
    if (amount <= 0 || _moneyEntries.length >= maxMoneyEntries) return;
    _moneyEntries.add(
      ExpenseEntry(
        id: _newId('money'),
        type: type,
        title: _cap(title, ExpenseEntry.maxTitleLength),
        amount: amount.clamp(0, ExpenseEntry.maxAmount).toDouble(),
        category: category,
        detail: _detailFor(category, detail),
        date: dateOnly(date),
        createdAt: wallNow(),
      ),
    );
    await _persistMoneyEntries();
  }

  Future<void> updateMoneyEntry(
    String id, {
    EntryType? type,
    double? amount,
    String? category,
    DateTime? date,
    String? title,
    String? detail,
  }) async {
    final index = _moneyEntries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final entry = _moneyEntries[index];
    final nextCategory = category ?? entry.category;
    _moneyEntries[index] = entry.copyWith(
      type: type,
      title: title == null ? null : _cap(title, ExpenseEntry.maxTitleLength),
      amount: amount?.clamp(0, ExpenseEntry.maxAmount).toDouble(),
      category: category,
      // Moving an entry away from Other drops what it said it was.
      detail: _detailFor(nextCategory, detail ?? entry.detail),
      date: date == null ? null : dateOnly(date),
    );
    await _persistMoneyEntries();
  }

  Future<void> removeMoneyEntry(String id) async {
    final before = _moneyEntries.length;
    _moneyEntries.removeWhere((entry) => entry.id == id);
    if (_moneyEntries.length == before) return;
    await _persistMoneyEntries();
  }

  /// Puts back an entry that was just deleted: the undo on its snackbar.
  Future<void> restoreMoneyEntry(ExpenseEntry entry) async {
    if (_moneyEntries.any((existing) => existing.id == entry.id)) return;
    _moneyEntries.add(entry);
    await _persistMoneyEntries();
  }

  Future<void> _persistMoneyEntries() async {
    _moneyBook = null;
    notifyListeners();
    final local = await _store;
    await local.saveMoneyEntries(_moneyEntries);
  }

  Future<void> addBudget({
    required String label,
    required double amount,
    required DateTime start,
    required DateTime end,
    String category = '',
  }) async {
    if (amount <= 0 || _budgets.length >= maxBudgets) return;
    final (from, to) = _ordered(start, end);
    _budgets.add(
      Budget(
        id: _newId('budget'),
        label: _cap(label, Budget.maxLabelLength),
        amount: amount,
        start: from,
        end: to,
        category: category,
      ),
    );
    await _persistBudgets();
  }

  Future<void> updateBudget(
    String id, {
    required String label,
    required double amount,
    required DateTime start,
    required DateTime end,
    String category = '',
  }) async {
    final index = _budgets.indexWhere((budget) => budget.id == id);
    if (index < 0 || amount <= 0) return;
    final (from, to) = _ordered(start, end);
    _budgets[index] = _budgets[index].copyWith(
      label: _cap(label, Budget.maxLabelLength),
      amount: amount,
      start: from,
      end: to,
      category: category,
    );
    await _persistBudgets();
  }

  Future<void> removeBudget(String id) async {
    _budgets.removeWhere((budget) => budget.id == id);
    await _persistBudgets();
  }

  Future<void> restoreBudget(Budget budget) async {
    if (_budgets.any((existing) => existing.id == budget.id)) return;
    _budgets.add(budget);
    await _persistBudgets();
  }

  /// Start never after end, whichever order the dates were picked in.
  static (DateTime, DateTime) _ordered(DateTime a, DateTime b) {
    final first = dateOnly(a);
    final second = dateOnly(b);
    return first.isAfter(second) ? (second, first) : (first, second);
  }

  Future<void> _persistBudgets() async {
    _moneyBook = null;
    notifyListeners();
    final local = await _store;
    await local.saveBudgets(_budgets);
  }

  Future<void> addLoan({
    required LoanType type,
    required String person,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    if (amount <= 0 || _loans.length >= maxLoans) return;
    _loans.add(
      LoanEntry(
        id: _newId('loan'),
        type: type,
        person: _cap(person, LoanEntry.maxNameLength),
        amount: amount,
        date: dateOnly(date),
        note: note.trim(),
      ),
    );
    await _persistLoans();
  }

  Future<void> updateLoan(
    String id, {
    required LoanType type,
    required String person,
    required double amount,
    required DateTime date,
    String note = '',
  }) async {
    final index = _loans.indexWhere((loan) => loan.id == id);
    if (index < 0 || amount <= 0) return;
    _loans[index] = _loans[index].copyWith(
      type: type,
      person: _cap(person, LoanEntry.maxNameLength),
      amount: amount,
      date: dateOnly(date),
      note: note.trim(),
    );
    await _persistLoans();
  }

  Future<void> toggleLoanSettled(String id) async {
    final index = _loans.indexWhere((loan) => loan.id == id);
    if (index < 0) return;
    final settled = !_loans[index].settled;
    _loans[index] = _loans[index].copyWith(
      settled: settled,
      settledAt: settled ? wallNow() : null,
      clearSettledAt: !settled,
    );
    await _persistLoans();
  }

  Future<void> removeLoan(String id) async {
    _loans.removeWhere((loan) => loan.id == id);
    await _persistLoans();
  }

  Future<void> restoreLoan(LoanEntry loan) async {
    if (_loans.any((existing) => existing.id == loan.id)) return;
    _loans.add(loan);
    await _persistLoans();
  }

  Future<void> _persistLoans() async {
    _moneyBook = null;
    notifyListeners();
    final local = await _store;
    await local.saveLoans(_loans);
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

  /// The highest stage already celebrated, so a new one is celebrated once.
  int growthStageSeen = 0;

  Future<void> markGrowthSeen(int stage) async {
    if (stage <= growthStageSeen) return;
    growthStageSeen = stage;
    final local = await _store;
    await local.saveGrowthStageSeen(stage);
  }

  /// How many of the habits due on [day] are done. A habit done on a day off
  /// counts on both sides, so extra credit never reads as a shortfall.
  ({int done, int due}) habitProgressOn(DateTime day) {
    var done = 0;
    var due = 0;
    for (final habit in habits) {
      // A habit counts only from the day it was created.
      if (dateOnly(day).isBefore(dateOnly(habit.createdAt))) continue;
      final isDone = habitStats(habit).isDoneOn(day);
      if (!habit.isDueOn(day) && !isDone) continue;
      due++;
      if (isDone) done++;
    }
    return (done: done, due: due);
  }

  Future<void> addHabit(Habit habit) async {
    _habits.add(habit);
    if (habit.reminders.isNotEmpty) _askForNotifications();
    await _persistHabits();
  }

  /// Every change lands in memory before the first await, so a sheet can
  /// close the moment it calls this; the file write follows on its own.
  Future<void> updateHabit(Habit updated) async {
    final index = _habits.indexWhere((habit) => habit.id == updated.id);
    if (index < 0) return;
    final previous = _habits[index];
    if (previous.reminders.isEmpty && updated.reminders.isNotEmpty) {
      _askForNotifications();
    }
    // A habit switched away from timing cannot keep a timer running. Stopped
    // before the switch, so the run is banked in the unit it was measured in.
    final stopping =
        updated.kind != HabitKind.timer && habitTimer?.habitId == updated.id
        ? stopHabitTimer()
        : null;
    _habits[index] = updated;

    // Seconds do not mean glasses. When the measure changes, the days that
    // were done stay done and the partial ones are let go, so streaks survive
    // the edit without inventing progress.
    final log = _habitLog[updated.id];
    final remapped = previous.kind != updated.kind && log != null;
    if (remapped) {
      log
        ..updateAll((_, amount) => amount >= previous.goal ? updated.goal : 0)
        ..removeWhere((_, amount) => amount <= 0);
    }
    notifyListeners();

    await stopping;
    if (remapped) {
      final local = await _store;
      await local.saveHabitLog(_habitLog);
    }
    await _persistHabits();
  }

  Future<void> removeHabit(String id) async {
    final hadTimer = habitTimer?.habitId == id;
    if (hadTimer) {
      habitTimer = null;
      _habitTicker?.cancel();
      _habitTicker = null;
    }
    _habits.removeWhere((habit) => habit.id == id);
    _habitLog.remove(id);
    notifyListeners();

    if (hadTimer) {
      final local = await _store;
      await local.saveHabitTimer(null);
    }
    await _persistHabits();
    await _persistHabitLog();
  }

  /// Sets the stored amount for [day]. Never below zero, and never for a day
  /// before the habit was created or after today.
  Future<void> setHabitAmount(String id, DateTime day, int amount) async {
    final habit = habitById(id);
    if (habit == null || !habitStats(habit).canLog(day)) return;
    final log = _habitLog.putIfAbsent(id, () => {});
    if (amount <= 0) {
      log.remove(dayKey(day));
    } else {
      log[dayKey(day)] = amount;
    }
    await _persistHabitLog();
  }

  Future<void> addHabitAmount(String id, DateTime day, int delta) {
    final current = _habitLog[id]?[dayKey(day)] ?? 0;
    return setHabitAmount(id, day, current + delta);
  }

  /// Done becomes not done, and anything short of done becomes done.
  Future<void> toggleHabit(String id, DateTime day) {
    final habit = habitById(id);
    if (habit == null) return Future.value();
    final done = habitStats(habit).isDoneOn(day);
    return setHabitAmount(id, day, done ? 0 : habit.goal);
  }

  Future<void> startHabitTimer(String id) async {
    final stopping = habitTimer == null ? null : stopHabitTimer();
    habitTimer = HabitTimer(habitId: id, startedAt: wallNow());
    _startHabitTicker();
    notifyListeners();
    await stopping;
    final local = await _store;
    await local.saveHabitTimer(habitTimer);
  }

  /// Banks the run into the log, split across midnight if it crossed one.
  Future<void> stopHabitTimer() async {
    final timer = habitTimer;
    if (timer == null) return;
    habitTimer = null;
    _habitTicker?.cancel();
    _habitTicker = null;

    final log = _habitLog.putIfAbsent(timer.habitId, () => {});
    for (final entry in timer.secondsByDay(wallNow()).entries) {
      log[entry.key] = (log[entry.key] ?? 0) + entry.value;
    }
    final local = await _store;
    await local.saveHabitTimer(null);
    await _persistHabitLog();
  }

  void _startHabitTicker() {
    _habitTicker?.cancel();
    _habitTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (habitTimer == null) {
        _habitTicker?.cancel();
        _habitTicker = null;
        return;
      }
      notifyListeners();
    });
  }

  void _askForNotifications() => unawaited(
    _channel.requestNotificationPermission().catchError((Object error) {
      debugPrint('control: could not ask for notifications: $error');
    }),
  );

  Future<void> _persistHabits() async {
    notifyListeners();
    final local = await _store;
    await local.saveHabits(_habits);
    await _syncHabitReminders();
  }

  Future<void> _persistHabitLog() async {
    notifyListeners();
    final local = await _store;
    await local.saveHabitLog(_habitLog);
    await _syncHabitReminders();
  }

  /// Hands every reminder to Android, which owns the alarms.
  ///
  /// Like the widget summary, a failure here is logged and swallowed: a
  /// reminder that could not be scheduled must never undo the tick that
  /// triggered the sync.
  Future<void> _syncHabitReminders() async {
    final today = wallNow();
    try {
      await _channel.setHabitReminders([
        for (final habit in _habits)
          for (final minute in habit.reminders)
            {
              'id': '${habit.id}@$minute',
              'habitId': habit.id,
              'title': habit.name,
              'body': habit.description.trim().isNotEmpty
                  ? habit.description.trim()
                  : habit.kind == HabitKind.check
                  ? 'A small step still counts.'
                  : '${habit.goalLabel} today.',
              'minute': minute,
              'weekdays': habit.weekdays.toList()..sort(),
              'doneDay': habitStats(habit, now: today).isDoneOn(today)
                  ? dayKey(today)
                  : 0,
            },
      ]);
    } catch (error) {
      debugPrint('control: could not schedule habit reminders: $error');
    }
  }

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

    if (!locationStatus.granted) return CheckInResult.noPermission;
    if (!locationStatus.enabled) return CheckInResult.locationOff;

    final reading = await _channel.currentLocation();
    if (reading == null) return CheckInResult.noFix;

    // The condition decides, not this method: the same rule has to hold
    // wherever it is asked.
    if (!condition.canCheckIn(reading, now)) {
      final distance = condition.zone.center.distanceTo(reading.point).round();
      return distance > condition.zone.radiusMeters
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

  Future<void> requestLocationPermission() =>
      _channel.requestLocationPermission();

  /// One fix for the editor, so a zone can be dropped where the user is
  /// standing without a map.
  Future<GeoReading?> currentLocation() => _channel.currentLocation();

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

  Future<void> openAccessibilitySettings() =>
      _channel.openAccessibilitySettings();

  Future<void> openUsageAccessSettings() => _channel.openUsageAccessSettings();

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

    await _channel.applyPlan(
      plan,
      details: _detailsFor(plan),
      blocks: _blocks,
      grants: grants,
    );
    await _pushSummary(plan);
    notifyListeners();

    final local = await _store;
    await local.saveGrants(grants);
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
