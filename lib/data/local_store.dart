import 'dart:convert';
import 'dart:io';

import 'package:control_core/control_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'block_codec.dart';
import 'focus.dart';
import 'habits.dart';
import 'money.dart';
import 'notes.dart';
import 'page_lock.dart';
import 'todos.dart';

/// Local persistence for everything a restart must not reset.
///
/// A single JSON file rather than key-value preferences, written atomically:
/// blocks, locks, grants, and the emergency-unlock budget are one consistent
/// state, and a half-written update that loses the lock while keeping the block
/// is worse than no update at all. The file is also readable with `adb`, which
/// matters when the bug being chased is "my rules vanished".
class LocalStore {
  LocalStore._(this._file, this._state);

  static const _fileName = 'control_state.json';

  /// [directory] is injectable so tests can use a temp folder instead of the
  /// platform application-support path.
  static Future<LocalStore> open({Directory? directory}) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    return LocalStore._(file, await _read(file));
  }

  final File _file;
  final Map<String, Object?> _state;

  /// Serialises writes. Two saves landing at once must not interleave into a
  /// file that is neither.
  Future<void> _writing = Future.value();

  static Future<Map<String, Object?>> _read(File file) async {
    try {
      if (!file.existsSync()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : {};
    } catch (error) {
      // Never let unreadable storage take the app down: an empty state still
      // starts, and the next save rewrites the file.
      debugPrint('control: could not read $_fileName: $error');
      return {};
    }
  }

  Future<void> _save() {
    final snapshot = jsonEncode(_state);
    _writing = _writing.then((_) async {
      try {
        await _file.parent.create(recursive: true);
        // Write beside the target, then rename: a rename is atomic, so a crash
        // mid-write leaves the previous good file rather than a truncated one.
        final temp = File('${_file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(_file.path);
      } catch (error) {
        debugPrint('control: could not write $_fileName: $error');
      }
    });
    return _writing;
  }

  /// Waits for any in-flight write. Used before reading the file back.
  Future<void> flush() => _writing;

  // Blocks -------------------------------------------------------------------

  List<Block> loadBlocks() {
    final raw = _state[_blocks];
    if (raw is! List) return [];

    return raw
        .whereType<Map<String, Object?>>()
        .map((json) {
          // One unreadable block must not take the rest of the rules with it.
          try {
            return BlockCodec.decode(json);
          } catch (error) {
            debugPrint('control: dropping unreadable block: $error');
            return null;
          }
        })
        .whereType<Block>()
        .toList();
  }

  Future<void> saveBlocks(List<Block> blocks) {
    _state[_blocks] = blocks.map(BlockCodec.encode).toList();
    return _save();
  }

  // Unlock grants ------------------------------------------------------------

  Map<String, UnlockGrant> loadGrants() {
    final raw = _state[_grants];
    if (raw is! Map) return {};

    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is Map<String, Object?>)
          entry.key! as String:
              _decodeGrant(entry.value! as Map<String, Object?>),
    };
  }

  Future<void> saveGrants(Map<String, UnlockGrant> grants) {
    _state[_grants] = {
      for (final entry in grants.entries)
        entry.key: {
          'grantedAt': entry.value.grantedAt.millisecondsSinceEpoch,
          'expiresAt': entry.value.expiresAt?.millisecondsSinceEpoch,
        },
    };
    return _save();
  }

  static UnlockGrant _decodeGrant(Map<String, Object?> json) {
    final expiresAt = (json['expiresAt'] as num?)?.toInt();
    return UnlockGrant(
      grantedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['grantedAt'] as num?)?.toInt() ?? 0,
      ),
      expiresAt: expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAt),
    );
  }

  // Focus sessions -----------------------------------------------------------

  List<FocusSession> loadFocusSessions() {
    final raw = _state[_focusSessions];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, Object?>>()
        .map(FocusSession.fromMap)
        .whereType<FocusSession>()
        .toList();
  }

  /// Keeps a rolling window. Statistics never look further back than a few
  /// months, and an unbounded list would grow the file forever.
  Future<void> saveFocusSessions(List<FocusSession> sessions, DateTime now) {
    final cutoff = now.subtract(const Duration(days: 120));
    _state[_focusSessions] = sessions
        .where((session) => session.isRunning || session.startedAt.isAfter(cutoff))
        .map((session) => session.toMap())
        .toList();
    return _save();
  }

  // Place check-ins ----------------------------------------------------------

  /// Ids checked in on [day]. Stored with the day they belong to, so a check-in
  /// earned yesterday morning does not still be counting tomorrow.
  Set<String> loadPlaceCheckIns(DateTime day) {
    if (_state[_checkInDay] != _dayKey(day)) return {};
    final raw = _state[_checkIns];
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  Future<void> savePlaceCheckIns(Set<String> ids, DateTime day) {
    _state[_checkInDay] = _dayKey(day);
    _state[_checkIns] = ids.toList();
    return _save();
  }

  static int _dayKey(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  // Hard mode ----------------------------------------------------------------

  bool loadHardMode() => _state[_hardMode] as bool? ?? false;

  Future<void> saveHardMode(bool enabled) {
    _state[_hardMode] = enabled;
    return _save();
  }

  /// The lock guarding uninstall protection itself.
  Lock loadProtectionLock() => LockCodec.decode(_state[_protectionLock]);

  Future<void> saveProtectionLock(Lock lock) {
    _state[_protectionLock] = LockCodec.encode(lock);
    return _save();
  }

  // Emergency unlocks --------------------------------------------------------

  EmergencyUnlocks loadEmergencyUnlocks() => EmergencyUnlocks(
        remaining: (_state[_emergencyRemaining] as num?)?.toInt() ??
            EmergencyUnlocks.defaultTotal,
        total: EmergencyUnlocks.defaultTotal,
      );

  Future<void> saveEmergencyUnlocks(EmergencyUnlocks pool) {
    _state[_emergencyRemaining] = pool.remaining;
    return _save();
  }

  // Clock --------------------------------------------------------------------

  DateTime? loadClockHighWaterMark() {
    final millis = (_state[_clockHighWater] as num?)?.toInt();
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Held in memory and flushed with the next real save. Called on every clock
  /// read, and rewriting the whole file that often would be pointless churn.
  void noteClockHighWaterMark(DateTime value) {
    _state[_clockHighWater] = value.millisecondsSinceEpoch;
  }

  // Habits -------------------------------------------------------------------

  List<Habit> loadHabits() {
    final raw = _state[_habits];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, Object?>>()
        .map(Habit.fromMap)
        .whereType<Habit>()
        .toList();
  }

  Future<void> saveHabits(List<Habit> habits) {
    _state[_habits] = habits.map((habit) => habit.toMap()).toList();
    return _save();
  }

  /// Habit id to day key to amount. Day keys are stored as strings because
  /// JSON object keys cannot be anything else.
  Map<String, Map<int, int>> loadHabitLog() {
    final raw = _state[_habitLog];
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is Map)
          entry.key! as String: {
            for (final day in (entry.value! as Map).entries)
              if (int.tryParse('${day.key}') case final key?)
                if (day.value is num) key: (day.value! as num).toInt(),
          },
    };
  }

  Future<void> saveHabitLog(Map<String, Map<int, int>> log) {
    _state[_habitLog] = {
      for (final entry in log.entries)
        if (entry.value.isNotEmpty)
          entry.key: {
            for (final day in entry.value.entries)
              if (day.value > 0) '${day.key}': day.value,
          },
    };
    return _save();
  }

  HabitTimer? loadHabitTimer() => HabitTimer.fromMap(_state[_habitTimer]);

  // Todos and notes -----------------------------------------------------

  List<Todo> loadTodos() => [
    for (final raw in (_state[_todos] as List?) ?? const []) ?Todo.fromJson(raw),
  ];

  Future<void> saveTodos(List<Todo> todos) {
    _state[_todos] = [for (final todo in todos) todo.toJson()];
    return _save();
  }

  List<Note> loadNotes() => [
    for (final raw in (_state[_notes] as List?) ?? const []) ?Note.fromJson(raw),
  ];

  Future<void> saveNotes(List<Note> notes) {
    _state[_notes] = [for (final note in notes) note.toJson()];
    return _save();
  }

  // Money ---------------------------------------------------------------------

  List<ExpenseEntry> loadMoneyEntries() => [
    for (final raw in (_state[_moneyEntries] as List?) ?? const [])
      ?ExpenseEntry.fromJson(raw),
  ];

  Future<void> saveMoneyEntries(List<ExpenseEntry> entries) {
    _state[_moneyEntries] = [for (final entry in entries) entry.toJson()];
    return _save();
  }

  List<Budget> loadBudgets() => [
    for (final raw in (_state[_budgets] as List?) ?? const [])
      ?Budget.fromJson(raw),
  ];

  Future<void> saveBudgets(List<Budget> budgets) {
    _state[_budgets] = [for (final budget in budgets) budget.toJson()];
    return _save();
  }

  List<LoanEntry> loadLoans() => [
    for (final raw in (_state[_loans] as List?) ?? const [])
      ?LoanEntry.fromJson(raw),
  ];

  Future<void> saveLoans(List<LoanEntry> loans) {
    _state[_loans] = [for (final loan in loans) loan.toJson()];
    return _save();
  }

  String? loadCurrency() => _state[_currency] as String?;

  Future<void> saveCurrency(String code) {
    _state[_currency] = code;
    return _save();
  }

  // Page lock -----------------------------------------------------------------

  PageLock loadPageLock() => PageLock.fromJson(_state[_pageLock]);

  Future<void> savePageLock(PageLock lock) {
    if (lock.enabled) {
      _state[_pageLock] = lock.toJson();
    } else {
      _state.remove(_pageLock);
    }
    return _save();
  }

  /// The highest growth stage already celebrated.
  int loadGrowthStageSeen() => (_state[_growthSeen] as num?)?.toInt() ?? 0;

  Future<void> saveGrowthStageSeen(int stage) {
    _state[_growthSeen] = stage;
    return _save();
  }

  Future<void> saveHabitTimer(HabitTimer? timer) {
    if (timer == null) {
      _state.remove(_habitTimer);
    } else {
      _state[_habitTimer] = timer.toMap();
    }
    return _save();
  }

  // Preferences --------------------------------------------------------------

  String? loadThemeChoice() => _state[_theme] as String?;

  String? loadWaveMotion() => _state[_waveMotion] as String?;

  Future<void> saveWaveMotion(String motion) {
    _state[_waveMotion] = motion;
    return _save();
  }

  Future<void> saveThemeChoice(String choice) {
    _state[_theme] = choice;
    return _save();
  }

  static const _blocks = 'blocks';
  static const _grants = 'grants';
  static const _emergencyRemaining = 'emergencyUnlocksRemaining';
  static const _clockHighWater = 'clockHighWaterMark';
  static const _theme = 'themeChoice';
  static const _waveMotion = 'waveMotion';
  static const _focusSessions = 'focusSessions';
  static const _hardMode = 'hardMode';
  static const _checkIns = 'placeCheckIns';
  static const _checkInDay = 'placeCheckInDay';
  static const _protectionLock = 'protectionLock';
  static const _habits = 'habits';
  static const _habitLog = 'habitLog';
  static const _habitTimer = 'habitTimer';
  static const _growthSeen = 'growthStageSeen';
  static const _todos = 'todos';
  static const _notes = 'notes';
  static const _moneyEntries = 'moneyEntries';
  static const _budgets = 'moneyBudgets';
  static const _loans = 'moneyLoans';
  static const _currency = 'currency';
  static const _pageLock = 'pageLock';
}
