import 'package:flutter/material.dart';

import '../main.dart';
import '../platform/platform_models.dart';
import '../state/control_store.dart';
import 'control_page.dart';
import 'controls.dart';
import 'theme.dart';
import 'widgets.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    final rangePicker = ControlSegmented<InsightsRange>(
      compact: true,
      value: store.insightsRange,
      options: [
        for (final range in InsightsRange.values) (range, range.label),
      ],
      onChanged: store.setInsightsRange,
    );

    if (!store.usageAccessGranted) {
      // No app bar on this one, so it has to keep clear of the status bar
      // itself.
      return SafeArea(
        child: PermissionPrompt(
          icon: Icons.hourglass_empty_rounded,
          title: 'Usage access needed',
          body: 'Android reports screen time only to apps you allow '
              'explicitly. Control reads it on device and sends it nowhere.',
          actionLabel: 'Open settings',
          onPressed: store.openUsageAccessSettings,
        ),
      );
    }

    final usage = store.usage;
    final worst =
        usage.apps.isEmpty ? Duration.zero : usage.apps.first.duration;

    return RefreshIndicator(
      onRefresh: store.refreshSignals,
      child: ControlPage(
        title: 'insights',
        children: [
          Align(alignment: Alignment.centerRight, child: rangePicker),
          const SizedBox(height: 12),
          _SummaryCard(usage: usage, range: store.insightsRange),
          const SizedBox(height: 16),
          if (usage.apps.isEmpty)
            EmptyState(
              message: store.insightsRange == InsightsRange.day
                  ? 'No screen time recorded yet today.'
                  : 'No screen time recorded in this window.',
            )
          else
            ControlCard(
              child: Column(
                children: [
                  // No cap: a row missing from Insights reads as lost data.
                  for (final app in usage.apps)
                    _UsageRow(
                      label: app.label,
                      duration: app.duration,
                      worst: worst,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.usage, required this.range});

  final UsageSnapshot usage;
  final InsightsRange range;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);

    return ControlCard(
      child: Column(
        children: [
          Text(
            formatDuration(usage.screenTime),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: colors.heavy,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty_rounded,
                  size: 15, color: colors.textMuted),
              const SizedBox(width: 6),
              Text('screen time', style: TextStyle(color: colors.textMuted)),
              const SizedBox(width: 18),
              Icon(Icons.smartphone_rounded, size: 15, color: colors.textMuted),
              const SizedBox(width: 6),
              Text(
                '${usage.pickups} pickups',
                style: TextStyle(color: colors.textMuted),
              ),
            ],
          ),
          // A multi-day total is hard to judge on its own; the daily average is
          // the number people actually compare against.
          if (range != InsightsRange.day) ...[
            const SizedBox(height: 8),
            Text(
              '${formatDuration(usage.screenTime ~/ range.days)} a day '
              'on average',
              style: TextStyle(color: colors.textMuted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.label,
    required this.duration,
    required this.worst,
  });

  final String label;
  final Duration duration;
  final Duration worst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ControlColors.of(context);
    final colour = colors.forDuration(duration, worst);
    final share = worst == Duration.zero
        ? 0.0
        : (duration.inSeconds / worst.inSeconds).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Text(
                formatDuration(duration),
                style: theme.textTheme.labelLarge?.copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: colors.cardRaised,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
        ],
      ),
    );
  }
}
