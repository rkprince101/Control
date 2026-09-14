// Named parameters cannot be private in Dart, so the injected collaborators
// below cannot be initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:control_core/control_core.dart';
import 'package:flutter/foundation.dart';

import '../data/descriptions.dart';
import '../data/focus.dart';
import '../data/local_store.dart';
import '../data/password.dart';
import '../platform/enforcement_channel.dart';
import '../platform/platform_models.dart';
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
        CheckInResult.outsideWindow =>
          'Not during the window for this habit.',
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
      InsightsRange.week => today.subtract(const Duration(days: 6)),
      InsightsRange.month => today.subtract(const Duration(days: 29)),
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
  })  : _channel = channel,
        _engine = engine,
        _storageDirectory = storageDirectory;

  final EnforcementChannel _channel;
  final RuleEngine _engine;
  final Directory? _storageDirectory;
  final LockPolicy _lockPolicy = const LockPolicy();
  final TamperResistantClock _clock = const TamperResistantClock();

  /// Opened once. Every write goes through [_store] rather than a nullable
  /// field, so a save that happens while the app is still starting waits for
  /// storage instead of being silently dropped.
  Future<LocalStore>? _opening;
  LocalStore? _local;

  Future<LocalStore> get _store =>
      _opening ??= LocalStore.open(directory: _storageDirectory)
          .then((store) => _local = store);

  final List<Block> _blocks = [];
  List<Block> get blocks => List.unmodifiable(_blocks);

  Signals _signals = const Signals();
  Signals get signals => _signals;

  EnforcementPlan? _plan;
  EnforcementPlan? get plan => _plan;

  bool accessibilityEnabled = false;
  bool usageAccessGranted = false;
  StepsStatus stepsStatus = const StepsStatus.unknown();
  LocationStatus locationStatus = const LocationStatus.unknown();
  ProtectionStatus protection = const ProtectionStatus.none();

  UsageSnapshot usage = const UsageSnapshot.empty();
  InsightsRange insightsRange = InsightsRange.day;
  List<InstalledApp> installedApps = const [];

  EmergencyUnlocks emergencyUnlocks = const EmergencyUnlocks.fresh();
  AppThemeChoice theme = AppThemeChoice.system;

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

  Duration? get protectionLockRemaining => _lockPolicy.remaining(
        block: _protectionCarrier,
        now: _now(),
      );

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

  /// Ticks once a second while a session runs, so the card and the timer sheet
  /// stay live without polling anything else.
  Timer? _focusTicker;

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

    _signals = _signals.copyWith(
      grants: local.loadGrants(),
      placeCheckIns: local.loadPlaceCheckIns(_now()),
    );
    emergencyUnlocks = local.loadEmergencyUnlocks();
    theme = AppThemeChoice.fromName(local.loadThemeChoice());
    hardMode = local.loadHardMode();
    weeklyReport = await _channel.weeklyReportEnabled();
    protectionLock = local.loadProtectionLock();

    _focusSessions
      ..clear()
      ..addAll(local.loadFocusSessions());
    // A session that was running when the app died keeps running: the clock
    // did not stop just because the process did.
    if (runningFocus != null) _startTicker();
    await _channel.setHardMode(hardMode);

    notifyListeners();
    if (_blocks.length != stored.length) await _persistBlocks();
    await refreshAll();
  }

  /// Everything that can change while the app was in the background.
  Future<void> refreshAll() async {
    await refreshPermissions();
    await refreshSignals();
  }

  Future<void> refreshPermissions() async {
    accessibilityEnabled = await _channel.isAccessibilityEnabled();
    usageAccessGranted = await _channel.hasUsageAccess();
    stepsStatus = await _channel.stepsStatus();
    locationStatus = await _channel.locationStatus();
    protection = await _channel.protectionStatus();

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
            end: today.add(const Duration(days: 1)),
          )
        : const UsageSnapshot.empty();

    usage = insightsRange == InsightsRange.day
        ? todayUsage
        : await _rangeUsage(insightsRange, now);

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

    notifyListeners();
    await publish(at: now);
  }

  Future<void> setInsightsRange(InsightsRange range) async {
    if (range == insightsRange) return;
    insightsRange = range;
    notifyListeners();

    final now = _now();
    usage = range == InsightsRange.day
        ? await _channel.usageSnapshot(
            start: range.startFrom(now),
            end: now,
          )
        : await _rangeUsage(range, now);
    notifyListeners();
  }

  Future<UsageSnapshot> _rangeUsage(InsightsRange range, DateTime now) async {
    if (!usageAccessGranted) return const UsageSnapshot.empty();
    return _channel.usageSnapshot(start: range.startFrom(now), end: now);
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
      setEquals(before.categories, after.categories) &&
      before.blockAgainAfter == after.blockAgainAfter &&
      before.schedulePolarity == after.schedulePolarity &&
      before.zonePolarity == after.zonePolarity &&
      before.devicePolarity == after.devicePolarity &&
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

  static String _conditionKey(UnlockCondition condition) =>
      switch (condition) {
        StepsCondition() => 'steps:${condition.targetSteps}',
        WorkoutCondition() => 'workout:${condition.target.inSeconds}',
        MeditateCondition() => 'meditate:${condition.target.inSeconds}',
        AppTimeCondition() => 'appTime:${condition.target.inSeconds}:'
            '${(condition.apps.toList()..sort()).join(',')}',
        FocusCondition() => 'focus:${condition.target.inSeconds}',
        PlaceCheckInCondition() => 'place:${condition.zone.center.latitude}:'
            '${condition.zone.center.longitude}:${condition.zone.radiusMeters}:'
            '${condition.window.startMinute}-${condition.window.endMinute}',
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

  /// Arms a lock. Always permitted: locking is a strengthening change, and a
  /// lock you cannot apply because of an existing lock would be absurd.
  Future<void> lockBlock(
    String id, {
    Duration? duration,
    String? password,
  }) async {
    final block = blockById(id);
    if (block == null) return;

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

  /// Starts a session. Only one runs at a time: two timers counting the same
  /// minutes would be a way to buy an unlock twice over.
  Future<void> startFocus(
    String blockId, {
    required FocusKind kind,
    Duration? plannedWork,
  }) async {
    if (runningFocus != null) await stopFocus();

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
    _startTicker();
    await _persistFocus();
    await publish();
  }

  Future<void> stopFocus() async {
    final running = runningFocus;
    if (running == null) return;

    final index = _focusSessions.indexOf(running);
    _focusSessions[index] = running.stoppedAt(_now());
    _stopTicker();

    await _persistFocus();
    // The finished minutes may have just bought an unlock.
    await refreshSignals();
  }

  void _startTicker() {
    _focusTicker?.cancel();
    _focusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final running = runningFocus;
      if (running == null) {
        _stopTicker();
        return;
      }
      notifyListeners();
      // A pomodoro closes itself the moment it has served its time, so the
      // reward does not depend on the user being there to press stop.
      if (running.isComplete(_now())) unawaited(stopFocus());
    });
  }

  void _stopTicker() {
    _focusTicker?.cancel();
    _focusTicker = null;
  }

  Future<void> _persistFocus() async {
    _signals = _signals.copyWith(focusToday: focusToday);
    notifyListeners();
    final local = await _store;
    await local.saveFocusSessions(_focusSessions, _now());
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
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
      final distance =
          condition.zone.center.distanceTo(reading.point).round();
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
  /// Turning it off is refused while a timed lock is running, for the same
  /// reason releasing device admin is: it is the first step of getting rid of
  /// the block.
  Future<bool> setHardMode(bool enabled) async {
    if (!enabled && (protectionLocked || _hasLiveTimedLock())) return false;

    hardMode = enabled;
    notifyListeners();
    await _channel.setHardMode(enabled);
    final local = await _store;
    await local.saveHardMode(enabled);
    return true;
  }

  bool _hasLiveTimedLock() {
    final now = _now();
    return _blocks.any(
      (block) => block.lock.kind == LockKind.timed && !block.lock.isExpired(now),
    );
  }

  Future<DeviceOwnerStatus> deviceOwnerStatus() => _channel.deviceOwnerStatus();

  Future<void> requestDeviceAdmin() async {
    await _channel.requestDeviceAdmin();
  }

  Future<void> setUninstallBlocked(bool blocked) async {
    await _channel.setUninstallBlocked(blocked);
    await refreshPermissions();
  }

  /// Refuses while any block is still under a timed lock. Releasing protection
  /// is the first step of uninstalling, which would clear every block: allowing
  /// it here would make the timed lock decorative.
  Future<bool> releaseProtection() async {
    if (protectionLocked || _hasLiveTimedLock()) return false;

    await _channel.releaseProtection();
    await refreshPermissions();
    return true;
  }

  /// Arms the lock on uninstall protection. Turning protection on at the same
  /// time, if it is not already: locking an unarmed setting would be a promise
  /// with nothing behind it.
  Future<void> lockProtection({Duration? duration, String? password}) async {
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

  Future<void> requestStepsPermission() => _channel.requestStepsPermission();

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

    final grants = Map<String, UnlockGrant>.from(_signals.grants);
    for (final block in _blocks) {
      final grant = _engine.mintGrantIfEarned(
        block: block,
        signals: _signals,
        now: now,
      );
      if (grant != null) grants[block.id] = grant;
    }
    grants.removeWhere((_, grant) => !grant.isActive(now));
    _signals = _signals.copyWith(grants: grants);

    final plan = _engine.plan(blocks: _blocks, signals: _signals, now: now);
    _plan = plan;

    await _channel.applyPlan(plan, details: _detailsFor(plan));
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

  /// Time that only moves forward.
  ///
  /// The monotonic-uptime anchor is not wired up yet, so this is the system
  /// clock floored by the latest time already observed: enough to stop a lock
  /// being skipped by winding the date back, not yet enough to survive a reboot
  /// plus a clock change in the same sitting.
  DateTime _now() {
    final systemNow = DateTime.now();
    final local = _local;
    if (local == null) return systemNow;

    final resolved = _clock.resolve(
      systemNow: systemNow,
      highWaterMark: local.loadClockHighWaterMark(),
    );
    clockTampered = _clock.detectsRollback(systemNow, resolved);
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
        BlockReason.grantActive =>
          'Blocked right now.',
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
