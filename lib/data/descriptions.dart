import 'package:control_core/control_core.dart';
import 'package:flutter/foundation.dart';

/// Human wording for rules, shared by the block cards and by the block screen
/// that appears over other apps.
///
/// In one place because the two have to agree. A card that says "5,000 steps"
/// and a block screen that says something else is the kind of mismatch that
/// makes people stop trusting the numbers.
String describeCondition(UnlockCondition condition) => switch (condition) {
      StepsCondition() => '${_thousands(condition.targetSteps)} steps',
      WorkoutCondition() => '${condition.target.inMinutes} min workout',
      MeditateCondition() => '${condition.target.inMinutes} min meditation',
      AppTimeCondition() => '${condition.target.inMinutes} min in '
          '${condition.apps.length} app${condition.apps.length == 1 ? '' : 's'}',
      FocusCondition() => '${formatSpan(condition.target)} focused',
      PlaceCheckInCondition() => 'check in at ${condition.zone.name} '
          '${describeWindow(condition.window)}',
      ShortcutCondition() => condition.requiredCount > 1
          ? '${condition.channel} x${condition.requiredCount}'
          : condition.channel,
    };

/// What the user still has to do, phrased as an instruction rather than a
/// label: this is what the block screen shows.
String describeRemaining(List<UnlockCondition> conditions) {
  if (conditions.isEmpty) return 'No habit set for this block.';
  return 'Finish ${conditions.map(describeCondition).join(' and ')} to unlock.';
}

/// "Every day", "Weekdays", "Sat, Sun".
String describeWeekdays(Set<int> weekdays) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (weekdays.length >= 7) return 'Every day';
  if (weekdays.isEmpty) return 'Never';

  const workweek = {1, 2, 3, 4, 5};
  const weekend = {6, 7};
  if (setEquals(weekdays, workweek)) return 'Weekdays';
  if (setEquals(weekdays, weekend)) return 'Weekends';

  final sorted = weekdays.toList()..sort();
  return sorted.map((day) => names[day - 1]).join(', ');
}

String describeWindow(TimeRange range) =>
    '${formatMinuteOfDay(range.startMinute)}-'
    '${formatMinuteOfDay(range.endMinute)}';

String formatMinuteOfDay(int minuteOfDay) {
  final hour = (minuteOfDay ~/ 60) % 24;
  final minute = minuteOfDay % 60;
  return '$hour:${minute.toString().padLeft(2, '0')}';
}

/// Clock time of a moment, in the same 24-hour shape as the schedule editor.
String formatTimeOfDay(DateTime moment) =>
    '${moment.hour}:${moment.minute.toString().padLeft(2, '0')}';

/// `6h 27m`, `59m`, `0m`.
String formatSpan(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

String _thousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
