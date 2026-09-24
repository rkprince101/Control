import 'dart:async';

import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state/control_store.dart';
import 'app_picker_sheet.dart';
import 'block_icon.dart';
import 'place_picker_sheet.dart';
import 'controls.dart';
import 'shortcut_help_sheet.dart';
import 'sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Creates a block, or edits an existing one.
///
/// Locked blocks can be renamed, re-iconed, or tightened, but never weakened.
///
/// Only the modes and habits whose signals this platform actually measures are
/// offered. A Place rule with no location source fails closed and would read as
/// an app that blocks everything forever; a Workout condition with no Health
/// Connect source could never be satisfied at all.
class BlockEditorSheet extends StatefulWidget {
  const BlockEditorSheet({
    this.existing,
    this.initialApps = const {},
    super.key,
  });

  final Block? existing;
  final Set<AppId> initialApps;

  static Future<void> show(
    BuildContext context, {
    Block? existing,
    Set<AppId> initialApps = const {},
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ControlColors.of(context).background,
      builder: (_) =>
          BlockEditorSheet(existing: existing, initialApps: initialApps),
    );
  }

  @override
  State<BlockEditorSheet> createState() => _BlockEditorSheetState();
}

class _BlockEditorSheetState extends State<BlockEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _channel;

  late Set<AppId> _apps;
  late Set<String> _categories;
  late Set<AppId> _excludedApps;
  late Set<String> _domains;
  late final TextEditingController _domainInput;
  late LimitMode _mode;
  String? _iconAsset;

  late List<_Range> _ranges;
  late Set<int> _weekdays;
  late RulePolarity _polarity;

  late bool _stepsOn;
  late int _stepsTarget;
  late bool _appTimeOn;
  late Set<AppId> _earnApps;
  late int _earnMinutes;
  late bool _shortcutOn;
  late int _shortcutCount;
  late bool _focusOn;
  late int _focusMinutes;
  late bool _placeOn;
  GeoPoint? _placeCentre;
  late String _placeName;
  late double _placeRadius;
  late TimeOfDay _placeFrom;
  late TimeOfDay _placeTo;
  bool _capturingPlace = false;
  late Duration? _blockAgainAfter;

  bool get _isEditing => widget.existing != null;

  static TimeOfDay _timeOf(int minuteOfDay) =>
      TimeOfDay(hour: (minuteOfDay ~/ 60) % 24, minute: minuteOfDay % 60);

  static int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

  @override
  void initState() {
    super.initState();
    final block = widget.existing;

    _name = TextEditingController(text: block?.name ?? 'Focus');
    _apps = {...(block?.apps ?? widget.initialApps)};
    _categories = {...?block?.categories};
    _excludedApps = {...?block?.excludedApps};
    _domains = {...?block?.blockedDomains};
    _domainInput = TextEditingController();
    _mode = block?.mode ?? LimitMode.time;
    _iconAsset = block?.iconAsset;

    final schedule = block?.schedule ?? const <TimeRange>[];
    _ranges = schedule.isEmpty
        ? [
            _Range(
              const TimeOfDay(hour: 9, minute: 0),
              const TimeOfDay(hour: 17, minute: 0),
            ),
          ]
        : schedule.map(_Range.fromRange).toList();
    _weekdays = schedule.isEmpty
        ? {1, 2, 3, 4, 5, 6, 7}
        : {...schedule.first.weekdays};
    _polarity = block?.schedulePolarity ?? RulePolarity.blockDuring;

    final steps = block?.conditions.whereType<StepsCondition>().firstOrNull;
    _stepsOn = steps != null;
    _stepsTarget = steps?.targetSteps ?? 5000;

    final appTime = block?.conditions.whereType<AppTimeCondition>().firstOrNull;
    _appTimeOn = appTime != null;
    _earnApps = {...?appTime?.apps};
    _earnMinutes = appTime?.target.inMinutes ?? 30;

    final shortcut = block?.conditions
        .whereType<ShortcutCondition>()
        .firstOrNull;
    _shortcutOn = shortcut != null;
    _shortcutCount = shortcut?.requiredCount ?? 1;
    _channel = TextEditingController(text: shortcut?.channel ?? '');

    final focus = block?.conditions.whereType<FocusCondition>().firstOrNull;
    _focusOn = focus != null;
    _focusMinutes = focus?.target.inMinutes ?? 240;

    final place = block?.conditions
        .whereType<PlaceCheckInCondition>()
        .firstOrNull;
    _placeOn = place != null;
    _placeCentre = place?.zone.center;
    _placeName = place?.zone.name ?? 'The place';
    _placeRadius = place?.zone.radiusMeters ?? 150;
    _placeFrom = _timeOf(place?.window.startMinute ?? 270);
    _placeTo = _timeOf(place?.window.endMinute ?? 300);

    _blockAgainAfter = block?.blockAgainAfter;
  }

  @override
  void dispose() {
    _name.dispose();
    _channel.dispose();
    _domainInput.dispose();
    super.dispose();
  }

  bool get _locked {
    final block = widget.existing;
    return block != null && StoreScope.of(context).isLocked(block);
  }

  /// A host still sitting in the site field, not yet turned into a chip.
  ///
  /// Counted everywhere the committed list is, so Save is enabled for someone
  /// who typed a site and reached straight for it.
  String? get _pendingDomain => _normaliseDomain(_domainInput.text);

  bool get _isValid {
    if (_locked) {
      // Still has to be a superset: the picker enforces it, and this is the
      // second gate in case it ever does not.
      final before = widget.existing;
      return before == null ||
          (_apps.containsAll(before.apps) &&
              _categories.containsAll(before.categories) &&
              before.excludedApps.containsAll(_excludedApps) &&
              _domains.containsAll(before.blockedDomains));
    }
    if (_apps.isEmpty &&
        _categories.isEmpty &&
        _domains.isEmpty &&
        _pendingDomain == null) {
      return false;
    }
    return switch (_mode) {
      LimitMode.time => _ranges.isNotEmpty && _weekdays.isNotEmpty,
      LimitMode.condition => _buildConditions().isNotEmpty,
      LimitMode.place || LimitMode.device => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;

    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            const SheetGrabber(),
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _identityCard(),
                  if (locked) ...[
                    const SizedBox(height: 12),
                    _LockedBanner(block: widget.existing!),
                  ],
                  const SizedBox(height: 16),
                  _appsCard(),
                  const SizedBox(height: 16),
                  _websitesCard(),
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: locked,
                    child: Opacity(
                      opacity: locked ? 0.45 : 1,
                      child: Column(
                        children: [
                          _modeCard(),
                          const SizedBox(height: 16),
                          if (_mode == LimitMode.time)
                            _timeCard()
                          else
                            _conditionCard(),
                        ],
                      ),
                    ),
                  ),
                  if (_isEditing && !locked) ...[
                    const SizedBox(height: 20),
                    _DeleteButton(block: widget.existing!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => SheetHeader(
    title: _isEditing ? 'Edit block' : 'New block',
    leading: SheetAction('Cancel', onPressed: () => Navigator.pop(context)),
    trailing: SheetAction(
      'Save',
      primary: true,
      onPressed: _isValid ? _save : null,
    ),
  );

  /// Name and icon can change without affecting the commitment.
  Widget _identityCard() => ControlCard(
    child: Row(
      children: [
        GestureDetector(
          onTap: () async {
            final picked = await IconPickerSheet.show(context, _iconAsset);
            if (picked == null) return;
            setState(() => _iconAsset = picked.isEmpty ? null : picked);
          },
          child: _iconAsset == null
              ? _EmptyIconTile()
              : BlockIconTile(asset: _iconAsset!, size: 56),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            controller: _name,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Block name',
            ),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _appsCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(
          icon: Icons.apps_rounded,
          text: 'Which apps do you want to limit?',
        ),
        const SizedBox(height: 12),
        _PickerButton(
          label: _apps.isEmpty && _categories.isEmpty && _excludedApps.isEmpty
              ? 'Select apps'
              : '${_apps.length} apps, ${_categories.length} categories, '
                    '${_excludedApps.length} exclusions',
          onTap: () async {
            final picked = await AppPickerSheet.show(
              context,
              _apps,
              allowCategories: true,
              initialCategories: _categories,
              initialExcludedApps: _excludedApps,
              lockedCategories: _locked
                  ? {...?widget.existing?.categories}
                  : const {},
              categoryRulesLocked: _locked,
              // While locked, the apps already covered cannot be dropped.
              locked: _locked ? {...?widget.existing?.apps} : const {},
            );
            if (picked == null || !mounted) return;
            setState(() {
              _apps = picked.apps;
              _categories = picked.categories;
              _excludedApps = picked.excludedApps;
              // Presets bring their websites with them.
              _domains.addAll(picked.domains);
            });
          },
        ),
      ],
    ),
  );

  /// Blocking the app and leaving the website open is the loophole everyone
  /// finds first, so it sits directly under the app picker rather than in some
  /// advanced section.
  Widget _websitesCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(
          icon: Icons.language_rounded,
          text: 'Block these sites too',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _domainInput,
          autocorrect: false,
          // Save reads the pending text, so the header has to rebuild as it
          // is typed or the button stays greyed out over a valid form.
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: 'instagram.com',
            isDense: true,
            filled: true,
            fillColor: ControlColors.of(context).cardRaised,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: _addDomain,
            ),
          ),
          onSubmitted: (_) => _addDomain(),
        ),
        if (_domains.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final domain in _domains)
                () {
                  final pinned =
                      _locked &&
                      (widget.existing?.blockedDomains.contains(domain) ??
                          false);
                  return ControlChip(
                    label: domain,
                    selected: true,
                    icon: pinned ? Icons.lock : Icons.close_rounded,
                    onTap: pinned
                        ? () {}
                        : () => setState(() => _domains.remove(domain)),
                  );
                }(),
            ],
          ),
        ],
        const SizedBox(height: 10),
        const _Hint(
          'Covers subdomains, so instagram.com also stops '
          'www.instagram.com. Control reads the address bar of the common '
          'browsers to do this, and nothing else about the page. A site '
          'opened inside another app is still a way through.',
        ),
      ],
    ),
  );

  void _addDomain() {
    final host = _pendingDomain;
    if (host == null) return;

    setState(() {
      _domains.add(host);
      _domainInput.clear();
    });
  }

  /// Accepts what people actually paste, and keeps only the host.
  static String? _normaliseDomain(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed.contains(' ')) return null;

    var host = trimmed.split('://').last.split('/').first.split('?').first;
    if (host.startsWith('www.')) host = host.substring(4);
    return host.contains('.') ? host : null;
  }

  Widget _modeCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(
          icon: Icons.tune_rounded,
          text: 'How do you want to limit them?',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ModeChip(
                icon: Icons.vpn_key_outlined,
                label: 'Condition',
                selected: _mode == LimitMode.condition,
                onTap: () => setState(() => _mode = LimitMode.condition),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeChip(
                icon: Icons.schedule_rounded,
                label: 'Time',
                selected: _mode == LimitMode.time,
                onTap: () => setState(() => _mode = LimitMode.time),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _Hint(
          'Place and Device rules need location and Bluetooth signals that '
          'are not wired up yet.',
        ),
      ],
    ),
  );

  // Time ---------------------------------------------------------------------

  Widget _timeCard() => ControlCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardLabel(
          icon: Icons.schedule_rounded,
          text: 'Use the apps you selected on a schedule',
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _ranges.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TimeButton(
                  time: _ranges[i].start,
                  onPicked: (value) => setState(() => _ranges[i].start = value),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                _TimeButton(
                  time: _ranges[i].end,
                  onPicked: (value) => setState(() => _ranges[i].end = value),
                ),
                if (_ranges.length > 1)
                  IconButton(
                    onPressed: () => setState(() => _ranges.removeAt(i)),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: ControlChip(
            label: 'Add range',
            icon: Icons.add,
            selected: false,
            onTap: () => setState(
              () => _ranges.add(
                _Range(
                  const TimeOfDay(hour: 20, minute: 0),
                  const TimeOfDay(hour: 22, minute: 0),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _CardLabel(
          icon: Icons.calendar_today_rounded,
          text: 'On these days',
        ),
        const SizedBox(height: 12),
        WeekdayPicker(
          selected: _weekdays,
          onChanged: (days) => setState(() => _weekdays = days),
        ),
        const SizedBox(height: 18),
        ControlSegmented<RulePolarity>(
          value: _polarity,
          options: const [
            (RulePolarity.blockDuring, 'Block during'),
            (RulePolarity.unblockDuring, 'Unblock during'),
          ],
          onChanged: (value) => setState(() => _polarity = value),
        ),
        const SizedBox(height: 10),
        _Hint(
          _polarity == RulePolarity.blockDuring
              ? 'Apps are blocked during these times on the days you picked.'
              : 'Apps are blocked except during these times on the days you '
                    'picked.',
        ),
        if (_weekdays.isEmpty) ...[
          const SizedBox(height: 8),
          const _Hint('Pick at least one day, or the schedule never runs.'),
        ],
      ],
    ),
  );

  // Conditions ---------------------------------------------------------------

  Widget _conditionCard() {
    final store = StoreScope.of(context);

    return ControlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel(
            icon: Icons.vpn_key_outlined,
            text: 'Select a habit to unlock your apps',
          ),
          const SizedBox(height: 12),
          _HabitTile(
            icon: Icons.directions_walk_rounded,
            label: 'Steps',
            subtitle: store.stepsStatus.available
                ? '$_stepsTarget steps today'
                : 'No step counter on this device',
            enabled: store.stepsStatus.available,
            selected: _stepsOn,
            onToggle: (value) => setState(() => _stepsOn = value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!store.stepsStatus.granted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ControlChip(
                      label: 'Allow step access',
                      icon: Icons.lock_open,
                      selected: false,
                      onTap: store.requestStepsPermission,
                    ),
                  ),
                _Stepper(
                  value: _stepsTarget,
                  min: 500,
                  max: 30000,
                  step: 500,
                  format: (value) => '$value steps',
                  onChanged: (value) => setState(() => _stepsTarget = value),
                ),
              ],
            ),
          ),
          const _HabitTile(
            icon: Icons.fitness_center_rounded,
            label: 'Workout',
            subtitle: 'Needs Health Connect',
            enabled: false,
            selected: false,
            onToggle: _ignoreToggle,
          ),
          const _HabitTile(
            icon: Icons.self_improvement_rounded,
            label: 'Meditate',
            subtitle: 'Needs Health Connect',
            enabled: false,
            selected: false,
            onToggle: _ignoreToggle,
          ),
          _HabitTile(
            icon: Icons.timelapse_rounded,
            label: 'App time',
            subtitle:
                '$_earnMinutes min in '
                '${_earnApps.length} app${_earnApps.length == 1 ? '' : 's'}',
            enabled: true,
            selected: _appTimeOn,
            onToggle: (value) => setState(() => _appTimeOn = value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PickerButton(
                  label: _earnApps.isEmpty
                      ? 'Apps that count towards it'
                      : '${_earnApps.length} app'
                            '${_earnApps.length == 1 ? '' : 's'} count',
                  onTap: () async {
                    final picked = await AppPickerSheet.show(
                      context,
                      _earnApps,
                    );
                    if (picked != null) {
                      setState(() => _earnApps = picked.apps);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _Stepper(
                  value: _earnMinutes,
                  min: 5,
                  max: 180,
                  step: 5,
                  format: (value) => '$value min',
                  onChanged: (value) => setState(() => _earnMinutes = value),
                ),
              ],
            ),
          ),
          _HabitTile(
            icon: Icons.timer_outlined,
            label: 'Focus timer',
            subtitle:
                '${formatDuration(Duration(minutes: _focusMinutes))} '
                'of pomodoro or stopwatch',
            enabled: true,
            selected: _focusOn,
            onToggle: (value) => setState(() => _focusOn = value),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stepper(
                  value: _focusMinutes,
                  min: 15,
                  max: 720,
                  step: 15,
                  format: (value) => formatDuration(Duration(minutes: value)),
                  onChanged: (value) => setState(() => _focusMinutes = value),
                ),
                const SizedBox(height: 8),
                const _Hint(
                  'Start the timer from the block card. The reward window below '
                  'is how long the apps open for once the time is in.',
                ),
              ],
            ),
          ),
          _HabitTile(
            icon: Icons.place_outlined,
            label: 'Be somewhere',
            subtitle: _placeCentre == null
                ? 'Check in at a place, inside a time window'
                : '$_placeName, ${_placeRadius.round()} m, '
                      '${_placeFrom.format(context)} to ${_placeTo.format(context)}',
            enabled: true,
            selected: _placeOn,
            onToggle: (value) => setState(() => _placeOn = value),
            child: _placeConfig(),
          ),
          _HabitTile(
            icon: Icons.bolt_rounded,
            label: 'Shortcut',
            subtitle: _shortcutCount == 1
                ? '1 trigger'
                : '$_shortcutCount triggers',
            enabled: true,
            selected: _shortcutOn,
            onToggle: (value) => setState(() => _shortcutOn = value),
            child: _shortcutConfig(),
          ),
          const SizedBox(height: 14),
          Text(
            _focusOn ? 'Unlock the apps for' : 'Block again after',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, duration) in _reArmOptions)
                ControlChip(
                  label: label,
                  selected: _blockAgainAfter == duration,
                  onTap: () => setState(() => _blockAgainAfter = duration),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Hint(
            _blockAgainAfter == null
                ? 'Once earned, the apps stay open until midnight.'
                : 'The apps lock again '
                      '${_humaniseReArm(_blockAgainAfter!)} after you earn them. '
                      'One earned allowance per day; today\'s completed habits '
                      'cannot renew it.',
          ),
        ],
      ),
    );
  }

  Widget _placeConfig() {
    final store = StoreScope.of(context);
    final centre = _placeCentre;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!store.locationStatus.granted)
          TextButton(
            onPressed: store.requestLocationPermission,
            child: const Text('Allow location access'),
          ),
        _PickerButton(
          label: centre == null ? 'Choose on a map' : 'Change the place',
          onTap: _pickPlaceOnMap,
        ),
        const SizedBox(height: 8),
        _PickerButton(
          label: centre == null
              ? 'Or use where I am now'
              : 'Move it to where I am now',
          onTap: _capturePlace,
        ),
        if (_capturingPlace)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (centre != null) ...[
          const SizedBox(height: 10),
          TextFormField(
            initialValue: _placeName,
            decoration: const InputDecoration(
              labelText: 'Name of the place',
              isDense: true,
            ),
            onChanged: (value) => _placeName = value,
          ),
          const SizedBox(height: 12),
          Text('Within ${_placeRadius.round()} m'),
          Slider(
            value: _placeRadius,
            min: 50,
            max: 500,
            divisions: 18,
            label: '${_placeRadius.round()} m',
            onChanged: (value) => setState(() => _placeRadius = value),
          ),
          const _Hint(
            'A tight radius is the point of the habit, but GPS needs room to '
            'be sure. Below about 100 m a check-in often fails outdoors, and '
            'almost always indoors.',
          ),
        ],
        const SizedBox(height: 14),
        const Text(
          'Check in between',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TimeButton(
              time: _placeFrom,
              onPicked: (value) => setState(() => _placeFrom = value),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.arrow_forward, size: 18),
            ),
            _TimeButton(
              time: _placeTo,
              onPicked: (value) => setState(() => _placeTo = value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _Hint(
          'Control takes one location fix when you tap Check in, and never '
          'looks while the app is closed. The unlock lasts the rest of the '
          'day: you have to be there at the time, not stay there.',
        ),
      ],
    );
  }

  Future<void> _pickPlaceOnMap() async {
    final picked = await PlacePickerSheet.show(
      context,
      centre: _placeCentre,
      radius: _placeRadius,
    );
    if (picked == null) return;

    setState(() {
      _placeCentre = picked.centre;
      _placeRadius = picked.radiusMeters;
    });
  }

  Future<void> _capturePlace() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _capturingPlace = true);
    final reading = await store.currentLocation();
    if (!mounted) return;

    setState(() {
      _capturingPlace = false;
      if (reading != null) _placeCentre = reading.point;
    });

    if (reading == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No location fix yet. Try again outside.'),
        ),
      );
      return;
    }

    // A place saved from a vague fix is a place in the wrong spot, and the
    // check-in will keep failing for reasons the user cannot see.
    if (reading.accuracyMeters > _placeRadius) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Saved, but the fix is only accurate to '
            '${reading.accuracyMeters.round()} m. Widen the radius or set it '
            'again outdoors.',
          ),
        ),
      );
    }
  }

  Widget _shortcutConfig() {
    final store = StoreScope.of(context);
    final colors = ControlColors.of(context);
    final channel = _channel.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final count in const [1, 5, 10, 25])
              ControlChip(
                label: '$count',
                selected: _shortcutCount == count,
                onTap: () => setState(() => _shortcutCount = count),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TextField(
            controller: _channel,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: InputBorder.none,
              prefixText: '#  ',
              prefixStyle: TextStyle(color: colors.textMuted, fontSize: 15),
              hintText: 'Channel name, e.g. pushups',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: _Hint(
                'Fire this channel from an NFC tag, a QR code, or an '
                'automation app. Use this exact name.',
              ),
            ),
            const SizedBox(width: 8),
            ControlChip(
              label: 'How?',
              icon: Icons.help_outline_rounded,
              selected: false,
              onTap: () => ShortcutHelpSheet.show(context, _channel.text),
            ),
          ],
        ),
        if (channel.isNotEmpty) ...[
          const SizedBox(height: 10),
          SelectableText(
            'control://shortcut?channel=${channel.toLowerCase()}',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          ControlChip(
            label: 'Test it',
            icon: Icons.play_arrow_rounded,
            selected: false,
            onTap: () async {
              final count = await store.fireShortcut(channel);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$channel fired ($count today)')),
              );
            },
          ),
        ],
      ],
    );
  }

  static void _ignoreToggle(bool _) {}

  static const _reArmOptions = <(String, Duration?)>[
    ('Off', null),
    ('30m', Duration(minutes: 30)),
    ('1h', Duration(hours: 1)),
    ('2h', Duration(hours: 2)),
    ('4h', Duration(hours: 4)),
  ];

  static String _humaniseReArm(Duration duration) => duration.inHours >= 1
      ? '${duration.inHours} hour${duration.inHours == 1 ? '' : 's'}'
      : '${duration.inMinutes} minutes';

  List<UnlockCondition> _buildConditions() {
    final id = _blockId;
    return [
      if (_stepsOn) StepsCondition(id: '$id-steps', targetSteps: _stepsTarget),
      if (_appTimeOn && _earnApps.isNotEmpty)
        AppTimeCondition(
          id: '$id-app-time',
          apps: _earnApps,
          target: Duration(minutes: _earnMinutes),
        ),
      if (_focusOn)
        FocusCondition(
          id: '$id-focus',
          target: Duration(minutes: _focusMinutes),
        ),
      if (_placeOn && _placeCentre != null)
        PlaceCheckInCondition(
          id: '$id-place',
          zone: Zone(
            name: _placeName.trim().isEmpty ? 'The place' : _placeName.trim(),
            center: _placeCentre!,
            radiusMeters: _placeRadius,
          ),
          window: TimeRange(
            startMinute: _minutesOf(_placeFrom),
            endMinute: _minutesOf(_placeTo),
          ),
        ),
      if (_shortcutOn && _channel.text.trim().isNotEmpty)
        ShortcutCondition(
          id: '$id-shortcut',
          channel: _channel.text.trim().toLowerCase(),
          requiredCount: _shortcutCount,
        ),
    ];
  }

  late final String _blockId =
      widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

  void _save() {
    final store = StoreScope.of(context);

    // Anything still sitting in the site field counts: nobody expects text they
    // typed to be discarded because they did not press the plus first.
    _addDomain();

    final name = _name.text.trim().isEmpty ? 'Block' : _name.text.trim();
    final existing = widget.existing;

    // Fire and forget, then close. The store adds the block to memory and
    // notifies listeners synchronously; everything after that is a file write
    // and two platform round-trips. Awaiting all of it before popping made
    // dismissal depend on work the user does not care about, and any stall out
    // there left the editor stuck open over a block that already existed.
    unawaited(_commit(store, name, existing));
    Navigator.of(context).pop();
  }

  Future<void> _commit(ControlStore store, String name, Block? existing) async {
    if (_locked && existing != null) {
      // A locked block can be renamed, re-iconed, and tightened. Selection rules
      // come from the form because they may have tightened; everything else is
      // carried over untouched, because the form could not change it.
      await store.updateBlock(
        existing.copyWith(
          name: name,
          apps: _apps,
          categories: _categories,
          excludedApps: _excludedApps,
          blockedDomains: _domains,
          iconAsset: _iconAsset,
          clearIconAsset: _iconAsset == null,
        ),
      );
      return;
    }

    final block = _mode == LimitMode.time
        ? Block(
            id: _blockId,
            name: name,
            mode: LimitMode.time,
            apps: _apps,
            categories: _categories,
            excludedApps: _excludedApps,
            blockedDomains: _domains,
            iconAsset: _iconAsset,
            schedule: [
              for (final range in _ranges)
                TimeRange(
                  startMinute: range.start.hour * 60 + range.start.minute,
                  endMinute: range.end.hour * 60 + range.end.minute,
                  weekdays: _weekdays,
                ),
            ],
            schedulePolarity: _polarity,
            enabled: existing?.enabled ?? true,
          )
        : Block(
            id: _blockId,
            name: name,
            mode: LimitMode.condition,
            apps: _apps,
            categories: _categories,
            excludedApps: _excludedApps,
            blockedDomains: _domains,
            iconAsset: _iconAsset,
            conditions: _buildConditions(),
            blockAgainAfter: _blockAgainAfter,
            enabled: existing?.enabled ?? true,
          );

    if (existing == null) {
      await store.addBlock(block);
    } else {
      // The editor already refuses to offer a change a lock forbids, so a
      // refusal here means the two disagreed. Worth a log line rather than a
      // snackbar over a screen the user has already left.
      final verdict = await store.updateBlock(block);
      if (verdict != LockVerdict.allowed) {
        debugPrint('control: update refused by the lock on ${block.id}');
      }
    }
  }
}

class _Range {
  _Range(this.start, this.end);

  factory _Range.fromRange(TimeRange range) => _Range(
    TimeOfDay(hour: range.startMinute ~/ 60, minute: range.startMinute % 60),
    TimeOfDay(hour: range.endMinute ~/ 60, minute: range.endMinute % 60),
  );

  TimeOfDay start;
  TimeOfDay end;
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final remaining = StoreScope.of(context).lockRemaining(block);

    return ControlCard(
      child: Row(
        children: [
          Icon(Icons.lock, size: 18, color: colors.medium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              remaining == null
                  ? 'This block is locked. You can rename it, change its icon, '
                        'add apps, sites or categories, and remove category '
                        'exclusions. Existing coverage cannot be removed.'
                  : 'Locked for another ${_humanise(remaining)}. You can '
                        'rename it, change its icon, add apps, sites or categories, '
                        'and remove category exclusions. Existing coverage cannot '
                        'be removed.',
              style: TextStyle(color: colors.textMuted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  static String _humanise(Duration duration) {
    if (duration.inDays >= 1) {
      return '${duration.inDays} day${duration.inDays == 1 ? '' : 's'}';
    }
    if (duration.inHours >= 1) {
      return '${duration.inHours} hour${duration.inHours == 1 ? '' : 's'}';
    }
    return '${duration.inMinutes} minute${duration.inMinutes == 1 ? '' : 's'}';
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return GestureDetector(
      onTap: () async {
        final store = StoreScope.of(context);
        final navigator = Navigator.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: ControlColors.of(context).card,
            title: Text('Delete ${block.name}?'),
            content: const Text('The apps it covers stop being blocked.'),
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
          await store.removeBlock(block.id);
          navigator.pop();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'Delete block',
          style: TextStyle(color: colors.heavy, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _EmptyIconTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: colors.cardRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.add_photo_alternate_outlined,
        color: colors.textMuted,
        size: 22,
      ),
    );
  }
}

/// Plus/minus stepper. Replaces the Material slider, whose track and thumb were
/// the last piece of stock chrome left in the editor.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.format,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _button(
            context,
            Icons.remove,
            value > min,
            () => onChanged((value - step).clamp(min, max)),
          ),
          Expanded(
            child: Text(
              format(value),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _button(
            context,
            Icons.add,
            value < max,
            () => onChanged((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    bool enabled,
    VoidCallback onTap,
  ) {
    final colors = ControlColors.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.cardRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: enabled ? null : colors.textMuted),
      ),
    );
  }
}

/// One habit row: a switch, a summary, and its settings once it is on.
class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.selected,
    required this.onToggle,
    this.child,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? colors.light.withValues(alpha: 0.10)
                : colors.cardRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.light : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.light : colors.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: selected, onChanged: enabled ? onToggle : null),
                ],
              ),
              if (selected && child != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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

class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colors.light.withValues(alpha: 0.14)
              : colors.cardRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colors.light : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? colors.light : null),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colors.light : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.time, required this.onPicked});

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPicked;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onPicked(picked);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: colors.cardRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          time.format(context),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
