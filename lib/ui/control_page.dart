import 'package:flutter/material.dart';

/// The shell every tab sits in.
///
/// A pinned top app bar carrying the screen title, sized to the title and
/// nothing more.
///
/// The large and medium M3 variants both anchor their title to the *bottom* of
/// an expanded band, which means the space above it is empty by design: 152dp
/// for large, 112 for medium. On a phone that reads as a screen that starts a
/// third of the way down, and it was the single loudest complaint about this
/// layout. A pinned bar at 64dp keeps the oversized title and the scroll-under
/// behaviour without reserving a band to hold nothing.
class ControlPage extends StatelessWidget {
  const ControlPage({
    required this.title,
    required this.children,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(title),
          actions: actions,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          titleTextStyle: theme.textTheme.headlineMedium,
          // Aligns the title with the 20dp body padding rather than the 16dp
          // default, so the heading and the cards share one left edge.
          titleSpacing: 20,
          toolbarHeight: 64,
        ),
        SliverPadding(
          // Bottom room for the floating nav pill, which the body extends
          // underneath.
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 108),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed(children),
          ),
        ),
      ],
    );
  }
}

/// A tinted hero container, the way M3 uses a container role to make one number
/// the subject of a screen.
class HeroCard extends StatelessWidget {
  const HeroCard({
    required this.child,
    this.tone,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Defaults to `secondaryContainer`, the M3 role for a supporting emphasis
  /// surface that is not competing with the primary action.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tone ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }
}
