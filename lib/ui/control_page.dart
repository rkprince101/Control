import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'navigation.dart';

/// A shared responsive canvas, with independently retained tab scroll positions.
class ControlPage extends StatelessWidget {
  const ControlPage({
    required this.title,
    required this.children,
    this.actions = const [],
    this.eyebrow,
    this.subtitle,
    super.key,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final String? eyebrow;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Inside the app shell every page carries the search bar, which floats
    // back in on the first scroll up, as it does in Gmail.
    final inShell = HomeNavigation.maybeOf(context) != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(20.0, (constraints.maxWidth - 1120) / 2);
        return CustomScrollView(
          key: PageStorageKey(title),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (inShell)
              SliverFloatingHeader(
                child: ShellSearchBar(horizontalPadding: side),
              ),
            SliverSafeArea(
              bottom: false,
              sliver: SliverPadding(
                padding: EdgeInsets.fromLTRB(side, inShell ? 12 : 24, side, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.headlineLarge,
                              ),
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 104),
              sliver: SliverList(delegate: SliverChildListDelegate(children)),
            ),
          ],
        );
      },
    );
  }
}

class HeroCard extends StatelessWidget {
  const HeroCard({
    required this.child,
    this.tone,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });
  final Widget child;
  final Color? tone;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: tone ?? Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(32),
    ),
    child: child,
  );
}
