import 'package:flutter/material.dart';

import 'theme.dart';

/// The screen title at the top of each tab.
///
/// `headlineLarge` from the M3 type scale rather than a hand-picked size, so
/// the three tabs and every sheet title sit on the same scale.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.headlineLarge,
      );
}

/// A filled container at the M3 large radius.
///
/// No shadow: M3 conveys depth with tonal surfaces, and a drop shadow under a
/// container that is already lighter than the page is a second, competing cue.
class ControlCard extends StatelessWidget {
  const ControlCard({
    required this.child,
    this.padding,
    this.raised = false,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;

  /// One step further up the surface family, for a container that sits on top
  /// of another one.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: raised
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        borderRadius: Shapes.card,
      ),
      child: child,
    );
  }
}

/// The label above a group of cards.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.icon, super.key});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of a screen that cannot work without a permission.
///
/// States plainly what is read and where it goes: this app asks for the two
/// most invasive-looking permissions on Android, and a vague prompt is what
/// makes people decline them.
class PermissionPrompt extends StatelessWidget {
  const PermissionPrompt({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
    this.icon = Icons.lock_outline_rounded,
    super.key,
  });

  final String title;
  final String body;
  final String actionLabel;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onSecondaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label: the mode tag on a block card, the state pill on its
/// detail row.
class Pill extends StatelessWidget {
  const Pill(this.text, {this.color, this.background, super.key});

  final String text;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? foreground.withValues(alpha: 0.14),
        borderRadius: Shapes.chip,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: foreground,
        ),
      ),
    );
  }
}
