import 'package:flutter/material.dart';

import 'theme.dart';

/// The one segmented control in the app: a track with the selected segment
/// raised out of it.
///
/// Hand-built rather than `SegmentedButton` because M3 sizes that component for
/// a full-width row with check marks, and this is used inline beside headings
/// and inside sheets. The colour roles are the M3 ones, so it still reads as
/// part of the same system.
class ControlSegmented<T> extends StatelessWidget {
  const ControlSegmented({
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Tighter padding and type, for placing beside a heading.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
      ),
      padding: EdgeInsets.all(compact ? 3 : 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (optionValue, label) in options)
            _Segment(
              label: label,
              selected: optionValue == value,
              compact: compact,
              onTap: () => onChanged(optionValue),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(compact ? 13 : 17);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 7 : 10,
              ),
              constraints: const BoxConstraints(minHeight: 48, minWidth: 56),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: radius,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style:
                      (compact
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.labelLarge)
                          ?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable pill, following the M3 filter-chip colour roles.
///
/// Used for day presets, re-arm delays and repeat counts, so those rows read as
/// one family.
class ControlChip extends StatelessWidget {
  const ControlChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: Shapes.chip,
          child: InkWell(
            onTap: onTap,
            borderRadius: Shapes.chip,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The seven day circles under "On these days".
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;

  /// Monday first, matching `DateTime.weekday`, which is what the engine reads.
  static const _days = [
    (1, 'M'),
    (2, 'T'),
    (3, 'W'),
    (4, 'T'),
    (5, 'F'),
    (6, 'S'),
    (7, 'S'),
  ];

  static const presets = [
    ('Every day', {1, 2, 3, 4, 5, 6, 7}),
    ('Weekdays', {1, 2, 3, 4, 5}),
    ('Weekends', {6, 7}),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final (day, label) in _days)
                () {
                  final isOn = selected.contains(day);
                  return Semantics(
                    label: const [
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday',
                      'Sunday',
                    ][day - 1],
                    selected: isOn,
                    enabled: enabled,
                    button: true,
                    onTap: enabled
                        ? () {
                            final next = {...selected};
                            if (!next.remove(day)) next.add(day);
                            onChanged(next);
                          }
                        : null,
                    child: ExcludeSemantics(
                      child: Material(
                        color: isOn
                            ? scheme.secondaryContainer
                            : scheme.surfaceContainerHigh,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: enabled
                              ? () {
                                  final next = {...selected};
                                  if (!next.remove(day)) next.add(day);
                                  onChanged(next);
                                }
                              : null,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Text(
                                label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: isOn
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }(),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, days) in presets)
                ControlChip(
                  label: label,
                  selected:
                      selected.length == days.length &&
                      selected.containsAll(days),
                  onTap: enabled ? () => onChanged({...days}) : () {},
                ),
            ],
          ),
        ],
      ),
    );
  }
}
