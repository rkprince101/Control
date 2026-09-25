import 'package:flutter/material.dart';

import 'theme.dart';

/// A month of days in a sideways strip, for picking the day a list is about.
///
/// Every day of the visible month, with a button at the front to go back a
/// month and, while looking at a past month, one at the end to come forward
/// again. Months after the current one are out of reach. The parent owns the
/// selected day; picking one calls [onSelect].
class MonthDateStrip extends StatefulWidget {
  const MonthDateStrip({
    required this.selected,
    required this.today,
    required this.onSelect,
    super.key,
  });

  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  State<MonthDateStrip> createState() => _MonthDateStripState();
}

class _MonthDateStripState extends State<MonthDateStrip> {
  final _scroll = ScrollController();
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  /// A day's card and the gap beside it.
  static const _itemWidth = 60.0;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollTo(widget.selected.day, animate: false),
    );
  }

  @override
  void didUpdateWidget(MonthDateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = widget.selected;
    if (selected.year != _month.year || selected.month != _month.month) {
      setState(() => _month = DateTime(selected.year, selected.month));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollTo(selected.day),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _isCurrentMonth =>
      _month.year == widget.today.year && _month.month == widget.today.month;

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isAfter(DateTime(widget.today.year, widget.today.month))) return;
    setState(() => _month = next);
    // Land on today in the current month, on the 1st in any other.
    final landing = _isCurrentMonth ? widget.today : next;
    widget.onSelect(landing);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(landing.day));
  }

  /// Centres list item [index]; the month button is item 0, so day D is D.
  void _scrollTo(int index, {bool animate = true}) {
    if (!_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final target = (index * _itemWidth - viewport / 2 + _itemWidth / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showNext = !_isCurrentMonth;
    final count = 1 + _daysInMonth + (showNext ? 1 : 0);
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(40) + 26,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: count,
        itemBuilder: (context, index) {
          if (index == 0) {
            final previous = DateTime(_month.year, _month.month - 1);
            return _MonthButton(
              icon: Icons.chevron_left_rounded,
              label: _months[previous.month - 1],
              tooltip: 'Previous month',
              onTap: () => _changeMonth(-1),
            );
          }
          if (index <= _daysInMonth) {
            final day = DateTime(_month.year, _month.month, index);
            return _DayCard(
              weekday: _weekdays[day.weekday - 1],
              day: day,
              selected: day == widget.selected,
              isToday: day == widget.today,
              onTap: () {
                widget.onSelect(day);
                _scrollTo(index);
              },
            );
          }
          final next = DateTime(_month.year, _month.month + 1);
          return _MonthButton(
            icon: Icons.chevron_right_rounded,
            label: _months[next.month - 1],
            tooltip: 'Next month',
            onTap: () => _changeMonth(1),
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.weekday,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final String weekday;
  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.primary
        : isToday
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onPrimary
        : isToday
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: MaterialLocalizations.of(context).formatFullDate(day),
        child: ExcludeSemantics(
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekday,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? foreground.withValues(alpha: 0.8)
                            : isToday
                            ? foreground
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: theme.colorScheme.primary),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ControlColors.of(context).textMuted,
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

/// "Today", "Yesterday", "Tomorrow", or the date.
String describeRelativeDay(BuildContext context, DateTime day, DateTime today) {
  final date = DateTime(day.year, day.month, day.day);
  if (date == today) return 'Today';
  if (date == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  if (date == DateTime(today.year, today.month, today.day + 1)) {
    return 'Tomorrow';
  }
  return MaterialLocalizations.of(context).formatMediumDate(date);
}
