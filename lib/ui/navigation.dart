import 'dart:math' as math;

import 'package:control_core/control_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/habits.dart';
import '../main.dart';
import '../state/control_store.dart';
import 'block_editor_sheet.dart';
import 'habit_sheets.dart';
import 'habit_widgets.dart';
import 'theme.dart';

/// The four places the app can be.
enum Destination {
  blocks('Blocks', Icons.shield_outlined, Icons.shield_rounded),
  habits('Habits', Icons.local_florist_outlined, Icons.local_florist_rounded),
  insights('Insights', Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  settings('Settings', Icons.tune_outlined, Icons.tune_rounded);

  const Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// What a page needs from the shell: where it is, how to go somewhere else,
/// and how to open the drawer.
///
/// An inherited widget rather than constructor arguments, because the pages
/// are const and the search bar sits deep inside each one.
class HomeNavigation extends InheritedWidget {
  const HomeNavigation({
    required this.destination,
    required this.onSelect,
    required super.child,
    this.onOpenDrawer,
    super.key,
  });

  final Destination destination;
  final ValueChanged<Destination> onSelect;

  /// Null on wide layouts, where the rail carries its own menu button.
  final VoidCallback? onOpenDrawer;

  static HomeNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeNavigation>();

  @override
  bool updateShouldNotify(HomeNavigation oldWidget) =>
      destination != oldWidget.destination ||
      onSelect != oldWidget.onSelect ||
      onOpenDrawer != oldWidget.onOpenDrawer;
}

/// The search bar across the top of every page, in the Gmail arrangement:
/// the menu on the left, the search in the middle, and a status avatar on the
/// right.
///
/// It is also the fastest way around the app: every rule, habit and page is a
/// few letters away.
class ShellSearchBar extends StatelessWidget {
  const ShellSearchBar({required this.horizontalPadding, super.key});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final navigation = HomeNavigation.maybeOf(context);
    final scheme = Theme.of(context).colorScheme;
    if (navigation == null) return const SizedBox.shrink();

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          8,
          horizontalPadding,
          8,
        ),
        child: SearchAnchor(
          viewHintText: 'Search rules, habits and pages',
          viewBackgroundColor: scheme.surface,
          viewSurfaceTintColor: Colors.transparent,
          dividerColor: scheme.outlineVariant,
          builder: (context, controller) => SearchBar(
            controller: controller,
            hintText: 'Search rules and habits',
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
              scheme.surfaceContainerHigh,
            ),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 4),
            ),
            onTap: controller.openView,
            onChanged: (_) => controller.openView(),
            leading: navigation.onOpenDrawer == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.search_rounded),
                  )
                : IconButton(
                    tooltip: 'Open navigation drawer',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: navigation.onOpenDrawer,
                  ),
            trailing: [
              _StatusAvatar(
                onTap: () => navigation.onSelect(Destination.settings),
              ),
            ],
          ),
          suggestionsBuilder: (searchContext, controller) =>
              _results(context, searchContext, controller, navigation),
        ),
      ),
    );
  }

  /// [pageContext] outlives the search view, so sheets opened from a result
  /// are opened from it rather than from the route that is closing.
  List<Widget> _results(
    BuildContext pageContext,
    BuildContext searchContext,
    SearchController controller,
    HomeNavigation navigation,
  ) {
    final store = StoreScope.of(searchContext);
    final query = controller.text.trim().toLowerCase();
    bool matches(String text) =>
        query.isEmpty || text.toLowerCase().contains(query);

    final pages = Destination.values.where((page) => matches(page.label));
    final rules = store.blocks.where((block) => matches(block.name));
    final habits = store.habits.where(
      (habit) => matches(habit.name) || matches(habit.description),
    );

    void close() => controller.closeView('');

    return [
      if (pages.isNotEmpty) ...[
        const _ResultHeader('Pages'),
        for (final page in pages)
          ListTile(
            leading: Icon(page.icon),
            title: Text(page.label),
            onTap: () {
              close();
              navigation.onSelect(page);
            },
          ),
      ],
      if (rules.isNotEmpty) ...[
        const _ResultHeader('Rules'),
        for (final block in rules)
          ListTile(
            leading: _RuleGlyph(block: block),
            title: Text(block.name),
            subtitle: Text(
              '${block.mode.name[0].toUpperCase()}${block.mode.name.substring(1)}'
              ' rule, ${block.enabled ? 'on' : 'off'}',
            ),
            onTap: () {
              close();
              navigation.onSelect(Destination.blocks);
              BlockEditorSheet.show(pageContext, existing: block);
            },
          ),
      ],
      if (habits.isNotEmpty) ...[
        const _ResultHeader('Habits'),
        for (final habit in habits)
          ListTile(
            leading: HabitIconTile(habit: habit, size: 36),
            title: Text(habit.name),
            subtitle: Text(habit.goalLabel),
            onTap: () {
              close();
              navigation.onSelect(Destination.habits);
              HabitDetailSheet.show(pageContext, habit);
            },
          ),
      ],
      if (pages.isEmpty && rules.isEmpty && habits.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nothing matches "${controller.text.trim()}".',
            textAlign: TextAlign.center,
            style: TextStyle(color: ControlColors.of(searchContext).textMuted),
          ),
        ),
    ];
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Where Gmail puts the account, this puts the one thing worth knowing at a
/// glance: whether the rules are actually being enforced.
class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enforcing = store.accessibilityEnabled;

    return IconButton(
      tooltip: enforcing ? 'Your setup' : 'Your setup: app blocking is off',
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: !enforcing,
        smallSize: 10,
        backgroundColor: ControlColors.of(context).medium,
        child: CircleAvatar(
          radius: 16,
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            enforcing ? Icons.shield_rounded : Icons.shield_outlined,
            size: 18,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// The modal drawer: main places first, then every rule the way Gmail lists
/// labels, then settings on its own.
class ControlDrawer extends StatelessWidget {
  const ControlDrawer({
    required this.selected,
    required this.onSelect,
    required this.onOpenRule,
    required this.onNewRule,
    super.key,
  });

  final Destination selected;
  final ValueChanged<Destination> onSelect;
  final ValueChanged<Block> onOpenRule;
  final VoidCallback onNewRule;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;

    return Drawer(
      width: math.min(360, width * 0.86),
      backgroundColor: scheme.surfaceContainerLow,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            const _DrawerHeader(),
            for (final destination in const [
              Destination.blocks,
              Destination.habits,
              Destination.insights,
            ])
              DrawerItem(
                icon: destination == selected
                    ? destination.selectedIcon
                    : destination.icon,
                label: destination.label,
                badge: badgeFor(store, destination),
                selected: destination == selected,
                onTap: () => onSelect(destination),
              ),
            const _DrawerDivider(),
            const _DrawerSection('Your rules'),
            for (final block in store.blocks)
              DrawerItem(
                icon: null,
                leading: _RuleGlyph(block: block),
                label: block.name,
                trailing: _RuleDot(block: block),
                onTap: () => onOpenRule(block),
              ),
            DrawerItem(
              icon: Icons.add_rounded,
              label: 'Create new',
              onTap: onNewRule,
            ),
            const _DrawerDivider(),
            DrawerItem(
              icon: selected == Destination.settings
                  ? Destination.settings.selectedIcon
                  : Destination.settings.icon,
              label: Destination.settings.label,
              selected: selected == Destination.settings,
              onTap: () => onSelect(Destination.settings),
            ),
          ],
        ),
      ),
    );
  }

  /// The number beside a destination, as Gmail puts unread counts beside
  /// labels: what is live right now, or nothing.
  static String? badgeFor(ControlStore store, Destination destination) {
    switch (destination) {
      case Destination.blocks:
        final blocking =
            store.plan?.decisions
                .where((decision) => decision.blocked)
                .length ??
            0;
        return blocking == 0 ? null : '$blocking';
      case Destination.habits:
        final today = store.habitProgressOn(dateOnly(store.wallNow()));
        final left = today.due - today.done;
        return left <= 0 ? null : '$left';
      case Destination.insights:
        final time = store.usage.screenTime;
        return !store.usageAccessGranted || time == Duration.zero
            ? null
            : formatDuration(time);
      case Destination.settings:
        return null;
    }
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Icon(Icons.spa_rounded, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Text(
            'control',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 17, indent: 16, endIndent: 16);
}

/// One 56dp row with the M3 stadium indicator behind it when selected.
class DrawerItem extends StatelessWidget {
  const DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.leading,
    this.badge,
    this.trailing,
    this.selected = false,
    super.key,
  });

  final IconData? icon;
  final Widget? leading;
  final String label;
  final String? badge;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Semantics(
      label: label,
      value: badge,
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 24, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Center(
                        child:
                            leading ?? Icon(icon, size: 24, color: foreground),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 15,
                          color: selected ? scheme.onPrimaryContainer : null,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        badge!,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
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

/// A rule's chosen icon at label size, or a shield when it has none.
class _RuleGlyph extends StatelessWidget {
  const _RuleGlyph({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final asset = block.iconAsset;
    if (asset == null) {
      return Icon(Icons.shield_outlined, size: 22, color: color);
    }
    return SvgPicture.asset(
      asset,
      width: 22,
      height: 22,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      placeholderBuilder: (_) => const SizedBox(width: 22, height: 22),
    );
  }
}

/// Blocking, open, or switched off: the same three states as the pill on the
/// rule's card.
class _RuleDot extends StatelessWidget {
  const _RuleDot({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final colors = ControlColors.of(context);
    final blocking =
        StoreScope.of(context).decisionFor(block.id)?.blocked ?? false;
    final color = !block.enabled
        ? colors.textMuted.withValues(alpha: 0.4)
        : blocking
        ? colors.heavy
        : colors.light;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Gmail's Compose button: extended at rest, shrinking to its icon while the
/// list scrolls down so it covers less of what is being read.
class CollapsingFab extends StatelessWidget {
  const CollapsingFab({
    required this.extended,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool extended;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: extended ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => ExtendingFab(
        progress: t,
        icon: icon,
        label: label,
        onPressed: onPressed,
      ),
    );
  }
}

/// An action button at any point between its icon alone (0) and fully
/// extended with its label (1).
class ExtendingFab extends StatelessWidget {
  const ExtendingFab({
    required this.progress,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final double progress;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    return FloatingActionButton.extended(
      tooltip: t < 0.5 ? label : null,
      onPressed: onPressed,
      extendedPadding: EdgeInsetsDirectional.only(start: 16, end: 16 + 4 * t),
      extendedIconLabelSpacing: 8 * t,
      icon: Icon(icon),
      label: ClipRect(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: t,
          child: Text(label),
        ),
      ),
    );
  }
}

/// The head of the wide-screen rail: the menu, then the page's action, both
/// pinned to the leading edge and following the rail as it widens.
class RailHead extends StatelessWidget {
  const RailHead({
    required this.extended,
    required this.onToggle,
    required this.collapsedWidth,
    required this.extendedWidth,
    this.icon,
    this.label,
    this.onPressed,
    super.key,
  });

  final bool extended;
  final VoidCallback onToggle;
  final double collapsedWidth;
  final double extendedWidth;
  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final animation = NavigationRail.extendedAnimation(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return SizedBox(
          width: collapsedWidth + (extendedWidth - collapsedWidth) * t,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: (collapsedWidth - 48) / 2,
                  ),
                  child: IconButton(
                    tooltip: extended
                        ? 'Collapse navigation'
                        : 'Expand navigation',
                    onPressed: onToggle,
                    icon: const Icon(Icons.menu_rounded),
                  ),
                ),
                if (icon != null && label != null && onPressed != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: (collapsedWidth - 56) / 2,
                    ),
                    child: ExtendingFab(
                      progress: t,
                      icon: icon!,
                      label: label!,
                      onPressed: onPressed!,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
