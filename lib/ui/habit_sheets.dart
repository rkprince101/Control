import 'dart:async';

import 'package:flutter/material.dart';

import '../data/descriptions.dart';
import '../data/habits.dart';
import '../main.dart';
import 'block_icon.dart';
import 'controls.dart';
import 'expressive_progress.dart';
import 'habit_widgets.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// A starting point for a new habit, so the first one takes a tap rather than
/// a form.
class _Preset {
  const _Preset(
    this.name,
    this.kind,
    this.target,
    this.color,
    this.asset, {
    this.unit = '',
  });

  final String name;
  final HabitKind kind;
  final int target;
  final int color;
  final String asset;
  final String unit;
}

const _presets = [
  _Preset(
    'Drink water',
    HabitKind.count,
    8,
    0xFF2F6F73,
    'assets/icons/glass-7613mgbn-.svg',
    unit: 'glasses',
  ),
  _Preset(
    'Read',
    HabitKind.timer,
    20,
    0xFF3F5F9A,
    'assets/icons/book-open-bkvs82d7-.svg',
  ),
  _Preset(
    'Meditate',
    HabitKind.timer,
    10,
    0xFF6A4FA0,
    'assets/icons/Yoga-Half-Moon-Pose-1.svg',
  ),
  _Preset(
    'Stretch',
    HabitKind.check,
    1,
    0xFF365E49,
    'assets/icons/Yoga-Back-Stretch-1.svg',
  ),
  _Preset(
    'Journal',
    HabitKind.check,
    1,
    0xFF8A6D1F,
    'assets/icons/Content-Pen-Write.svg',
  ),
  _Preset(
    'Ride',
    HabitKind.timer,
    30,
    0xFFAA563A,
    'assets/icons/Fitness-Bicycle-1.svg',
  ),
  _Preset(
    'In bed by 11',
    HabitKind.check,
    1,
    0xFF5B6168,
    'assets/icons/moon-swqnuoxq-.svg',
  ),
];

/// Creates a habit, or edits one.
class HabitEditorSheet extends StatefulWidget {
  const HabitEditorSheet({this.existing, super.key});

  final Habit? existing;

  /// Resolves to true when the habit was deleted, so a sheet underneath that
  /// was showing it knows to close as well.
  static Future<bool?> show(BuildContext context, {Habit? existing}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => HabitEditorSheet(existing: existing),
    );
  }

  @override
  State<HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<HabitEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _unit;
  String? _icon;
  late int _color;
  late HabitKind _kind;
  late int _count;
  late int _minutes;
  late Set<int> _weekdays;
  late List<int> _reminders;

  bool get _isEditing => widget.existing != null;

  bool get _isValid => _name.text.trim().isNotEmpty && _weekdays.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final habit = widget.existing;
    _name = TextEditingController(text: habit?.name ?? '');
    _description = TextEditingController(text: habit?.description ?? '');
    _unit = TextEditingController(text: habit?.unit ?? '');
    _icon = habit?.iconAsset;
    _color = habit?.color ?? HabitPalette.seeds.first;
    _kind = habit?.kind ?? HabitKind.check;
    _count = habit?.kind == HabitKind.count ? habit!.target : 8;
    _minutes = habit?.kind == HabitKind.timer ? habit!.target : 20;
    _weekdays = {
      ...(habit?.weekdays ?? const {1, 2, 3, 4, 5, 6, 7}),
    };
    _reminders = [...?habit?.reminders];
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _apply(_Preset preset) => setState(() {
    _name.text = preset.name;
    _kind = preset.kind;
    _color = preset.color;
    _icon = preset.asset;
    if (preset.kind == HabitKind.count) _count = preset.target;
    if (preset.kind == HabitKind.timer) _minutes = preset.target;
    _unit.text = preset.unit;
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SheetGrabber(),
            SheetHeader(
              title: _isEditing ? 'Edit habit' : 'New habit',
              leading: SheetAction(
                'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              trailing: SheetAction(
                'Save',
                primary: true,
                onPressed: _isValid ? _save : null,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  if (!_isEditing) ...[
                    _presetRow(),
                    const SizedBox(height: 16),
                  ],
                  _identityCard(),
                  const SizedBox(height: 16),
                  _colourCard(),
                  const SizedBox(height: 16),
                  _trackingCard(),
                  const SizedBox(height: 16),
                  ControlCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _CardLabel(
                          icon: Icons.event_repeat_rounded,
                          text: 'On these days',
                        ),
                        const SizedBox(height: 12),
                        WeekdayPicker(
                          selected: _weekdays,
                          onChanged: (days) => setState(() => _weekdays = days),
                        ),
                        const SizedBox(height: 10),
                        const _Hint(
                          'A day off never breaks a streak. Doing it anyway '
                          'still counts.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _remindersCard(),
                  if (_isEditing) ...[
                    const SizedBox(height: 20),
                    _DeleteButton(habit: widget.existing!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetRow() => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _presets.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final preset = _presets[index];
        return ControlChip(
          label: preset.name,
          selected: _name.text == preset.name,
          onTap: () => _apply(preset),
        );
      },
    ),
  );

  Widget _identityCard() => ControlCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Choose icon',
          child: GestureDetector(
            onTap: () async {
              final picked = await IconPickerSheet.show(context, _icon);
              if (picked == null) return;
              setState(() => _icon = picked.isEmpty ? null : picked);
            },
            child: HabitIconSwatch(
              asset: _icon,
              color: _color,
              kind: _kind,
              size: 56,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: 'Habit name',
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  hintText: 'Why it matters (optional)',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _colourCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(icon: Icons.palette_outlined, text: 'Colour'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seed in HabitPalette.seeds)
              _ColourDot(
                seed: seed,
                selected: seed == _color,
                onTap: () => setState(() => _color = seed),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _trackingCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(icon: Icons.straighten_rounded, text: 'Track by'),
        const SizedBox(height: 12),
        ControlSegmented<HabitKind>(
          value: _kind,
          options: [for (final kind in HabitKind.values) (kind, kind.label)],
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: 14),
        ...switch (_kind) {
          HabitKind.check => const [
            _Hint('Tick it off once a day. Done or not, nothing in between.'),
          ],
          HabitKind.count => [
            Row(
              children: [
                Expanded(
                  child: HabitStepper(
                    label: 'Daily goal',
                    value: '$_count',
                    onMinus: _count > 1
                        ? () => setState(() => _count -= 1)
                        : null,
                    onPlus: _count < 999
                        ? () => setState(() => _count += 1)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    decoration: const InputDecoration(
                      hintText: 'glasses, pages, km',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _Hint('Each tap on the card adds one.'),
          ],
          HabitKind.timer => [
            HabitStepper(
              label: 'Daily goal',
              value: '$_minutes min',
              onMinus: _minutes > 1
                  ? () => setState(
                      () => _minutes = _minutes <= 5
                          ? _minutes - 1
                          : _minutes - 5,
                    )
                  : null,
              onPlus: _minutes < 600
                  ? () => setState(
                      () =>
                          _minutes = _minutes < 5 ? _minutes + 1 : _minutes + 5,
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in const [5, 10, 15, 20, 30, 45, 60])
                  ControlChip(
                    label: '$minutes min',
                    selected: _minutes == minutes,
                    onTap: () => setState(() => _minutes = minutes),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const _Hint(
              'Start the timer from the card. It keeps running with the app '
              'closed.',
            ),
          ],
        },
      ],
    ),
  );

  Widget _remindersCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(
          icon: Icons.notifications_none_rounded,
          text: 'Reminders',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final minute in _reminders)
              ControlChip(
                label: formatReminder(context, minute),
                selected: true,
                icon: Icons.close_rounded,
                onTap: () => setState(() => _reminders.remove(minute)),
              ),
            ControlChip(
              label: 'Add reminder',
              selected: false,
              icon: Icons.add_alarm_rounded,
              onTap: _addReminder,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Hint(
          StoreScope.of(context).notifications.exactAlarms
              ? 'Arrives at the time, on the days above, and stays quiet once '
                    'the habit is done for the day.'
              : 'Arrives within a few minutes of the time, on the days above, '
                    'and stays quiet once the habit is done for the day. Allow '
                    'exact timing in Settings to have it on the minute.',
        ),
        if (_reminders.isNotEmpty &&
            !StoreScope.of(context).notifications.enabled) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 18,
                color: ControlColors.of(context).medium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notifications are off for Control, so these cannot arrive.',
                  style: TextStyle(
                    color: ControlColors.of(context).medium,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              TextButton(
                onPressed: StoreScope.of(context).fixNotifications,
                child: const Text('Turn on'),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _addReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    final minute = picked.hour * 60 + picked.minute;
    if (_reminders.contains(minute)) return;
    setState(() => _reminders = [..._reminders, minute]..sort());
  }

  void _save() {
    final store = StoreScope.of(context);
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    final habit = Habit(
      id: existing?.id ?? 'habit-${DateTime.now().microsecondsSinceEpoch}',
      createdAt: existing?.createdAt ?? store.wallNow(),
      name: _name.text.trim(),
      description: _description.text.trim(),
      iconAsset: _icon,
      color: _color,
      kind: _kind,
      target: switch (_kind) {
        HabitKind.check => 1,
        HabitKind.count => _count,
        HabitKind.timer => _minutes,
      },
      unit: _kind == HabitKind.count ? _unit.text.trim() : '',
      weekdays: {..._weekdays},
      reminders: [..._reminders]..sort(),
    );
    // Close first, as the block editor does: the store has the habit in
    // memory before its first await, and the file write is not worth holding
    // the sheet open for.
    unawaited(
      existing == null ? store.addHabit(habit) : store.updateHabit(habit),
    );
    navigator.pop(false);
  }
}

/// `9:00 AM` or `09:00`, following the device setting.
String formatReminder(BuildContext context, int minute) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

class _ColourDot extends StatelessWidget {
  const _ColourDot({
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  final int seed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = HabitTones.of(context, seed);
    return Semantics(
      button: true,
      selected: selected,
      label: HabitPalette.nameOf(seed),
      child: ExcludeSemantics(
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tones.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded, color: tones.onAccent, size: 20)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minus, a value, plus. Null callbacks grey a side out.
class HabitStepper extends StatelessWidget {
  const HabitStepper({
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.label,
    super.key,
  });

  final String value;
  final String? label;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: label == null ? 'Less' : 'Lower ${label!.toLowerCase()}',
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Text(
                    label!,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colors.textMuted),
                  ),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: label == null ? 'More' : 'Raise ${label!.toLowerCase()}',
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          final store = StoreScope.of(context);
          final navigator = Navigator.of(context);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: ControlColors.of(context).card,
              title: Text('Delete ${habit.name}?'),
              content: const Text(
                'Its streaks and history go with it. This cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed ?? false) {
            unawaited(store.removeHabit(habit.id));
            navigator.pop(true);
          }
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          child: Text(
            'Delete habit',
            style: TextStyle(color: colors.heavy, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// One habit in full: its numbers, a month to browse, and the controls to log
/// any day, not just today.
class HabitDetailSheet extends StatefulWidget {
  const HabitDetailSheet({required this.habitId, this.initialDay, super.key});

  final String habitId;
  final DateTime? initialDay;

  static Future<void> show(BuildContext context, Habit habit, {DateTime? day}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) => HabitDetailSheet(habitId: habit.id, initialDay: day),
    );
  }

  @override
  State<HabitDetailSheet> createState() => _HabitDetailSheetState();
}

class _HabitDetailSheetState extends State<HabitDetailSheet> {
  late DateTime _selected = dateOnly(
    widget.initialDay ?? StoreScope.of(context).wallNow(),
  );
  late DateTime _month = DateTime(_selected.year, _selected.month);

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final habit = store.habitById(widget.habitId);
    // Deleted from the editor on top of this sheet, which is closing.
    if (habit == null) return const SizedBox(height: 120);

    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final stats = store.habitStats(habit);
    final rate = (stats.completionRate() * 100).round();

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Column(
        children: [
          const SheetGrabber(),
          SheetHeader(
            leading: SheetAction(
              'Close',
              onPressed: () => Navigator.pop(context),
            ),
            trailing: SheetAction(
              'Edit',
              primary: true,
              onPressed: () async {
                final navigator = Navigator.of(context);
                final deleted = await HabitEditorSheet.show(
                  context,
                  existing: habit,
                );
                if (deleted ?? false) navigator.pop();
              },
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HabitIconTile(habit: habit, size: 64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              habit.name,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          if (habit.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              habit.description,
                              style: TextStyle(
                                color: colors.textMuted,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Pill(habit.goalLabel.toUpperCase()),
                              Pill(
                                describeWeekdays(habit.weekdays).toUpperCase(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final tiles = [
                      _StatTile(
                        icon: Icons.local_fire_department_rounded,
                        value: '${stats.currentStreak}',
                        label: 'Current streak',
                        habit: habit,
                      ),
                      _StatTile(
                        icon: Icons.emoji_events_outlined,
                        value: '${stats.longestStreak}',
                        label: 'Best streak',
                        habit: habit,
                      ),
                      _StatTile(
                        icon: Icons.check_circle_outline_rounded,
                        value: '${stats.totalDone}',
                        label: 'Times done',
                        habit: habit,
                      ),
                      _StatTile(
                        icon: Icons.percent_rounded,
                        value: '$rate%',
                        label: 'Last 30 days',
                        habit: habit,
                      ),
                    ];
                    final columns = constraints.maxWidth >= 560 ? 4 : 2;
                    final width =
                        (constraints.maxWidth - 10 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final tile in tiles)
                          SizedBox(width: width, child: tile),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                HabitLogCard(habit: habit, stats: stats, day: _selected),
                const SizedBox(height: 16),
                ControlCard(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                  child: HabitCalendar(
                    stats: stats,
                    month: _month,
                    selected: _selected,
                    onSelect: (day) => setState(() => _selected = day),
                    onMonthChanged: (month) => setState(() => _month = month),
                  ),
                ),
                if (habit.reminders.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ControlCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Reminders at ${habit.reminders.map((m) => formatReminder(context, m)).join(', ')}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.habit,
  });

  final IconData icon;
  final String value;
  final String label;
  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final tones = HabitTones.of(context, habit.color);
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: ControlCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: tones.accent),
              const SizedBox(height: 10),
              Text(value, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ControlColors.of(context).textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logging controls for one day, shaped by how the habit is measured.
class HabitLogCard extends StatelessWidget {
  const HabitLogCard({
    required this.habit,
    required this.stats,
    required this.day,
    super.key,
  });

  final Habit habit;
  final HabitStats stats;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final tones = HabitTones.of(context, habit.color);
    final amount = stats.amountOn(day);
    final done = stats.isDoneOn(day);
    final isToday = day == stats.today;
    final running = store.habitTimer?.habitId == habit.id;

    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  describeHabitDay(context, day, stats.today),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (done)
                Pill('DONE', color: tones.accent)
              else if (!habit.isDueOn(day))
                const Pill('DAY OFF'),
            ],
          ),
          const SizedBox(height: 14),
          ...switch (habit.kind) {
            HabitKind.check => [
              SizedBox(
                width: double.infinity,
                child: done
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: tones.accent,
                          foregroundColor: tones.onAccent,
                        ),
                        onPressed: () => store.toggleHabit(habit.id, day),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Done. Tap to undo'),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: () => store.toggleHabit(habit.id, day),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Mark as done'),
                      ),
              ),
            ],
            HabitKind.count => [
              HabitStepper(
                value:
                    '$amount / ${habit.target} '
                    '${habit.unit.isEmpty ? 'times' : habit.unit}',
                onMinus: amount > 0
                    ? () => store.addHabitAmount(habit.id, day, -1)
                    : null,
                onPlus: () => store.addHabitAmount(habit.id, day, 1),
              ),
              const SizedBox(height: 14),
              ExpressiveProgress(
                value: stats.progressOn(day),
                color: tones.accent,
                semanticsLabel: '${habit.name} progress',
              ),
            ],
            HabitKind.timer => [
              HabitStepper(
                value: formatHabitTime(
                  habit,
                  amount,
                  running: running && isToday,
                ),
                onMinus: amount > 0
                    ? () => store.addHabitAmount(
                        habit.id,
                        day,
                        -(amount < 300 ? amount : 300),
                      )
                    : null,
                onPlus: () => store.addHabitAmount(habit.id, day, 300),
              ),
              const SizedBox(height: 14),
              ExpressiveProgress(
                value: stats.progressOn(day),
                color: tones.accent,
                semanticsLabel: '${habit.name} progress',
              ),
              if (isToday) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: running
                        ? store.stopHabitTimer
                        : () => store.startHabitTimer(habit.id),
                    icon: Icon(
                      running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(running ? 'Stop timer' : 'Start timer'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Minus and plus adjust by five minutes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ControlColors.of(context).textMuted,
                ),
              ),
            ],
          },
        ],
      ),
    );
  }
}

/// "Today", "Yesterday", or the date.
String describeHabitDay(BuildContext context, DateTime day, DateTime today) {
  if (day == today) return 'Today';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatMediumDate(day);
}

/// Logged time against a goal: `12 / 20 min` at rest, and a ticking
/// `12:04 / 20 min` while the timer runs, when the seconds are the point.
String formatHabitTime(Habit habit, int seconds, {required bool running}) =>
    '${running ? formatClock(Duration(seconds: seconds)) : seconds ~/ 60} '
    '/ ${habit.target} min';

class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: ControlColors.of(context).textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: ControlColors.of(context).textMuted,
      fontSize: 12,
      height: 1.4,
    ),
  );
}
