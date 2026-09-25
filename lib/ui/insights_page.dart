import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import '../state/control_store.dart';
import 'app_icons.dart';
import 'block_editor_sheet.dart';
import 'control_page.dart';
import 'disclosures.dart';
import 'controls.dart';
import 'expressive_progress.dart';
import 'sheet.dart';
import 'widgets.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!store.usageAccessGranted) {
      // Still a ControlPage, so the search bar and its menu stay reachable.
      return ControlPage(
        title: 'Your time',
        eyebrow: 'INSIGHTS',
        children: [
          PermissionPrompt(
            icon: Icons.hourglass_empty_rounded,
            title: 'Usage access needed',
            body:
                'Allow usage access to see your recorded activity. '
                'Control processes your app usage on this device, not on a server.',
            actionLabel: 'Open settings',
            onPressed: () => Disclosures.usageAccess(context),
          ),
        ],
      );
    }

    final usage = store.insightsUsage;
    final apps = [...usage.apps]
      ..sort((a, b) => b.duration.compareTo(a.duration));
    final period = _periodLabel(context, usage, store.insightsRange);

    return RefreshIndicator(
      onRefresh: store.refreshInsights,
      child: ControlPage(
        title: 'Your time',
        eyebrow: 'INSIGHTS',
        subtitle: 'See your patterns. Choose your next step.',
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            onPressed: store.insightsLoading ? null : store.refreshInsights,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          Text(period, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          // Keep all three choices reachable even at 320dp with large text.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ControlSegmented<InsightsRange>(
              value: store.insightsRange,
              options: [
                for (final range in InsightsRange.values) (range, range.label),
              ],
              onChanged: store.setInsightsRange,
            ),
          ),
          const SizedBox(height: 20),
          if (store.insightsLoading)
            const _TonalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reading recorded activity'),
                  SizedBox(height: 20),
                  ExpressiveProgress(semanticsLabel: 'Loading usage activity'),
                  SizedBox(height: 12),
                  Text('Your usage is processed on this device.'),
                ],
              ),
            )
          else if (store.insightsError != null)
            _TonalCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sync_problem_rounded),
                  const SizedBox(height: 12),
                  Text(
                    'Activity could not be loaded',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(store.insightsError!),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: store.refreshInsights,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            )
          else ...[
            _SummaryCard(usage: usage, topApp: apps.firstOrNull),
            const SizedBox(height: 16),
            _ActivityChart(
              key: ValueKey(
                '${store.insightsRange}-${usage.start}-${usage.end}',
              ),
              usage: usage,
              range: store.insightsRange,
            ),
            const SizedBox(height: 24),
            Text('Where your time went', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'App time and share of recorded screen time.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (apps.isEmpty)
              const _TonalCard(
                child: Text(
                  'No app activity recorded for this period. '
                  'Only activity available from Android appears here.',
                ),
              )
            else
              _TonalCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (var i = 0; i < apps.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 20, endIndent: 20),
                      _AppRow(
                        app: apps[i],
                        rank: i + 1,
                        total: usage.screenTime,
                        onTap: () => _showApp(context, apps[i], usage, period),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (usage.historyNote != null &&
                usage.historyNote!.trim().isNotEmpty) ...[
              _TonalCard(
                tone: scheme.tertiaryContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About this history',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      usage.historyNote!,
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Recorded activity, not a complete device history. Android may '
              'retain only part of this period. Usage is processed locally.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (store.insightsUpdatedAt case final updated?) ...[
              const SizedBox(height: 8),
              Text(
                'Updated ${MaterialLocalizations.of(context).formatShortDate(updated)} '
                'at ${TimeOfDay.fromDateTime(updated).format(context)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _showApp(
    BuildContext context,
    AppUsage app,
    UsageSnapshot usage,
    String period,
  ) async {
    final createBlock = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) {
        final theme = Theme.of(context);
        return SheetScaffold(
          title: 'App details',
          leading: SheetAction(
            'Close',
            onPressed: () => Navigator.pop(context),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(id: app.id, size: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(app.label, style: theme.textTheme.titleLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(period, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                Text(
                  _duration(app.duration),
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_share(app.duration, usage.screenTime)} of recorded '
                  'screen time in this period.',
                ),
                const SizedBox(height: 20),
                const Text(
                  'Want to make room for something else? '
                  'Choose when this app is available.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create a block'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (createBlock == true && context.mounted) {
      await BlockEditorSheet.show(context, initialApps: {app.id});
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.usage, required this.topApp});

  final UsageSnapshot usage;
  final AppUsage? topApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _TonalCard(
      tone: scheme.primaryContainer,
      padding: const EdgeInsets.all(20),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: scheme.onPrimaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Screen time'),
            const SizedBox(height: 8),
            Text(
              _duration(usage.screenTime),
              key: const ValueKey('screen-time-total'),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 64,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                height: 1.1,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Recorded activity in this period'),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(14) > 21;
                final pickups = _Metric(
                  label: 'Pickups',
                  value: '${usage.pickups}',
                  foreground: scheme.onPrimaryContainer,
                );
                final mostUsed = _Metric(
                  label: 'Most used',
                  value: topApp?.label ?? 'No app activity',
                  detail: topApp == null
                      ? null
                      : '${_share(topApp!.duration, usage.screenTime)} of total',
                  foreground: scheme.onPrimaryContainer,
                );
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          pickups,
                          const SizedBox(height: 20),
                          mostUsed,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: pickups),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: mostUsed),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.foreground,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (detail != null) ...[const SizedBox(height: 4), Text(detail!)],
    ],
  );
}

class _ActivityChart extends StatefulWidget {
  const _ActivityChart({required this.usage, required this.range, super.key});

  final UsageSnapshot usage;
  final InsightsRange range;

  @override
  State<_ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<_ActivityChart> {
  DateTime? _selectedStart;
  ScrollController? _chartScroll;

  @override
  void dispose() {
    _chartScroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buckets = [...widget.usage.buckets]
      ..sort((a, b) => a.start.compareTo(b.start));
    final selected =
        buckets.where((bucket) => bucket.start == _selectedStart).firstOrNull ??
        buckets.reversed
            .where((bucket) => bucket.screenTime > Duration.zero)
            .firstOrNull ??
        buckets.lastOrNull;
    final maximum = buckets.fold<int>(
      0,
      (value, bucket) => math.max(value, bucket.screenTime.inMilliseconds),
    );
    // A rounded, labelled duration scale. Zero activity never gains a fake bar.
    final unit = maximum > const Duration(hours: 1).inMilliseconds
        ? const Duration(hours: 1).inMilliseconds
        : const Duration(minutes: 10).inMilliseconds;
    final ceiling = math.max(unit, (maximum / unit).ceil() * unit);
    final scale = MediaQuery.textScalerOf(context);
    final minimumBucketWidth = math.max(64.0, scale.scale(44));
    final labelHeight = scale.scale(32) + 12;
    final gaps = [
      for (var i = 1; i < buckets.length; i++)
        if (buckets[i].start.isAfter(buckets[i - 1].end)) i,
    ];

    return _TonalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity over time', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            widget.range == InsightsRange.day
                ? 'Hourly recorded screen time'
                : 'Daily recorded screen time',
          ),
          if (buckets.isEmpty) ...[
            const SizedBox(height: 24),
            Text(
              widget.usage.screenTime == Duration.zero
                  ? 'No screen time recorded for this period.'
                  : 'A timeline is not available for this period.',
            ),
            const SizedBox(height: 8),
            const Text('Missing history is not the same as no activity.'),
          ] else ...[
            const SizedBox(height: 16),
            Semantics(
              key: const ValueKey('bucket-readout'),
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _bucketLabel(context, selected!, widget.range),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    direction: scale.scale(14) > 21
                        ? Axis.vertical
                        : Axis.horizontal,
                    spacing: scale.scale(14) > 21 ? 6 : 16,
                    runSpacing: 6,
                    crossAxisAlignment: scale.scale(14) > 21
                        ? WrapCrossAlignment.start
                        : WrapCrossAlignment.center,
                    children: [
                      Text(
                        _duration(selected.screenTime),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                      Text('${selected.pickups} pickups'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: scale.scale(42),
                  height: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _duration(Duration(milliseconds: ceiling)),
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(
                        _duration(Duration(milliseconds: ceiling ~/ 2)),
                        style: theme.textTheme.labelSmall,
                      ),
                      Text('0m', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bucketWidth = math.max(
                        minimumBucketWidth,
                        constraints.maxWidth / (buckets.length + gaps.length),
                      );
                      final selectedIndex = buckets.indexOf(selected);
                      final selectedSlot =
                          selectedIndex +
                          gaps.where((gap) => gap <= selectedIndex).length;
                      // Set the initial viewport only. Subsequent selections and
                      // rebuilds must not pull people away from earlier history.
                      _chartScroll ??= ScrollController(
                        keepScrollOffset: false,
                        initialScrollOffset:
                            ((selectedSlot + 0.5) * bucketWidth -
                                    constraints.maxWidth / 2)
                                .clamp(
                                  0.0,
                                  math.max(
                                    0.0,
                                    (buckets.length + gaps.length) *
                                            bucketWidth -
                                        constraints.maxWidth,
                                  ),
                                ),
                      );
                      return SingleChildScrollView(
                        key: const ValueKey('activity-chart-scroll'),
                        controller: _chartScroll,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < buckets.length; i++) ...[
                              if (gaps.contains(i))
                                SizedBox(
                                  width: bucketWidth,
                                  height: 160 + labelHeight,
                                  child: Center(
                                    child: Text(
                                      'No data',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ),
                                ),
                              Semantics(
                                button: true,
                                selected: buckets[i].start == selected.start,
                                label:
                                    '${_bucketLabel(context, buckets[i], widget.range)}, '
                                    '${_duration(buckets[i].screenTime)} recorded screen time, '
                                    '${buckets[i].pickups} pickups',
                                child: InkWell(
                                  key: ValueKey(
                                    'usage-bucket-${buckets[i].start.millisecondsSinceEpoch}',
                                  ),
                                  onTap: () => setState(
                                    () => _selectedStart = buckets[i].start,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: ExcludeSemantics(
                                    child: SizedBox(
                                      width: bucketWidth,
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 160,
                                            child: Stack(
                                              children: [
                                                for (final alignment in [
                                                  Alignment.topCenter,
                                                  Alignment.center,
                                                  Alignment.bottomCenter,
                                                ])
                                                  Align(
                                                    alignment: alignment,
                                                    child: Container(
                                                      height: 1,
                                                      color:
                                                          scheme.outlineVariant,
                                                    ),
                                                  ),
                                                Align(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: Container(
                                                    key: ValueKey(
                                                      'usage-bar-${buckets[i].start.millisecondsSinceEpoch}',
                                                    ),
                                                    width: 28,
                                                    height:
                                                        160 *
                                                        buckets[i]
                                                            .screenTime
                                                            .inMilliseconds /
                                                        ceiling,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          buckets[i].start ==
                                                              selected.start
                                                          ? scheme.primary
                                                          : scheme.secondary,
                                                      borderRadius:
                                                          const BorderRadius.vertical(
                                                            top:
                                                                Radius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height: labelHeight,
                                            child: Center(
                                              child: Text(
                                                widget.range ==
                                                        InsightsRange.day
                                                    ? '${buckets[i].start.hour.toString().padLeft(2, '0')}:'
                                                          '${buckets[i].start.minute.toString().padLeft(2, '0')}'
                                                    : '${buckets[i].start.day}/${buckets[i].start.month}',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          buckets[i].start ==
                                                              selected.start
                                                          ? FontWeight.w800
                                                          : FontWeight.w400,
                                                    ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.range == InsightsRange.day
                  ? 'Hour of day. Tap a bar for details; swipe to see more.'
                  : 'Date (day/month). Tap a bar for details; swipe to see more.',
              style: theme.textTheme.bodySmall,
            ),
            if (maximum == 0) ...[
              const SizedBox(height: 12),
              const Text('No screen time recorded in these intervals.'),
            ],
          ],
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.rank,
    required this.total,
    required this.onTap,
  });

  final AppUsage app;
  final int rank;
  final Duration total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label:
          '$rank. ${app.label}, ${_duration(app.duration)}, '
          '${_share(app.duration, total)} of recorded screen time. App details',
      child: InkWell(
        key: ValueKey('usage-app-${app.id}'),
        onTap: onTap,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(id: app.id, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$rank. ${app.label}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_duration(app.duration)}  /  ${_share(app.duration, total)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TonalCard extends StatelessWidget {
  const _TonalCard({
    required this.child,
    this.tone,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final Color? tone;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    color: tone ?? Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(32),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

String _duration(Duration duration) {
  if (duration <= Duration.zero) return '0m';
  if (duration.inMinutes == 0) return '<1m';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

String _share(Duration duration, Duration total) {
  if (total <= Duration.zero) return '0%';
  final percent = duration.inMilliseconds / total.inMilliseconds * 100;
  if (percent > 0 && percent < 1) return '<1%';
  return '${percent.toStringAsFixed(0)}%';
}

String _periodLabel(
  BuildContext context,
  UsageSnapshot usage,
  InsightsRange range,
) {
  final start = usage.start;
  final end = usage.end;
  if (start == null || end == null) {
    return switch (range) {
      InsightsRange.day => 'Today',
      InsightsRange.week => 'Last 7 days',
      InsightsRange.month => 'Last 30 days',
    };
  }
  final localizations = MaterialLocalizations.of(context);
  // Query end is exclusive, so midnight belongs to the preceding date.
  final last = end.isAfter(start)
      ? end.subtract(const Duration(microseconds: 1))
      : end;
  if (DateUtils.isSameDay(start, last)) {
    return localizations.formatMediumDate(start);
  }
  return '${localizations.formatShortDate(start)} - '
      '${localizations.formatShortDate(last)}';
}

String _bucketLabel(
  BuildContext context,
  UsageBucket bucket,
  InsightsRange range,
) {
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatMediumDate(bucket.start);
  final start = TimeOfDay.fromDateTime(bucket.start).format(context);
  final end = TimeOfDay.fromDateTime(bucket.end).format(context);
  if (range == InsightsRange.day) return '$date, $start - $end';
  return '$date, $start - '
      '${DateUtils.isSameDay(bucket.start, bucket.end) ? '' : '${localizations.formatMediumDate(bucket.end)}, '}$end';
}
